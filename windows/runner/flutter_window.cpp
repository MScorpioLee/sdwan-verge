#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <windows.h>

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <map>
#include <optional>
#include <sstream>
#include <string>
#include <variant>
#include <vector>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr char kTunChannelName[] = "sdwan_client/tun";
constexpr char kDefaultCpeHost[] = "192.168.1.140";
std::string g_last_cpe_host = kDefaultCpeHost;

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

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }
  const int size =
      MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr, 0);
  if (size <= 0) {
    return std::wstring();
  }
  std::wstring out(static_cast<size_t>(size - 1), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, out.data(), size);
  return out;
}

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) {
    return std::string();
  }
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, nullptr,
                                       0, nullptr, nullptr);
  if (size <= 0) {
    return std::string();
  }
  std::string out(static_cast<size_t>(size - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, out.data(), size, nullptr,
                      nullptr);
  return out;
}

std::wstring RunnerDir() {
  wchar_t path[MAX_PATH] = {};
  GetModuleFileNameW(nullptr, path, MAX_PATH);
  std::wstring value(path);
  const size_t slash = value.find_last_of(L"\\/");
  if (slash == std::wstring::npos) {
    return L".";
  }
  return value.substr(0, slash);
}

std::wstring HelperPath() {
  return RunnerDir() + L"\\sdwan_windows_helper.exe";
}

std::wstring ExePath() {
  wchar_t path[MAX_PATH] = {};
  GetModuleFileNameW(nullptr, path, MAX_PATH);
  return path;
}

std::wstring Quote(const std::wstring& value) {
  return L"\"" + value + L"\"";
}

std::string RunHelper(const std::wstring& arguments) {
  SECURITY_ATTRIBUTES security_attributes = {};
  security_attributes.nLength = sizeof(security_attributes);
  security_attributes.bInheritHandle = TRUE;
  security_attributes.lpSecurityDescriptor = nullptr;

  HANDLE read_pipe = nullptr;
  HANDLE write_pipe = nullptr;
  if (!CreatePipe(&read_pipe, &write_pipe, &security_attributes, 0)) {
    return "state=failed\npermission=denied\nlastError=failed to create pipe\n";
  }
  SetHandleInformation(read_pipe, HANDLE_FLAG_INHERIT, 0);

  STARTUPINFOW startup = {};
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESTDHANDLES;
  startup.hStdOutput = write_pipe;
  startup.hStdError = write_pipe;
  startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);

  PROCESS_INFORMATION process = {};
  std::wstring command = Quote(HelperPath()) + L" " + arguments;
  BOOL ok = CreateProcessW(nullptr, command.data(), nullptr, nullptr, TRUE,
                           CREATE_NO_WINDOW, nullptr, RunnerDir().c_str(),
                           &startup, &process);
  CloseHandle(write_pipe);
  if (!ok) {
    CloseHandle(read_pipe);
    return "state=stopped\nadapterName=Windows Half Route\n"
           "permission=needsHelperInstall\nhelperInstalled=false\n"
           "lastError=helper executable not found or service unavailable\n";
  }

  std::string output;
  char buffer[4096] = {};
  DWORD read = 0;
  while (ReadFile(read_pipe, buffer, sizeof(buffer), &read, nullptr) &&
         read > 0) {
    output.append(buffer, buffer + read);
  }
  WaitForSingleObject(process.hProcess, 30000);
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  CloseHandle(read_pipe);
  return output;
}

bool RunHelperElevated(const std::wstring& arguments) {
  SHELLEXECUTEINFOW exec = {};
  exec.cbSize = sizeof(exec);
  exec.fMask = SEE_MASK_NOCLOSEPROCESS;
  exec.lpVerb = L"runas";
  exec.lpFile = HelperPath().c_str();
  exec.lpParameters = arguments.c_str();
  exec.lpDirectory = RunnerDir().c_str();
  exec.nShow = SW_HIDE;
  if (!ShellExecuteExW(&exec)) {
    return false;
  }
  WaitForSingleObject(exec.hProcess, INFINITE);
  DWORD exit_code = 1;
  GetExitCodeProcess(exec.hProcess, &exit_code);
  CloseHandle(exec.hProcess);
  return exit_code == 0;
}

std::map<std::string, std::string> ParseKeyValueLines(const std::string& text) {
  std::map<std::string, std::string> values;
  std::istringstream stream(text);
  std::string line;
  while (std::getline(stream, line)) {
    if (!line.empty() && line.back() == '\r') {
      line.pop_back();
    }
    const size_t equals = line.find('=');
    if (equals == std::string::npos) {
      continue;
    }
    values[line.substr(0, equals)] = line.substr(equals + 1);
  }
  return values;
}

std::map<std::string, std::string> ParsePipeFields(const std::string& line) {
  std::map<std::string, std::string> values;
  size_t start = 0;
  while (start <= line.size()) {
    size_t end = line.find('|', start);
    if (end == std::string::npos) {
      end = line.size();
    }
    const std::string part = line.substr(start, end - start);
    const size_t equals = part.find('=');
    if (equals != std::string::npos) {
      values[part.substr(0, equals)] = part.substr(equals + 1);
    }
    if (end == line.size()) {
      break;
    }
    start = end + 1;
  }
  return values;
}

int64_t IntValue(const std::map<std::string, std::string>& values,
                 const std::string& key) {
  const auto entry = values.find(key);
  if (entry == values.end()) {
    return 0;
  }
  return _atoi64(entry->second.c_str());
}

bool BoolValue(const std::map<std::string, std::string>& values,
               const std::string& key) {
  const auto entry = values.find(key);
  return entry != values.end() && entry->second == "true";
}

std::string StringValue(const std::map<std::string, std::string>& values,
                        const std::string& key,
                        const std::string& fallback = "") {
  const auto entry = values.find(key);
  return entry == values.end() ? fallback : entry->second;
}

flutter::EncodableValue HealthFromValues(
    const std::map<std::string, std::string>& values,
    const std::string& host) {
  return flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("host"), flutter::EncodableValue(host)},
      {flutter::EncodableValue("reachable"),
       flutter::EncodableValue(BoolValue(values, "reachable"))},
      {flutter::EncodableValue("serviceReady"),
       flutter::EncodableValue(BoolValue(values, "serviceReady"))},
      {flutter::EncodableValue("error"),
       flutter::EncodableValue(StringValue(values, "lastError"))},
  });
}

flutter::EncodableValue StatusFromText(const std::string& text,
                                       const std::string& requested_host) {
  const auto values = ParseKeyValueLines(text);
  const std::string host = StringValue(values, "host", requested_host);
  return flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("state"),
       flutter::EncodableValue(StringValue(values, "state", "stopped"))},
      {flutter::EncodableValue("adapterName"),
       flutter::EncodableValue(StringValue(values, "adapterName",
                                           "Windows Half Route"))},
      {flutter::EncodableValue("permission"),
       flutter::EncodableValue(StringValue(values, "permission",
                                           "needsHelperInstall"))},
      {flutter::EncodableValue("cpe"), HealthFromValues(values, host)},
      {flutter::EncodableValue("helperInstalled"),
       flutter::EncodableValue(BoolValue(values, "helperInstalled"))},
      {flutter::EncodableValue("txBytes"),
       flutter::EncodableValue(IntValue(values, "txBytes"))},
      {flutter::EncodableValue("rxBytes"),
       flutter::EncodableValue(IntValue(values, "rxBytes"))},
      {flutter::EncodableValue("txRate"),
       flutter::EncodableValue(IntValue(values, "txRate"))},
      {flutter::EncodableValue("rxRate"),
       flutter::EncodableValue(IntValue(values, "rxRate"))},
      {flutter::EncodableValue("txPackets"),
       flutter::EncodableValue(IntValue(values, "txPackets"))},
      {flutter::EncodableValue("rxPackets"),
       flutter::EncodableValue(IntValue(values, "rxPackets"))},
      {flutter::EncodableValue("txDropped"),
       flutter::EncodableValue(IntValue(values, "txDropped"))},
      {flutter::EncodableValue("rxDropped"),
       flutter::EncodableValue(IntValue(values, "rxDropped"))},
      {flutter::EncodableValue("natMisses"),
       flutter::EncodableValue(IntValue(values, "natMisses"))},
      {flutter::EncodableValue("sendFailures"),
       flutter::EncodableValue(IntValue(values, "sendFailures"))},
      {flutter::EncodableValue("udp443Packets"),
       flutter::EncodableValue(IntValue(values, "udp443Packets"))},
      {flutter::EncodableValue("lastError"),
       flutter::EncodableValue(StringValue(values, "lastError"))},
  });
}

flutter::EncodableValue LogsFromText(const std::string& text) {
  flutter::EncodableList logs;
  std::istringstream stream(text);
  std::string line;
  while (std::getline(stream, line)) {
    if (!line.empty() && line.back() == '\r') {
      line.pop_back();
    }
    if (line.empty()) {
      continue;
    }
    const auto values = ParsePipeFields(line);
    logs.push_back(flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("time"),
         flutter::EncodableValue(StringValue(values, "time"))},
        {flutter::EncodableValue("message"),
         flutter::EncodableValue(StringValue(values, "message"))},
    }));
  }
  return flutter::EncodableValue(logs);
}

flutter::EncodableValue ConnectionsFromText(const std::string& text) {
  flutter::EncodableList connections;
  std::istringstream stream(text);
  std::string line;
  while (std::getline(stream, line)) {
    if (!line.empty() && line.back() == '\r') {
      line.pop_back();
    }
    if (line.empty()) {
      continue;
    }
    const auto values = ParsePipeFields(line);
    connections.push_back(flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("lastSeen"),
         flutter::EncodableValue(StringValue(values, "lastSeen"))},
        {flutter::EncodableValue("proto"),
         flutter::EncodableValue(StringValue(values, "proto"))},
        {flutter::EncodableValue("source"),
         flutter::EncodableValue(StringValue(values, "source"))},
        {flutter::EncodableValue("target"),
         flutter::EncodableValue(StringValue(values, "target"))},
        {flutter::EncodableValue("domain"),
         flutter::EncodableValue(StringValue(values, "domain"))},
        {flutter::EncodableValue("via"),
         flutter::EncodableValue(StringValue(values, "via"))},
        {flutter::EncodableValue("txBytes"),
         flutter::EncodableValue(IntValue(values, "txBytes"))},
        {flutter::EncodableValue("rxBytes"),
         flutter::EncodableValue(IntValue(values, "rxBytes"))},
        {flutter::EncodableValue("txRate"),
         flutter::EncodableValue(IntValue(values, "txRate"))},
        {flutter::EncodableValue("rxRate"),
         flutter::EncodableValue(IntValue(values, "rxRate"))},
        {flutter::EncodableValue("dnsRedirect"),
         flutter::EncodableValue(BoolValue(values, "dnsRedirect"))},
    }));
  }
  return flutter::EncodableValue(connections);
}

std::wstring HelperArgs(const std::wstring& method, const std::string& host,
                        int limit = 0) {
  std::wstring args = method;
  if (!host.empty()) {
    args += L" --cpe " + Utf8ToWide(host);
  }
  if (limit > 0) {
    args += L" --limit " + std::to_wstring(limit);
  }
  return args;
}

int LimitFromArgs(const flutter::EncodableValue* args, int fallback) {
  if (!args) {
    return fallback;
  }
  const auto* map = std::get_if<flutter::EncodableMap>(args);
  if (!map) {
    return fallback;
  }
  const auto entry = map->find(flutter::EncodableValue("limit"));
  if (entry == map->end()) {
    return fallback;
  }
  if (const auto* value = std::get_if<int>(&entry->second)) {
    return *value;
  }
  if (const auto* value = std::get_if<int64_t>(&entry->second)) {
    return static_cast<int>(*value);
  }
  return fallback;
}

bool LaunchAtLoginEnabled() {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER,
                    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0,
                    KEY_READ, &key) != ERROR_SUCCESS) {
    return false;
  }
  wchar_t value[MAX_PATH] = {};
  DWORD size = sizeof(value);
  const LONG result =
      RegQueryValueExW(key, L"SD-WAN Verge", nullptr, nullptr,
                       reinterpret_cast<LPBYTE>(value), &size);
  RegCloseKey(key);
  return result == ERROR_SUCCESS;
}

bool SetLaunchAtLogin(bool enabled) {
  HKEY key = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER,
                      L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0,
                      nullptr, 0, KEY_SET_VALUE, nullptr, &key,
                      nullptr) != ERROR_SUCCESS) {
    return false;
  }
  LONG result = ERROR_SUCCESS;
  if (enabled) {
    const std::wstring value = Quote(ExePath());
    result = RegSetValueExW(key, L"SD-WAN Verge", 0, REG_SZ,
                            reinterpret_cast<const BYTE*>(value.c_str()),
                            static_cast<DWORD>((value.size() + 1) *
                                                sizeof(wchar_t)));
  } else {
    result = RegDeleteValueW(key, L"SD-WAN Verge");
    if (result == ERROR_FILE_NOT_FOUND) {
      result = ERROR_SUCCESS;
    }
  }
  RegCloseKey(key);
  return result == ERROR_SUCCESS;
}

bool BoolArg(const flutter::EncodableValue* args, const std::string& key,
             bool fallback) {
  if (!args) {
    return fallback;
  }
  const auto* map = std::get_if<flutter::EncodableMap>(args);
  if (!map) {
    return fallback;
  }
  const auto entry = map->find(flutter::EncodableValue(key));
  if (entry == map->end()) {
    return fallback;
  }
  const auto* value = std::get_if<bool>(&entry->second);
  return value == nullptr ? fallback : *value;
}

bool IsAccelerationRunning() {
  const auto values =
      ParseKeyValueLines(RunHelper(HelperArgs(L"status", g_last_cpe_host)));
  const std::string state = StringValue(values, "state", "stopped");
  return state == "running" || state == "starting";
}

void ToggleAccelerationFromTray() {
  if (IsAccelerationRunning()) {
    RunHelper(HelperArgs(L"stop", g_last_cpe_host));
  } else {
    RunHelper(HelperArgs(L"start", g_last_cpe_host));
  }
}

bool g_stop_before_exit_called = false;

void StopAccelerationBeforeExit() {
  if (g_stop_before_exit_called) {
    return;
  }
  g_stop_before_exit_called = true;
  RunHelper(HelperArgs(L"stop", g_last_cpe_host));
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
  SetTrayAccelerationHandlers(IsAccelerationRunning, ToggleAccelerationFromTray,
                              StopAccelerationBeforeExit);
  tun_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    const std::string& method = call.method_name();
    const std::string host = CpeHostFromArgs(call.arguments());
    g_last_cpe_host = host;
    if (method == "status") {
      const auto status =
          StatusFromText(RunHelper(HelperArgs(L"status", host)), host);
      RefreshTrayIcon();
      result->Success(status);
    } else if (method == "healthCheck") {
      const auto values =
          ParseKeyValueLines(RunHelper(HelperArgs(L"health", host)));
      result->Success(HealthFromValues(values, host));
    } else if (method == "logs") {
      const int limit = LimitFromArgs(call.arguments(), 80);
      result->Success(LogsFromText(RunHelper(HelperArgs(L"logs", host, limit))));
    } else if (method == "connections") {
      const int limit = LimitFromArgs(call.arguments(), 80);
      result->Success(
          ConnectionsFromText(RunHelper(HelperArgs(L"connections", host, limit))));
    } else if (method == "installHelper") {
      const bool ok = RunHelperElevated(L"install");
      const std::string text = ok ? RunHelper(HelperArgs(L"status", host))
                                  : "state=failed\nadapterName=Windows Half Route\n"
                                    "permission=denied\nhelperInstalled=false\n"
                                    "lastError=helper install was cancelled\n";
      result->Success(StatusFromText(text, host));
    } else if (method == "uninstallHelper") {
      const bool ok = RunHelperElevated(L"uninstall");
      const std::string text = ok ? RunHelper(HelperArgs(L"status", host))
                                  : "state=failed\nadapterName=Windows Half Route\n"
                                    "permission=denied\nhelperInstalled=true\n"
                                    "lastError=helper uninstall was cancelled\n";
      result->Success(StatusFromText(text, host));
    } else if (method == "start") {
      const auto status =
          StatusFromText(RunHelper(HelperArgs(L"start", host)), host);
      RefreshTrayIcon();
      result->Success(status);
    } else if (method == "stop") {
      const auto status =
          StatusFromText(RunHelper(HelperArgs(L"stop", host)), host);
      RefreshTrayIcon();
      result->Success(status);
    } else if (method == "launchAtLoginStatus") {
      result->Success(flutter::EncodableValue(LaunchAtLoginEnabled()));
    } else if (method == "setLaunchAtLogin") {
      result->Success(flutter::EncodableValue(
          SetLaunchAtLogin(BoolArg(call.arguments(), "enabled", false))));
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
  StopAccelerationBeforeExit();
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
