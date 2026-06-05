#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlMethodChannel* tun_channel;
  GtkWidget* window;
  gpointer status_icon;
  GtkWidget* tray_menu;
  GtkWidget* tray_toggle_item;
  gchar* last_cpe_host;
  gboolean tun_running;
  gboolean quit_requested;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static constexpr char kTunChannelName[] = "sdwan_client/tun";
static constexpr char kDefaultCpeHost[] = "192.168.1.140";

static const gchar* last_cpe_host(MyApplication* self) {
  return self->last_cpe_host == nullptr || self->last_cpe_host[0] == '\0'
             ? kDefaultCpeHost
             : self->last_cpe_host;
}

static void remember_cpe_host(MyApplication* self, const gchar* host) {
  g_free(self->last_cpe_host);
  self->last_cpe_host = g_strdup(
      host == nullptr || host[0] == '\0' ? kDefaultCpeHost : host);
}

static gchar* bundled_tray_icon_path(const gchar* filename) {
  g_autofree gchar* executable = g_file_read_link("/proc/self/exe", nullptr);
  if (executable != nullptr) {
    g_autofree gchar* executable_dir = g_path_get_dirname(executable);
    g_autofree gchar* installed =
        g_build_filename(executable_dir, "data", "tray", filename, nullptr);
    if (g_file_test(installed, G_FILE_TEST_EXISTS)) {
      return g_strdup(installed);
    }
  }
  return g_build_filename("linux", "runner", "resources", filename, nullptr);
}

static const gchar* cpe_host_from_call(FlMethodCall* method_call) {
  FlValue* args = fl_method_call_get_args(method_call);
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return kDefaultCpeHost;
  }
  FlValue* value = fl_value_lookup_string(args, "cpeHost");
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return kDefaultCpeHost;
  }
  const gchar* host = fl_value_get_string(value);
  if (host == nullptr || host[0] == '\0') {
    return kDefaultCpeHost;
  }
  return host;
}

static FlValue* unavailable_health(const gchar* host) {
  FlValue* value = fl_value_new_map();
  fl_value_set_string_take(value, "host", fl_value_new_string(host));
  fl_value_set_string_take(value, "reachable", fl_value_new_bool(FALSE));
  fl_value_set_string_take(value, "serviceReady", fl_value_new_bool(FALSE));
  fl_value_set_string_take(
      value, "error",
      fl_value_new_string("TUN native service is not wired yet"));
  return value;
}

static FlValue* unsupported_status(
    const gchar* state = "stopped",
    const gchar* message = "Linux /dev/net/tun backend is not wired yet",
    const gchar* host = kDefaultCpeHost) {
  FlValue* value = fl_value_new_map();
  fl_value_set_string_take(value, "state", fl_value_new_string(state));
  fl_value_set_string_take(value, "permission",
                           fl_value_new_string("unsupported"));
  fl_value_set_string_take(value, "cpe", unavailable_health(host));
  fl_value_set_string_take(value, "helperInstalled", fl_value_new_bool(FALSE));
  fl_value_set_string_take(value, "txBytes", fl_value_new_int(0));
  fl_value_set_string_take(value, "rxBytes", fl_value_new_int(0));
  fl_value_set_string_take(value, "txRate", fl_value_new_int(0));
  fl_value_set_string_take(value, "rxRate", fl_value_new_int(0));
  fl_value_set_string_take(value, "lastError", fl_value_new_string(message));
  return value;
}

static void update_tun_state_from_status(MyApplication* self, FlValue* status) {
  FlValue* state = fl_value_lookup_string(status, "state");
  if (state == nullptr || fl_value_get_type(state) != FL_VALUE_TYPE_STRING) {
    self->tun_running = FALSE;
    return;
  }
  const gchar* state_text = fl_value_get_string(state);
  self->tun_running = g_strcmp0(state_text, "running") == 0 ||
                      g_strcmp0(state_text, "starting") == 0;
}

static void update_tray_icon(MyApplication* self) {
  if (self->status_icon == nullptr) {
    return;
  }
  const gchar* icon_name =
      self->tun_running ? "tray-active.png" : "tray-idle.png";
  g_autofree gchar* icon_path = bundled_tray_icon_path(icon_name);
  G_GNUC_BEGIN_IGNORE_DEPRECATIONS
  gtk_status_icon_set_from_file(GTK_STATUS_ICON(self->status_icon), icon_path);
  gtk_status_icon_set_tooltip_text(
      GTK_STATUS_ICON(self->status_icon),
      self->tun_running ? "SD-WAN Verge - 已加速" : "SD-WAN Verge");
  G_GNUC_END_IGNORE_DEPRECATIONS
  if (self->tray_toggle_item != nullptr) {
    gtk_menu_item_set_label(GTK_MENU_ITEM(self->tray_toggle_item),
                            self->tun_running ? "关闭加速" : "开启加速");
  }
}

static void show_main_window(MyApplication* self) {
  if (self->window == nullptr) {
    return;
  }
  gtk_widget_show(self->window);
  gtk_window_present(GTK_WINDOW(self->window));
}

static void tray_show_cb(GtkMenuItem* item, gpointer user_data) {
  show_main_window(MY_APPLICATION(user_data));
}

static void tray_toggle_cb(GtkMenuItem* item, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  g_autoptr(FlValue) result =
      self->tun_running
          ? unsupported_status("stopped",
                               "Linux /dev/net/tun backend is not wired yet",
                               last_cpe_host(self))
          : unsupported_status("failed",
                               "Linux /dev/net/tun backend is not wired yet",
                               last_cpe_host(self));
  update_tun_state_from_status(self, result);
  update_tray_icon(self);
}

static void tray_quit_cb(GtkMenuItem* item, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  self->quit_requested = TRUE;
  g_application_quit(G_APPLICATION(self));
}

static gboolean window_delete_event_cb(GtkWidget* widget,
                                       GdkEvent* event,
                                       gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (self->quit_requested) {
    return FALSE;
  }
  gtk_widget_hide(widget);
  return TRUE;
}

static void tray_activate_cb(gpointer status_icon, gpointer user_data) {
  show_main_window(MY_APPLICATION(user_data));
}

static void tray_popup_menu_cb(gpointer status_icon,
                               guint button,
                               guint activate_time,
                               gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  update_tray_icon(self);
  gtk_menu_popup_at_pointer(GTK_MENU(self->tray_menu), nullptr);
}

static void setup_tray_icon(MyApplication* self) {
  if (self->status_icon != nullptr) {
    update_tray_icon(self);
    return;
  }
  self->tray_menu = gtk_menu_new();
  GtkWidget* show_item = gtk_menu_item_new_with_label("打开");
  g_signal_connect(show_item, "activate", G_CALLBACK(tray_show_cb), self);
  gtk_menu_shell_append(GTK_MENU_SHELL(self->tray_menu), show_item);

  self->tray_toggle_item = gtk_menu_item_new_with_label("开启加速");
  g_signal_connect(self->tray_toggle_item, "activate", G_CALLBACK(tray_toggle_cb),
                   self);
  gtk_menu_shell_append(GTK_MENU_SHELL(self->tray_menu),
                        self->tray_toggle_item);
  gtk_menu_shell_append(GTK_MENU_SHELL(self->tray_menu),
                        gtk_separator_menu_item_new());

  GtkWidget* quit_item = gtk_menu_item_new_with_label("退出");
  g_signal_connect(quit_item, "activate", G_CALLBACK(tray_quit_cb), self);
  gtk_menu_shell_append(GTK_MENU_SHELL(self->tray_menu), quit_item);
  gtk_widget_show_all(self->tray_menu);

  G_GNUC_BEGIN_IGNORE_DEPRECATIONS
  self->status_icon = gtk_status_icon_new();
  gtk_status_icon_set_visible(GTK_STATUS_ICON(self->status_icon), TRUE);
  g_signal_connect(self->status_icon, "activate", G_CALLBACK(tray_activate_cb),
                   self);
  g_signal_connect(self->status_icon, "popup-menu",
                   G_CALLBACK(tray_popup_menu_cb), self);
  G_GNUC_END_IGNORE_DEPRECATIONS
  update_tray_icon(self);
}

static void tun_method_call_cb(FlMethodChannel* channel,
                               FlMethodCall* method_call,
                               gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  const gchar* host = cpe_host_from_call(method_call);
  remember_cpe_host(self, host);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (g_strcmp0(method, "status") == 0) {
    g_autoptr(FlValue) result = unsupported_status(
        "stopped", "Linux /dev/net/tun backend is not wired yet", host);
    update_tun_state_from_status(self, result);
    update_tray_icon(self);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "healthCheck") == 0) {
    g_autoptr(FlValue) result = unavailable_health(host);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "logs") == 0 ||
             g_strcmp0(method, "connections") == 0) {
    g_autoptr(FlValue) result = fl_value_new_list();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "installHelper") == 0) {
    g_autoptr(FlValue) result = unsupported_status(
        "failed", "Linux /dev/net/tun backend is not wired yet", host);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "uninstallHelper") == 0) {
    g_autoptr(FlValue) result = unsupported_status(
        "stopped", "Linux /dev/net/tun backend is not wired yet", host);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "start") == 0) {
    g_autoptr(FlValue) result = unsupported_status(
        "failed", "Linux /dev/net/tun backend is not wired yet", host);
    update_tun_state_from_status(self, result);
    update_tray_icon(self);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "stop") == 0) {
    g_autoptr(FlValue) result = unsupported_status(
        "stopped", "Linux /dev/net/tun backend is not wired yet", host);
    update_tun_state_from_status(self, result);
    update_tray_icon(self);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "launchAtLoginStatus") == 0 ||
             g_strcmp0(method, "setLaunchAtLogin") == 0) {
    g_autoptr(FlValue) result = fl_value_new_bool(FALSE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to send TUN response: %s", error->message);
  }
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = GTK_WIDGET(window);
  g_signal_connect(window, "delete-event", G_CALLBACK(window_delete_event_cb),
                   self);

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "SD-WAN Verge");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "SD-WAN Verge");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  FlEngine* engine = fl_view_get_engine(view);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->tun_channel = fl_method_channel_new(
      messenger, kTunChannelName, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->tun_channel, tun_method_call_cb, self, nullptr);
  setup_tray_icon(self);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_object(&self->tun_channel);
  if (self->status_icon != nullptr) {
    G_GNUC_BEGIN_IGNORE_DEPRECATIONS
    gtk_status_icon_set_visible(GTK_STATUS_ICON(self->status_icon), FALSE);
    G_GNUC_END_IGNORE_DEPRECATIONS
    g_object_unref(self->status_icon);
    self->status_icon = nullptr;
  }
  g_clear_pointer(&self->tray_menu, gtk_widget_destroy);
  self->tray_toggle_item = nullptr;
  self->window = nullptr;
  g_clear_pointer(&self->last_cpe_host, g_free);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  remember_cpe_host(self, kDefaultCpeHost);
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
