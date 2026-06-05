#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <algorithm>
#include <sstream>
#include <string>
#include <vector>

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
  guint64 base_tx;
  guint64 base_rx;
  guint64 last_tx_total;
  guint64 last_rx_total;
  gint64 last_sample_ms;
  guint64 tx_bytes;
  guint64 rx_bytes;
  guint64 tx_rate;
  guint64 rx_rate;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static constexpr char kTunChannelName[] = "sdwan_client/tun";
static constexpr char kDefaultCpeHost[] = "192.168.1.140";
static constexpr char kLinuxAdapterName[] = "Linux Half Route";
static constexpr char kLogPath[] = "/tmp/sdwan-verge-linux-events.log";

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

static gboolean safe_ipv4(const gchar* host) {
  if (host == nullptr || host[0] == '\0') {
    return FALSE;
  }
  gchar** parts = g_strsplit(host, ".", 4);
  int count = 0;
  for (gchar** part = parts; part != nullptr && *part != nullptr; ++part) {
    count++;
    if ((*part)[0] == '\0') {
      g_strfreev(parts);
      return FALSE;
    }
    for (const gchar* cursor = *part; *cursor != '\0'; ++cursor) {
      if (!g_ascii_isdigit(*cursor)) {
        g_strfreev(parts);
        return FALSE;
      }
    }
    const int value = atoi(*part);
    if (value < 0 || value > 255) {
      g_strfreev(parts);
      return FALSE;
    }
  }
  g_strfreev(parts);
  return count == 4;
}

static gchar* run_command_capture(const gchar* command) {
  FILE* pipe = popen(command, "r");
  if (pipe == nullptr) {
    return g_strdup("");
  }
  GString* output = g_string_new("");
  char buffer[2048];
  while (fgets(buffer, sizeof(buffer), pipe) != nullptr) {
    g_string_append(output, buffer);
  }
  pclose(pipe);
  return g_string_free(output, FALSE);
}

static gboolean run_command(const gchar* command) {
  const int code = system(command);
  return code == 0;
}

static void append_log(const gchar* message) {
  g_autoptr(GDateTime) now = g_date_time_new_now_local();
  g_autofree gchar* time = g_date_time_format(now, "%Y-%m-%d %H:%M:%S");
  FILE* file = fopen(kLogPath, "a");
  if (file == nullptr) {
    return;
  }
  fprintf(file, "%s %s\n", time, message == nullptr ? "" : message);
  fclose(file);
}

static gboolean route_get_uses_cpe(const gchar* destination,
                                   const gchar* host) {
  g_autofree gchar* command =
      g_strdup_printf("ip route get %s 2>/dev/null", destination);
  g_autofree gchar* output = run_command_capture(command);
  g_autofree gchar* expected = g_strdup_printf("via %s", host);
  return g_strstr_len(output, -1, expected) != nullptr;
}

static gboolean half_routes_present(const gchar* host) {
  return route_get_uses_cpe("1.1.1.1", host) &&
         route_get_uses_cpe("129.0.0.1", host);
}

static gboolean apply_half_routes(const gchar* host, gchar** error) {
  if (!safe_ipv4(host)) {
    if (error != nullptr) {
      *error = g_strdup("invalid CPE IPv4 address");
    }
    return FALSE;
  }
  g_autofree gchar* script = g_strdup_printf(
      "ip route replace 0.0.0.0/1 via %s; "
      "ip route replace 128.0.0.0/1 via %s",
      host, host);
  g_autofree gchar* quoted = g_shell_quote(script);
  g_autofree gchar* command = g_strdup_printf("pkexec /bin/sh -c %s", quoted);
  if (!run_command(command)) {
    if (error != nullptr) {
      *error = g_strdup("failed to apply Linux half routes");
    }
    return FALSE;
  }
  return TRUE;
}

static gboolean remove_half_routes(gchar** error) {
  g_autofree gchar* script = g_strdup(
      "ip route del 0.0.0.0/1 2>/dev/null; "
      "ip route del 128.0.0.0/1 2>/dev/null; true");
  g_autofree gchar* quoted = g_shell_quote(script);
  g_autofree gchar* command = g_strdup_printf("pkexec /bin/sh -c %s", quoted);
  if (!run_command(command)) {
    if (error != nullptr) {
      *error = g_strdup("failed to remove Linux half routes");
    }
    return FALSE;
  }
  return TRUE;
}

static gboolean ping_cpe(const gchar* host) {
  if (!safe_ipv4(host)) {
    return FALSE;
  }
  g_autofree gchar* command =
      g_strdup_printf("ping -c 1 -W 1 %s >/dev/null 2>&1", host);
  return run_command(command);
}

static gboolean l3_probe() {
  return run_command("nc -w 2 -z 1.1.1.1 443 >/dev/null 2>&1");
}

static gboolean read_linux_counters(guint64* tx, guint64* rx) {
  *tx = 0;
  *rx = 0;
  FILE* file = fopen("/proc/net/dev", "r");
  if (file == nullptr) {
    return FALSE;
  }
  char line[1024];
  while (fgets(line, sizeof(line), file) != nullptr) {
    char* colon = strchr(line, ':');
    if (colon == nullptr) {
      continue;
    }
    *colon = '\0';
    gchar* iface = g_strstrip(line);
    if (g_strcmp0(iface, "lo") == 0) {
      continue;
    }
    std::vector<guint64> values;
    std::istringstream stream(colon + 1);
    guint64 value = 0;
    while (stream >> value) {
      values.push_back(value);
    }
    if (values.size() >= 16) {
      *rx += values[0];
      *tx += values[8];
    }
  }
  fclose(file);
  return TRUE;
}

static void reset_traffic_baseline(MyApplication* self) {
  guint64 tx = 0;
  guint64 rx = 0;
  read_linux_counters(&tx, &rx);
  self->base_tx = tx;
  self->base_rx = rx;
  self->last_tx_total = tx;
  self->last_rx_total = rx;
  self->last_sample_ms = g_get_monotonic_time() / 1000;
  self->tx_bytes = 0;
  self->rx_bytes = 0;
  self->tx_rate = 0;
  self->rx_rate = 0;
}

static void update_traffic(MyApplication* self) {
  guint64 tx = 0;
  guint64 rx = 0;
  if (!read_linux_counters(&tx, &rx)) {
    return;
  }
  const gint64 now_ms = g_get_monotonic_time() / 1000;
  if (self->last_sample_ms > 0 && now_ms > self->last_sample_ms) {
    const guint64 elapsed = static_cast<guint64>(now_ms - self->last_sample_ms);
    const guint64 tx_delta =
        tx >= self->last_tx_total ? tx - self->last_tx_total : 0;
    const guint64 rx_delta =
        rx >= self->last_rx_total ? rx - self->last_rx_total : 0;
    self->tx_rate = tx_delta * 1000 / elapsed;
    self->rx_rate = rx_delta * 1000 / elapsed;
  }
  self->last_tx_total = tx;
  self->last_rx_total = rx;
  self->last_sample_ms = now_ms;
  self->tx_bytes = tx >= self->base_tx ? tx - self->base_tx : 0;
  self->rx_bytes = rx >= self->base_rx ? rx - self->base_rx : 0;
}

static FlValue* health_value(const gchar* host) {
  const gboolean l1 = ping_cpe(host);
  const gboolean l3 = l1 && l3_probe();
  FlValue* value = fl_value_new_map();
  fl_value_set_string_take(value, "host", fl_value_new_string(host));
  fl_value_set_string_take(value, "reachable", fl_value_new_bool(l1));
  fl_value_set_string_take(value, "serviceReady", fl_value_new_bool(l1));
  fl_value_set_string_take(
      value, "error",
      fl_value_new_string(l1 ? (l3 ? "" : "CPE reachable but L3 probe failed")
                             : "CPE ping failed"));
  return value;
}

static FlValue* status_value(MyApplication* self,
                             const gchar* host,
                             const gchar* forced_state = nullptr,
                             const gchar* last_error = "") {
  update_traffic(self);
  const gboolean running = half_routes_present(host);
  self->tun_running = forced_state == nullptr ? running
                                              : g_strcmp0(forced_state, "running") == 0;
  FlValue* value = fl_value_new_map();
  fl_value_set_string_take(
      value, "state",
      fl_value_new_string(forced_state != nullptr
                              ? forced_state
                              : (running ? "running" : "stopped")));
  fl_value_set_string_take(value, "adapterName",
                           fl_value_new_string(kLinuxAdapterName));
  fl_value_set_string_take(value, "permission", fl_value_new_string("ready"));
  fl_value_set_string_take(value, "cpe", health_value(host));
  fl_value_set_string_take(value, "helperInstalled", fl_value_new_bool(TRUE));
  fl_value_set_string_take(value, "txBytes",
                           fl_value_new_int(static_cast<gint64>(self->tx_bytes)));
  fl_value_set_string_take(value, "rxBytes",
                           fl_value_new_int(static_cast<gint64>(self->rx_bytes)));
  fl_value_set_string_take(value, "txRate",
                           fl_value_new_int(static_cast<gint64>(self->tx_rate)));
  fl_value_set_string_take(value, "rxRate",
                           fl_value_new_int(static_cast<gint64>(self->rx_rate)));
  fl_value_set_string_take(value, "txPackets", fl_value_new_int(0));
  fl_value_set_string_take(value, "rxPackets", fl_value_new_int(0));
  fl_value_set_string_take(value, "txDropped", fl_value_new_int(0));
  fl_value_set_string_take(value, "rxDropped", fl_value_new_int(0));
  fl_value_set_string_take(value, "natMisses", fl_value_new_int(0));
  fl_value_set_string_take(value, "sendFailures", fl_value_new_int(0));
  fl_value_set_string_take(value, "udp443Packets", fl_value_new_int(0));
  fl_value_set_string_take(value, "lastError",
                           fl_value_new_string(last_error == nullptr ? "" : last_error));
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

static FlValue* logs_value(int limit) {
  FlValue* list = fl_value_new_list();
  gchar* content = nullptr;
  gsize length = 0;
  if (!g_file_get_contents(kLogPath, &content, &length, nullptr) ||
      content == nullptr) {
    return list;
  }
  gchar** lines = g_strsplit(content, "\n", -1);
  g_free(content);
  int count = 0;
  for (int i = 0; lines[i] != nullptr; ++i) {
    if (lines[i][0] != '\0') {
      count++;
    }
  }
  const int start = count > limit ? count - limit : 0;
  int seen = 0;
  for (int i = 0; lines[i] != nullptr; ++i) {
    if (lines[i][0] == '\0') {
      continue;
    }
    if (seen++ < start) {
      continue;
    }
    FlValue* item = fl_value_new_map();
    gchar time[20] = {};
    strncpy(time, lines[i], 19);
    const gchar* message = strlen(lines[i]) > 20 ? lines[i] + 20 : "";
    fl_value_set_string_take(item, "time", fl_value_new_string(time));
    fl_value_set_string_take(item, "message", fl_value_new_string(message));
    fl_value_append_take(list, item);
  }
  g_strfreev(lines);
  return list;
}

static int limit_from_call(FlMethodCall* method_call, int fallback) {
  FlValue* args = fl_method_call_get_args(method_call);
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
  FlValue* value = fl_value_lookup_string(args, "limit");
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_INT) {
    return fallback;
  }
  return std::max(1, std::min(static_cast<int>(fl_value_get_int(value)), 300));
}

static FlValue* connections_value(int limit) {
  FlValue* list = fl_value_new_list();
  g_autofree gchar* output = run_command_capture("ss -tunp 2>/dev/null");
  gchar** lines = g_strsplit(output, "\n", -1);
  g_autoptr(GDateTime) now = g_date_time_new_now_local();
  g_autofree gchar* time = g_date_time_format(now, "%Y-%m-%d %H:%M:%S");
  int added = 0;
  for (int i = 0; lines[i] != nullptr && added < limit; ++i) {
    gchar** parts = g_strsplit_set(lines[i], " \t", -1);
    std::vector<const gchar*> tokens;
    for (int j = 0; parts[j] != nullptr; ++j) {
      if (parts[j][0] != '\0') {
        tokens.push_back(parts[j]);
      }
    }
    if (tokens.size() < 6) {
      g_strfreev(parts);
      continue;
    }
    const gboolean tcp = g_strcmp0(tokens[0], "tcp") == 0;
    const gboolean udp = g_strcmp0(tokens[0], "udp") == 0;
    if (!tcp && !udp) {
      g_strfreev(parts);
      continue;
    }
    const gchar* source = tokens[4];
    const gchar* target = tokens[5];
    FlValue* item = fl_value_new_map();
    fl_value_set_string_take(item, "lastSeen", fl_value_new_string(time));
    fl_value_set_string_take(item, "proto",
                             fl_value_new_string(tcp ? "TCP" : "UDP"));
    fl_value_set_string_take(item, "source", fl_value_new_string(source));
    fl_value_set_string_take(item, "target", fl_value_new_string(target));
    fl_value_set_string_take(item, "domain", fl_value_new_string(""));
    fl_value_set_string_take(item, "via", fl_value_new_string(target));
    fl_value_set_string_take(item, "txBytes", fl_value_new_int(0));
    fl_value_set_string_take(item, "rxBytes", fl_value_new_int(0));
    fl_value_set_string_take(item, "txRate", fl_value_new_int(0));
    fl_value_set_string_take(item, "rxRate", fl_value_new_int(0));
    fl_value_set_string_take(item, "dnsRedirect", fl_value_new_bool(FALSE));
    fl_value_append_take(list, item);
    g_strfreev(parts);
    added++;
  }
  g_strfreev(lines);
  return list;
}

static FlValue* start_acceleration(MyApplication* self, const gchar* host) {
  reset_traffic_baseline(self);
  gchar* error = nullptr;
  if (!apply_half_routes(host, &error)) {
    FlValue* result = status_value(self, host, "failed", error);
    g_free(error);
    return result;
  }
  append_log("开启半路由");
  self->tun_running = TRUE;
  return status_value(self, host, "running", "");
}

static FlValue* stop_acceleration(MyApplication* self, const gchar* host) {
  gchar* error = nullptr;
  remove_half_routes(&error);
  if (error != nullptr) {
    FlValue* result = status_value(self, host, "failed", error);
    g_free(error);
    return result;
  }
  append_log("关闭半路由");
  self->tun_running = FALSE;
  return status_value(self, host, "stopped", "");
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
      self->tun_running ? stop_acceleration(self, last_cpe_host(self))
                        : start_acceleration(self, last_cpe_host(self));
  update_tun_state_from_status(self, result);
  update_tray_icon(self);
}

static void stop_acceleration_before_exit(MyApplication* self) {
  if (self == nullptr || !self->tun_running) {
    return;
  }
  g_autoptr(FlValue) result = stop_acceleration(self, last_cpe_host(self));
  update_tun_state_from_status(self, result);
  update_tray_icon(self);
}

static void tray_quit_cb(GtkMenuItem* item, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  stop_acceleration_before_exit(self);
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
    g_autoptr(FlValue) result = status_value(self, host);
    update_tun_state_from_status(self, result);
    update_tray_icon(self);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "healthCheck") == 0) {
    g_autoptr(FlValue) result = health_value(host);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "logs") == 0) {
    g_autoptr(FlValue) result = logs_value(limit_from_call(method_call, 80));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "connections") == 0) {
    g_autoptr(FlValue) result =
        connections_value(limit_from_call(method_call, 80));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "installHelper") == 0) {
    g_autoptr(FlValue) result = status_value(self, host, "stopped", "");
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "uninstallHelper") == 0) {
    g_autoptr(FlValue) result = stop_acceleration(self, host);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "start") == 0) {
    g_autoptr(FlValue) result = start_acceleration(self, host);
    update_tun_state_from_status(self, result);
    update_tray_icon(self);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "stop") == 0) {
    g_autoptr(FlValue) result = stop_acceleration(self, host);
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
    g_warning("Failed to send half-route response: %s", error->message);
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
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

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
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  stop_acceleration_before_exit(self);

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
  reset_traffic_baseline(self);
}

MyApplication* my_application_new() {
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
