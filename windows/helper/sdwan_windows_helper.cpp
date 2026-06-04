#include <winsock2.h>
#include <ws2tcpip.h>

#include <windows.h>
#include <Ipexport.h>
#include <iphlpapi.h>
#include <icmpapi.h>
#include <netioapi.h>
#include <sddl.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <ctime>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "windivert.h"

namespace {

constexpr wchar_t kServiceName[] = L"SDWANVergeHelper";
constexpr wchar_t kServiceDisplayName[] = L"SD-WAN Verge Helper";
constexpr wchar_t kPipeName[] = L"\\\\.\\pipe\\sdwan_verge_helper";
constexpr wchar_t kAdapterName[] = L"SD-WAN Verge";
constexpr wchar_t kTunnelType[] = L"SDWAN";
constexpr char kDefaultCpe[] = "192.168.1.140";
constexpr char kTunLocal[] = "10.255.0.2";
constexpr char kTunPeer[] = "10.255.0.1";
constexpr uint16_t kNatPortStart = 42000;
constexpr uint16_t kNatPortEnd = 42999;
constexpr size_t kMaxNat = 4096;
constexpr size_t kMaxDnsCache = 512;

using WINTUN_ADAPTER_HANDLE = void*;
using WINTUN_SESSION_HANDLE = void*;
using WintunCreateAdapterFn =
    WINTUN_ADAPTER_HANDLE(WINAPI*)(const WCHAR*, const WCHAR*, const GUID*);
using WintunOpenAdapterFn = WINTUN_ADAPTER_HANDLE(WINAPI*)(const WCHAR*);
using WintunCloseAdapterFn = void(WINAPI*)(WINTUN_ADAPTER_HANDLE);
using WintunStartSessionFn =
    WINTUN_SESSION_HANDLE(WINAPI*)(WINTUN_ADAPTER_HANDLE, DWORD);
using WintunEndSessionFn = void(WINAPI*)(WINTUN_SESSION_HANDLE);
using WintunReceivePacketFn = BYTE*(WINAPI*)(WINTUN_SESSION_HANDLE, DWORD*);
using WintunReleaseReceivePacketFn =
    void(WINAPI*)(WINTUN_SESSION_HANDLE, const BYTE*);
using WintunAllocateSendPacketFn = BYTE*(WINAPI*)(WINTUN_SESSION_HANDLE, DWORD);
using WintunSendPacketFn = void(WINAPI*)(WINTUN_SESSION_HANDLE, const BYTE*);
using WintunGetReadWaitEventFn = HANDLE(WINAPI*)(WINTUN_SESSION_HANDLE);
using WintunDeleteDriverFn = BOOL(WINAPI*)();

using WinDivertOpenFn = HANDLE(WINAPI*)(const char*, WINDIVERT_LAYER, INT16, UINT64);
using WinDivertCloseFn = BOOL(WINAPI*)(HANDLE);
using WinDivertRecvFn =
    BOOL(WINAPI*)(HANDLE, PVOID, UINT, UINT*, WINDIVERT_ADDRESS*);
using WinDivertSendFn =
    BOOL(WINAPI*)(HANDLE, const VOID*, UINT, UINT*, const WINDIVERT_ADDRESS*);
using WinDivertHelperCalcChecksumsFn =
    BOOL(WINAPI*)(PVOID, UINT, WINDIVERT_ADDRESS*, UINT64);

struct NatEntry {
  bool used = false;
  uint8_t proto = 0;
  uint32_t original_src_ip = 0;
  uint32_t original_remote_ip = 0;
  uint32_t remote_ip = 0;
  uint16_t original_src_port = 0;
  uint16_t remote_port = 0;
  uint16_t translated_port = 0;
  uint64_t tx_bytes = 0;
  uint64_t rx_bytes = 0;
  uint64_t last_tx_bytes = 0;
  uint64_t last_rx_bytes = 0;
  uint64_t tx_rate = 0;
  uint64_t rx_rate = 0;
  time_t last_rate_at = 0;
  time_t last_seen = 0;
  char domain[256] = {};
};

struct DnsCacheEntry {
  bool used = false;
  uint32_t ip = 0;
  time_t last_seen = 0;
  char domain[256] = {};
};

struct NatTable {
  NatEntry entries[kMaxNat];
  DnsCacheEntry dns[kMaxDnsCache];
};

struct WintunApi {
  HMODULE module = nullptr;
  WintunCreateAdapterFn create_adapter = nullptr;
  WintunOpenAdapterFn open_adapter = nullptr;
  WintunCloseAdapterFn close_adapter = nullptr;
  WintunStartSessionFn start_session = nullptr;
  WintunEndSessionFn end_session = nullptr;
  WintunReceivePacketFn receive_packet = nullptr;
  WintunReleaseReceivePacketFn release_receive_packet = nullptr;
  WintunAllocateSendPacketFn allocate_send_packet = nullptr;
  WintunSendPacketFn send_packet = nullptr;
  WintunGetReadWaitEventFn get_read_wait_event = nullptr;
  WintunDeleteDriverFn delete_driver = nullptr;
};

struct WinDivertApi {
  HMODULE module = nullptr;
  WinDivertOpenFn open = nullptr;
  WinDivertCloseFn close = nullptr;
  WinDivertRecvFn recv = nullptr;
  WinDivertSendFn send = nullptr;
  WinDivertHelperCalcChecksumsFn calc_checksums = nullptr;
};

struct PhysicalAdapter {
  uint32_t if_index = 0;
  uint32_t sub_if_index = 0;
  uint32_t ip = 0;
  uint32_t mask = 0;
  std::wstring name;
};

struct Runtime {
  std::mutex mutex;
  std::atomic<bool> service_stopping{false};
  std::atomic<bool> running{false};
  std::atomic<bool> stop_requested{false};
  std::string state = "stopped";
  std::string permission = "ready";
  std::string cpe = kDefaultCpe;
  std::string last_error;
  uint32_t cpe_ip = 0;
  PhysicalAdapter physical;
  uint32_t wintun_if_index = 0;
  NatTable nat = {};
  uint64_t tx_bytes = 0;
  uint64_t rx_bytes = 0;
  uint64_t last_tx_bytes = 0;
  uint64_t last_rx_bytes = 0;
  uint64_t tx_rate = 0;
  uint64_t rx_rate = 0;
  time_t last_rate_at = 0;
  int health_failures = 0;
  WintunApi wintun;
  WinDivertApi windivert;
  WINTUN_ADAPTER_HANDLE wintun_adapter = nullptr;
  WINTUN_SESSION_HANDLE wintun_session = nullptr;
  HANDLE divert_return = INVALID_HANDLE_VALUE;
  std::thread tun_thread;
  std::thread divert_thread;
  std::thread health_thread;
};

Runtime g_runtime;
SERVICE_STATUS_HANDLE g_service_status_handle = nullptr;
SERVICE_STATUS g_service_status = {};

uint16_t ReadU16(const uint8_t* p) {
  return static_cast<uint16_t>((p[0] << 8) | p[1]);
}

uint32_t ReadU32(const uint8_t* p) {
  return (static_cast<uint32_t>(p[0]) << 24) |
         (static_cast<uint32_t>(p[1]) << 16) |
         (static_cast<uint32_t>(p[2]) << 8) | p[3];
}

void WriteU16(uint8_t* p, uint16_t v) {
  p[0] = static_cast<uint8_t>(v >> 8);
  p[1] = static_cast<uint8_t>(v & 0xff);
}

void WriteU32(uint8_t* p, uint32_t v) {
  p[0] = static_cast<uint8_t>(v >> 24);
  p[1] = static_cast<uint8_t>((v >> 16) & 0xff);
  p[2] = static_cast<uint8_t>((v >> 8) & 0xff);
  p[3] = static_cast<uint8_t>(v & 0xff);
}

bool ParseIpv4(const char* text, uint32_t* out) {
  in_addr addr = {};
  if (inet_pton(AF_INET, text, &addr) != 1) {
    return false;
  }
  *out = ntohl(addr.s_addr);
  return true;
}

std::string Ipv4ToString(uint32_t ip) {
  in_addr addr = {};
  addr.s_addr = htonl(ip);
  char buffer[INET_ADDRSTRLEN] = {};
  inet_ntop(AF_INET, &addr, buffer, sizeof(buffer));
  return buffer;
}

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr, 0);
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
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, nullptr, 0, nullptr, nullptr);
  if (size <= 0) {
    return std::string();
  }
  std::string out(static_cast<size_t>(size - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, out.data(), size, nullptr, nullptr);
  return out;
}

std::wstring ExeDir() {
  wchar_t path[MAX_PATH] = {};
  GetModuleFileNameW(nullptr, path, MAX_PATH);
  std::wstring value(path);
  const size_t slash = value.find_last_of(L"\\/");
  if (slash == std::wstring::npos) {
    return L".";
  }
  return value.substr(0, slash);
}

std::wstring ProgramDataDir() {
  wchar_t buffer[MAX_PATH] = {};
  DWORD len = GetEnvironmentVariableW(L"ProgramData", buffer, MAX_PATH);
  std::wstring base = (len > 0 && len < MAX_PATH) ? std::wstring(buffer) : L"C:\\ProgramData";
  std::wstring dir = base + L"\\SD-WAN Verge";
  CreateDirectoryW(dir.c_str(), nullptr);
  return dir;
}

std::wstring EventsPath() {
  return ProgramDataDir() + L"\\events.log";
}

std::string TimeString(time_t value) {
  tm local_tm = {};
  localtime_s(&local_tm, &value);
  char out[32] = {};
  strftime(out, sizeof(out), "%Y-%m-%d %H:%M:%S", &local_tm);
  return out;
}

void AppendFileUtf8(const std::wstring& path, const std::string& content) {
  FILE* file = nullptr;
  _wfopen_s(&file, path.c_str(), L"ab");
  if (file == nullptr) {
    return;
  }
  fwrite(content.data(), 1, content.size(), file);
  fclose(file);
}

void LogEvent(const std::string& message) {
  const time_t now = time(nullptr);
  AppendFileUtf8(EventsPath(), std::to_string(static_cast<long long>(now)) + " " + message + "\n");
}

uint16_t Checksum16(const uint8_t* data, size_t len) {
  uint32_t sum = 0;
  for (size_t i = 0; i + 1 < len; i += 2) {
    sum += ReadU16(data + i);
  }
  if ((len & 1) != 0) {
    sum += static_cast<uint16_t>(data[len - 1] << 8);
  }
  while ((sum >> 16) != 0) {
    sum = (sum & 0xffff) + (sum >> 16);
  }
  return static_cast<uint16_t>(~sum);
}

void FixIpv4Checksum(uint8_t* packet, size_t len) {
  if (len < 20) {
    return;
  }
  const size_t ihl = (packet[0] & 0x0f) * 4;
  if (ihl < 20 || ihl > len) {
    return;
  }
  WriteU16(packet + 10, 0);
  WriteU16(packet + 10, Checksum16(packet, ihl));
}

uint16_t TransportChecksum(const uint8_t* packet, size_t len, size_t offset, uint8_t proto) {
  if (len < offset) {
    return 0;
  }
  const size_t payload_len = len - offset;
  uint32_t sum = 0;
  sum += ReadU16(packet + 12);
  sum += ReadU16(packet + 14);
  sum += ReadU16(packet + 16);
  sum += ReadU16(packet + 18);
  sum += proto;
  sum += static_cast<uint16_t>(payload_len);
  const uint8_t* payload = packet + offset;
  for (size_t i = 0; i + 1 < payload_len; i += 2) {
    sum += ReadU16(payload + i);
  }
  if ((payload_len & 1) != 0) {
    sum += static_cast<uint16_t>(payload[payload_len - 1] << 8);
  }
  while ((sum >> 16) != 0) {
    sum = (sum & 0xffff) + (sum >> 16);
  }
  return static_cast<uint16_t>(~sum);
}

void FixTransportChecksum(uint8_t* packet, size_t len) {
  if (len < 20) {
    return;
  }
  const size_t ihl = (packet[0] & 0x0f) * 4;
  const uint8_t proto = packet[9];
  if (ihl < 20 || ihl > len) {
    return;
  }
  if (proto == IPPROTO_TCP && len >= ihl + 20) {
    WriteU16(packet + ihl + 16, 0);
    WriteU16(packet + ihl + 16, TransportChecksum(packet, len, ihl, proto));
  } else if (proto == IPPROTO_UDP && len >= ihl + 8) {
    WriteU16(packet + ihl + 6, 0);
    WriteU16(packet + ihl + 6, TransportChecksum(packet, len, ihl, proto));
  } else if (proto == IPPROTO_ICMP && len > ihl + 4) {
    WriteU16(packet + ihl + 2, 0);
    WriteU16(packet + ihl + 2, Checksum16(packet + ihl, len - ihl));
  }
}

bool ParseIpv4Ports(const uint8_t* packet, size_t len, uint16_t* src_port, uint16_t* dst_port) {
  if (len < 20) {
    return false;
  }
  const size_t ihl = (packet[0] & 0x0f) * 4;
  const uint8_t proto = packet[9];
  if ((proto == IPPROTO_TCP || proto == IPPROTO_UDP) && len >= ihl + 4) {
    *src_port = ReadU16(packet + ihl);
    *dst_port = ReadU16(packet + ihl + 2);
    return true;
  }
  if (proto == IPPROTO_ICMP && len >= ihl + 8) {
    *src_port = ReadU16(packet + ihl + 4);
    *dst_port = 0;
    return true;
  }
  return false;
}

bool WriteIpv4SrcPort(uint8_t* packet, size_t len, uint16_t port) {
  const size_t ihl = (packet[0] & 0x0f) * 4;
  const uint8_t proto = packet[9];
  if ((proto == IPPROTO_TCP || proto == IPPROTO_UDP) && len >= ihl + 4) {
    WriteU16(packet + ihl, port);
    return true;
  }
  if (proto == IPPROTO_ICMP && len >= ihl + 8) {
    WriteU16(packet + ihl + 4, port);
    return true;
  }
  return false;
}

bool WriteIpv4DstPort(uint8_t* packet, size_t len, uint16_t port) {
  const size_t ihl = (packet[0] & 0x0f) * 4;
  const uint8_t proto = packet[9];
  if ((proto == IPPROTO_TCP || proto == IPPROTO_UDP) && len >= ihl + 4) {
    WriteU16(packet + ihl + 2, port);
    return true;
  }
  if (proto == IPPROTO_ICMP && len >= ihl + 8) {
    WriteU16(packet + ihl + 4, port);
    return true;
  }
  return false;
}

bool DnsReadName(const uint8_t* dns, size_t len, size_t* offset, char* out, size_t out_size) {
  size_t pos = *offset;
  size_t out_len = 0;
  int jumps = 0;
  bool jumped = false;
  size_t next_offset = pos;
  if (out_size == 0) {
    return false;
  }
  out[0] = '\0';
  while (pos < len && jumps < 16) {
    const uint8_t label_len = dns[pos];
    if (label_len == 0) {
      ++pos;
      if (!jumped) {
        next_offset = pos;
      }
      *offset = next_offset;
      return out_len > 0;
    }
    if ((label_len & 0xc0) == 0xc0) {
      if (pos + 1 >= len) {
        return false;
      }
      const uint16_t pointer = static_cast<uint16_t>(((label_len & 0x3f) << 8) | dns[pos + 1]);
      if (!jumped) {
        next_offset = pos + 2;
      }
      pos = pointer;
      jumped = true;
      ++jumps;
      continue;
    }
    if ((label_len & 0xc0) != 0 || label_len > 63 || pos + 1 + label_len > len) {
      return false;
    }
    if (out_len != 0) {
      if (out_len + 1 >= out_size) {
        return false;
      }
      out[out_len++] = '.';
    }
    if (out_len + label_len >= out_size) {
      return false;
    }
    memcpy(out + out_len, dns + pos + 1, label_len);
    out_len += label_len;
    out[out_len] = '\0';
    pos += 1 + label_len;
    if (!jumped) {
      next_offset = pos;
    }
  }
  return false;
}

bool DnsQueryDomainFromPacket(const uint8_t* packet, size_t len, char* out, size_t out_size) {
  if (len < 20 || packet[9] != IPPROTO_UDP) {
    return false;
  }
  const size_t ihl = (packet[0] & 0x0f) * 4;
  if (ihl < 20 || len < ihl + 8 + 12) {
    return false;
  }
  const uint8_t* dns = packet + ihl + 8;
  const size_t dns_len = len - ihl - 8;
  if (ReadU16(dns + 4) == 0) {
    return false;
  }
  size_t offset = 12;
  return DnsReadName(dns, dns_len, &offset, out, out_size);
}

void DnsCachePut(NatTable* table, uint32_t ip, const char* domain) {
  if (ip == 0 || domain == nullptr || domain[0] == '\0') {
    return;
  }
  DnsCacheEntry* slot = nullptr;
  for (size_t i = 0; i < kMaxDnsCache; ++i) {
    DnsCacheEntry* entry = &table->dns[i];
    if (entry->used && entry->ip == ip) {
      slot = entry;
      break;
    }
    if (slot == nullptr || !entry->used || entry->last_seen < slot->last_seen) {
      slot = entry;
    }
  }
  if (slot == nullptr) {
    return;
  }
  slot->used = true;
  slot->ip = ip;
  slot->last_seen = time(nullptr);
  strcpy_s(slot->domain, domain);
}

const char* DnsCacheLookup(NatTable* table, uint32_t ip) {
  const time_t now = time(nullptr);
  for (size_t i = 0; i < kMaxDnsCache; ++i) {
    DnsCacheEntry* entry = &table->dns[i];
    if (entry->used && entry->ip == ip && now - entry->last_seen <= 600) {
      return entry->domain;
    }
  }
  return "";
}

void DnsCacheAnswersFromPacket(NatTable* table, const uint8_t* packet, size_t len,
                               const char* fallback_domain) {
  if (fallback_domain == nullptr || fallback_domain[0] == '\0' ||
      len < 20 || packet[9] != IPPROTO_UDP) {
    return;
  }
  const size_t ihl = (packet[0] & 0x0f) * 4;
  if (ihl < 20 || len < ihl + 8 + 12) {
    return;
  }
  const uint8_t* dns = packet + ihl + 8;
  const size_t dns_len = len - ihl - 8;
  if ((dns[2] & 0x80) == 0) {
    return;
  }
  const uint16_t qdcount = ReadU16(dns + 4);
  const uint16_t ancount = ReadU16(dns + 6);
  size_t offset = 12;
  char name[256] = {};
  for (uint16_t i = 0; i < qdcount; ++i) {
    if (!DnsReadName(dns, dns_len, &offset, name, sizeof(name)) || offset + 4 > dns_len) {
      return;
    }
    offset += 4;
  }
  for (uint16_t i = 0; i < ancount; ++i) {
    if (!DnsReadName(dns, dns_len, &offset, name, sizeof(name)) || offset + 10 > dns_len) {
      return;
    }
    const uint16_t type = ReadU16(dns + offset);
    const uint16_t klass = ReadU16(dns + offset + 2);
    const uint16_t rdlen = ReadU16(dns + offset + 8);
    offset += 10;
    if (offset + rdlen > dns_len) {
      return;
    }
    if (type == 1 && klass == 1 && rdlen == 4) {
      DnsCachePut(table, ReadU32(dns + offset), fallback_domain);
    }
    offset += rdlen;
  }
}

bool NatPortInUse(NatTable* table, uint8_t proto, uint16_t translated_port) {
  for (size_t i = 0; i < kMaxNat; ++i) {
    NatEntry* entry = &table->entries[i];
    if (entry->used && entry->proto == proto && entry->translated_port == translated_port) {
      return true;
    }
  }
  return false;
}

uint16_t NatAllocatePort(NatTable* table, uint8_t proto, uint16_t original_port) {
  const uint16_t range = static_cast<uint16_t>(kNatPortEnd - kNatPortStart + 1);
  const uint16_t first = static_cast<uint16_t>(kNatPortStart + (original_port % range));
  for (uint16_t i = 0; i < range; ++i) {
    const uint16_t candidate =
        static_cast<uint16_t>(kNatPortStart + ((first - kNatPortStart + i) % range));
    if (!NatPortInUse(table, proto, candidate)) {
      return candidate;
    }
  }
  return 0;
}

NatEntry* NatFindOutgoing(NatTable* table, uint8_t proto, uint32_t original_src_ip,
                          uint32_t remote_ip, uint16_t original_src_port,
                          uint16_t remote_port) {
  for (size_t i = 0; i < kMaxNat; ++i) {
    NatEntry* entry = &table->entries[i];
    if (entry->used && entry->proto == proto && entry->original_src_ip == original_src_ip &&
        entry->original_remote_ip == remote_ip && entry->original_src_port == original_src_port &&
        entry->remote_port == remote_port) {
      entry->last_seen = time(nullptr);
      return entry;
    }
  }
  return nullptr;
}

NatEntry* NatFindFreeSlot(NatTable* table) {
  const time_t now = time(nullptr);
  NatEntry* free_slot = nullptr;
  for (size_t i = 0; i < kMaxNat; ++i) {
    NatEntry* entry = &table->entries[i];
    if (!entry->used) {
      return entry;
    }
    if (free_slot == nullptr || entry->last_seen < free_slot->last_seen) {
      free_slot = entry;
    }
    if (now - entry->last_seen > 300) {
      return entry;
    }
  }
  return free_slot;
}

NatEntry* NatLookupReturn(NatTable* table, uint8_t proto, uint32_t remote_ip,
                          uint16_t local_port, uint16_t remote_port) {
  for (size_t i = 0; i < kMaxNat; ++i) {
    NatEntry* entry = &table->entries[i];
    if (entry->used && entry->proto == proto && entry->remote_ip == remote_ip &&
        entry->translated_port == local_port && entry->remote_port == remote_port) {
      entry->last_seen = time(nullptr);
      return entry;
    }
  }
  return nullptr;
}

bool ShouldRedirectDns(uint8_t proto, uint16_t dst_port) {
  return (proto == IPPROTO_TCP || proto == IPPROTO_UDP) && dst_port == 53;
}

bool NatTranslateOutgoing(NatTable* table, uint8_t* packet, size_t len,
                          uint32_t physical_ip, uint32_t cpe_ip) {
  if (len < 20 || (packet[0] >> 4) != 4) {
    return false;
  }
  const uint8_t proto = packet[9];
  uint16_t src_port = 0;
  uint16_t dst_port = 0;
  if (!ParseIpv4Ports(packet, len, &src_port, &dst_port)) {
    return false;
  }
  const uint32_t original_src_ip = ReadU32(packet + 12);
  const uint32_t original_remote_ip = ReadU32(packet + 16);
  const uint32_t remote_ip = ShouldRedirectDns(proto, dst_port) ? cpe_ip : original_remote_ip;
  NatEntry* entry =
      NatFindOutgoing(table, proto, original_src_ip, original_remote_ip, src_port, dst_port);
  if (entry == nullptr) {
    entry = NatFindFreeSlot(table);
    if (entry == nullptr) {
      return false;
    }
    *entry = NatEntry();
    const uint16_t translated_port = NatAllocatePort(table, proto, src_port);
    if (translated_port == 0) {
      return false;
    }
    entry->translated_port = translated_port;
  }
  entry->used = true;
  entry->proto = proto;
  entry->remote_ip = remote_ip;
  entry->original_remote_ip = original_remote_ip;
  entry->original_src_ip = original_src_ip;
  entry->original_src_port = src_port;
  entry->remote_port = dst_port;
  if (ShouldRedirectDns(proto, dst_port)) {
    (void)DnsQueryDomainFromPacket(packet, len, entry->domain, sizeof(entry->domain));
  }
  entry->tx_bytes += len;
  entry->last_seen = time(nullptr);
  WriteU32(packet + 12, physical_ip);
  WriteU32(packet + 16, remote_ip);
  if (!WriteIpv4SrcPort(packet, len, entry->translated_port)) {
    return false;
  }
  FixIpv4Checksum(packet, len);
  FixTransportChecksum(packet, len);
  return true;
}

bool NatTranslateIncoming(NatTable* table, uint8_t* packet, size_t len, uint32_t physical_ip) {
  if (len < 20 || (packet[0] >> 4) != 4 || ReadU32(packet + 16) != physical_ip) {
    return false;
  }
  const uint8_t proto = packet[9];
  uint16_t src_port = 0;
  uint16_t dst_port = 0;
  if (!ParseIpv4Ports(packet, len, &src_port, &dst_port)) {
    return false;
  }
  const uint32_t remote_ip = ReadU32(packet + 12);
  NatEntry* entry = NatLookupReturn(table, proto, remote_ip, dst_port, src_port);
  if (entry == nullptr) {
    return false;
  }
  if (entry->remote_port == 53 && entry->domain[0] != '\0') {
    DnsCacheAnswersFromPacket(table, packet, len, entry->domain);
  }
  entry->rx_bytes += len;
  WriteU32(packet + 12, entry->original_remote_ip);
  WriteU32(packet + 16, entry->original_src_ip);
  if (!WriteIpv4DstPort(packet, len, entry->original_src_port)) {
    return false;
  }
  FixIpv4Checksum(packet, len);
  FixTransportChecksum(packet, len);
  return true;
}

void MakeUdpPacket(uint8_t* packet, size_t* len, uint32_t src_ip, uint32_t dst_ip,
                   uint16_t src_port, uint16_t dst_port) {
  memset(packet, 0, 64);
  packet[0] = 0x45;
  packet[8] = 64;
  packet[9] = IPPROTO_UDP;
  WriteU16(packet + 2, 28);
  WriteU32(packet + 12, src_ip);
  WriteU32(packet + 16, dst_ip);
  WriteU16(packet + 20, src_port);
  WriteU16(packet + 22, dst_port);
  WriteU16(packet + 24, 8);
  *len = 28;
  FixIpv4Checksum(packet, *len);
  FixTransportChecksum(packet, *len);
}

void AppendUdpPayload(uint8_t* packet, size_t* len, const uint8_t* payload, size_t payload_len) {
  memcpy(packet + *len, payload, payload_len);
  *len += payload_len;
  WriteU16(packet + 2, static_cast<uint16_t>(*len));
  const size_t udp_len = *len - 20;
  WriteU16(packet + 24, static_cast<uint16_t>(udp_len));
  FixIpv4Checksum(packet, *len);
  FixTransportChecksum(packet, *len);
}

void UpdateRatesLocked(Runtime* runtime, time_t now) {
  if (runtime->last_rate_at == 0) {
    runtime->last_rate_at = now;
    runtime->last_tx_bytes = runtime->tx_bytes;
    runtime->last_rx_bytes = runtime->rx_bytes;
    return;
  }
  const time_t elapsed = std::max<time_t>(1, now - runtime->last_rate_at);
  runtime->tx_rate = (runtime->tx_bytes - runtime->last_tx_bytes) / static_cast<uint64_t>(elapsed);
  runtime->rx_rate = (runtime->rx_bytes - runtime->last_rx_bytes) / static_cast<uint64_t>(elapsed);
  runtime->last_tx_bytes = runtime->tx_bytes;
  runtime->last_rx_bytes = runtime->rx_bytes;
  runtime->last_rate_at = now;
  for (size_t i = 0; i < kMaxNat; ++i) {
    NatEntry* entry = &runtime->nat.entries[i];
    if (!entry->used) {
      continue;
    }
    if (entry->last_rate_at == 0) {
      entry->last_rate_at = now;
      entry->last_tx_bytes = entry->tx_bytes;
      entry->last_rx_bytes = entry->rx_bytes;
      continue;
    }
    const time_t entry_elapsed = std::max<time_t>(1, now - entry->last_rate_at);
    entry->tx_rate = (entry->tx_bytes - entry->last_tx_bytes) /
                     static_cast<uint64_t>(entry_elapsed);
    entry->rx_rate = (entry->rx_bytes - entry->last_rx_bytes) /
                     static_cast<uint64_t>(entry_elapsed);
    entry->last_tx_bytes = entry->tx_bytes;
    entry->last_rx_bytes = entry->rx_bytes;
    entry->last_rate_at = now;
  }
}

bool RunCommand(const std::wstring& command) {
  const int code = _wsystem(command.c_str());
  return code == 0;
}

bool LoadWintun(WintunApi* api) {
  if (api->module != nullptr) {
    return true;
  }
  const std::wstring dll = ExeDir() + L"\\wintun.dll";
  api->module = LoadLibraryW(dll.c_str());
  if (api->module == nullptr) {
    api->module = LoadLibraryW(L"wintun.dll");
  }
  if (api->module == nullptr) {
    return false;
  }
  api->create_adapter =
      reinterpret_cast<WintunCreateAdapterFn>(GetProcAddress(api->module, "WintunCreateAdapter"));
  api->open_adapter =
      reinterpret_cast<WintunOpenAdapterFn>(GetProcAddress(api->module, "WintunOpenAdapter"));
  api->close_adapter =
      reinterpret_cast<WintunCloseAdapterFn>(GetProcAddress(api->module, "WintunCloseAdapter"));
  api->start_session =
      reinterpret_cast<WintunStartSessionFn>(GetProcAddress(api->module, "WintunStartSession"));
  api->end_session =
      reinterpret_cast<WintunEndSessionFn>(GetProcAddress(api->module, "WintunEndSession"));
  api->receive_packet =
      reinterpret_cast<WintunReceivePacketFn>(GetProcAddress(api->module, "WintunReceivePacket"));
  api->release_receive_packet = reinterpret_cast<WintunReleaseReceivePacketFn>(
      GetProcAddress(api->module, "WintunReleaseReceivePacket"));
  api->allocate_send_packet = reinterpret_cast<WintunAllocateSendPacketFn>(
      GetProcAddress(api->module, "WintunAllocateSendPacket"));
  api->send_packet =
      reinterpret_cast<WintunSendPacketFn>(GetProcAddress(api->module, "WintunSendPacket"));
  api->get_read_wait_event = reinterpret_cast<WintunGetReadWaitEventFn>(
      GetProcAddress(api->module, "WintunGetReadWaitEvent"));
  api->delete_driver =
      reinterpret_cast<WintunDeleteDriverFn>(GetProcAddress(api->module, "WintunDeleteDriver"));
  return api->create_adapter != nullptr && api->close_adapter != nullptr &&
         api->start_session != nullptr && api->end_session != nullptr &&
         api->receive_packet != nullptr && api->release_receive_packet != nullptr &&
         api->allocate_send_packet != nullptr && api->send_packet != nullptr &&
         api->get_read_wait_event != nullptr;
}

bool LoadWinDivert(WinDivertApi* api) {
  if (api->module != nullptr) {
    return true;
  }
  const std::wstring dll = ExeDir() + L"\\WinDivert.dll";
  api->module = LoadLibraryW(dll.c_str());
  if (api->module == nullptr) {
    api->module = LoadLibraryW(L"WinDivert.dll");
  }
  if (api->module == nullptr) {
    return false;
  }
  api->open = reinterpret_cast<WinDivertOpenFn>(GetProcAddress(api->module, "WinDivertOpen"));
  api->close = reinterpret_cast<WinDivertCloseFn>(GetProcAddress(api->module, "WinDivertClose"));
  api->recv = reinterpret_cast<WinDivertRecvFn>(GetProcAddress(api->module, "WinDivertRecv"));
  api->send = reinterpret_cast<WinDivertSendFn>(GetProcAddress(api->module, "WinDivertSend"));
  api->calc_checksums = reinterpret_cast<WinDivertHelperCalcChecksumsFn>(
      GetProcAddress(api->module, "WinDivertHelperCalcChecksums"));
  return api->open != nullptr && api->close != nullptr && api->recv != nullptr &&
         api->send != nullptr && api->calc_checksums != nullptr;
}

bool IsSameSubnet(uint32_t ip, uint32_t target, uint32_t mask) {
  return (ip & mask) == (target & mask);
}

bool DiscoverPhysicalAdapter(uint32_t cpe_ip, PhysicalAdapter* out) {
  ULONG flags = GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER;
  ULONG size = 16 * 1024;
  std::vector<uint8_t> buffer(size);
  IP_ADAPTER_ADDRESSES* addresses = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data());
  ULONG result = GetAdaptersAddresses(AF_INET, flags, nullptr, addresses, &size);
  if (result == ERROR_BUFFER_OVERFLOW) {
    buffer.resize(size);
    addresses = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data());
    result = GetAdaptersAddresses(AF_INET, flags, nullptr, addresses, &size);
  }
  if (result != NO_ERROR) {
    return false;
  }
  for (IP_ADAPTER_ADDRESSES* adapter = addresses; adapter != nullptr; adapter = adapter->Next) {
    if (adapter->OperStatus != IfOperStatusUp ||
        adapter->IfType == IF_TYPE_SOFTWARE_LOOPBACK ||
        adapter->IfType == IF_TYPE_TUNNEL ||
        wcscmp(adapter->FriendlyName, kAdapterName) == 0) {
      continue;
    }
    for (IP_ADAPTER_UNICAST_ADDRESS* unicast = adapter->FirstUnicastAddress; unicast != nullptr;
         unicast = unicast->Next) {
      if (unicast->Address.lpSockaddr == nullptr ||
          unicast->Address.lpSockaddr->sa_family != AF_INET) {
        continue;
      }
      const sockaddr_in* sin = reinterpret_cast<const sockaddr_in*>(unicast->Address.lpSockaddr);
      const uint32_t ip = ntohl(sin->sin_addr.s_addr);
      const uint32_t mask =
          unicast->OnLinkPrefixLength == 0
              ? 0
              : (0xffffffffu << (32 - unicast->OnLinkPrefixLength));
      if (IsSameSubnet(ip, cpe_ip, mask)) {
        out->if_index = adapter->IfIndex;
        out->sub_if_index = 0;
        out->ip = ip;
        out->mask = mask;
        out->name = adapter->FriendlyName;
        return true;
      }
    }
  }
  return false;
}

bool FindAdapterIndexByName(const wchar_t* friendly_name, uint32_t* if_index) {
  ULONG size = 16 * 1024;
  std::vector<uint8_t> buffer(size);
  IP_ADAPTER_ADDRESSES* addresses = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data());
  ULONG result = GetAdaptersAddresses(AF_INET, GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST,
                                      nullptr, addresses, &size);
  if (result == ERROR_BUFFER_OVERFLOW) {
    buffer.resize(size);
    addresses = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data());
    result = GetAdaptersAddresses(AF_INET, GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST,
                                  nullptr, addresses, &size);
  }
  if (result != NO_ERROR) {
    return false;
  }
  for (IP_ADAPTER_ADDRESSES* adapter = addresses; adapter != nullptr; adapter = adapter->Next) {
    if (wcscmp(adapter->FriendlyName, friendly_name) == 0) {
      *if_index = adapter->IfIndex;
      return true;
    }
  }
  return false;
}

void CleanupRoutes(Runtime* runtime) {
  RunCommand(L"route delete 0.0.0.0 mask 128.0.0.0 >NUL 2>NUL");
  RunCommand(L"route delete 128.0.0.0 mask 128.0.0.0 >NUL 2>NUL");
  std::wstring cpe = Utf8ToWide(runtime->cpe);
  RunCommand(L"netsh interface ipv4 delete route " + cpe + L"/32 \"" +
             runtime->physical.name + L"\" store=active >NUL 2>NUL");
}

bool ConfigureWintunAddressAndRoutes(Runtime* runtime) {
  const std::wstring adapter = kAdapterName;
  const std::wstring cpe = Utf8ToWide(runtime->cpe);
  bool ok = true;
  ok &= RunCommand(L"netsh interface ipv4 set address name=\"" + adapter +
                   L"\" static 10.255.0.2 255.255.255.252 >NUL");
  ok &= RunCommand(L"netsh interface ipv4 set dnsservers name=\"" + adapter +
                   L"\" static " + cpe + L" primary >NUL");
  ok &= RunCommand(L"netsh interface ipv4 add route " + cpe + L"/32 \"" +
                   runtime->physical.name + L"\" 0.0.0.0 store=active >NUL");
  ok &= RunCommand(L"route add 0.0.0.0 mask 128.0.0.0 10.255.0.1 metric 5 if " +
                   std::to_wstring(runtime->wintun_if_index) + L" >NUL");
  ok &= RunCommand(L"route add 128.0.0.0 mask 128.0.0.0 10.255.0.1 metric 5 if " +
                   std::to_wstring(runtime->wintun_if_index) + L" >NUL");
  return ok;
}

bool PingCpe(const std::string& host) {
  uint32_t ip = 0;
  if (!ParseIpv4(host.c_str(), &ip)) {
    return false;
  }
  HANDLE icmp = IcmpCreateFile();
  if (icmp == INVALID_HANDLE_VALUE) {
    return false;
  }
  char data[] = "sdwan";
  std::vector<uint8_t> reply(sizeof(ICMP_ECHO_REPLY) + sizeof(data) + 32);
  DWORD result = IcmpSendEcho(icmp, htonl(ip), data, sizeof(data), nullptr,
                              reply.data(), static_cast<DWORD>(reply.size()), 1000);
  IcmpCloseHandle(icmp);
  return result != 0;
}

bool L3Probe() {
  SOCKET sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (sock == INVALID_SOCKET) {
    return false;
  }
  DWORD timeout = 1500;
  setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, reinterpret_cast<const char*>(&timeout), sizeof(timeout));
  setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, reinterpret_cast<const char*>(&timeout), sizeof(timeout));
  sockaddr_in target = {};
  target.sin_family = AF_INET;
  inet_pton(AF_INET, "1.1.1.1", &target.sin_addr);
  target.sin_port = htons(443);
  const bool ok = connect(sock, reinterpret_cast<sockaddr*>(&target), sizeof(target)) == 0;
  closesocket(sock);
  return ok;
}

const char* ProtoName(uint8_t proto) {
  if (proto == IPPROTO_TCP) {
    return "TCP";
  }
  if (proto == IPPROTO_UDP) {
    return "UDP";
  }
  if (proto == IPPROTO_ICMP) {
    return "ICMP";
  }
  return "IP";
}

std::string StatusTextLocked(Runtime* runtime) {
  const bool cpe_reachable = PingCpe(runtime->cpe);
  std::string out;
  out += "state=" + runtime->state + "\n";
  out += "adapterName=Windows Wintun\n";
  out += "permission=" + runtime->permission + "\n";
  out += "helperInstalled=true\n";
  out += "host=" + runtime->cpe + "\n";
  out += std::string("reachable=") + (cpe_reachable ? "true" : "false") + "\n";
  out += std::string("serviceReady=") + (runtime->running ? "true" : (cpe_reachable ? "true" : "false")) + "\n";
  out += "txBytes=" + std::to_string(runtime->tx_bytes) + "\n";
  out += "rxBytes=" + std::to_string(runtime->rx_bytes) + "\n";
  out += "txRate=" + std::to_string(runtime->tx_rate) + "\n";
  out += "rxRate=" + std::to_string(runtime->rx_rate) + "\n";
  out += "lastError=" + runtime->last_error + "\n";
  return out;
}

std::string ConnectionsTextLocked(Runtime* runtime, int limit) {
  std::string out;
  const time_t now = time(nullptr);
  int count = 0;
  for (size_t i = 0; i < kMaxNat && count < limit; ++i) {
    NatEntry* entry = &runtime->nat.entries[i];
    if (!entry->used || now - entry->last_seen > 300) {
      continue;
    }
    const bool dns_redirect = entry->remote_ip != entry->original_remote_ip;
    const char* domain =
        dns_redirect ? entry->domain : DnsCacheLookup(&runtime->nat, entry->original_remote_ip);
    out += "lastSeen=" + std::to_string(static_cast<long long>(entry->last_seen));
    out += "|proto=" + std::string(ProtoName(entry->proto));
    out += "|source=" + Ipv4ToString(entry->original_src_ip) + ":" +
           std::to_string(entry->original_src_port);
    out += "|target=" + Ipv4ToString(entry->original_remote_ip) + ":" +
           std::to_string(entry->remote_port);
    out += "|domain=" + std::string(domain);
    out += "|via=" + Ipv4ToString(entry->remote_ip) + ":" + std::to_string(entry->remote_port);
    out += "|txBytes=" + std::to_string(entry->tx_bytes);
    out += "|rxBytes=" + std::to_string(entry->rx_bytes);
    out += "|txRate=" + std::to_string(entry->tx_rate);
    out += "|rxRate=" + std::to_string(entry->rx_rate);
    out += std::string("|dnsRedirect=") + (dns_redirect ? "true" : "false") + "\n";
    ++count;
  }
  return out;
}

std::string LogsText(int limit) {
  FILE* file = nullptr;
  _wfopen_s(&file, EventsPath().c_str(), L"rb");
  if (file == nullptr) {
    return std::string();
  }
  std::vector<std::string> lines;
  char buffer[1024] = {};
  while (fgets(buffer, sizeof(buffer), file) != nullptr) {
    std::string line(buffer);
    while (!line.empty() && (line.back() == '\r' || line.back() == '\n')) {
      line.pop_back();
    }
    lines.push_back(line);
  }
  fclose(file);
  std::string out;
  const int start = std::max<int>(0, static_cast<int>(lines.size()) - limit);
  for (int i = start; i < static_cast<int>(lines.size()); ++i) {
    const std::string& line = lines[static_cast<size_t>(i)];
    const size_t space = line.find(' ');
    if (space == std::string::npos) {
      continue;
    }
    const time_t raw = static_cast<time_t>(_atoi64(line.substr(0, space).c_str()));
    out += "time=" + TimeString(raw) + "|message=" + line.substr(space + 1) + "\n";
  }
  return out;
}

void StopAcceleration(const std::string& reason, bool auto_recovered);

void TunReadLoop(Runtime* runtime) {
  HANDLE event = runtime->wintun.get_read_wait_event(runtime->wintun_session);
  while (!runtime->stop_requested.load()) {
    DWORD packet_size = 0;
    BYTE* packet = runtime->wintun.receive_packet(runtime->wintun_session, &packet_size);
    if (packet == nullptr) {
      WaitForSingleObject(event, 200);
      continue;
    }
    if (packet_size >= 20 && packet_size <= 0xffff) {
      std::vector<uint8_t> copy(packet, packet + packet_size);
      bool translated = false;
      {
        std::lock_guard<std::mutex> lock(runtime->mutex);
        translated = NatTranslateOutgoing(&runtime->nat, copy.data(), copy.size(),
                                          runtime->physical.ip, runtime->cpe_ip);
        if (translated) {
          runtime->tx_bytes += copy.size();
        }
      }
      if (translated) {
        WINDIVERT_ADDRESS addr = {};
        addr.Outbound = 1;
        addr.Network.IfIdx = runtime->physical.if_index;
        addr.Network.SubIfIdx = runtime->physical.sub_if_index;
        runtime->windivert.calc_checksums(copy.data(), static_cast<UINT>(copy.size()), &addr, 0);
        UINT written = 0;
        runtime->windivert.send(runtime->divert_return, copy.data(), static_cast<UINT>(copy.size()),
                                &written, &addr);
      }
    }
    runtime->wintun.release_receive_packet(runtime->wintun_session, packet);
  }
}

void DivertReturnLoop(Runtime* runtime) {
  std::vector<uint8_t> packet(0xffff);
  while (!runtime->stop_requested.load()) {
    UINT read_len = 0;
    WINDIVERT_ADDRESS addr = {};
    if (!runtime->windivert.recv(runtime->divert_return, packet.data(),
                                 static_cast<UINT>(packet.size()), &read_len, &addr)) {
      Sleep(50);
      continue;
    }
    if (read_len == 0) {
      continue;
    }
    std::vector<uint8_t> copy(packet.data(), packet.data() + read_len);
    bool translated = false;
    {
      std::lock_guard<std::mutex> lock(runtime->mutex);
      translated =
          NatTranslateIncoming(&runtime->nat, copy.data(), copy.size(), runtime->physical.ip);
      if (translated) {
        runtime->rx_bytes += copy.size();
      }
    }
    if (!translated) {
      continue;
    }
    BYTE* out = runtime->wintun.allocate_send_packet(runtime->wintun_session,
                                                     static_cast<DWORD>(copy.size()));
    if (out == nullptr) {
      continue;
    }
    memcpy(out, copy.data(), copy.size());
    runtime->wintun.send_packet(runtime->wintun_session, out);
  }
}

void HealthLoop(Runtime* runtime) {
  while (!runtime->stop_requested.load()) {
    Sleep(1000);
    {
      std::lock_guard<std::mutex> lock(runtime->mutex);
      UpdateRatesLocked(runtime, time(nullptr));
    }
    const bool l1 = PingCpe(runtime->cpe);
    const bool l3 = runtime->running ? L3Probe() : l1;
    if (l1 && l3) {
      runtime->health_failures = 0;
    } else {
      runtime->health_failures++;
      if (runtime->health_failures >= 3) {
        StopAcceleration("CPE health failed, auto rollback completed", true);
        return;
      }
    }
  }
}

bool StartAcceleration(const std::string& cpe) {
  std::lock_guard<std::mutex> lock(g_runtime.mutex);
  if (g_runtime.running.load()) {
    g_runtime.cpe = cpe.empty() ? kDefaultCpe : cpe;
    return true;
  }
  g_runtime.cpe = cpe.empty() ? kDefaultCpe : cpe;
  g_runtime.last_error.clear();
  g_runtime.state = "starting";
  g_runtime.stop_requested = false;
  g_runtime.health_failures = 0;
  memset(&g_runtime.nat, 0, sizeof(g_runtime.nat));
  if (!ParseIpv4(g_runtime.cpe.c_str(), &g_runtime.cpe_ip)) {
    g_runtime.state = "failed";
    g_runtime.last_error = "invalid cpe ip";
    return false;
  }
  if (!PingCpe(g_runtime.cpe)) {
    g_runtime.state = "failed";
    g_runtime.last_error = "cpe unreachable";
    return false;
  }
  if (!DiscoverPhysicalAdapter(g_runtime.cpe_ip, &g_runtime.physical)) {
    g_runtime.state = "failed";
    g_runtime.last_error = "physical adapter for cpe not found";
    return false;
  }
  if (!LoadWintun(&g_runtime.wintun)) {
    g_runtime.state = "failed";
    g_runtime.last_error = "wintun.dll is missing or incompatible";
    return false;
  }
  if (!LoadWinDivert(&g_runtime.windivert)) {
    g_runtime.state = "failed";
    g_runtime.last_error = "WinDivert.dll is missing or incompatible";
    return false;
  }
  if (g_runtime.wintun_adapter == nullptr) {
    if (g_runtime.wintun.open_adapter != nullptr) {
      g_runtime.wintun_adapter = g_runtime.wintun.open_adapter(kAdapterName);
    }
    if (g_runtime.wintun_adapter == nullptr) {
      g_runtime.wintun_adapter =
          g_runtime.wintun.create_adapter(kAdapterName, kTunnelType, nullptr);
    }
  }
  if (g_runtime.wintun_adapter == nullptr) {
    g_runtime.state = "failed";
    g_runtime.last_error = "failed to create Wintun adapter";
    return false;
  }
  Sleep(600);
  if (!FindAdapterIndexByName(kAdapterName, &g_runtime.wintun_if_index)) {
    g_runtime.state = "failed";
    g_runtime.last_error = "failed to find Wintun interface index";
    return false;
  }
  CleanupRoutes(&g_runtime);
  if (!ConfigureWintunAddressAndRoutes(&g_runtime)) {
    CleanupRoutes(&g_runtime);
    g_runtime.state = "failed";
    g_runtime.last_error = "failed to configure Wintun routes";
    return false;
  }
  const std::string physical_ip = Ipv4ToString(g_runtime.physical.ip);
  const std::string filter =
      "inbound and ip and ip.DstAddr == " + physical_ip +
      " and ((tcp.DstPort >= 42000 and tcp.DstPort <= 42999) or "
      "(udp.DstPort >= 42000 and udp.DstPort <= 42999) or "
      "(icmp.Id >= 42000 and icmp.Id <= 42999))";
  g_runtime.divert_return =
      g_runtime.windivert.open(filter.c_str(), WINDIVERT_LAYER_NETWORK, -500, 0);
  if (g_runtime.divert_return == INVALID_HANDLE_VALUE) {
    CleanupRoutes(&g_runtime);
    g_runtime.state = "failed";
    g_runtime.last_error = "failed to open WinDivert return filter";
    return false;
  }
  g_runtime.wintun_session = g_runtime.wintun.start_session(g_runtime.wintun_adapter, 0x400000);
  if (g_runtime.wintun_session == nullptr) {
    CleanupRoutes(&g_runtime);
    g_runtime.windivert.close(g_runtime.divert_return);
    g_runtime.divert_return = INVALID_HANDLE_VALUE;
    g_runtime.state = "failed";
    g_runtime.last_error = "failed to start Wintun session";
    return false;
  }
  g_runtime.running = true;
  g_runtime.state = "running";
  LogEvent("Windows TUN acceleration started");
  g_runtime.tun_thread = std::thread(TunReadLoop, &g_runtime);
  g_runtime.divert_thread = std::thread(DivertReturnLoop, &g_runtime);
  g_runtime.health_thread = std::thread(HealthLoop, &g_runtime);
  return true;
}

void StopAcceleration(const std::string& reason, bool auto_recovered) {
  {
    std::lock_guard<std::mutex> lock(g_runtime.mutex);
    if (!g_runtime.running.load() && g_runtime.state != "starting") {
      g_runtime.state = auto_recovered ? "autoRecovered" : "stopped";
      g_runtime.last_error = auto_recovered ? reason : "";
      return;
    }
    g_runtime.state = "stopping";
    g_runtime.stop_requested = true;
  }
  {
    std::lock_guard<std::mutex> lock(g_runtime.mutex);
    if (g_runtime.divert_return != INVALID_HANDLE_VALUE) {
      g_runtime.windivert.close(g_runtime.divert_return);
      g_runtime.divert_return = INVALID_HANDLE_VALUE;
    }
  }
  if (g_runtime.tun_thread.joinable() &&
      g_runtime.tun_thread.get_id() != std::this_thread::get_id()) {
    g_runtime.tun_thread.join();
  }
  if (g_runtime.divert_thread.joinable() &&
      g_runtime.divert_thread.get_id() != std::this_thread::get_id()) {
    g_runtime.divert_thread.join();
  }
  if (g_runtime.health_thread.joinable() &&
      g_runtime.health_thread.get_id() != std::this_thread::get_id()) {
    g_runtime.health_thread.join();
  } else if (g_runtime.health_thread.joinable()) {
    g_runtime.health_thread.detach();
  }
  std::lock_guard<std::mutex> lock(g_runtime.mutex);
  CleanupRoutes(&g_runtime);
  if (g_runtime.wintun_session != nullptr) {
    g_runtime.wintun.end_session(g_runtime.wintun_session);
    g_runtime.wintun_session = nullptr;
  }
  g_runtime.running = false;
  g_runtime.state = auto_recovered ? "autoRecovered" : "stopped";
  g_runtime.last_error = auto_recovered ? reason : "";
  LogEvent(auto_recovered ? "CPE abnormal, auto rollback completed"
                          : "Windows TUN acceleration stopped");
}

std::string HandleCommand(const std::string& command) {
  std::string name = command;
  std::string arg;
  const size_t space = command.find(' ');
  if (space != std::string::npos) {
    name = command.substr(0, space);
    arg = command.substr(space + 1);
  }
  std::string cpe = kDefaultCpe;
  int limit = 80;
  const size_t cpe_pos = arg.find("cpe=");
  if (cpe_pos != std::string::npos) {
    const size_t end = arg.find(' ', cpe_pos);
    cpe = arg.substr(cpe_pos + 4, end == std::string::npos ? std::string::npos : end - cpe_pos - 4);
  }
  const size_t limit_pos = arg.find("limit=");
  if (limit_pos != std::string::npos) {
    limit = std::max(1, atoi(arg.c_str() + limit_pos + 6));
  }
  if (name == "start") {
    const bool ok = StartAcceleration(cpe);
    std::lock_guard<std::mutex> lock(g_runtime.mutex);
    return StatusTextLocked(&g_runtime) + std::string("ok=") + (ok ? "true\n" : "false\n");
  }
  if (name == "stop") {
    StopAcceleration("stopped", false);
    std::lock_guard<std::mutex> lock(g_runtime.mutex);
    return StatusTextLocked(&g_runtime);
  }
  if (name == "status" || name == "health") {
    std::lock_guard<std::mutex> lock(g_runtime.mutex);
    if (!cpe.empty()) {
      g_runtime.cpe = cpe;
    }
    return StatusTextLocked(&g_runtime);
  }
  if (name == "logs") {
    return LogsText(limit);
  }
  if (name == "connections") {
    std::lock_guard<std::mutex> lock(g_runtime.mutex);
    return ConnectionsTextLocked(&g_runtime, limit);
  }
  return "error=unknown command\n";
}

std::string SendPipeCommand(const std::string& command) {
  HANDLE pipe = CreateFileW(kPipeName, GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_EXISTING, 0,
                            nullptr);
  if (pipe == INVALID_HANDLE_VALUE) {
    return "state=stopped\nadapterName=Windows Wintun\npermission=needsHelperInstall\n"
           "helperInstalled=false\nhost=192.168.1.140\nreachable=false\nserviceReady=false\n"
           "txBytes=0\nrxBytes=0\ntxRate=0\nrxRate=0\n"
           "lastError=helper service is not running\n";
  }
  DWORD written = 0;
  WriteFile(pipe, command.data(), static_cast<DWORD>(command.size()), &written, nullptr);
  char buffer[65536] = {};
  DWORD read = 0;
  std::string out;
  while (ReadFile(pipe, buffer, sizeof(buffer), &read, nullptr) && read > 0) {
    out.append(buffer, buffer + read);
    if (read < sizeof(buffer)) {
      break;
    }
  }
  CloseHandle(pipe);
  return out;
}

void PipeServerLoop() {
  PSECURITY_DESCRIPTOR security_descriptor = nullptr;
  ConvertStringSecurityDescriptorToSecurityDescriptorW(
      L"D:(A;;GA;;;SY)(A;;GA;;;BA)(A;;GRGW;;;AU)", SDDL_REVISION_1, &security_descriptor, nullptr);
  SECURITY_ATTRIBUTES security_attributes = {};
  security_attributes.nLength = sizeof(security_attributes);
  security_attributes.lpSecurityDescriptor = security_descriptor;
  security_attributes.bInheritHandle = FALSE;
  while (!g_runtime.service_stopping.load()) {
    HANDLE pipe = CreateNamedPipeW(kPipeName, PIPE_ACCESS_DUPLEX,
                                   PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,
                                   PIPE_UNLIMITED_INSTANCES, 65536, 4096, 0,
                                   security_descriptor == nullptr ? nullptr : &security_attributes);
    if (pipe == INVALID_HANDLE_VALUE) {
      Sleep(200);
      continue;
    }
    BOOL connected = ConnectNamedPipe(pipe, nullptr)
                         ? TRUE
                         : (GetLastError() == ERROR_PIPE_CONNECTED ? TRUE : FALSE);
    if (!connected) {
      CloseHandle(pipe);
      continue;
    }
    char command[4096] = {};
    DWORD read = 0;
    if (ReadFile(pipe, command, sizeof(command) - 1, &read, nullptr) && read > 0) {
      command[read] = '\0';
      std::string response = HandleCommand(command);
      DWORD written = 0;
      WriteFile(pipe, response.data(), static_cast<DWORD>(response.size()), &written, nullptr);
    }
    FlushFileBuffers(pipe);
    DisconnectNamedPipe(pipe);
    CloseHandle(pipe);
  }
  if (security_descriptor != nullptr) {
    LocalFree(security_descriptor);
  }
}

void SetServiceState(DWORD state, DWORD win32_exit_code = NO_ERROR, DWORD wait_hint = 0) {
  g_service_status.dwCurrentState = state;
  g_service_status.dwWin32ExitCode = win32_exit_code;
  g_service_status.dwWaitHint = wait_hint;
  g_service_status.dwControlsAccepted =
      state == SERVICE_RUNNING ? SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN : 0;
  SetServiceStatus(g_service_status_handle, &g_service_status);
}

void WINAPI ServiceControlHandler(DWORD control) {
  if (control == SERVICE_CONTROL_STOP || control == SERVICE_CONTROL_SHUTDOWN) {
    SetServiceState(SERVICE_STOP_PENDING, NO_ERROR, 3000);
    g_runtime.service_stopping = true;
    StopAcceleration("service stopped", false);
    SetServiceState(SERVICE_STOPPED);
  }
}

void WINAPI ServiceMain(DWORD, LPWSTR*) {
  g_service_status_handle = RegisterServiceCtrlHandlerW(kServiceName, ServiceControlHandler);
  if (g_service_status_handle == nullptr) {
    return;
  }
  g_service_status.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
  SetServiceState(SERVICE_START_PENDING, NO_ERROR, 3000);
  WSADATA wsa = {};
  WSAStartup(MAKEWORD(2, 2), &wsa);
  LogEvent("Windows helper service started");
  SetServiceState(SERVICE_RUNNING);
  PipeServerLoop();
  StopAcceleration("service stopped", false);
  {
    std::lock_guard<std::mutex> lock(g_runtime.mutex);
    if (g_runtime.wintun_adapter != nullptr) {
      g_runtime.wintun.close_adapter(g_runtime.wintun_adapter);
      g_runtime.wintun_adapter = nullptr;
    }
  }
  WSACleanup();
  LogEvent("Windows helper service stopped");
  SetServiceState(SERVICE_STOPPED);
}

bool InstallService() {
  wchar_t path[MAX_PATH] = {};
  GetModuleFileNameW(nullptr, path, MAX_PATH);
  std::wstring command = L"\"" + std::wstring(path) + L"\" service";
  SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CREATE_SERVICE);
  if (scm == nullptr) {
    return false;
  }
  SC_HANDLE service = CreateServiceW(
      scm, kServiceName, kServiceDisplayName, SERVICE_ALL_ACCESS, SERVICE_WIN32_OWN_PROCESS,
      SERVICE_AUTO_START, SERVICE_ERROR_NORMAL, command.c_str(), nullptr, nullptr, nullptr,
      nullptr, nullptr);
  if (service == nullptr && GetLastError() == ERROR_SERVICE_EXISTS) {
    service = OpenServiceW(scm, kServiceName, SERVICE_ALL_ACCESS);
    if (service != nullptr) {
      ChangeServiceConfigW(service, SERVICE_WIN32_OWN_PROCESS, SERVICE_AUTO_START,
                           SERVICE_ERROR_NORMAL, command.c_str(), nullptr, nullptr,
                           nullptr, nullptr, nullptr, nullptr);
    }
  }
  if (service == nullptr) {
    CloseServiceHandle(scm);
    return false;
  }
  StartServiceW(service, 0, nullptr);
  SERVICE_STATUS status = {};
  for (int i = 0; i < 30; ++i) {
    QueryServiceStatus(service, &status);
    if (status.dwCurrentState == SERVICE_RUNNING) {
      break;
    }
    Sleep(200);
  }
  SERVICE_DESCRIPTIONW desc = {};
  desc.lpDescription = const_cast<LPWSTR>(
      L"Privileged SD-WAN Verge helper for Wintun, WinDivert, routes, and cleanup.");
  ChangeServiceConfig2W(service, SERVICE_CONFIG_DESCRIPTION, &desc);
  CloseServiceHandle(service);
  CloseServiceHandle(scm);
  LogEvent("Windows helper service installed");
  return true;
}

bool StopAndDeleteService() {
  SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT);
  if (scm == nullptr) {
    return false;
  }
  SC_HANDLE service = OpenServiceW(scm, kServiceName, SERVICE_STOP | DELETE | SERVICE_QUERY_STATUS);
  if (service == nullptr) {
    const DWORD error = GetLastError();
    CloseServiceHandle(scm);
    return error == ERROR_SERVICE_DOES_NOT_EXIST;
  }
  SERVICE_STATUS status = {};
  ControlService(service, SERVICE_CONTROL_STOP, &status);
  for (int i = 0; i < 30; ++i) {
    QueryServiceStatus(service, &status);
    if (status.dwCurrentState == SERVICE_STOPPED) {
      break;
    }
    Sleep(200);
  }
  const bool ok = DeleteService(service) == TRUE;
  CloseServiceHandle(service);
  CloseServiceHandle(scm);
  LogEvent("Windows helper service uninstalled");
  return ok;
}

int CommandSelfTest() {
  WSADATA wsa = {};
  WSAStartup(MAKEWORD(2, 2), &wsa);
  uint8_t packet[256] = {};
  size_t len = 0;
  NatTable table = {};
  const uint32_t tun_ip = 0x0aff0002;
  const uint32_t physical_ip = 0xc0a80158;
  const uint32_t cpe_ip = 0xc0a8018c;
  const uint32_t remote_ip = 0x08080808;
  MakeUdpPacket(packet, &len, tun_ip, remote_ip, 12345, 53);
  if (!NatTranslateOutgoing(&table, packet, len, physical_ip, cpe_ip)) {
    fprintf(stderr, "nat outgoing failed\n");
    return 1;
  }
  if (ReadU32(packet + 12) != physical_ip ||
      ReadU16(packet + 20) < kNatPortStart || ReadU16(packet + 20) > kNatPortEnd ||
      ReadU32(packet + 16) != cpe_ip) {
    fprintf(stderr, "nat outbound rewrite failed\n");
    return 1;
  }
  const uint16_t translated_port = ReadU16(packet + 20);
  uint8_t reply[256] = {};
  MakeUdpPacket(reply, &len, cpe_ip, physical_ip, 53, translated_port);
  if (!NatTranslateIncoming(&table, reply, len, physical_ip) ||
      ReadU32(reply + 16) != tun_ip ||
      ReadU32(reply + 12) != remote_ip ||
      ReadU16(reply + 22) != 12345) {
    fprintf(stderr, "nat inbound restore failed\n");
    return 1;
  }
  NatTable dns_table = {};
  const uint8_t dns_query_payload[] = {
      0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x07, 'e',  'x',  'a',
      'm',  'p',  'l',  'e',  0x03, 'c',  'o',  'm',
      0x00, 0x00, 0x01, 0x00, 0x01,
  };
  MakeUdpPacket(packet, &len, tun_ip, remote_ip, 12345, 53);
  AppendUdpPayload(packet, &len, dns_query_payload, sizeof(dns_query_payload));
  char query_domain[256] = {};
  if (!DnsQueryDomainFromPacket(packet, len, query_domain, sizeof(query_domain)) ||
      strcmp(query_domain, "example.com") != 0) {
    fprintf(stderr, "dns query parse failed\n");
    return 1;
  }
  if (!NatTranslateOutgoing(&dns_table, packet, len, physical_ip, cpe_ip)) {
    fprintf(stderr, "dns nat outgoing failed\n");
    return 1;
  }
  const uint16_t dns_translated_port = ReadU16(packet + 20);
  const uint8_t dns_response_payload[] = {
      0x12, 0x34, 0x81, 0x80, 0x00, 0x01, 0x00, 0x01,
      0x00, 0x00, 0x00, 0x00, 0x07, 'e',  'x',  'a',
      'm',  'p',  'l',  'e',  0x03, 'c',  'o',  'm',
      0x00, 0x00, 0x01, 0x00, 0x01, 0xc0, 0x0c, 0x00,
      0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x3c, 0x00,
      0x04, 0x5d, 0xb8, 0xd8, 0x22,
  };
  MakeUdpPacket(reply, &len, cpe_ip, physical_ip, 53, dns_translated_port);
  AppendUdpPayload(reply, &len, dns_response_payload, sizeof(dns_response_payload));
  if (!NatTranslateIncoming(&dns_table, reply, len, physical_ip) ||
      strcmp(DnsCacheLookup(&dns_table, 0x5db8d822), "example.com") != 0) {
    fprintf(stderr, "dns cache failed\n");
    return 1;
  }
  Runtime rate_runtime = {};
  rate_runtime.tx_bytes = 1500;
  rate_runtime.rx_bytes = 3000;
  rate_runtime.last_tx_bytes = 500;
  rate_runtime.last_rx_bytes = 1000;
  rate_runtime.last_rate_at = 10;
  NatEntry* rate_entry = &rate_runtime.nat.entries[0];
  rate_entry->used = true;
  rate_entry->tx_bytes = 700;
  rate_entry->rx_bytes = 900;
  rate_entry->last_tx_bytes = 100;
  rate_entry->last_rx_bytes = 300;
  rate_entry->last_rate_at = 10;
  UpdateRatesLocked(&rate_runtime, 15);
  if (rate_runtime.tx_rate != 200 || rate_runtime.rx_rate != 400 ||
      rate_entry->tx_rate != 120 || rate_entry->rx_rate != 120) {
    fprintf(stderr, "rate calculation failed\n");
    return 1;
  }
  WSACleanup();
  printf("SELF_TEST_OK\n");
  return 0;
}

void PrintUsage() {
  fprintf(stderr,
          "sdwan_windows_helper {install|uninstall|service|start|stop|status|health|logs|connections|self-test} [--cpe ip] [--limit n]\n");
}

std::string CliCommandFromArgs(int argc, wchar_t** argv) {
  std::string command = argc >= 2 ? WideToUtf8(argv[1]) : "status";
  for (int i = 2; i < argc; ++i) {
    const std::wstring arg = argv[i];
    if (arg == L"--cpe" && i + 1 < argc) {
      command += " cpe=" + WideToUtf8(argv[++i]);
    } else if (arg == L"--limit" && i + 1 < argc) {
      command += " limit=" + WideToUtf8(argv[++i]);
    }
  }
  return command;
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
  if (argc < 2) {
    PrintUsage();
    return 1;
  }
  const std::wstring command = argv[1];
  if (command == L"service") {
    SERVICE_TABLE_ENTRYW table[] = {
        {const_cast<LPWSTR>(kServiceName), ServiceMain},
        {nullptr, nullptr},
    };
    return StartServiceCtrlDispatcherW(table) ? 0 : 1;
  }
  if (command == L"self-test") {
    return CommandSelfTest();
  }
  if (command == L"install") {
    const bool ok = InstallService();
    printf("state=stopped\nadapterName=Windows Wintun\npermission=%s\nhelperInstalled=%s\n"
           "host=192.168.1.140\nreachable=false\nserviceReady=%s\n"
           "txBytes=0\nrxBytes=0\ntxRate=0\nrxRate=0\nlastError=%s\n",
           ok ? "ready" : "denied", ok ? "true" : "false", ok ? "true" : "false",
           ok ? "" : "failed to install service");
    return ok ? 0 : 1;
  }
  if (command == L"uninstall") {
    SendPipeCommand("stop");
    const bool ok = StopAndDeleteService();
    printf("state=stopped\nadapterName=Windows Wintun\npermission=%s\nhelperInstalled=false\n"
           "host=192.168.1.140\nreachable=false\nserviceReady=false\n"
           "txBytes=0\nrxBytes=0\ntxRate=0\nrxRate=0\nlastError=%s\n",
           ok ? "needsHelperInstall" : "denied", ok ? "" : "failed to uninstall service");
    return ok ? 0 : 1;
  }
  const std::string pipe_command = CliCommandFromArgs(argc, argv);
  const std::string response = SendPipeCommand(pipe_command);
  fwrite(response.data(), 1, response.size(), stdout);
  return response.find("permission=needsHelperInstall") == std::string::npos ? 0 : 2;
}
