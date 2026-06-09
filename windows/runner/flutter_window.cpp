#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <windows.h>

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <map>
#include <optional>
#include <shlobj.h>
#include <shellapi.h>
#include <sstream>
#include <string>
#include <variant>
#include <vector>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr char kTunChannelName[] = "sdwan_client/tun";
constexpr char kDefaultCpeHost[] = "192.168.1.140";
constexpr ULONGLONG kOpenVpnConnectionsCacheMs = 15000;
std::string g_last_cpe_host = kDefaultCpeHost;
std::string g_last_mode = "openvpn";
bool g_last_sync_dns = false;
std::optional<flutter::EncodableValue> g_last_openvpn_args;
int64_t g_openvpn_last_tx_bytes = 0;
int64_t g_openvpn_last_rx_bytes = 0;
ULONGLONG g_openvpn_last_traffic_tick = 0;
std::string g_openvpn_cached_connections_text;
ULONGLONG g_openvpn_connections_cache_tick = 0;

std::string StringArg(const flutter::EncodableValue* args,
                      const std::string& key,
                      const std::string& fallback) {
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
  const auto* host = std::get_if<std::string>(&entry->second);
  if (!host || host->empty()) {
    return fallback;
  }
  return *host;
}

std::string CpeHostFromArgs(const flutter::EncodableValue* args) {
  return StringArg(args, "cpeHost", kDefaultCpeHost);
}

std::string ModeFromArgs(const flutter::EncodableValue* args) {
  std::string mode = StringArg(args, "mode", "halfRoute");
  std::string normalized = mode;
  std::transform(normalized.begin(), normalized.end(), normalized.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  normalized.erase(
      std::remove_if(normalized.begin(), normalized.end(),
                     [](char c) { return c == '_' || c == '-'; }),
      normalized.end());
  return normalized == "openvpn" ? "openvpn" : mode;
}

std::string OpenVpnRemoteHostFromArgs(const flutter::EncodableValue* args,
                                      const std::string& fallback_host) {
  return StringArg(args, "openvpnRemoteHost", fallback_host);
}

bool BoolArg(const flutter::EncodableValue* args, const std::string& key,
             bool fallback);

int OpenVpnRemotePortFromArgs(const flutter::EncodableValue* args) {
  if (!args) {
    return 1194;
  }
  const auto* map = std::get_if<flutter::EncodableMap>(args);
  if (!map) {
    return 1194;
  }
  const auto entry = map->find(flutter::EncodableValue("openvpnRemotePort"));
  if (entry == map->end()) {
    return 1194;
  }
  if (const auto* value = std::get_if<int>(&entry->second)) {
    return *value;
  }
  if (const auto* value = std::get_if<int64_t>(&entry->second)) {
    return static_cast<int>(*value);
  }
  return 1194;
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

std::string RunCommandCapture(const std::string& command) {
  SECURITY_ATTRIBUTES security_attributes = {};
  security_attributes.nLength = sizeof(security_attributes);
  security_attributes.bInheritHandle = TRUE;
  security_attributes.lpSecurityDescriptor = nullptr;

  HANDLE read_pipe = nullptr;
  HANDLE write_pipe = nullptr;
  if (!CreatePipe(&read_pipe, &write_pipe, &security_attributes, 0)) {
    return {};
  }
  SetHandleInformation(read_pipe, HANDLE_FLAG_INHERIT, 0);

  STARTUPINFOW startup = {};
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESTDHANDLES;
  startup.hStdOutput = write_pipe;
  startup.hStdError = write_pipe;
  startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);

  PROCESS_INFORMATION process = {};
  std::wstring command_line = L"cmd.exe /C " + Utf8ToWide(command);
  BOOL ok = CreateProcessW(nullptr, command_line.data(), nullptr, nullptr, TRUE,
                           CREATE_NO_WINDOW, nullptr, nullptr, &startup,
                           &process);
  CloseHandle(write_pipe);
  if (!ok) {
    CloseHandle(read_pipe);
    return {};
  }

  std::string output;
  char buffer[4096] = {};
  DWORD read = 0;
  while (ReadFile(read_pipe, buffer, sizeof(buffer), &read, nullptr) &&
         read > 0) {
    output.append(buffer, buffer + read);
  }
  WaitForSingleObject(process.hProcess, 10000);
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

std::string NowString() {
  SYSTEMTIME st = {};
  GetLocalTime(&st);
  char buffer[32] = {};
  snprintf(buffer, sizeof(buffer), "%04u-%02u-%02u %02u:%02u:%02u", st.wYear,
           st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);
  return buffer;
}

std::vector<std::string> SplitWhitespace(const std::string& value) {
  std::istringstream stream(value);
  std::vector<std::string> parts;
  std::string part;
  while (stream >> part) {
    parts.push_back(part);
  }
  return parts;
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

std::wstring OpenVpnRuntimeDir() {
  wchar_t local_app_data[MAX_PATH] = {};
  if (SUCCEEDED(SHGetFolderPathW(nullptr, CSIDL_LOCAL_APPDATA, nullptr,
                                 SHGFP_TYPE_CURRENT, local_app_data))) {
    std::wstring dir(local_app_data);
    dir += L"\\SD-WAN Verge\\OpenVPN";
    CreateDirectoryW((std::wstring(local_app_data) + L"\\SD-WAN Verge").c_str(),
                     nullptr);
    CreateDirectoryW(dir.c_str(), nullptr);
    return dir;
  }
  std::wstring dir = RunnerDir() + L"\\openvpn-runtime";
  CreateDirectoryW(dir.c_str(), nullptr);
  return dir;
}

std::wstring OpenVpnConfigPath() {
  return OpenVpnRuntimeDir() + L"\\client.ovpn";
}

std::wstring OpenVpnAuthPath() {
  return OpenVpnRuntimeDir() + L"\\auth.txt";
}

std::wstring OpenVpnPidPath() {
  return OpenVpnRuntimeDir() + L"\\openvpn.pid";
}

std::wstring OpenVpnLogPath() {
  return OpenVpnRuntimeDir() + L"\\openvpn.log";
}

std::wstring OpenVpnStatusPath() {
  return OpenVpnRuntimeDir() + L"\\openvpn.status";
}

bool FileExists(const std::wstring& path) {
  const DWORD attributes = GetFileAttributesW(path.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES &&
         !(attributes & FILE_ATTRIBUTE_DIRECTORY);
}

std::wstring FindOpenVpnBinary();

std::wstring BundledOpenVpnPath() {
  return RunnerDir() + L"\\openvpn\\bin\\openvpn.exe";
}

std::wstring FindBundledOpenVpnInstaller() {
  const std::wstring installer_dir = RunnerDir() + L"\\openvpn\\installer\\";
  const std::wstring pattern = installer_dir + L"OpenVPN-*.msi";
  WIN32_FIND_DATAW data = {};
  HANDLE find = FindFirstFileW(pattern.c_str(), &data);
  if (find == INVALID_HANDLE_VALUE) {
    return L"";
  }
  std::wstring installer = installer_dir + data.cFileName;
  FindClose(find);
  return installer;
}

bool CommandOutputLooksSuccessful(const std::string& output) {
  return output.find("SERVICE_NAME") != std::string::npos ||
         output.find("STATE") != std::string::npos;
}

bool WindowsDriverServiceExists(const std::string& service_name) {
  return CommandOutputLooksSuccessful(RunCommandCapture("sc query " + service_name));
}

bool OpenVpnDriverReady() {
  if (FileExists(RunnerDir() + L"\\openvpn\\bin\\wintun.dll")) {
    return true;
  }
  return WindowsDriverServiceExists("ovpn-dco") ||
         WindowsDriverServiceExists("tap0901") ||
         WindowsDriverServiceExists("Wintun");
}

bool OpenVpnDependenciesReady() {
  return !FindOpenVpnBinary().empty() && OpenVpnDriverReady();
}

std::string OpenVpnDependencyError() {
  if (FindOpenVpnBinary().empty()) {
    return "未找到 OpenVPN CLI，请安装 OpenVPN 或使用随包版本";
  }
  if (!OpenVpnDriverReady()) {
    return "OpenVPN TUN 驱动未安装，请先安装 OpenVPN 组件后再开启加速";
  }
  return "";
}

std::wstring FindOpenVpnBinary() {
  wchar_t env[MAX_PATH] = {};
  if (GetEnvironmentVariableW(L"SDWAN_OPENVPN_PATH", env, MAX_PATH) > 0 &&
      FileExists(env)) {
    return env;
  }
  const std::wstring bundled = BundledOpenVpnPath();
  if (FileExists(bundled)) {
    return bundled;
  }
  std::vector<std::wstring> roots;
  wchar_t program_files[MAX_PATH] = {};
  if (SHGetFolderPathW(nullptr, CSIDL_PROGRAM_FILES, nullptr,
                       SHGFP_TYPE_CURRENT, program_files) == S_OK) {
    roots.push_back(program_files);
  }
  wchar_t program_files_x86[MAX_PATH] = {};
  if (SHGetFolderPathW(nullptr, CSIDL_PROGRAM_FILESX86, nullptr,
                       SHGFP_TYPE_CURRENT, program_files_x86) == S_OK) {
    roots.push_back(program_files_x86);
  }
  for (const auto& root : roots) {
    for (const auto& candidate : {
             root + L"\\OpenVPN\\bin\\openvpn.exe",
             root + L"\\OpenVPN\\bin\\openvpn.exe",
         }) {
      if (FileExists(candidate)) {
        return candidate;
      }
    }
  }
  return L"";
}

DWORD OpenVpnPid() {
  std::ifstream file(OpenVpnPidPath());
  DWORD pid = 0;
  file >> pid;
  return pid;
}

bool OpenVpnPidRunning() {
  const DWORD pid = OpenVpnPid();
  if (pid == 0) {
    return false;
  }
  HANDLE process = OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION,
                               FALSE, pid);
  if (!process) {
    return false;
  }
  const DWORD wait = WaitForSingleObject(process, 0);
  CloseHandle(process);
  return wait == WAIT_TIMEOUT;
}

std::vector<std::string> StringListArg(const flutter::EncodableValue* args,
                                       const std::string& key) {
  std::vector<std::string> values;
  if (!args) {
    return values;
  }
  const auto* map = std::get_if<flutter::EncodableMap>(args);
  if (!map) {
    return values;
  }
  const auto entry = map->find(flutter::EncodableValue(key));
  if (entry == map->end()) {
    return values;
  }
  const auto* list = std::get_if<flutter::EncodableList>(&entry->second);
  if (!list) {
    return values;
  }
  for (const auto& item : *list) {
    if (const auto* text = std::get_if<std::string>(&item)) {
      values.push_back(*text);
    }
  }
  return values;
}

std::string OpenVpnConfigQuote(std::string value) {
  std::replace(value.begin(), value.end(), '\\', '/');
  std::string escaped;
  for (char c : value) {
    if (c == '"') {
      escaped += "\\\"";
    } else {
      escaped += c;
    }
  }
  return "\"" + escaped + "\"";
}

std::map<std::string, std::string> StringMapArg(
    const flutter::EncodableValue* args,
    const std::string& key) {
  std::map<std::string, std::string> values;
  if (!args) {
    return values;
  }
  const auto* map = std::get_if<flutter::EncodableMap>(args);
  if (!map) {
    return values;
  }
  const auto entry = map->find(flutter::EncodableValue(key));
  if (entry == map->end()) {
    return values;
  }
  const auto* nested = std::get_if<flutter::EncodableMap>(&entry->second);
  if (!nested) {
    return values;
  }
  for (const auto& item : *nested) {
    const auto* name = std::get_if<std::string>(&item.first);
    const auto* content = std::get_if<std::string>(&item.second);
    if (name && content && !name->empty()) {
      values[*name] = *content;
    }
  }
  return values;
}

std::string Trim(std::string value) {
  value.erase(value.begin(),
              std::find_if(value.begin(), value.end(), [](unsigned char c) {
                return !std::isspace(c);
              }));
  value.erase(std::find_if(value.rbegin(), value.rend(), [](unsigned char c) {
                return !std::isspace(c);
              }).base(),
              value.end());
  return value;
}

std::string OpenVpnDirectiveKey(const std::string& raw) {
  std::istringstream stream(raw);
  std::string key;
  stream >> key;
  std::transform(key.begin(), key.end(), key.begin(), [](unsigned char c) {
    return static_cast<char>(std::tolower(c));
  });
  return key;
}

bool IsGeneratedOpenVpnDirective(const std::string& raw) {
  const std::string key = OpenVpnDirectiveKey(raw);
  return key == "client" || key == "proto" || key == "block-outside-dns" ||
         key == "pull-filter" || key == "route-nopull";
}

std::string OpenVpnRuntimeProtocol(const flutter::EncodableValue* args) {
  const std::string protocol = StringArg(args, "openvpnProtocol", "udp4");
  if (protocol == "udp4") {
    return "udp";
  }
  return protocol;
}

bool OpenVpnConfigHasTlsTrust(const flutter::EncodableValue* args) {
  const auto blocks = StringMapArg(args, "openvpnInlineBlocks");
  const auto ca_block = blocks.find("ca");
  if (ca_block != blocks.end() && !Trim(ca_block->second).empty()) {
    return true;
  }
  for (const auto& directive : StringListArg(args, "openvpnCustomDirectives")) {
    const std::string key = OpenVpnDirectiveKey(directive);
    if (key == "ca" || key == "capath" || key == "peer-fingerprint") {
      return true;
    }
  }
  return false;
}

std::string OpenVpnConfigText(const flutter::EncodableValue* args,
                              const std::string& host) {
  std::ostringstream config;
  config << "client\n";
  const std::string tun_name = StringArg(args, "openvpnTunName", "auto");
  config << "dev " << (tun_name == "auto" ? "tun" : tun_name) << "\n";
  config << "proto " << OpenVpnRuntimeProtocol(args) << "\n";
  config << "remote " << host << " " << OpenVpnRemotePortFromArgs(args) << "\n";
  const std::string redirect =
      StringArg(args, "openvpnRedirectGateway", "def1");
  if (!redirect.empty()) {
    config << "redirect-gateway " << redirect << "\n";
  }
  if (BoolArg(args, "openvpnAuthUserPass", false)) {
    config << "auth-user-pass "
           << OpenVpnConfigQuote(WideToUtf8(OpenVpnAuthPath())) << "\n";
  }
  // The Windows test machine has OpenVPN 2.3.x, which exits before logging when
  // newer pull-filter directives are present. route-nopull is supported by 2.3
  // and keeps pushed IPv6 or extra routes out while local redirect-gateway still
  // takes over IPv4 traffic.
  if (BoolArg(args, "openvpnIpv4Only", true) ||
      BoolArg(args, "openvpnPullFilterIpv6", true)) {
    config << "route-nopull\n";
  }
  const std::string mtu = StringArg(args, "openvpnMtu", "auto");
  if (mtu != "auto") {
    config << "tun-mtu " << mtu << "\n";
  }
  const std::string mssfix = StringArg(args, "openvpnMssfix", "auto");
  if (mssfix != "auto") {
    config << "mssfix " << mssfix << "\n";
  }
  for (const auto& directive : StringListArg(args, "openvpnCustomDirectives")) {
    if (IsGeneratedOpenVpnDirective(directive)) {
      continue;
    }
    config << directive << "\n";
  }
  for (const auto& block : StringMapArg(args, "openvpnInlineBlocks")) {
    config << "<" << block.first << ">\n";
    config << block.second;
    if (!block.second.empty() && block.second.back() != '\n') {
      config << "\n";
    }
    config << "</" << block.first << ">\n";
  }
  return config.str();
}

void WriteTextFile(const std::wstring& path, const std::string& text) {
  HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr,
                            CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return;
  }
  DWORD written = 0;
  WriteFile(file, text.data(), static_cast<DWORD>(text.size()), &written,
            nullptr);
  CloseHandle(file);
}

std::string ReadTextFile(const std::wstring& path) {
  HANDLE file =
      CreateFileW(path.c_str(), GENERIC_READ,
                  FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                  nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return "";
  }
  std::string text;
  char buffer[4096] = {};
  DWORD read = 0;
  while (ReadFile(file, buffer, sizeof(buffer), &read, nullptr) && read > 0) {
    text.append(buffer, buffer + read);
  }
  CloseHandle(file);
  return text;
}

std::string OpenVpnLastError() {
  const std::string text = ReadTextFile(OpenVpnLogPath());
  std::istringstream stream(text);
  std::string line;
  std::string fallback;
  while (std::getline(stream, line)) {
    if (!line.empty() && line.back() == '\r') {
      line.pop_back();
    }
    const std::string trimmed = Trim(line);
    if (trimmed.empty()) {
      continue;
    }
    fallback = trimmed;
    if (trimmed.find("Options error:") != std::string::npos ||
        trimmed.find("AUTH_FAILED") != std::string::npos ||
        trimmed.find("TLS Error") != std::string::npos ||
        trimmed.find("ERROR:") != std::string::npos) {
      return trimmed;
    }
  }
  return fallback;
}

struct OpenVpnTrafficStats {
  int64_t txBytes = 0;
  int64_t rxBytes = 0;
  int64_t txRate = 0;
  int64_t rxRate = 0;
};

void ResetOpenVpnTrafficStats() {
  g_openvpn_last_tx_bytes = 0;
  g_openvpn_last_rx_bytes = 0;
  g_openvpn_last_traffic_tick = 0;
}

void ResetOpenVpnConnectionsCache() {
  g_openvpn_cached_connections_text.clear();
  g_openvpn_connections_cache_tick = 0;
}

OpenVpnTrafficStats ReadOpenVpnTrafficStats() {
  OpenVpnTrafficStats stats;
  const std::string text = ReadTextFile(OpenVpnStatusPath());
  std::istringstream stream(text);
  std::string line;
  while (std::getline(stream, line)) {
    if (!line.empty() && line.back() == '\r') {
      line.pop_back();
    }
    const size_t comma = line.find(',');
    if (comma == std::string::npos) {
      continue;
    }
    const std::string key = Trim(line.substr(0, comma));
    const std::string value = Trim(line.substr(comma + 1));
    if (key == "TUN/TAP read bytes") {
      stats.txBytes = _atoi64(value.c_str());
    } else if (key == "TUN/TAP write bytes") {
      stats.rxBytes = _atoi64(value.c_str());
    }
  }

  const ULONGLONG now = GetTickCount64();
  if (g_openvpn_last_traffic_tick > 0 && now > g_openvpn_last_traffic_tick) {
    const ULONGLONG elapsed = now - g_openvpn_last_traffic_tick;
    const int64_t tx_delta =
        stats.txBytes >= g_openvpn_last_tx_bytes
            ? stats.txBytes - g_openvpn_last_tx_bytes
            : 0;
    const int64_t rx_delta =
        stats.rxBytes >= g_openvpn_last_rx_bytes
            ? stats.rxBytes - g_openvpn_last_rx_bytes
            : 0;
    stats.txRate = static_cast<int64_t>(tx_delta * 1000 / elapsed);
    stats.rxRate = static_cast<int64_t>(rx_delta * 1000 / elapsed);
  }

  g_openvpn_last_tx_bytes = stats.txBytes;
  g_openvpn_last_rx_bytes = stats.rxBytes;
  g_openvpn_last_traffic_tick = now;
  return stats;
}

void PrepareOpenVpnRuntime(const flutter::EncodableValue* args,
                           const std::string& host) {
  WriteTextFile(OpenVpnConfigPath(), OpenVpnConfigText(args, host));
  const std::string username = StringArg(args, "openvpnUsername", "");
  const std::string password = StringArg(args, "openvpnPassword", "");
  if (!username.empty() || !password.empty()) {
    WriteTextFile(OpenVpnAuthPath(), username + "\n" + password + "\n");
  }
}

flutter::EncodableValue OpenVpnHealth(const std::string& host) {
  const bool has_binary = !FindOpenVpnBinary().empty();
  const bool dependencies_ready = OpenVpnDependenciesReady();
  const std::string dependency_error = OpenVpnDependencyError();
  return flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("host"), flutter::EncodableValue(host)},
      {flutter::EncodableValue("reachable"), flutter::EncodableValue(has_binary)},
      {flutter::EncodableValue("serviceReady"),
       flutter::EncodableValue(OpenVpnPidRunning() || dependencies_ready)},
      {flutter::EncodableValue("error"),
       flutter::EncodableValue(dependency_error)},
  });
}

flutter::EncodableValue OpenVpnStatus(
    const flutter::EncodableValue* args,
    const std::string& state,
    const std::string& error = "") {
  const std::string host =
      OpenVpnRemoteHostFromArgs(args, CpeHostFromArgs(args));
  const bool has_binary = !FindOpenVpnBinary().empty();
  const bool dependencies_ready = OpenVpnDependenciesReady();
  const bool running = OpenVpnPidRunning();
  const std::string actual_state =
      state.empty() ? (running ? "running" : "stopped") : state;
  const std::string last_error =
      !error.empty() ? error : (!dependencies_ready ? OpenVpnDependencyError()
                                                    : (!running ? OpenVpnLastError() : ""));
  const OpenVpnTrafficStats traffic =
      running ? ReadOpenVpnTrafficStats() : OpenVpnTrafficStats();
  if (!running) {
    ResetOpenVpnTrafficStats();
  }
  return flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("state"), flutter::EncodableValue(actual_state)},
      {flutter::EncodableValue("adapterName"),
       flutter::EncodableValue("OpenVPN")},
      {flutter::EncodableValue("permission"),
       flutter::EncodableValue(dependencies_ready ? "ready"
                                                  : (has_binary ? "needsHelperInstall"
                                                                : "unsupported"))},
      {flutter::EncodableValue("cpe"), OpenVpnHealth(host)},
      {flutter::EncodableValue("helperInstalled"),
       flutter::EncodableValue(dependencies_ready)},
      {flutter::EncodableValue("txBytes"),
       flutter::EncodableValue(traffic.txBytes)},
      {flutter::EncodableValue("rxBytes"),
       flutter::EncodableValue(traffic.rxBytes)},
      {flutter::EncodableValue("txRate"),
       flutter::EncodableValue(traffic.txRate)},
      {flutter::EncodableValue("rxRate"),
       flutter::EncodableValue(traffic.rxRate)},
      {flutter::EncodableValue("txPackets"), flutter::EncodableValue(0)},
      {flutter::EncodableValue("rxPackets"), flutter::EncodableValue(0)},
      {flutter::EncodableValue("txDropped"), flutter::EncodableValue(0)},
      {flutter::EncodableValue("rxDropped"), flutter::EncodableValue(0)},
      {flutter::EncodableValue("natMisses"), flutter::EncodableValue(0)},
      {flutter::EncodableValue("sendFailures"), flutter::EncodableValue(0)},
      {flutter::EncodableValue("udp443Packets"), flutter::EncodableValue(0)},
      {flutter::EncodableValue("lastError"),
       flutter::EncodableValue(last_error)},
  });
}

bool StartOpenVpnElevated(const flutter::EncodableValue* args,
                          const std::string& host,
                          std::string* error) {
  const std::wstring binary = FindOpenVpnBinary();
  if (binary.empty()) {
    *error = OpenVpnDependencyError();
    return false;
  }
  if (!OpenVpnDependenciesReady()) {
    *error = OpenVpnDependencyError();
    return false;
  }
  if (!OpenVpnConfigHasTlsTrust(args)) {
    *error = "OpenVPN 配置缺少服务端 CA，请重新导入完整 .ovpn 或添加 ca/capath；不需要客户端证书";
    return false;
  }
  ResetOpenVpnTrafficStats();
  ResetOpenVpnConnectionsCache();
  PrepareOpenVpnRuntime(args, host);
  const std::wstring parameters =
      L"--log " + Quote(OpenVpnLogPath()) + L" --status " +
      Quote(OpenVpnStatusPath()) + L" 10 --writepid " + Quote(OpenVpnPidPath()) +
      L" --config " + Quote(OpenVpnConfigPath());
  SHELLEXECUTEINFOW exec = {};
  exec.cbSize = sizeof(exec);
  exec.fMask = SEE_MASK_NOCLOSEPROCESS;
  exec.lpVerb = L"runas";
  exec.lpFile = binary.c_str();
  exec.lpParameters = parameters.c_str();
  exec.lpDirectory = OpenVpnRuntimeDir().c_str();
  exec.nShow = SW_HIDE;
  if (!ShellExecuteExW(&exec)) {
    *error = "OpenVPN 启动被取消或失败";
    return false;
  }
  CloseHandle(exec.hProcess);
  return true;
}

flutter::EncodableValue InstallOpenVpnDependencies(
    const flutter::EncodableValue* args) {
  const std::wstring installer = FindBundledOpenVpnInstaller();
  if (installer.empty()) {
    return OpenVpnStatus(
        args, "failed",
        "包内未包含 OpenVPN 安装器，请重新安装新版客户端或安装 OpenVPN 官方客户端");
  }
  const std::wstring parameters =
      L"/i " + Quote(installer) + L" /qn /norestart";
  SHELLEXECUTEINFOW exec = {};
  exec.cbSize = sizeof(exec);
  exec.fMask = SEE_MASK_NOCLOSEPROCESS;
  exec.lpVerb = L"runas";
  exec.lpFile = L"msiexec.exe";
  exec.lpParameters = parameters.c_str();
  exec.nShow = SW_HIDE;
  if (!ShellExecuteExW(&exec)) {
    return OpenVpnStatus(args, "failed", "OpenVPN 组件安装被取消或失败");
  }
  WaitForSingleObject(exec.hProcess, INFINITE);
  DWORD exit_code = 1;
  GetExitCodeProcess(exec.hProcess, &exit_code);
  CloseHandle(exec.hProcess);
  if (exit_code != 0 && exit_code != 3010) {
    return OpenVpnStatus(
        args, "failed",
        "OpenVPN 组件安装失败，msiexec exit=" + std::to_string(exit_code));
  }
  const std::string message =
      exit_code == 3010 ? "OpenVPN 组件已安装，系统提示需要重启后驱动完全生效" : "";
  return OpenVpnStatus(args, "stopped", message);
}

flutter::EncodableValue StartOpenVpn(const flutter::EncodableValue* args) {
  if (OpenVpnPidRunning()) {
    return OpenVpnStatus(args, "running");
  }
  const std::string host =
      OpenVpnRemoteHostFromArgs(args, CpeHostFromArgs(args));
  std::string error;
  if (!StartOpenVpnElevated(args, host, &error)) {
    return OpenVpnStatus(args, "failed", error);
  }
  Sleep(800);
  if (OpenVpnPidRunning()) {
    return OpenVpnStatus(args, "running");
  }
  error = OpenVpnLastError();
  return OpenVpnStatus(args, error.empty() ? "starting" : "failed", error);
}

flutter::EncodableValue StopOpenVpn(const flutter::EncodableValue* args) {
  const DWORD pid = OpenVpnPid();
  if (pid != 0) {
    std::wstring command = L"/C taskkill /PID " + std::to_wstring(pid) + L" /T /F";
    SHELLEXECUTEINFOW exec = {};
    exec.cbSize = sizeof(exec);
    exec.fMask = SEE_MASK_NOCLOSEPROCESS;
    exec.lpVerb = L"runas";
    exec.lpFile = L"cmd.exe";
    exec.lpParameters = command.c_str();
    exec.nShow = SW_HIDE;
    if (ShellExecuteExW(&exec)) {
      WaitForSingleObject(exec.hProcess, 15000);
      CloseHandle(exec.hProcess);
    }
  }
  DeleteFileW(OpenVpnPidPath().c_str());
  DeleteFileW(OpenVpnAuthPath().c_str());
  ResetOpenVpnTrafficStats();
  ResetOpenVpnConnectionsCache();
  return OpenVpnStatus(args, "stopped");
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

std::string CleanAddress(const std::string& value) {
  if (value == "*:*" || value == "0.0.0.0:0" || value == "[::]:0") {
    return "";
  }
  return value;
}

bool IsIpv4Address(const std::string& host) {
  std::istringstream stream(host);
  std::string part;
  int count = 0;
  while (std::getline(stream, part, '.')) {
    count++;
    if (part.empty()) {
      return false;
    }
    for (const char ch : part) {
      if (!std::isdigit(static_cast<unsigned char>(ch))) {
        return false;
      }
    }
    const int value = std::atoi(part.c_str());
    if (value < 0 || value > 255) {
      return false;
    }
  }
  return count == 4;
}

bool IsIpv4Endpoint(const std::string& endpoint) {
  if (endpoint.empty() || endpoint.find('[') != std::string::npos ||
      endpoint.find(']') != std::string::npos) {
    return false;
  }
  const size_t first_colon = endpoint.find(':');
  if (first_colon == std::string::npos) {
    return IsIpv4Address(endpoint);
  }
  if (first_colon != endpoint.rfind(':')) {
    return false;
  }
  return IsIpv4Address(endpoint.substr(0, first_colon));
}

std::string EndpointHost(const std::string& endpoint) {
  const size_t colon = endpoint.find(':');
  if (colon == std::string::npos) {
    return endpoint;
  }
  if (colon != endpoint.rfind(':')) {
    return "";
  }
  return endpoint.substr(0, colon);
}

bool ParseIpv4Octets(const std::string& host, int octets[4]) {
  std::istringstream stream(host);
  std::string part;
  int count = 0;
  while (std::getline(stream, part, '.') && count < 4) {
    if (part.empty()) {
      return false;
    }
    for (const char ch : part) {
      if (!std::isdigit(static_cast<unsigned char>(ch))) {
        return false;
      }
    }
    octets[count++] = std::atoi(part.c_str());
  }
  return count == 4 && stream.eof();
}

bool IsPublicIpv4Endpoint(const std::string& endpoint) {
  const std::string host = EndpointHost(endpoint);
  if (host.empty() || !IsIpv4Address(host)) {
    return false;
  }
  int octets[4] = {};
  if (!ParseIpv4Octets(host, octets)) {
    return false;
  }
  const int first = octets[0];
  const int second = octets[1];
  if (first == 0 || first == 10 || first == 127) {
    return false;
  }
  if (first == 100 && second >= 64 && second <= 127) {
    return false;
  }
  if (first == 169 && second == 254) {
    return false;
  }
  if (first == 172 && second >= 16 && second <= 31) {
    return false;
  }
  if (first == 192 && second == 168) {
    return false;
  }
  if (first >= 224) {
    return false;
  }
  return true;
}

std::string ToLowerAscii(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(), [](char ch) {
    return static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
  });
  return value;
}

std::string NormalizeDomainName(std::string value) {
  value = Trim(value);
  while (!value.empty() && value.back() == '.') {
    value.pop_back();
  }
  if (value.empty() || value.find('.') == std::string::npos ||
      IsIpv4Address(value)) {
    return "";
  }
  for (const char ch : value) {
    const unsigned char byte = static_cast<unsigned char>(ch);
    if (std::isspace(byte) || ch == '|' || ch == '=' || ch == ':' ||
        ch == '[' || ch == ']') {
      return "";
    }
  }
  return ToLowerAscii(value);
}

std::map<std::string, std::string> DnsCacheDomainsByIp() {
  const std::string output = RunCommandCapture("ipconfig /displaydns");
  std::istringstream stream(output);
  std::map<std::string, std::string> domains;
  std::string current_domain;
  std::string line;
  while (std::getline(stream, line)) {
    line = Trim(line);
    if (line.empty() || line.find("---") != std::string::npos) {
      continue;
    }

    const size_t colon = line.find(':');
    std::string value =
        colon == std::string::npos ? line : Trim(line.substr(colon + 1));
    value = Trim(value);
    const std::string domain = NormalizeDomainName(value);
    if (!domain.empty()) {
      current_domain = domain;
      continue;
    }
    if (IsIpv4Address(value) && !current_domain.empty()) {
      domains[value] = current_domain;
    }
  }
  return domains;
}

std::string DomainForTarget(
    const std::string& target,
    const std::map<std::string, std::string>& domains_by_ip) {
  const std::string host = EndpointHost(target);
  if (host.empty()) {
    return "";
  }
  const auto found = domains_by_ip.find(host);
  return found == domains_by_ip.end() ? "" : found->second;
}

std::string OpenVpnConnectionsText(int limit) {
  if (limit <= 0) {
    limit = 80;
  }
  const ULONGLONG now_tick = GetTickCount64();
  if (!g_openvpn_cached_connections_text.empty() &&
      g_openvpn_connections_cache_tick > 0 &&
      now_tick - g_openvpn_connections_cache_tick < kOpenVpnConnectionsCacheMs) {
    return g_openvpn_cached_connections_text;
  }
  const std::string tcp = RunCommandCapture("netstat -ano -p tcp");
  const std::string udp = RunCommandCapture("netstat -ano -p udp");
  const std::map<std::string, std::string> dns_cache = DnsCacheDomainsByIp();
  std::istringstream stream(tcp + "\n" + udp);
  std::ostringstream out;
  std::string line;
  int count = 0;
  const std::string now = NowString();
  while (std::getline(stream, line) && count < limit) {
    line = Trim(line);
    if (line.rfind("TCP", 0) != 0 && line.rfind("UDP", 0) != 0) {
      continue;
    }
    const std::vector<std::string> parts = SplitWhitespace(line);
    if (parts.size() < 3) {
      continue;
    }
    const std::string proto = parts[0];
    const std::string source = CleanAddress(parts[1]);
    const std::string target = CleanAddress(parts[2]);
    if (source.empty() || target.empty()) {
      continue;
    }
    if (!IsIpv4Endpoint(source)) {
      continue;
    }
    if (!IsPublicIpv4Endpoint(target)) {
      continue;
    }
    if (proto == "TCP" && parts.size() >= 4 &&
        (parts[3] == "LISTENING" || parts[3] == "TIME_WAIT")) {
      continue;
    }
    const std::string domain = DomainForTarget(target, dns_cache);
    out << "lastSeen=" << now << "|proto=" << proto << "|source=" << source
        << "|target=" << target << "|domain=" << domain << "|via="
        << "|txBytes=0|rxBytes=0|txRate=0|rxRate=0|dnsRedirect=false\n";
    count++;
  }
  g_openvpn_cached_connections_text = out.str();
  g_openvpn_connections_cache_tick = now_tick;
  return g_openvpn_cached_connections_text;
}

flutter::EncodableValue OpenVpnConnections(int limit) {
  return ConnectionsFromText(OpenVpnConnectionsText(limit));
}

std::wstring HelperArgs(const std::wstring& method, const std::string& host,
                        int limit = 0, bool sync_dns = false) {
  std::wstring args = method;
  if (!host.empty()) {
    args += L" --cpe " + Utf8ToWide(host);
  }
  if (sync_dns) {
    args += L" --sync-dns true";
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

bool EncodableMapHasKey(const flutter::EncodableMap& map,
                        const std::string& key) {
  return map.find(flutter::EncodableValue(key)) != map.end();
}

void PreserveOpenVpnSecret(flutter::EncodableMap* next,
                           const flutter::EncodableMap& previous,
                           const std::string& key) {
  if (EncodableMapHasKey(*next, key)) {
    return;
  }
  const auto entry = previous.find(flutter::EncodableValue(key));
  if (entry != previous.end()) {
    (*next)[flutter::EncodableValue(key)] = entry->second;
  }
}

void RememberTrayArguments(const flutter::EncodableValue* args,
                           const std::string& mode,
                           const std::string& host,
                           const std::string& method) {
  g_last_mode = mode == "openvpn" ? "openvpn" : "halfRoute";
  if (g_last_mode != "openvpn") {
    return;
  }

  flutter::EncodableMap next;
  if (args) {
    if (const auto* map = std::get_if<flutter::EncodableMap>(args)) {
      next = *map;
    }
  }
  next[flutter::EncodableValue("mode")] = flutter::EncodableValue("openvpn");
  next[flutter::EncodableValue("cpeHost")] = flutter::EncodableValue(host);
  if (!EncodableMapHasKey(next, "openvpnRemoteHost")) {
    next[flutter::EncodableValue("openvpnRemoteHost")] =
        flutter::EncodableValue(host);
  }

  if (method != "start" && g_last_openvpn_args.has_value()) {
    if (const auto* previous =
            std::get_if<flutter::EncodableMap>(&g_last_openvpn_args.value())) {
      PreserveOpenVpnSecret(&next, *previous, "openvpnUsername");
      PreserveOpenVpnSecret(&next, *previous, "openvpnPassword");
    }
  }
  g_last_openvpn_args = flutter::EncodableValue(next);
}

const flutter::EncodableValue* LastOpenVpnArguments() {
  if (!g_last_openvpn_args.has_value()) {
    flutter::EncodableMap args;
    args[flutter::EncodableValue("mode")] = flutter::EncodableValue("openvpn");
    args[flutter::EncodableValue("cpeHost")] =
        flutter::EncodableValue(g_last_cpe_host);
    args[flutter::EncodableValue("openvpnRemoteHost")] =
        flutter::EncodableValue(g_last_cpe_host);
    g_last_openvpn_args = flutter::EncodableValue(args);
  }
  return &g_last_openvpn_args.value();
}

bool IsAccelerationRunning() {
  if (g_last_mode == "openvpn") {
    return OpenVpnPidRunning();
  }
  const auto values =
      ParseKeyValueLines(RunHelper(HelperArgs(L"status", g_last_cpe_host)));
  const std::string state = StringValue(values, "state", "stopped");
  return state == "running" || state == "starting";
}

void ToggleAccelerationFromTray() {
  if (g_last_mode == "openvpn") {
    if (OpenVpnPidRunning()) {
      StopOpenVpn(LastOpenVpnArguments());
    } else {
      StartOpenVpn(LastOpenVpnArguments());
    }
    return;
  }
  if (IsAccelerationRunning()) {
    RunHelper(HelperArgs(L"stop", g_last_cpe_host));
  } else {
    RunHelper(HelperArgs(L"start", g_last_cpe_host, 0, g_last_sync_dns));
  }
}

bool g_stop_before_exit_called = false;

void StopAccelerationBeforeExit() {
  if (g_stop_before_exit_called) {
    return;
  }
  g_stop_before_exit_called = true;
  if (g_last_mode == "openvpn") {
    if (OpenVpnPidRunning()) {
      StopOpenVpn(LastOpenVpnArguments());
    }
    return;
  }
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
    const std::string mode = ModeFromArgs(call.arguments());
    const bool sync_dns = BoolArg(call.arguments(), "syncDns", false);
    g_last_cpe_host = host;
    g_last_sync_dns = sync_dns;
    RememberTrayArguments(call.arguments(), mode, host, method);
    if (method == "status") {
      if (mode == "openvpn") {
        const auto status = OpenVpnStatus(call.arguments(), "");
        RefreshTrayIcon();
        result->Success(status);
        return;
      }
      const auto status =
          StatusFromText(RunHelper(HelperArgs(L"status", host)), host);
      RefreshTrayIcon();
      result->Success(status);
    } else if (method == "healthCheck") {
      if (mode == "openvpn") {
        result->Success(OpenVpnHealth(
            OpenVpnRemoteHostFromArgs(call.arguments(), host)));
        return;
      }
      const auto values =
          ParseKeyValueLines(RunHelper(HelperArgs(L"health", host)));
      result->Success(HealthFromValues(values, host));
    } else if (method == "logs") {
      const int limit = LimitFromArgs(call.arguments(), 80);
      if (mode == "openvpn") {
        result->Success(LogsFromText(ReadTextFile(OpenVpnLogPath())));
        return;
      }
      result->Success(LogsFromText(RunHelper(HelperArgs(L"logs", host, limit))));
    } else if (method == "connections") {
      const int limit = LimitFromArgs(call.arguments(), 80);
      if (mode == "openvpn") {
        result->Success(OpenVpnConnections(limit));
        return;
      }
      result->Success(
          ConnectionsFromText(RunHelper(HelperArgs(L"connections", host, limit))));
    } else if (method == "installHelper") {
      if (mode == "openvpn") {
        const auto status = InstallOpenVpnDependencies(call.arguments());
        RefreshTrayIcon();
        result->Success(status);
        return;
      }
      const bool ok = RunHelperElevated(L"install");
      const std::string text = ok ? RunHelper(HelperArgs(L"status", host))
                                  : "state=failed\nadapterName=Windows Half Route\n"
                                    "permission=denied\nhelperInstalled=false\n"
                                    "lastError=helper install was cancelled\n";
      result->Success(StatusFromText(text, host));
    } else if (method == "uninstallHelper") {
      if (mode == "openvpn") {
        const auto status = StopOpenVpn(call.arguments());
        RefreshTrayIcon();
        result->Success(status);
        return;
      }
      const bool ok = RunHelperElevated(L"uninstall");
      const std::string text = ok ? RunHelper(HelperArgs(L"status", host))
                                  : "state=failed\nadapterName=Windows Half Route\n"
                                    "permission=denied\nhelperInstalled=true\n"
                                    "lastError=helper uninstall was cancelled\n";
      result->Success(StatusFromText(text, host));
    } else if (method == "start") {
      if (mode == "openvpn") {
        const auto status = StartOpenVpn(call.arguments());
        RefreshTrayIcon();
        result->Success(status);
        return;
      }
      const auto status =
          StatusFromText(RunHelper(HelperArgs(L"start", host, 0, sync_dns)),
                         host);
      RefreshTrayIcon();
      result->Success(status);
    } else if (method == "stop") {
      if (mode == "openvpn") {
        const auto status = StopOpenVpn(call.arguments());
        RefreshTrayIcon();
        result->Success(status);
        return;
      }
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
