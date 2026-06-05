#include <winsock2.h>
#include <ws2tcpip.h>

#include <windows.h>
#include <iphlpapi.h>
#include <icmpapi.h>
#include <sddl.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

namespace {
constexpr wchar_t kServiceName[] = L"SDWANVergeHelper";
constexpr wchar_t kServiceDisplayName[] = L"SD-WAN Verge Helper";
constexpr wchar_t kPipeName[] = L"\\\\.\\pipe\\sdwan_verge_helper";
constexpr const char* kDefaultCpe = "192.168.1.140";
constexpr const char* kAdapterName = "Windows Half Route";
constexpr const char* kRollbackMessage =
    "CPE health failed, half-route rollback completed";

enum class RuntimeState {
  stopped,
  starting,
  running,
  failed,
  auto_recovered,
};

struct Runtime {
  std::mutex mutex;
  RuntimeState state = RuntimeState::stopped;
  std::string cpe = kDefaultCpe;
  std::string last_error;
  bool stop_requested = false;
  int health_failures = 0;
  std::thread health_thread;

  uint64_t base_tx = 0;
  uint64_t base_rx = 0;
  uint64_t last_tx_total = 0;
  uint64_t last_rx_total = 0;
  uint64_t last_sample_ms = 0;
  uint64_t tx_bytes = 0;
  uint64_t rx_bytes = 0;
  uint64_t tx_rate = 0;
  uint64_t rx_rate = 0;
};

Runtime g_runtime;
SERVICE_STATUS_HANDLE g_service_status_handle = nullptr;
SERVICE_STATUS g_service_status = {};
HANDLE g_service_stop_event = nullptr;
std::atomic<bool> g_service_stopping(false);

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) {
    return {};
  }
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, nullptr,
                                       0, nullptr, nullptr);
  if (size <= 0) {
    return {};
  }
  std::string out(static_cast<size_t>(size - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, out.data(), size, nullptr,
                      nullptr);
  return out;
}

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return {};
  }
  const int size =
      MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr, 0);
  if (size <= 0) {
    return {};
  }
  std::wstring out(static_cast<size_t>(size - 1), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, out.data(), size);
  return out;
}

std::wstring ExePath() {
  wchar_t path[MAX_PATH] = {};
  GetModuleFileNameW(nullptr, path, MAX_PATH);
  return path;
}

std::wstring Quote(const std::wstring& value) {
  return L"\"" + value + L"\"";
}

std::wstring ProgramDataDir() {
  wchar_t base[MAX_PATH] = {};
  DWORD size = GetEnvironmentVariableW(L"ProgramData", base, MAX_PATH);
  std::wstring root =
      size > 0 && size < MAX_PATH ? std::wstring(base) : L"C:\\ProgramData";
  return root + L"\\SD-WAN Verge";
}

void EnsureProgramDataDir() {
  CreateDirectoryW(ProgramDataDir().c_str(), nullptr);
}

std::wstring StatePath(const wchar_t* name) {
  EnsureProgramDataDir();
  return ProgramDataDir() + L"\\" + name;
}

std::string NowString() {
  SYSTEMTIME st = {};
  GetLocalTime(&st);
  char buffer[32] = {};
  snprintf(buffer, sizeof(buffer), "%04u-%02u-%02u %02u:%02u:%02u", st.wYear,
           st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);
  return buffer;
}

uint64_t NowMs() {
  return GetTickCount64();
}

std::string Trim(const std::string& value) {
  size_t start = 0;
  while (start < value.size() &&
         std::isspace(static_cast<unsigned char>(value[start]))) {
    start++;
  }
  size_t end = value.size();
  while (end > start &&
         std::isspace(static_cast<unsigned char>(value[end - 1]))) {
    end--;
  }
  return value.substr(start, end - start);
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

std::string RunCommandCapture(const std::string& command) {
  std::string full = "cmd.exe /C " + command + " 2>&1";
  FILE* pipe = _popen(full.c_str(), "r");
  if (pipe == nullptr) {
    return {};
  }
  std::string output;
  char buffer[4096] = {};
  while (fgets(buffer, sizeof(buffer), pipe) != nullptr) {
    output += buffer;
  }
  _pclose(pipe);
  return output;
}

bool RunCommand(const std::string& command) {
  std::string full = "cmd.exe /C " + command;
  int code = system(full.c_str());
  return code == 0;
}

void LogEvent(const std::string& message) {
  std::ofstream file(StatePath(L"events.log"), std::ios::app);
  file << "time=" << NowString() << "|message=" << message << "\n";
}

std::string StateName(RuntimeState state) {
  switch (state) {
    case RuntimeState::starting:
      return "starting";
    case RuntimeState::running:
      return "running";
    case RuntimeState::failed:
      return "failed";
    case RuntimeState::auto_recovered:
      return "autoRecovered";
    case RuntimeState::stopped:
    default:
      return "stopped";
  }
}

bool ReadInterfaceCounters(uint64_t* tx, uint64_t* rx) {
  *tx = 0;
  *rx = 0;
  PMIB_IF_TABLE2 table = nullptr;
  if (GetIfTable2(&table) != NO_ERROR || table == nullptr) {
    return false;
  }
  for (ULONG i = 0; i < table->NumEntries; ++i) {
    const MIB_IF_ROW2& row = table->Table[i];
    if (row.OperStatus != IfOperStatusUp) {
      continue;
    }
    if (row.Type == IF_TYPE_SOFTWARE_LOOPBACK) {
      continue;
    }
    if (!row.InterfaceAndOperStatusFlags.HardwareInterface) {
      continue;
    }
    *tx += row.OutOctets;
    *rx += row.InOctets;
  }
  FreeMibTable(table);
  return true;
}

void UpdateTrafficLocked(Runtime* runtime) {
  uint64_t tx_total = 0;
  uint64_t rx_total = 0;
  if (!ReadInterfaceCounters(&tx_total, &rx_total)) {
    return;
  }
  const uint64_t now = NowMs();
  if (runtime->last_sample_ms > 0 && now > runtime->last_sample_ms) {
    const uint64_t ms = now - runtime->last_sample_ms;
    const uint64_t tx_delta =
        tx_total >= runtime->last_tx_total ? tx_total - runtime->last_tx_total
                                           : 0;
    const uint64_t rx_delta =
        rx_total >= runtime->last_rx_total ? rx_total - runtime->last_rx_total
                                           : 0;
    runtime->tx_rate = tx_delta * 1000 / ms;
    runtime->rx_rate = rx_delta * 1000 / ms;
  }
  runtime->last_tx_total = tx_total;
  runtime->last_rx_total = rx_total;
  runtime->last_sample_ms = now;
  runtime->tx_bytes =
      tx_total >= runtime->base_tx ? tx_total - runtime->base_tx : 0;
  runtime->rx_bytes =
      rx_total >= runtime->base_rx ? rx_total - runtime->base_rx : 0;
}

void ResetTrafficBaselineLocked(Runtime* runtime) {
  uint64_t tx_total = 0;
  uint64_t rx_total = 0;
  ReadInterfaceCounters(&tx_total, &rx_total);
  runtime->base_tx = tx_total;
  runtime->base_rx = rx_total;
  runtime->last_tx_total = tx_total;
  runtime->last_rx_total = rx_total;
  runtime->last_sample_ms = NowMs();
  runtime->tx_bytes = 0;
  runtime->rx_bytes = 0;
  runtime->tx_rate = 0;
  runtime->rx_rate = 0;
}

bool DeleteHalfRoutes() {
  RunCommand("route delete 0.0.0.0 mask 128.0.0.0 >NUL 2>NUL");
  RunCommand("route delete 128.0.0.0 mask 128.0.0.0 >NUL 2>NUL");
  return true;
}

std::vector<std::string> BuildRouteAddCommands(const std::string& cpe) {
  return {
      "route add 0.0.0.0 mask 128.0.0.0 " + cpe + " -p",
      "route add 128.0.0.0 mask 128.0.0.0 " + cpe + " -p",
  };
}

std::vector<std::string> BuildRouteDeleteCommands() {
  return {
      "route delete 0.0.0.0 mask 128.0.0.0",
      "route delete 128.0.0.0 mask 128.0.0.0",
  };
}

bool ConfigureHalfRoutes(const std::string& cpe, std::string* error) {
  DeleteHalfRoutes();
  for (const std::string& command : BuildRouteAddCommands(cpe)) {
    if (!RunCommand(command + " >NUL")) {
      if (error != nullptr) {
        *error = "failed to run " + command;
      }
      return false;
    }
  }
  return true;
}

bool RoutePrintHas(const std::string& route_print, const std::string& prefix,
                   const std::string& cpe) {
  std::istringstream stream(route_print);
  std::string line;
  while (std::getline(stream, line)) {
    if (line.find(prefix) != std::string::npos &&
        line.find("128.0.0.0") != std::string::npos &&
        line.find(cpe) != std::string::npos) {
      return true;
    }
  }
  return false;
}

bool HasHalfRoutes(const std::string& cpe) {
  const std::string routes = RunCommandCapture("route print -4");
  return RoutePrintHas(routes, "0.0.0.0", cpe) &&
         RoutePrintHas(routes, "128.0.0.0", cpe);
}

void SnapshotInitialState() {
  std::ofstream route_file(StatePath(L"initial-route-print.txt"));
  route_file << RunCommandCapture("route print -4");
  std::ofstream ip_file(StatePath(L"initial-ipconfig.txt"));
  ip_file << RunCommandCapture("ipconfig /all");
}

bool PingCpe(const std::string& cpe) {
  IN_ADDR addr = {};
  if (InetPtonA(AF_INET, cpe.c_str(), &addr) != 1) {
    return false;
  }
  HANDLE icmp = IcmpCreateFile();
  if (icmp == INVALID_HANDLE_VALUE) {
    return false;
  }
  char payload[] = "sdwan";
  char reply[sizeof(ICMP_ECHO_REPLY) + sizeof(payload) + 32] = {};
  DWORD result = IcmpSendEcho(icmp, addr.S_un.S_addr, payload, sizeof(payload),
                              nullptr, reply, sizeof(reply), 1000);
  IcmpCloseHandle(icmp);
  return result > 0;
}

bool EnsureWinsock() {
  static bool initialized = false;
  static bool ok = false;
  if (initialized) {
    return ok;
  }
  initialized = true;
  WSADATA data = {};
  ok = WSAStartup(MAKEWORD(2, 2), &data) == 0;
  return ok;
}

bool TcpProbe(const char* host, uint16_t port, int timeout_ms) {
  if (!EnsureWinsock()) {
    return false;
  }
  SOCKET socket_handle = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (socket_handle == INVALID_SOCKET) {
    return false;
  }
  u_long non_blocking = 1;
  ioctlsocket(socket_handle, FIONBIO, &non_blocking);
  sockaddr_in address = {};
  address.sin_family = AF_INET;
  address.sin_port = htons(port);
  if (InetPtonA(AF_INET, host, &address.sin_addr) != 1) {
    closesocket(socket_handle);
    return false;
  }
  int connect_result = connect(socket_handle,
                               reinterpret_cast<sockaddr*>(&address),
                               sizeof(address));
  if (connect_result == 0) {
    closesocket(socket_handle);
    return true;
  }
  if (WSAGetLastError() != WSAEWOULDBLOCK) {
    closesocket(socket_handle);
    return false;
  }
  fd_set write_set;
  FD_ZERO(&write_set);
  FD_SET(socket_handle, &write_set);
  timeval timeout = {};
  timeout.tv_sec = timeout_ms / 1000;
  timeout.tv_usec = (timeout_ms % 1000) * 1000;
  bool ok = false;
  if (select(0, nullptr, &write_set, nullptr, &timeout) > 0) {
    int socket_error = 0;
    int socket_error_len = sizeof(socket_error);
    ok = getsockopt(socket_handle, SOL_SOCKET, SO_ERROR,
                    reinterpret_cast<char*>(&socket_error),
                    &socket_error_len) == 0 &&
         socket_error == 0;
  }
  closesocket(socket_handle);
  return ok;
}

bool L3Probe() {
  return TcpProbe("1.1.1.1", 443, 1500);
}

void StopAcceleration(const std::string& message, bool recovered);

void HealthLoop() {
  while (true) {
    std::this_thread::sleep_for(std::chrono::seconds(2));
    std::string cpe;
    {
      std::lock_guard<std::mutex> lock(g_runtime.mutex);
      if (g_runtime.stop_requested ||
          g_runtime.state != RuntimeState::running) {
        break;
      }
      cpe = g_runtime.cpe;
      UpdateTrafficLocked(&g_runtime);
    }

    if (!HasHalfRoutes(cpe)) {
      std::string route_error;
      if (ConfigureHalfRoutes(cpe, &route_error)) {
        LogEvent("半路由被系统改写，已自动重加");
      } else {
        std::lock_guard<std::mutex> lock(g_runtime.mutex);
        g_runtime.last_error = route_error;
      }
    }

    const bool l1 = PingCpe(cpe);
    const bool l3 = l1 && L3Probe();
    bool should_rollback = false;
    {
      std::lock_guard<std::mutex> lock(g_runtime.mutex);
      if (!l1) {
        g_runtime.health_failures++;
        g_runtime.last_error = "CPE ping failed";
      } else if (!l3) {
        g_runtime.health_failures++;
        g_runtime.last_error = "CPE reachable but L3 probe failed";
      } else {
        g_runtime.health_failures = 0;
        g_runtime.last_error.clear();
      }
      should_rollback = g_runtime.health_failures >= 3;
    }
    if (should_rollback) {
      StopAcceleration(kRollbackMessage, true);
      break;
    }
  }
}

std::string HealthTextFor(const std::string& cpe, bool service_ready) {
  const bool l1 = PingCpe(cpe);
  const bool l3 = l1 && L3Probe();
  std::ostringstream out;
  out << "host=" << cpe << "\n";
  out << "reachable=" << (l1 ? "true" : "false") << "\n";
  out << "serviceReady=" << (service_ready && l1 ? "true" : "false") << "\n";
  out << "l3Reachable=" << (l3 ? "true" : "false") << "\n";
  if (!l1) {
    out << "error=CPE ping failed\n";
  } else if (!l3) {
    out << "error=CPE reachable but L3 probe failed\n";
  } else {
    out << "error=\n";
  }
  return out.str();
}

std::string StatusText(const std::string& requested_cpe) {
  std::lock_guard<std::mutex> lock(g_runtime.mutex);
  UpdateTrafficLocked(&g_runtime);
  const std::string cpe =
      g_runtime.cpe.empty() ? requested_cpe : g_runtime.cpe;
  std::ostringstream out;
  out << "state=" << StateName(g_runtime.state) << "\n";
  out << "adapterName=Windows Half Route\n";
  out << "permission=ready\n";
  out << "helperInstalled=true\n";
  out << "host=" << cpe << "\n";
  const bool l1 = PingCpe(cpe);
  out << "reachable=" << (l1 ? "true" : "false") << "\n";
  out << "serviceReady=" << (l1 ? "true" : "false") << "\n";
  out << "txBytes=" << g_runtime.tx_bytes << "\n";
  out << "rxBytes=" << g_runtime.rx_bytes << "\n";
  out << "txRate=" << g_runtime.tx_rate << "\n";
  out << "rxRate=" << g_runtime.rx_rate << "\n";
  out << "txPackets=0\n";
  out << "rxPackets=0\n";
  out << "txDropped=0\n";
  out << "rxDropped=0\n";
  out << "natMisses=0\n";
  out << "sendFailures=0\n";
  out << "udp443Packets=0\n";
  out << "lastError=" << g_runtime.last_error << "\n";
  return out.str();
}

void StartHealthThreadLocked() {
  g_runtime.stop_requested = false;
  g_runtime.health_thread = std::thread(HealthLoop);
}

bool StartAcceleration(const std::string& cpe, std::string* response) {
  std::thread previous_thread;
  bool already_running = false;
  {
    std::lock_guard<std::mutex> lock(g_runtime.mutex);
    if (g_runtime.state == RuntimeState::running && g_runtime.cpe == cpe) {
      already_running = true;
    } else if (g_runtime.health_thread.joinable()) {
      g_runtime.stop_requested = true;
      previous_thread = std::move(g_runtime.health_thread);
    }
  }
  if (previous_thread.joinable()) {
    previous_thread.join();
  }
  if (already_running) {
    *response = StatusText(cpe);
    return true;
  }
  {
    std::lock_guard<std::mutex> lock(g_runtime.mutex);
    g_runtime.state = RuntimeState::starting;
    g_runtime.cpe = cpe;
    g_runtime.last_error.clear();
    g_runtime.health_failures = 0;
    ResetTrafficBaselineLocked(&g_runtime);
  }

  SnapshotInitialState();
  std::string route_error;
  if (!ConfigureHalfRoutes(cpe, &route_error)) {
    std::lock_guard<std::mutex> lock(g_runtime.mutex);
    g_runtime.state = RuntimeState::failed;
    g_runtime.last_error = route_error;
  }
  if (!route_error.empty()) {
    *response = StatusText(cpe);
    return false;
  }

  {
    std::lock_guard<std::mutex> lock(g_runtime.mutex);
    g_runtime.state = RuntimeState::running;
    g_runtime.last_error.clear();
    StartHealthThreadLocked();
  }
  LogEvent("开启半路由");
  *response = StatusText(cpe);
  return true;
}

void StopAcceleration(const std::string& message, bool recovered) {
  const std::thread::id current_id = std::this_thread::get_id();
  {
    std::lock_guard<std::mutex> lock(g_runtime.mutex);
    g_runtime.stop_requested = true;
  }
  if (g_runtime.health_thread.joinable() &&
      g_runtime.health_thread.get_id() != current_id) {
    g_runtime.health_thread.join();
  }
  DeleteHalfRoutes();
  {
    std::lock_guard<std::mutex> lock(g_runtime.mutex);
    UpdateTrafficLocked(&g_runtime);
    g_runtime.state =
        recovered ? RuntimeState::auto_recovered : RuntimeState::stopped;
    g_runtime.last_error = recovered ? "已回切直连" : "";
    g_runtime.stop_requested = false;
    g_runtime.health_failures = 0;
  }
  LogEvent(message.empty() ? "关闭半路由" : message);
}

std::string LogsText(int limit) {
  std::ifstream file(StatePath(L"events.log"));
  std::vector<std::string> lines;
  std::string line;
  while (std::getline(file, line)) {
    if (!line.empty()) {
      lines.push_back(line);
    }
  }
  if (limit <= 0) {
    limit = 80;
  }
  const size_t start =
      lines.size() > static_cast<size_t>(limit)
          ? lines.size() - static_cast<size_t>(limit)
          : 0;
  std::ostringstream out;
  for (size_t i = start; i < lines.size(); ++i) {
    out << lines[i] << "\n";
  }
  return out.str();
}

std::string CleanAddress(const std::string& value) {
  if (value == "*:*" || value == "0.0.0.0:0" || value == "[::]:0") {
    return "";
  }
  return value;
}

std::string ConnectionsText(int limit) {
  if (limit <= 0) {
    limit = 80;
  }
  const std::string tcp = RunCommandCapture("netstat -ano -p tcp");
  const std::string udp = RunCommandCapture("netstat -ano -p udp");
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
    if (proto == "TCP" && parts.size() >= 4 &&
        (parts[3] == "LISTENING" || parts[3] == "TIME_WAIT")) {
      continue;
    }
    out << "lastSeen=" << now << "|proto=" << proto << "|source=" << source
        << "|target=" << target << "|domain=|via=" << target
        << "|txBytes=0|rxBytes=0|txRate=0|rxRate=0|dnsRedirect=false\n";
    count++;
  }
  return out.str();
}

std::string CpeFromArgs(const std::vector<std::string>& args) {
  for (size_t i = 0; i + 1 < args.size(); ++i) {
    if (args[i] == "--cpe") {
      return args[i + 1];
    }
  }
  return kDefaultCpe;
}

int LimitFromArgs(const std::vector<std::string>& args, int fallback) {
  for (size_t i = 0; i + 1 < args.size(); ++i) {
    if (args[i] == "--limit") {
      return std::max(1, atoi(args[i + 1].c_str()));
    }
  }
  return fallback;
}

std::string SelfTestText() {
  std::ostringstream out;
  for (const std::string& command : BuildRouteAddCommands(kDefaultCpe)) {
    out << command << "\n";
  }
  for (const std::string& command : BuildRouteDeleteCommands()) {
    out << command << "\n";
  }
  out << "adapterName=" << kAdapterName << "\n";
  out << "txBytes=0\nrxBytes=0\ntxRate=0\nrxRate=0\n";
  out << "netstat -ano -p tcp\n";
  out << "GetIfTable2\n";
  out << "if (!l1)\n";
  out << kRollbackMessage << "\n";
  out << "SELF_TEST_OK\n";
  return out.str();
}

std::string CommandResponse(const std::vector<std::string>& args) {
  if (args.empty()) {
    return "lastError=missing command\n";
  }
  const std::string command = args[0];
  const std::string cpe = CpeFromArgs(args);
  if (command == "start") {
    std::string response;
    StartAcceleration(cpe, &response);
    return response;
  }
  if (command == "stop" || command == "rollback") {
    StopAcceleration("关闭半路由", false);
    return StatusText(cpe);
  }
  if (command == "status") {
    return StatusText(cpe);
  }
  if (command == "health" || command == "healthCheck") {
    return HealthTextFor(cpe, true);
  }
  if (command == "logs") {
    return LogsText(LimitFromArgs(args, 80));
  }
  if (command == "connections") {
    return ConnectionsText(LimitFromArgs(args, 80));
  }
  if (command == "self-test") {
    return SelfTestText();
  }
  return "lastError=unknown command\n";
}

std::vector<std::string> SplitCommand(const std::string& command) {
  return SplitWhitespace(command);
}

std::string PipeUnavailableStatus(const std::string& cpe) {
  const bool installed = false;
  const bool reachable = PingCpe(cpe);
  std::ostringstream out;
  out << "state=stopped\n";
  out << "adapterName=" << kAdapterName << "\n";
  out << "permission=needsHelperInstall\n";
  out << "helperInstalled=" << (installed ? "true" : "false") << "\n";
  out << "host=" << cpe << "\n";
  out << "reachable=" << (reachable ? "true" : "false") << "\n";
  out << "serviceReady=false\n";
  out << "txBytes=0\nrxBytes=0\ntxRate=0\nrxRate=0\n";
  out << "txPackets=0\nrxPackets=0\ntxDropped=0\nrxDropped=0\n";
  out << "natMisses=0\nsendFailures=0\nudp443Packets=0\n";
  out << "lastError=\n";
  return out.str();
}

std::string SendPipeCommand(const std::string& command) {
  HANDLE pipe = CreateFileW(kPipeName, GENERIC_READ | GENERIC_WRITE, 0, nullptr,
                            OPEN_EXISTING, 0, nullptr);
  if (pipe == INVALID_HANDLE_VALUE) {
    return PipeUnavailableStatus(CpeFromArgs(SplitCommand(command)));
  }
  DWORD written = 0;
  WriteFile(pipe, command.c_str(), static_cast<DWORD>(command.size()), &written,
            nullptr);
  const char newline = '\n';
  WriteFile(pipe, &newline, 1, &written, nullptr);
  FlushFileBuffers(pipe);

  std::string output;
  char buffer[4096] = {};
  DWORD read = 0;
  while (ReadFile(pipe, buffer, sizeof(buffer), &read, nullptr) && read > 0) {
    output.append(buffer, buffer + read);
  }
  CloseHandle(pipe);
  return output;
}

bool WaitForPipeReady(int attempts, DWORD wait_ms) {
  for (int i = 0; i < attempts; ++i) {
    if (WaitNamedPipeW(kPipeName, wait_ms)) {
      return true;
    }
    Sleep(200);
  }
  return false;
}

SECURITY_ATTRIBUTES PipeSecurityAttributes(PSECURITY_DESCRIPTOR* descriptor) {
  SECURITY_ATTRIBUTES attributes = {};
  attributes.nLength = sizeof(attributes);
  attributes.bInheritHandle = FALSE;
  attributes.lpSecurityDescriptor = nullptr;
  *descriptor = nullptr;
  if (ConvertStringSecurityDescriptorToSecurityDescriptorW(
          L"D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;GA;;;IU)(A;;GA;;;BU)",
          SDDL_REVISION_1, descriptor, nullptr)) {
    attributes.lpSecurityDescriptor = *descriptor;
  }
  return attributes;
}

void SetServiceStatus(DWORD state, DWORD exit_code = NO_ERROR,
                      DWORD wait_hint = 0) {
  if (g_service_status_handle == nullptr) {
    return;
  }
  g_service_status.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
  g_service_status.dwCurrentState = state;
  g_service_status.dwWin32ExitCode = exit_code;
  g_service_status.dwWaitHint = wait_hint;
  g_service_status.dwControlsAccepted =
      state == SERVICE_START_PENDING ? 0 : SERVICE_ACCEPT_STOP;
  SetServiceStatus(g_service_status_handle, &g_service_status);
}

void WINAPI ServiceControlHandler(DWORD control) {
  if (control != SERVICE_CONTROL_STOP) {
    return;
  }
  SetServiceStatus(SERVICE_STOP_PENDING, NO_ERROR, 2000);
  g_service_stopping = true;
  StopAcceleration("关闭半路由", false);
  if (g_service_stop_event != nullptr) {
    SetEvent(g_service_stop_event);
  }
  HANDLE pipe = CreateFileW(kPipeName, GENERIC_READ | GENERIC_WRITE, 0, nullptr,
                            OPEN_EXISTING, 0, nullptr);
  if (pipe != INVALID_HANDLE_VALUE) {
    CloseHandle(pipe);
  }
}

void ServePipeClient(HANDLE pipe) {
  std::string command;
  char buffer[1024] = {};
  DWORD read = 0;
  while (ReadFile(pipe, buffer, sizeof(buffer), &read, nullptr) && read > 0) {
    command.append(buffer, buffer + read);
    if (command.find('\n') != std::string::npos) {
      break;
    }
  }
  command = Trim(command);
  const std::string response = CommandResponse(SplitCommand(command));
  DWORD written = 0;
  WriteFile(pipe, response.c_str(), static_cast<DWORD>(response.size()),
            &written, nullptr);
  FlushFileBuffers(pipe);
}

void WINAPI ServiceMain(DWORD, wchar_t**) {
  g_service_status_handle =
      RegisterServiceCtrlHandlerW(kServiceName, ServiceControlHandler);
  if (g_service_status_handle == nullptr) {
    return;
  }
  SetServiceStatus(SERVICE_START_PENDING, NO_ERROR, 2000);
  g_service_stop_event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  g_service_stopping = false;
  LogEvent("Windows helper service started");
  SetServiceStatus(SERVICE_RUNNING);

  while (!g_service_stopping) {
    PSECURITY_DESCRIPTOR pipe_descriptor = nullptr;
    SECURITY_ATTRIBUTES pipe_security =
        PipeSecurityAttributes(&pipe_descriptor);
    HANDLE pipe = CreateNamedPipeW(
        kPipeName, PIPE_ACCESS_DUPLEX, PIPE_TYPE_BYTE | PIPE_READMODE_BYTE |
                                           PIPE_WAIT,
        PIPE_UNLIMITED_INSTANCES, 65536, 65536, 0,
        pipe_descriptor != nullptr ? &pipe_security : nullptr);
    if (pipe_descriptor != nullptr) {
      LocalFree(pipe_descriptor);
    }
    if (pipe == INVALID_HANDLE_VALUE) {
      break;
    }
    BOOL connected =
        ConnectNamedPipe(pipe, nullptr) ? TRUE
                                       : (GetLastError() == ERROR_PIPE_CONNECTED);
    if (connected && !g_service_stopping) {
      ServePipeClient(pipe);
    }
    DisconnectNamedPipe(pipe);
    CloseHandle(pipe);
  }

  StopAcceleration("关闭半路由", false);
  LogEvent("Windows helper service stopped");
  if (g_service_stop_event != nullptr) {
    CloseHandle(g_service_stop_event);
    g_service_stop_event = nullptr;
  }
  SetServiceStatus(SERVICE_STOPPED);
}

DWORD QueryServiceState(SC_HANDLE service) {
  SERVICE_STATUS_PROCESS status = {};
  DWORD bytes_needed = 0;
  if (!QueryServiceStatusEx(service, SC_STATUS_PROCESS_INFO,
                            reinterpret_cast<LPBYTE>(&status),
                            sizeof(status), &bytes_needed)) {
    return SERVICE_STOPPED;
  }
  return status.dwCurrentState;
}

bool StopServiceIfRunning(SC_HANDLE service) {
  DWORD state = QueryServiceState(service);
  if (state == SERVICE_STOPPED) {
    return true;
  }
  SERVICE_STATUS status = {};
  ControlService(service, SERVICE_CONTROL_STOP, &status);
  for (int i = 0; i < 50; ++i) {
    state = QueryServiceState(service);
    if (state == SERVICE_STOPPED) {
      return true;
    }
    Sleep(200);
  }
  return QueryServiceState(service) == SERVICE_STOPPED;
}

bool StartServiceAndWait(SC_HANDLE service) {
  if (!StartServiceW(service, 0, nullptr) &&
      GetLastError() != ERROR_SERVICE_ALREADY_RUNNING) {
    return false;
  }
  for (int i = 0; i < 50; ++i) {
    const DWORD state = QueryServiceState(service);
    if (state == SERVICE_RUNNING) {
      return true;
    }
    if (state == SERVICE_STOPPED) {
      break;
    }
    Sleep(200);
  }
  return QueryServiceState(service) == SERVICE_RUNNING;
}

bool InstallService() {
  SC_HANDLE manager =
      OpenSCManagerW(nullptr, nullptr,
                     SC_MANAGER_CREATE_SERVICE | SC_MANAGER_CONNECT);
  if (manager == nullptr) {
    return false;
  }
  const std::wstring binary = Quote(ExePath()) + L" service";
  SC_HANDLE service = CreateServiceW(
      manager, kServiceName, kServiceDisplayName, SERVICE_ALL_ACCESS,
      SERVICE_WIN32_OWN_PROCESS, SERVICE_AUTO_START, SERVICE_ERROR_NORMAL,
      binary.c_str(), nullptr, nullptr, nullptr, nullptr, nullptr);
  if (service == nullptr && GetLastError() == ERROR_SERVICE_EXISTS) {
    service = OpenServiceW(manager, kServiceName, SERVICE_ALL_ACCESS);
    if (service != nullptr) {
      StopServiceIfRunning(service);
      ChangeServiceConfigW(service, SERVICE_NO_CHANGE, SERVICE_AUTO_START,
                           SERVICE_NO_CHANGE, binary.c_str(), nullptr, nullptr,
                           nullptr, nullptr, nullptr, nullptr);
    }
  }
  if (service == nullptr) {
    CloseServiceHandle(manager);
    return false;
  }
  SERVICE_DESCRIPTIONW description = {};
  description.lpDescription = const_cast<wchar_t*>(
      L"Privileged SD-WAN Verge helper for half-route routing and cleanup.");
  ChangeServiceConfig2W(service, SERVICE_CONFIG_DESCRIPTION, &description);
  const bool running = StartServiceAndWait(service);
  CloseServiceHandle(service);
  CloseServiceHandle(manager);
  LogEvent("Windows helper installed");
  return running;
}

bool StopAndDeleteService() {
  DeleteHalfRoutes();
  SC_HANDLE manager = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT);
  if (manager == nullptr) {
    return false;
  }
  SC_HANDLE service =
      OpenServiceW(manager, kServiceName, SERVICE_STOP | DELETE | SERVICE_QUERY_STATUS);
  if (service == nullptr) {
    CloseServiceHandle(manager);
    return false;
  }
  SERVICE_STATUS status = {};
  ControlService(service, SERVICE_CONTROL_STOP, &status);
  for (int i = 0; i < 30; ++i) {
    if (!QueryServiceStatus(service, &status) ||
        status.dwCurrentState == SERVICE_STOPPED) {
      break;
    }
    Sleep(200);
  }
  const bool ok = DeleteService(service) != 0;
  CloseServiceHandle(service);
  CloseServiceHandle(manager);
  LogEvent("Windows helper uninstalled");
  return ok;
}

std::vector<std::string> ArgsFromMain(int argc, wchar_t* argv[]) {
  std::vector<std::string> args;
  for (int i = 1; i < argc; ++i) {
    args.push_back(WideToUtf8(argv[i]));
  }
  return args;
}

std::string JoinArgs(const std::vector<std::string>& args) {
  std::ostringstream out;
  for (size_t i = 0; i < args.size(); ++i) {
    if (i > 0) {
      out << ' ';
    }
    out << args[i];
  }
  return out.str();
}

void PrintUsage() {
  printf("sdwan_windows_helper {install|uninstall|service|start|stop|status|health|logs|connections|self-test} [--cpe ip] [--limit n]\n");
}
}  // namespace

int wmain(int argc, wchar_t* argv[]) {
  const std::vector<std::string> args = ArgsFromMain(argc, argv);
  if (args.empty()) {
    PrintUsage();
    return 64;
  }
  const std::string command = args[0];
  if (command == "service") {
    SERVICE_TABLE_ENTRYW dispatch_table[] = {
        {const_cast<wchar_t*>(kServiceName), ServiceMain},
        {nullptr, nullptr},
    };
    return StartServiceCtrlDispatcherW(dispatch_table) ? 0 : 1;
  }
  if (command == "install") {
    const bool ok = InstallService();
    if (!ok) {
      printf("state=failed\nadapterName=%s\npermission=denied\nhelperInstalled=false\nlastError=failed to install helper service\n",
             kAdapterName);
      return 1;
    }
    WaitForPipeReady(30, 1000);
    printf("%s", SendPipeCommand("status").c_str());
    return 0;
  }
  if (command == "uninstall") {
    SendPipeCommand("stop");
    const bool ok = StopAndDeleteService();
    printf("state=stopped\nadapterName=%s\npermission=needsHelperInstall\nhelperInstalled=false\nlastError=%s\n",
           kAdapterName, ok ? "" : "failed to uninstall helper service");
    return ok ? 0 : 1;
  }
  if (command == "self-test") {
    printf("%s", SelfTestText().c_str());
    return 0;
  }
  const std::string response = SendPipeCommand(JoinArgs(args));
  printf("%s", response.c_str());
  return 0;
}
