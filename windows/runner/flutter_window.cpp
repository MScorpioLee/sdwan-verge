#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>
#include <variant>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr char kTunChannelName[] = "sdwan_client/tun";
constexpr char kDefaultCpeHost[] = "192.168.1.140";

std::string CpeHostFromArgs(const flutter::EncodableValue* args) {
  if (!args) {
    return kDefaultCpeHost;
  }
  const auto* map = std::get_if<flutter::EncodableMap>(args);
  if (!map) {
    return kDefaultCpeHost;
  }
  const auto entry = map->find(flutter::EncodableValue("cpeHost"));
  if (entry == map->end()) {
    return kDefaultCpeHost;
  }
  const auto* host = std::get_if<std::string>(&entry->second);
  if (!host || host->empty()) {
    return kDefaultCpeHost;
  }
  return *host;
}

flutter::EncodableValue EmptyList() {
  return flutter::EncodableValue(flutter::EncodableList{});
}

flutter::EncodableValue UnavailableHealth(const std::string& host) {
  return flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("host"), flutter::EncodableValue(host)},
      {flutter::EncodableValue("reachable"), flutter::EncodableValue(false)},
      {flutter::EncodableValue("serviceReady"), flutter::EncodableValue(false)},
      {flutter::EncodableValue("error"),
       flutter::EncodableValue("TUN native service is not wired yet")},
  });
}

flutter::EncodableValue UnsupportedStatus(
    const std::string& state = "stopped",
    const std::string& message = "Windows Wintun backend is not wired yet",
    const std::string& host = kDefaultCpeHost) {
  return flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("state"), flutter::EncodableValue(state)},
      {flutter::EncodableValue("permission"),
       flutter::EncodableValue("unsupported")},
      {flutter::EncodableValue("cpe"), UnavailableHealth(host)},
      {flutter::EncodableValue("helperInstalled"), flutter::EncodableValue(false)},
      {flutter::EncodableValue("txBytes"), flutter::EncodableValue(0)},
      {flutter::EncodableValue("rxBytes"), flutter::EncodableValue(0)},
      {flutter::EncodableValue("txRate"), flutter::EncodableValue(0)},
      {flutter::EncodableValue("rxRate"), flutter::EncodableValue(0)},
      {flutter::EncodableValue("lastError"), flutter::EncodableValue(message)},
  });
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  tun_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kTunChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  tun_channel_->SetMethodCallHandler([](const auto& call, auto result) {
    const std::string& method = call.method_name();
    const std::string host = CpeHostFromArgs(call.arguments());
    if (method == "status") {
      result->Success(UnsupportedStatus("stopped",
                                        "Windows Wintun backend is not wired yet",
                                        host));
    } else if (method == "healthCheck") {
      result->Success(UnavailableHealth(host));
    } else if (method == "logs" || method == "connections") {
      result->Success(EmptyList());
    } else if (method == "installHelper") {
      result->Success(UnsupportedStatus(
          "failed", "Windows Wintun backend is not wired yet", host));
    } else if (method == "uninstallHelper") {
      result->Success(UnsupportedStatus("stopped",
                                        "Windows Wintun backend is not wired yet",
                                        host));
    } else if (method == "start") {
      result->Success(UnsupportedStatus(
          "failed", "Windows Wintun backend is not wired yet", host));
    } else if (method == "stop") {
      result->Success(UnsupportedStatus("stopped",
                                        "Windows Wintun backend is not wired yet",
                                        host));
    } else if (method == "launchAtLoginStatus" ||
               method == "setLaunchAtLogin") {
      result->Success(flutter::EncodableValue(false));
    } else {
      result->NotImplemented();
    }
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  tun_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
