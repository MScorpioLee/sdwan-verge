#define _DARWIN_C_SOURCE

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <net/bpf.h>
#include <net/ethernet.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <net/if_utun.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/kern_control.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/sys_domain.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#ifndef UTUN_CONTROL_NAME
#define UTUN_CONTROL_NAME "com.apple.net.utun_control"
#endif

#ifndef UTUN_OPT_IFNAME
#define UTUN_OPT_IFNAME 2
#endif

#ifndef IP_BOUND_IF
#define IP_BOUND_IF 25
#endif

#define DEFAULT_CPE "192.168.1.140"
#define DEFAULT_TUN_LOCAL "10.255.0.2"
#define DEFAULT_TUN_PEER "10.255.0.1"
#define DEFAULT_L3_HOST "1.1.1.1"
#define DEFAULT_L3_PORT 53
#define DEFAULT_STATE_DIR "/var/run/sdwan-verge"
#define DEFAULT_LOG_FILE "/var/log/sdwan-verge-helper.log"
#define EVENT_LOG_NAME "events.log"
#define CONNECTIONS_FILE_NAME "connections"
#define PF_ANCHOR "com.apple/sdwan-verge"
#define HELPER_NAME "sdwan-macos-helper"
#define INSTALLED_HELPER_DIR "/Library/PrivilegedHelperTools"
#define INSTALLED_HELPER_PATH "/Library/PrivilegedHelperTools/com.sdwan.verge.helper"
#define MAX_PACKET 2000
#define MAX_FRAME 2200
#define MAX_NAT 4096
#define MAX_DNS_CACHE 2048
#define HEARTBEAT_TIMEOUT_SEC 30
#define HEALTH_INTERVAL_SEC 2
#define DNS_PROBE_TIMEOUT_SEC 1
#define TUN_MTU 1400
#define TCP_MSS_CLAMP 1360
#define NAT_PORT_START 42000
#define NAT_PORT_END 42999

typedef struct {
  char cpe[64];
  char ifname[IFNAMSIZ];
  char utun[IFNAMSIZ];
  char tun_local[64];
  char tun_peer[64];
  char state_dir[256];
  char l3_host[64];
  int l3_port;
  bool foreground;
} HelperConfig;

typedef struct {
  bool used;
  uint8_t proto;
  uint32_t remote_ip;
  uint32_t original_remote_ip;
  uint32_t original_src_ip;
  uint16_t original_src_port;
  uint16_t translated_port;
  uint16_t remote_port;
  uint64_t tx_bytes;
  uint64_t rx_bytes;
  uint64_t tx_rate;
  uint64_t rx_rate;
  uint64_t last_tx_bytes;
  uint64_t last_rx_bytes;
  time_t last_rate_at;
  time_t last_seen;
  char domain[256];
} NatEntry;

typedef struct {
  bool used;
  uint32_t ip;
  time_t last_seen;
  char domain[256];
} DnsCacheEntry;

typedef struct {
  NatEntry entries[MAX_NAT];
  DnsCacheEntry dns[MAX_DNS_CACHE];
} NatTable;

typedef struct {
  int tun_fd;
  int bpf_fd;
  HelperConfig config;
  char state_file[512];
  char heartbeat_file[512];
  char event_log_file[512];
  char connections_file[512];
  char pf_token_file[512];
  char physical_ifname[IFNAMSIZ];
  char utun_ifname[IFNAMSIZ];
  uint8_t local_mac[6];
  uint8_t cpe_mac[6];
  uint32_t cpe_ip;
  uint32_t physical_ip;
  uint32_t tun_ip;
  bool routes_added;
  bool pf_loaded;
  bool auto_recovered;
  char last_error[512];
  uint64_t tx_bytes;
  uint64_t rx_bytes;
  uint64_t tx_rate;
  uint64_t rx_rate;
  uint64_t last_tx_bytes;
  uint64_t last_rx_bytes;
  time_t last_rate_at;
  NatTable nat;
} Runtime;

static Runtime g_runtime;
static volatile sig_atomic_t g_stop_requested = 0;

static void cleanup_routes(Runtime *runtime);

static void init_config(HelperConfig *config) {
  memset(config, 0, sizeof(*config));
  snprintf(config->cpe, sizeof(config->cpe), "%s", DEFAULT_CPE);
  snprintf(config->tun_local, sizeof(config->tun_local), "%s", DEFAULT_TUN_LOCAL);
  snprintf(config->tun_peer, sizeof(config->tun_peer), "%s", DEFAULT_TUN_PEER);
  snprintf(config->state_dir, sizeof(config->state_dir), "%s", DEFAULT_STATE_DIR);
  snprintf(config->l3_host, sizeof(config->l3_host), "%s", DEFAULT_L3_HOST);
  config->l3_port = DEFAULT_L3_PORT;
}

static void log_line(const char *message) {
  FILE *file = fopen(DEFAULT_LOG_FILE, "a");
  if (file == NULL) {
    return;
  }
  time_t now = time(NULL);
  fprintf(file, "%ld %s\n", (long)now, message);
  fclose(file);
}

static bool adopt_root_identity(void) {
  if (geteuid() != 0) {
    return false;
  }
  if (getgid() != 0 && setgid(0) != 0) {
    return false;
  }
  if (getuid() != 0 && setuid(0) != 0) {
    return false;
  }
  return getuid() == 0 && geteuid() == 0;
}

static int require_root_identity(const char *operation) {
  if (!adopt_root_identity()) {
    fprintf(stderr, "%s requires root\n", operation);
    return 77;
  }
  return 0;
}

static int run_command(const char *command) {
  log_line(command);
  return system(command);
}

static int run_command_capture(const char *command, char *buffer, size_t size) {
  log_line(command);
  FILE *pipe = popen(command, "r");
  if (pipe == NULL) {
    if (size > 0) {
      buffer[0] = '\0';
    }
    return 127;
  }
  size_t offset = 0;
  while (offset + 1 < size) {
    size_t n = fread(buffer + offset, 1, size - offset - 1, pipe);
    offset += n;
    if (n == 0) {
      break;
    }
  }
  if (size > 0) {
    buffer[offset] = '\0';
  }
  int status = pclose(pipe);
  if (status == -1) {
    return 127;
  }
  if (WIFEXITED(status)) {
    return WEXITSTATUS(status);
  }
  return status;
}

static bool capture_command(const char *command, char *buffer, size_t size) {
  FILE *pipe = popen(command, "r");
  if (pipe == NULL) {
    return false;
  }
  size_t offset = 0;
  while (offset + 1 < size) {
    size_t n = fread(buffer + offset, 1, size - offset - 1, pipe);
    offset += n;
    if (n == 0) {
      break;
    }
  }
  buffer[offset] = '\0';
  int rc = pclose(pipe);
  return rc == 0 || offset > 0;
}

static void path_join(char *out, size_t out_size, const char *dir, const char *name) {
  snprintf(out, out_size, "%s/%s", dir, name);
}

static bool ensure_state_dir(const char *dir) {
  if (mkdir(dir, 0755) == 0 || errno == EEXIST) {
    return true;
  }
  return false;
}

static void write_text_file(const char *path, const char *content) {
  FILE *file = fopen(path, "w");
  if (file == NULL) {
    return;
  }
  fputs(content, file);
  fclose(file);
}

static bool read_text_file(const char *path, char *buffer, size_t size) {
  FILE *file = fopen(path, "r");
  if (file == NULL) {
    return false;
  }
  size_t n = fread(buffer, 1, size - 1, file);
  buffer[n] = '\0';
  fclose(file);
  return true;
}

static void append_text_file(const char *path, const char *content) {
  FILE *file = fopen(path, "a");
  if (file == NULL) {
    return;
  }
  fputs(content, file);
  fclose(file);
}

static void format_event_time(time_t raw_time, char *out, size_t out_size) {
  struct tm tm_value;
  localtime_r(&raw_time, &tm_value);
  strftime(out, out_size, "%Y-%m-%d %H:%M:%S", &tm_value);
}

static void event_log_path(const HelperConfig *config, char *out, size_t out_size) {
  path_join(out, out_size, config->state_dir, EVENT_LOG_NAME);
}

static void connections_path(const HelperConfig *config, char *out, size_t out_size) {
  path_join(out, out_size, config->state_dir, CONNECTIONS_FILE_NAME);
}

static void log_event(const HelperConfig *config, const char *message) {
  char path[512];
  char line[1024];
  event_log_path(config, path, sizeof(path));
  snprintf(line, sizeof(line), "%ld %s\n", (long)time(NULL), message);
  append_text_file(path, line);
}

static void touch_file(const char *path) {
  FILE *file = fopen(path, "a");
  if (file != NULL) {
    fclose(file);
  }
  struct timeval times[2];
  gettimeofday(&times[0], NULL);
  times[1] = times[0];
  utimes(path, times);
}

static bool file_mtime_age_exceeds(const char *path, int seconds) {
  struct stat st;
  if (stat(path, &st) != 0) {
    return false;
  }
  return time(NULL) - st.st_mtime > seconds;
}

static void redirect_stdio_to_devnull(void) {
  int fd = open("/dev/null", O_RDWR);
  if (fd < 0) {
    return;
  }
  (void)dup2(fd, STDIN_FILENO);
  (void)dup2(fd, STDOUT_FILENO);
  (void)dup2(fd, STDERR_FILENO);
  if (fd > STDERR_FILENO) {
    close(fd);
  }
}

static uint16_t read_u16(const uint8_t *p) {
  return (uint16_t)((p[0] << 8) | p[1]);
}

static uint32_t read_u32(const uint8_t *p) {
  return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3];
}

static void ipv4_to_string(uint32_t ip, char *out, size_t out_size) {
  struct in_addr addr;
  addr.s_addr = htonl(ip);
  inet_ntop(AF_INET, &addr, out, (socklen_t)out_size);
}

static void write_u16(uint8_t *p, uint16_t v) {
  p[0] = (uint8_t)(v >> 8);
  p[1] = (uint8_t)(v & 0xff);
}

static void write_u32(uint8_t *p, uint32_t v) {
  p[0] = (uint8_t)(v >> 24);
  p[1] = (uint8_t)((v >> 16) & 0xff);
  p[2] = (uint8_t)((v >> 8) & 0xff);
  p[3] = (uint8_t)(v & 0xff);
}

static uint16_t checksum16(const uint8_t *data, size_t len) {
  uint32_t sum = 0;
  for (size_t i = 0; i + 1 < len; i += 2) {
    sum += read_u16(data + i);
  }
  if ((len & 1) != 0) {
    sum += (uint16_t)(data[len - 1] << 8);
  }
  while ((sum >> 16) != 0) {
    sum = (sum & 0xffff) + (sum >> 16);
  }
  return (uint16_t)(~sum);
}

static void fix_ipv4_checksum(uint8_t *packet, size_t len) {
  if (len < 20) {
    return;
  }
  size_t ihl = (packet[0] & 0x0f) * 4;
  if (ihl < 20 || ihl > len) {
    return;
  }
  write_u16(packet + 10, 0);
  write_u16(packet + 10, checksum16(packet, ihl));
}

static uint16_t transport_checksum(const uint8_t *packet, size_t len, size_t offset, uint8_t proto) {
  if (len < offset) {
    return 0;
  }
  size_t payload_len = len - offset;
  uint32_t sum = 0;
  sum += read_u16(packet + 12);
  sum += read_u16(packet + 14);
  sum += read_u16(packet + 16);
  sum += read_u16(packet + 18);
  sum += proto;
  sum += (uint16_t)payload_len;
  const uint8_t *payload = packet + offset;
  for (size_t i = 0; i + 1 < payload_len; i += 2) {
    sum += read_u16(payload + i);
  }
  if ((payload_len & 1) != 0) {
    sum += (uint16_t)(payload[payload_len - 1] << 8);
  }
  while ((sum >> 16) != 0) {
    sum = (sum & 0xffff) + (sum >> 16);
  }
  return (uint16_t)(~sum);
}

static void fix_transport_checksum(uint8_t *packet, size_t len) {
  if (len < 20) {
    return;
  }
  size_t ihl = (packet[0] & 0x0f) * 4;
  uint8_t proto = packet[9];
  if (ihl < 20 || ihl > len) {
    return;
  }
  if (proto == IPPROTO_TCP && len >= ihl + 20) {
    write_u16(packet + ihl + 16, 0);
    write_u16(packet + ihl + 16, transport_checksum(packet, len, ihl, proto));
  } else if (proto == IPPROTO_UDP && len >= ihl + 8) {
    write_u16(packet + ihl + 6, 0);
    write_u16(packet + ihl + 6, transport_checksum(packet, len, ihl, proto));
  } else if (proto == IPPROTO_ICMP && len > ihl + 4) {
    write_u16(packet + ihl + 2, 0);
    write_u16(packet + ihl + 2, checksum16(packet + ihl, len - ihl));
  }
}

static bool clamp_tcp_mss(uint8_t *packet, size_t len, uint16_t max_mss) {
  if (len < 40 || (packet[0] >> 4) != 4 || packet[9] != IPPROTO_TCP) {
    return false;
  }
  size_t ihl = (packet[0] & 0x0f) * 4;
  if (ihl < 20 || len < ihl + 20) {
    return false;
  }
  uint8_t *tcp = packet + ihl;
  uint8_t flags = tcp[13];
  if ((flags & 0x02) == 0) {
    return false;
  }
  size_t tcp_header_len = ((tcp[12] >> 4) & 0x0f) * 4;
  if (tcp_header_len < 20 || len < ihl + tcp_header_len) {
    return false;
  }
  size_t option = ihl + 20;
  size_t option_end = ihl + tcp_header_len;
  while (option < option_end) {
    uint8_t kind = packet[option];
    if (kind == 0) {
      break;
    }
    if (kind == 1) {
      option++;
      continue;
    }
    if (option + 1 >= option_end) {
      break;
    }
    uint8_t option_len = packet[option + 1];
    if (option_len < 2 || option + option_len > option_end) {
      break;
    }
    if (kind == 2 && option_len == 4) {
      uint16_t current = read_u16(packet + option + 2);
      if (current > max_mss) {
        write_u16(packet + option + 2, max_mss);
        fix_transport_checksum(packet, len);
        return true;
      }
      return false;
    }
    option += option_len;
  }
  return false;
}

static bool parse_ipv4_ports(const uint8_t *packet, size_t len, uint16_t *src_port, uint16_t *dst_port) {
  if (len < 20) {
    return false;
  }
  size_t ihl = (packet[0] & 0x0f) * 4;
  uint8_t proto = packet[9];
  if (proto == IPPROTO_TCP || proto == IPPROTO_UDP) {
    if (len < ihl + 4) {
      return false;
    }
    *src_port = read_u16(packet + ihl);
    *dst_port = read_u16(packet + ihl + 2);
    return true;
  }
  if (proto == IPPROTO_ICMP && len >= ihl + 8) {
    *src_port = read_u16(packet + ihl + 4);
    *dst_port = 0;
    return true;
  }
  return false;
}

static bool write_ipv4_src_port(uint8_t *packet, size_t len, uint16_t port) {
  size_t ihl = (packet[0] & 0x0f) * 4;
  uint8_t proto = packet[9];
  if ((proto == IPPROTO_TCP || proto == IPPROTO_UDP) && len >= ihl + 4) {
    write_u16(packet + ihl, port);
    return true;
  }
  if (proto == IPPROTO_ICMP && len >= ihl + 8) {
    write_u16(packet + ihl + 4, port);
    return true;
  }
  return false;
}

static bool write_ipv4_dst_port(uint8_t *packet, size_t len, uint16_t port) {
  size_t ihl = (packet[0] & 0x0f) * 4;
  uint8_t proto = packet[9];
  if ((proto == IPPROTO_TCP || proto == IPPROTO_UDP) && len >= ihl + 4) {
    write_u16(packet + ihl + 2, port);
    return true;
  }
  if (proto == IPPROTO_ICMP && len >= ihl + 8) {
    write_u16(packet + ihl + 4, port);
    return true;
  }
  return false;
}

static bool dns_read_name(const uint8_t *dns, size_t len, size_t *offset, char *out, size_t out_size) {
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
    uint8_t label_len = dns[pos];
    if (label_len == 0) {
      pos++;
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
      uint16_t pointer = (uint16_t)(((label_len & 0x3f) << 8) | dns[pos + 1]);
      if (!jumped) {
        next_offset = pos + 2;
      }
      pos = pointer;
      jumped = true;
      jumps++;
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

static bool dns_query_domain_from_packet(const uint8_t *packet, size_t len, char *out, size_t out_size) {
  if (len < 20 || packet[9] != IPPROTO_UDP) {
    return false;
  }
  size_t ihl = (packet[0] & 0x0f) * 4;
  if (ihl < 20 || len < ihl + 8 + 12) {
    return false;
  }
  const uint8_t *dns = packet + ihl + 8;
  size_t dns_len = len - ihl - 8;
  if (read_u16(dns + 4) == 0) {
    return false;
  }
  size_t offset = 12;
  return dns_read_name(dns, dns_len, &offset, out, out_size);
}

static void dns_cache_put(NatTable *table, uint32_t ip, const char *domain) {
  if (ip == 0 || domain == NULL || domain[0] == '\0') {
    return;
  }
  DnsCacheEntry *slot = NULL;
  for (size_t i = 0; i < MAX_DNS_CACHE; i++) {
    DnsCacheEntry *entry = &table->dns[i];
    if (entry->used && entry->ip == ip) {
      slot = entry;
      break;
    }
    if (slot == NULL || !entry->used || entry->last_seen < slot->last_seen) {
      slot = entry;
    }
  }
  if (slot == NULL) {
    return;
  }
  slot->used = true;
  slot->ip = ip;
  slot->last_seen = time(NULL);
  snprintf(slot->domain, sizeof(slot->domain), "%s", domain);
}

static const char *dns_cache_lookup(NatTable *table, uint32_t ip) {
  time_t now = time(NULL);
  for (size_t i = 0; i < MAX_DNS_CACHE; i++) {
    DnsCacheEntry *entry = &table->dns[i];
    if (entry->used && entry->ip == ip && now - entry->last_seen <= 600) {
      return entry->domain;
    }
  }
  return "";
}

static void dns_cache_answers_from_packet(NatTable *table, const uint8_t *packet, size_t len,
                                          const char *fallback_domain) {
  if (fallback_domain == NULL || fallback_domain[0] == '\0' ||
      len < 20 || packet[9] != IPPROTO_UDP) {
    return;
  }
  size_t ihl = (packet[0] & 0x0f) * 4;
  if (ihl < 20 || len < ihl + 8 + 12) {
    return;
  }
  const uint8_t *dns = packet + ihl + 8;
  size_t dns_len = len - ihl - 8;
  if ((dns[2] & 0x80) == 0) {
    return;
  }
  uint16_t qdcount = read_u16(dns + 4);
  uint16_t ancount = read_u16(dns + 6);
  size_t offset = 12;
  char name[256];
  for (uint16_t i = 0; i < qdcount; i++) {
    if (!dns_read_name(dns, dns_len, &offset, name, sizeof(name)) || offset + 4 > dns_len) {
      return;
    }
    offset += 4;
  }
  for (uint16_t i = 0; i < ancount; i++) {
    if (!dns_read_name(dns, dns_len, &offset, name, sizeof(name)) || offset + 10 > dns_len) {
      return;
    }
    uint16_t type = read_u16(dns + offset);
    uint16_t klass = read_u16(dns + offset + 2);
    uint16_t rdlen = read_u16(dns + offset + 8);
    offset += 10;
    if (offset + rdlen > dns_len) {
      return;
    }
    if (type == 1 && klass == 1 && rdlen == 4) {
      uint32_t ip = read_u32(dns + offset);
      dns_cache_put(table, ip, fallback_domain);
    }
    offset += rdlen;
  }
}

static bool nat_port_in_use(NatTable *table, uint8_t proto, uint16_t translated_port) {
  for (size_t i = 0; i < MAX_NAT; i++) {
    NatEntry *entry = &table->entries[i];
    if (entry->used && entry->proto == proto && entry->translated_port == translated_port) {
      return true;
    }
  }
  return false;
}

static uint16_t nat_allocate_port(NatTable *table, uint8_t proto, uint16_t original_port) {
  uint16_t range = (uint16_t)(NAT_PORT_END - NAT_PORT_START + 1);
  uint16_t first = (uint16_t)(NAT_PORT_START + (original_port % range));
  for (uint16_t i = 0; i < range; i++) {
    uint16_t candidate = (uint16_t)(NAT_PORT_START + ((first - NAT_PORT_START + i) % range));
    if (!nat_port_in_use(table, proto, candidate)) {
      return candidate;
    }
  }
  return 0;
}

static NatEntry *nat_find_outgoing(NatTable *table, uint8_t proto, uint32_t original_src_ip,
                                   uint32_t remote_ip, uint16_t original_src_port,
                                   uint16_t remote_port) {
  for (size_t i = 0; i < MAX_NAT; i++) {
    NatEntry *entry = &table->entries[i];
    if (entry->used && entry->proto == proto && entry->original_src_ip == original_src_ip &&
        entry->original_remote_ip == remote_ip && entry->original_src_port == original_src_port &&
        entry->remote_port == remote_port) {
      entry->last_seen = time(NULL);
      return entry;
    }
  }
  return NULL;
}

static NatEntry *nat_find_free_slot(NatTable *table) {
  time_t now = time(NULL);
  NatEntry *free_slot = NULL;
  for (size_t i = 0; i < MAX_NAT; i++) {
    NatEntry *entry = &table->entries[i];
    if (!entry->used) {
      return entry;
    }
    if (free_slot == NULL || entry->last_seen < free_slot->last_seen) {
      free_slot = entry;
    }
    if (now - entry->last_seen > 300) {
      return entry;
    }
  }
  return free_slot;
}

static NatEntry *nat_lookup_return(NatTable *table, uint8_t proto, uint32_t remote_ip,
                                   uint16_t local_port, uint16_t remote_port) {
  for (size_t i = 0; i < MAX_NAT; i++) {
    NatEntry *entry = &table->entries[i];
    if (entry->used && entry->proto == proto && entry->remote_ip == remote_ip &&
        entry->translated_port == local_port && entry->remote_port == remote_port) {
      entry->last_seen = time(NULL);
      return entry;
    }
  }
  return NULL;
}

static bool should_redirect_dns(uint8_t proto, uint16_t dst_port) {
  return (proto == IPPROTO_TCP || proto == IPPROTO_UDP) && dst_port == 53;
}

static bool nat_translate_outgoing(NatTable *table, uint8_t *packet, size_t len,
                                   uint32_t physical_ip, uint32_t cpe_ip) {
  if (len < 20 || (packet[0] >> 4) != 4) {
    return false;
  }
  uint8_t proto = packet[9];
  uint16_t src_port = 0;
  uint16_t dst_port = 0;
  if (!parse_ipv4_ports(packet, len, &src_port, &dst_port)) {
    return false;
  }
  uint32_t original_src_ip = read_u32(packet + 12);
  uint32_t original_remote_ip = read_u32(packet + 16);
  uint32_t remote_ip = should_redirect_dns(proto, dst_port) ? cpe_ip : original_remote_ip;
  NatEntry *entry = nat_find_outgoing(table, proto, original_src_ip, original_remote_ip, src_port, dst_port);
  if (entry == NULL) {
    entry = nat_find_free_slot(table);
    if (entry == NULL) {
      return false;
    }
    memset(entry, 0, sizeof(*entry));
    uint16_t translated_port = nat_allocate_port(table, proto, src_port);
    if (translated_port == 0) {
      return false;
    }
    entry->translated_port = translated_port;
  }
  if (entry == NULL) {
    return false;
  }
  entry->used = true;
  entry->proto = proto;
  entry->remote_ip = remote_ip;
  entry->original_remote_ip = original_remote_ip;
  entry->original_src_ip = original_src_ip;
  entry->original_src_port = src_port;
  entry->remote_port = dst_port;
  if (should_redirect_dns(proto, dst_port)) {
    (void)dns_query_domain_from_packet(packet, len, entry->domain, sizeof(entry->domain));
  }
  entry->tx_bytes += len;
  entry->last_seen = time(NULL);
  (void)clamp_tcp_mss(packet, len, TCP_MSS_CLAMP);
  write_u32(packet + 12, physical_ip);
  write_u32(packet + 16, remote_ip);
  if (!write_ipv4_src_port(packet, len, entry->translated_port)) {
    return false;
  }
  fix_ipv4_checksum(packet, len);
  fix_transport_checksum(packet, len);
  return true;
}

static bool nat_translate_incoming(NatTable *table, uint8_t *packet, size_t len, uint32_t physical_ip) {
  if (len < 20 || (packet[0] >> 4) != 4) {
    return false;
  }
  if (read_u32(packet + 16) != physical_ip) {
    return false;
  }
  uint8_t proto = packet[9];
  uint16_t src_port = 0;
  uint16_t dst_port = 0;
  if (!parse_ipv4_ports(packet, len, &src_port, &dst_port)) {
    return false;
  }
  uint32_t remote_ip = read_u32(packet + 12);
  NatEntry *entry = nat_lookup_return(table, proto, remote_ip, dst_port, src_port);
  if (entry == NULL) {
    return false;
  }
  if (entry->remote_port == 53 && entry->domain[0] != '\0') {
    dns_cache_answers_from_packet(table, packet, len, entry->domain);
  }
  entry->rx_bytes += len;
  write_u32(packet + 12, entry->original_remote_ip);
  write_u32(packet + 16, entry->original_src_ip);
  if (!write_ipv4_dst_port(packet, len, entry->original_src_port)) {
    return false;
  }
  fix_ipv4_checksum(packet, len);
  fix_transport_checksum(packet, len);
  return true;
}

static size_t build_ethernet_frame(uint8_t *frame, size_t frame_size,
                                   const uint8_t dst[6], const uint8_t src[6],
                                   const uint8_t *packet, size_t packet_len) {
  if (frame_size < packet_len + 14) {
    return 0;
  }
  memcpy(frame, dst, 6);
  memcpy(frame + 6, src, 6);
  frame[12] = 0x08;
  frame[13] = 0x00;
  memcpy(frame + 14, packet, packet_len);
  return packet_len + 14;
}

static void print_plan(const HelperConfig *config) {
  const char *ifname = config->ifname[0] == '\0' ? "en0" : config->ifname;
  const char *utun = config->utun[0] == '\0' ? "utun9" : config->utun;
  printf("/sbin/ifconfig %s inet %s %s mtu %d up\n", utun, config->tun_local, config->tun_peer, TUN_MTU);
  printf("/sbin/route -n add -host %s -interface %s\n", config->cpe, ifname);
  printf("/sbin/route -n add 0.0.0.0/1 -interface %s\n", utun);
  printf("/sbin/route -n add 128.0.0.0/1 -interface %s\n", utun);
  printf("printf 'block in quick on %s proto { tcp udp } from any to <physical_ip> port %d:%d\\n' | /sbin/pfctl -a %s -f -\n",
         ifname, NAT_PORT_START, NAT_PORT_END, PF_ANCHOR);
  printf("/sbin/pfctl -E\n");
  printf("PLAN_ONLY_NO_CHANGES_APPLIED\n");
}

static bool parse_mac(const char *text, uint8_t mac[6]) {
  unsigned int values[6];
  if (sscanf(text, "%x:%x:%x:%x:%x:%x",
             &values[0], &values[1], &values[2], &values[3], &values[4], &values[5]) == 6) {
    for (int i = 0; i < 6; i++) {
      mac[i] = (uint8_t)values[i];
    }
    return true;
  }
  return false;
}

static bool get_interface_mac_ip(const char *ifname, uint8_t mac[6], uint32_t *ip) {
  struct ifaddrs *ifaddr = NULL;
  if (getifaddrs(&ifaddr) != 0) {
    return false;
  }
  bool got_mac = false;
  bool got_ip = false;
  for (struct ifaddrs *ifa = ifaddr; ifa != NULL; ifa = ifa->ifa_next) {
    if (ifa->ifa_addr == NULL || strcmp(ifa->ifa_name, ifname) != 0) {
      continue;
    }
    if (ifa->ifa_addr->sa_family == AF_LINK) {
      struct sockaddr_dl *sdl = (struct sockaddr_dl *)ifa->ifa_addr;
      if (sdl->sdl_alen == 6) {
        memcpy(mac, LLADDR(sdl), 6);
        got_mac = true;
      }
    } else if (ifa->ifa_addr->sa_family == AF_INET) {
      struct sockaddr_in *sin = (struct sockaddr_in *)ifa->ifa_addr;
      *ip = ntohl(sin->sin_addr.s_addr);
      got_ip = true;
    }
  }
  freeifaddrs(ifaddr);
  return got_mac && got_ip;
}

static bool route_get_interface(const char *host, char *ifname, size_t ifname_size) {
  char command[256];
  char output[4096];
  snprintf(command, sizeof(command), "/sbin/route -n get %s 2>/dev/null", host);
  if (!capture_command(command, output, sizeof(output))) {
    return false;
  }
  char *line = strtok(output, "\n");
  while (line != NULL) {
    while (*line == ' ' || *line == '\t') {
      line++;
    }
    if (strncmp(line, "interface:", 10) == 0) {
      char value[IFNAMSIZ];
      if (sscanf(line + 10, "%15s", value) == 1) {
        snprintf(ifname, ifname_size, "%s", value);
        return true;
      }
    }
    line = strtok(NULL, "\n");
  }
  return false;
}

static bool resolve_cpe_mac(const char *cpe, uint8_t mac[6]) {
  char command[256];
  char output[4096];
  snprintf(command, sizeof(command), "/usr/sbin/arp -n %s 2>/dev/null", cpe);
  if (capture_command(command, output, sizeof(output))) {
    char *at = strstr(output, " at ");
    if (at != NULL) {
      at += 4;
      char mac_text[64];
      if (sscanf(at, "%63s", mac_text) == 1 && parse_mac(mac_text, mac)) {
        return true;
      }
    }
  }
  snprintf(command, sizeof(command), "/sbin/ping -c 1 -t 1 %s >/dev/null 2>&1", cpe);
  (void)system(command);
  snprintf(command, sizeof(command), "/usr/sbin/arp -n %s 2>/dev/null", cpe);
  if (!capture_command(command, output, sizeof(output))) {
    return false;
  }
  char *at = strstr(output, " at ");
  if (at == NULL) {
    return false;
  }
  at += 4;
  char mac_text[64];
  return sscanf(at, "%63s", mac_text) == 1 && parse_mac(mac_text, mac);
}

static int create_utun(char *ifname, size_t ifname_size) {
  int fd = socket(PF_SYSTEM, SOCK_DGRAM, SYSPROTO_CONTROL);
  if (fd < 0) {
    return -1;
  }
  struct ctl_info info;
  memset(&info, 0, sizeof(info));
  snprintf(info.ctl_name, sizeof(info.ctl_name), "%s", UTUN_CONTROL_NAME);
  if (ioctl(fd, CTLIOCGINFO, &info) < 0) {
    close(fd);
    return -1;
  }
  struct sockaddr_ctl addr;
  memset(&addr, 0, sizeof(addr));
  addr.sc_len = sizeof(addr);
  addr.sc_family = AF_SYSTEM;
  addr.ss_sysaddr = AF_SYS_CONTROL;
  addr.sc_id = info.ctl_id;
  addr.sc_unit = 0;
  if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
    close(fd);
    return -1;
  }
  socklen_t len = (socklen_t)ifname_size;
  if (getsockopt(fd, SYSPROTO_CONTROL, UTUN_OPT_IFNAME, ifname, &len) < 0) {
    close(fd);
    return -1;
  }
  return fd;
}

static int open_bpf(const char *ifname, unsigned int *buffer_len) {
  char path[32];
  int fd = -1;
  for (int i = 0; i < 256; i++) {
    snprintf(path, sizeof(path), "/dev/bpf%d", i);
    fd = open(path, O_RDWR);
    if (fd >= 0) {
      break;
    }
  }
  if (fd < 0) {
    return -1;
  }
  struct ifreq ifr;
  memset(&ifr, 0, sizeof(ifr));
  snprintf(ifr.ifr_name, sizeof(ifr.ifr_name), "%s", ifname);
  if (ioctl(fd, BIOCSETIF, &ifr) < 0) {
    close(fd);
    return -1;
  }
  unsigned int one = 1;
  (void)ioctl(fd, BIOCIMMEDIATE, &one);
  (void)ioctl(fd, BIOCSHDRCMPLT, &one);
  if (ioctl(fd, BIOCGBLEN, buffer_len) < 0) {
    *buffer_len = 4096;
  }
  return fd;
}

static void update_rates(Runtime *runtime, time_t now) {
  for (size_t i = 0; i < MAX_NAT; i++) {
    NatEntry *entry = &runtime->nat.entries[i];
    if (!entry->used) {
      continue;
    }
    if (entry->last_rate_at == 0) {
      entry->last_rate_at = now;
      entry->last_tx_bytes = entry->tx_bytes;
      entry->last_rx_bytes = entry->rx_bytes;
      continue;
    }
    time_t entry_elapsed = now - entry->last_rate_at;
    if (entry_elapsed <= 0) {
      continue;
    }
    entry->tx_rate = (entry->tx_bytes - entry->last_tx_bytes) / (uint64_t)entry_elapsed;
    entry->rx_rate = (entry->rx_bytes - entry->last_rx_bytes) / (uint64_t)entry_elapsed;
    entry->last_tx_bytes = entry->tx_bytes;
    entry->last_rx_bytes = entry->rx_bytes;
    entry->last_rate_at = now;
  }

  if (runtime->last_rate_at == 0) {
    runtime->last_rate_at = now;
    runtime->last_tx_bytes = runtime->tx_bytes;
    runtime->last_rx_bytes = runtime->rx_bytes;
    return;
  }
  time_t elapsed = now - runtime->last_rate_at;
  if (elapsed <= 0) {
    return;
  }
  runtime->tx_rate = (runtime->tx_bytes - runtime->last_tx_bytes) / (uint64_t)elapsed;
  runtime->rx_rate = (runtime->rx_bytes - runtime->last_rx_bytes) / (uint64_t)elapsed;
  runtime->last_tx_bytes = runtime->tx_bytes;
  runtime->last_rx_bytes = runtime->rx_bytes;
  runtime->last_rate_at = now;
}

static bool install_pf_rule(Runtime *runtime) {
  char ip_text[INET_ADDRSTRLEN];
  char command[1024];
  char output[2048];
  ipv4_to_string(runtime->physical_ip, ip_text, sizeof(ip_text));
  snprintf(command, sizeof(command),
           "printf 'block in quick on %s proto { tcp udp } from any to %s port %d:%d\\n' | "
           "/sbin/pfctl -a %s -f - 2>&1",
           runtime->physical_ifname, ip_text, NAT_PORT_START, NAT_PORT_END, PF_ANCHOR);
  int rc = run_command_capture(command, output, sizeof(output));
  if (rc != 0) {
    output[strcspn(output, "\r\n")] = '\0';
    snprintf(runtime->last_error, sizeof(runtime->last_error),
             "failed to install pf rule%s%s",
             output[0] == '\0' ? "" : ": ",
             output[0] == '\0' ? "" : output);
    return false;
  }
  snprintf(command, sizeof(command), "/sbin/pfctl -E 2>&1");
  if (capture_command(command, output, sizeof(output))) {
    char *token = strstr(output, "Token :");
    if (token != NULL) {
      token += 7;
      while (*token == ' ' || *token == '\t') {
        token++;
      }
      char line[128];
      snprintf(line, sizeof(line), "%s", token);
      line[strcspn(line, "\r\n")] = '\0';
      write_text_file(runtime->pf_token_file, line);
    }
  }
  runtime->pf_loaded = true;
  return true;
}

static void cleanup_pf(Runtime *runtime) {
  char command[512];
  snprintf(command, sizeof(command), "/sbin/pfctl -a %s -F rules >/dev/null 2>&1", PF_ANCHOR);
  (void)run_command(command);
  char token[128] = "";
  if (runtime->pf_token_file[0] != '\0' &&
      read_text_file(runtime->pf_token_file, token, sizeof(token))) {
    token[strcspn(token, "\r\n")] = '\0';
    if (token[0] != '\0') {
      snprintf(command, sizeof(command), "/sbin/pfctl -X %s >/dev/null 2>&1", token);
      (void)run_command(command);
    }
    unlink(runtime->pf_token_file);
  }
  runtime->pf_loaded = false;
}

static void write_state(Runtime *runtime, const char *state, const char *message) {
  char content[2048];
  snprintf(content, sizeof(content),
           "pid=%d\nstate=%s\nadapterName=IPv4 TUN 虚拟网卡\npermission=ready\ncpe=%s\nifname=%s\nutun=%s\n"
           "message=%s\ntx_bytes=%llu\nrx_bytes=%llu\ntx_rate=%llu\nrx_rate=%llu\n",
           getpid(), state, runtime->config.cpe, runtime->physical_ifname,
           runtime->utun_ifname, message == NULL ? "" : message,
           (unsigned long long)runtime->tx_bytes, (unsigned long long)runtime->rx_bytes,
           (unsigned long long)runtime->tx_rate, (unsigned long long)runtime->rx_rate);
  write_text_file(runtime->state_file, content);
}

static int start_fail(Runtime *runtime, const char *message, bool should_cleanup) {
  if (should_cleanup) {
    cleanup_routes(runtime);
  }
  if (runtime->tun_fd >= 0) {
    close(runtime->tun_fd);
    runtime->tun_fd = -1;
  }
  if (runtime->bpf_fd >= 0) {
    close(runtime->bpf_fd);
    runtime->bpf_fd = -1;
  }
  log_event(&runtime->config, message);
  write_state(runtime, "failed", message);
  return 1;
}

static const char *proto_name(uint8_t proto) {
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

static void write_connections_snapshot(Runtime *runtime) {
  char content[65536];
  size_t offset = 0;
  time_t now = time(NULL);
  for (size_t i = 0; i < MAX_NAT; i++) {
    NatEntry *entry = &runtime->nat.entries[i];
    if (!entry->used || now - entry->last_seen > 300) {
      continue;
    }
    char source_ip[INET_ADDRSTRLEN];
    char target_ip[INET_ADDRSTRLEN];
    char via_ip[INET_ADDRSTRLEN];
    ipv4_to_string(entry->original_src_ip, source_ip, sizeof(source_ip));
    ipv4_to_string(entry->original_remote_ip, target_ip, sizeof(target_ip));
    ipv4_to_string(entry->remote_ip, via_ip, sizeof(via_ip));
    bool dns_redirect = entry->remote_ip != entry->original_remote_ip;
    const char *domain = dns_redirect ? entry->domain : dns_cache_lookup(&runtime->nat, entry->original_remote_ip);
    int n = snprintf(content + offset, sizeof(content) - offset,
                     "lastSeen=%ld|proto=%s|source=%s:%u|target=%s:%u|domain=%s|via=%s:%u|"
                     "txBytes=%llu|rxBytes=%llu|txRate=%llu|rxRate=%llu|dnsRedirect=%s\n",
                     (long)entry->last_seen, proto_name(entry->proto), source_ip,
                     entry->original_src_port, target_ip, entry->remote_port, domain, via_ip,
                     entry->remote_port, (unsigned long long)entry->tx_bytes,
                     (unsigned long long)entry->rx_bytes, (unsigned long long)entry->tx_rate,
                     (unsigned long long)entry->rx_rate, dns_redirect ? "true" : "false");
    if (n < 0 || (size_t)n >= sizeof(content) - offset) {
      break;
    }
    offset += (size_t)n;
  }
  content[offset] = '\0';
  write_text_file(runtime->connections_file, content);
}

static bool read_state_value(const char *state_file, const char *key, char *out, size_t out_size) {
  FILE *file = fopen(state_file, "r");
  if (file == NULL) {
    return false;
  }
  char line[512];
  bool found = false;
  size_t key_len = strlen(key);
  while (fgets(line, sizeof(line), file) != NULL) {
    if (strncmp(line, key, key_len) == 0 && line[key_len] == '=') {
      char *value = line + key_len + 1;
      value[strcspn(value, "\r\n")] = '\0';
      snprintf(out, out_size, "%s", value);
      found = true;
      break;
    }
  }
  fclose(file);
  return found;
}

static void cleanup_routes(Runtime *runtime) {
  char command[512];
  cleanup_pf(runtime);
  snprintf(command, sizeof(command), "/sbin/route -n delete 0.0.0.0/1 >/dev/null 2>&1");
  (void)run_command(command);
  snprintf(command, sizeof(command), "/sbin/route -n delete 128.0.0.0/1 >/dev/null 2>&1");
  (void)run_command(command);
  snprintf(command, sizeof(command), "/sbin/route -n delete -host %s >/dev/null 2>&1",
           DEFAULT_L3_HOST);
  (void)run_command(command);
  snprintf(command, sizeof(command), "/sbin/route -n delete -host %s >/dev/null 2>&1", runtime->config.cpe);
  (void)run_command(command);
  if (runtime->utun_ifname[0] != '\0') {
    snprintf(command, sizeof(command), "/sbin/ifconfig %s down >/dev/null 2>&1", runtime->utun_ifname);
    (void)run_command(command);
  }
  runtime->routes_added = false;
}

static void cleanup_and_exit(int code) {
  if (g_runtime.auto_recovered) {
    log_event(&g_runtime.config, "CPE 异常，自动回退");
  } else {
    log_event(&g_runtime.config, "关闭 TUN");
  }
  cleanup_routes(&g_runtime);
  if (g_runtime.tun_fd >= 0) {
    close(g_runtime.tun_fd);
  }
  if (g_runtime.bpf_fd >= 0) {
    close(g_runtime.bpf_fd);
  }
  write_state(&g_runtime, g_runtime.auto_recovered ? "autoRecovered" : "stopped",
              g_runtime.auto_recovered ? "CPE 异常，已自动回切直连" : "stopped");
  exit(code);
}

static void signal_handler(int signum) {
  (void)signum;
  g_stop_requested = 1;
}

static bool ping_cpe(const char *cpe) {
  char command[256];
  snprintf(command, sizeof(command), "/sbin/ping -c 1 -t 1 %s >/dev/null 2>&1", cpe);
  return system(command) == 0;
}

static size_t build_dns_probe_query(uint8_t *buffer, size_t size, uint16_t id) {
  const uint8_t qname[] = {
      7, 'e', 'x', 'a', 'm', 'p', 'l', 'e',
      3, 'c', 'o', 'm',
      0,
  };
  const size_t needed = 12 + sizeof(qname) + 4;
  if (size < needed) {
    return 0;
  }
  memset(buffer, 0, needed);
  write_u16(buffer, id);
  write_u16(buffer + 2, 0x0100);
  write_u16(buffer + 4, 1);
  memcpy(buffer + 12, qname, sizeof(qname));
  write_u16(buffer + 12 + sizeof(qname), 1);
  write_u16(buffer + 12 + sizeof(qname) + 2, 1);
  return needed;
}

static bool dns_probe_cpe(const char *cpe) {
  int fd = socket(AF_INET, SOCK_DGRAM, 0);
  if (fd < 0) {
    return false;
  }
  struct timeval timeout;
  timeout.tv_sec = DNS_PROBE_TIMEOUT_SEC;
  timeout.tv_usec = 0;
  (void)setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));

  struct sockaddr_in addr;
  memset(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET;
  addr.sin_port = htons(53);
  if (inet_pton(AF_INET, cpe, &addr.sin_addr) != 1) {
    close(fd);
    return false;
  }
  uint8_t query[128];
  uint16_t id = (uint16_t)(time(NULL) & 0xffff);
  size_t query_len = build_dns_probe_query(query, sizeof(query), id);
  if (query_len == 0 ||
      sendto(fd, query, query_len, 0, (struct sockaddr *)&addr, sizeof(addr)) != (ssize_t)query_len) {
    close(fd);
    return false;
  }
  uint8_t reply[512];
  ssize_t n = recv(fd, reply, sizeof(reply), 0);
  close(fd);
  return n >= 12 && read_u16(reply) == id && (reply[2] & 0x80) != 0;
}

static int update_health_failures(int current_failures, bool l1_ok, bool l3_ok) {
  return (l1_ok && l3_ok) ? 0 : current_failures + 1;
}

static bool configure_routes(Runtime *runtime) {
  char command[512];
  snprintf(command, sizeof(command), "/sbin/ifconfig %s inet %s %s mtu %d up",
           runtime->utun_ifname, runtime->config.tun_local, runtime->config.tun_peer, TUN_MTU);
  if (run_command(command) != 0) {
    return false;
  }
  snprintf(command, sizeof(command), "/sbin/route -n add -host %s -interface %s",
           runtime->config.cpe, runtime->physical_ifname);
  if (run_command(command) != 0) {
    return false;
  }
  snprintf(command, sizeof(command), "/sbin/route -n add 0.0.0.0/1 -interface %s", runtime->utun_ifname);
  if (run_command(command) != 0) {
    return false;
  }
  snprintf(command, sizeof(command), "/sbin/route -n add 128.0.0.0/1 -interface %s", runtime->utun_ifname);
  if (run_command(command) != 0) {
    return false;
  }
  runtime->routes_added = true;
  return true;
}

static bool write_packet_to_utun(int tun_fd, const uint8_t *packet, size_t len) {
  uint8_t buffer[MAX_PACKET + 4];
  if (len + 4 > sizeof(buffer)) {
    return false;
  }
  write_u32(buffer, AF_INET);
  memcpy(buffer + 4, packet, len);
  return write(tun_fd, buffer, len + 4) == (ssize_t)(len + 4);
}

static void process_utun_packet(Runtime *runtime, const uint8_t *buffer, size_t len) {
  if (len <= 4 || len - 4 > MAX_PACKET) {
    return;
  }
  if (read_u32(buffer) != AF_INET) {
    return;
  }
  uint8_t packet[MAX_PACKET];
  memcpy(packet, buffer + 4, len - 4);
  size_t packet_len = len - 4;
  if ((packet[0] >> 4) != 4) {
    return;
  }
  if (!nat_translate_outgoing(&runtime->nat, packet, packet_len,
                              runtime->physical_ip, runtime->cpe_ip)) {
    return;
  }
  uint8_t frame[MAX_FRAME];
  size_t frame_len = build_ethernet_frame(frame, sizeof(frame), runtime->cpe_mac,
                                          runtime->local_mac, packet, packet_len);
  if (frame_len > 0) {
    if (write(runtime->bpf_fd, frame, frame_len) == (ssize_t)frame_len) {
      runtime->tx_bytes += packet_len;
    }
  }
}

static void process_bpf_frame(Runtime *runtime, const uint8_t *frame, size_t len) {
  if (len < 14 || memcmp(frame + 6, runtime->cpe_mac, 6) != 0) {
    return;
  }
  if (frame[12] != 0x08 || frame[13] != 0x00) {
    return;
  }
  uint8_t packet[MAX_PACKET];
  size_t packet_len = len - 14;
  if (packet_len > sizeof(packet)) {
    return;
  }
  memcpy(packet, frame + 14, packet_len);
  if (!nat_translate_incoming(&runtime->nat, packet, packet_len, runtime->physical_ip)) {
    return;
  }
  if (write_packet_to_utun(runtime->tun_fd, packet, packet_len)) {
    runtime->rx_bytes += packet_len;
  }
}

static void process_bpf_buffer(Runtime *runtime, const uint8_t *buffer, ssize_t len) {
  size_t offset = 0;
  while (offset + sizeof(struct bpf_hdr) <= (size_t)len) {
    const struct bpf_hdr *hdr = (const struct bpf_hdr *)(buffer + offset);
    if (hdr->bh_hdrlen + hdr->bh_caplen > (uint32_t)((size_t)len - offset)) {
      break;
    }
    const uint8_t *frame = buffer + offset + hdr->bh_hdrlen;
    process_bpf_frame(runtime, frame, hdr->bh_caplen);
    offset += BPF_WORDALIGN(hdr->bh_hdrlen + hdr->bh_caplen);
  }
}

static int data_loop(Runtime *runtime) {
  unsigned int bpf_len = 4096;
  uint8_t *bpf_buffer = malloc(bpf_len);
  if (bpf_buffer == NULL) {
    return 1;
  }
  int health_failures = 0;
  int l3_failures = 0;
  time_t last_health = 0;
  while (!g_stop_requested) {
    fd_set readfds;
    FD_ZERO(&readfds);
    FD_SET(runtime->tun_fd, &readfds);
    FD_SET(runtime->bpf_fd, &readfds);
    int maxfd = runtime->tun_fd > runtime->bpf_fd ? runtime->tun_fd : runtime->bpf_fd;
    struct timeval timeout;
    timeout.tv_sec = 1;
    timeout.tv_usec = 0;
    int rc = select(maxfd + 1, &readfds, NULL, NULL, &timeout);
    if (rc > 0) {
      if (FD_ISSET(runtime->tun_fd, &readfds)) {
        uint8_t buffer[MAX_PACKET + 4];
        ssize_t n = read(runtime->tun_fd, buffer, sizeof(buffer));
        if (n > 0) {
          process_utun_packet(runtime, buffer, (size_t)n);
        }
      }
      if (FD_ISSET(runtime->bpf_fd, &readfds)) {
        ssize_t n = read(runtime->bpf_fd, bpf_buffer, bpf_len);
        if (n > 0) {
          process_bpf_buffer(runtime, bpf_buffer, n);
        }
      }
    }
    time_t now = time(NULL);
    update_rates(runtime, now);
    write_state(runtime, "running", "running");
    write_connections_snapshot(runtime);
    if (now - last_health >= HEALTH_INTERVAL_SEC) {
      bool l1_ok = ping_cpe(runtime->config.cpe);
      bool l3_ok = l1_ok && dns_probe_cpe(runtime->config.cpe);
      health_failures = l1_ok ? 0 : update_health_failures(health_failures, l1_ok, l3_ok);
      if (l1_ok && !l3_ok) {
        l3_failures++;
      } else if (l3_ok) {
        l3_failures = 0;
      }
      if (!l1_ok || (l1_ok && !l3_ok && (l3_failures == 1 || l3_failures % 15 == 0))) {
        char health_event[256];
        snprintf(health_event, sizeof(health_event),
                 "健康检测%s l1=%s l3=%s failures=%d",
                 l1_ok ? "降级" : "失败",
                 l1_ok ? "true" : "false", l3_ok ? "true" : "false", health_failures);
        log_event(&runtime->config, health_event);
      }
      if (health_failures >= 3) {
        runtime->auto_recovered = true;
        free(bpf_buffer);
        cleanup_and_exit(0);
      }
      if (file_mtime_age_exceeds(runtime->heartbeat_file, HEARTBEAT_TIMEOUT_SEC)) {
        runtime->auto_recovered = true;
        free(bpf_buffer);
        cleanup_and_exit(0);
      }
      last_health = now;
    }
  }
  free(bpf_buffer);
  cleanup_and_exit(0);
  return 0;
}

static void snapshot_initial_network(const char *dir) {
  char output[65536];
  char path[512];
  const char *commands[] = {
      "/sbin/route -n get default 2>&1",
      "/usr/sbin/netstat -rn 2>&1",
      "/usr/sbin/networksetup -listallnetworkservices 2>&1",
      NULL,
  };
  for (int i = 0; commands[i] != NULL; i++) {
    if (capture_command(commands[i], output, sizeof(output))) {
      snprintf(path, sizeof(path), "%s/snapshot_%d.txt", dir, i);
      write_text_file(path, output);
    }
  }
}

static int command_start(HelperConfig *config) {
  int root_check = require_root_identity("start");
  if (root_check != 0) {
    return root_check;
  }
  memset(&g_runtime, 0, sizeof(g_runtime));
  g_runtime.tun_fd = -1;
  g_runtime.bpf_fd = -1;
  g_runtime.config = *config;
  path_join(g_runtime.state_file, sizeof(g_runtime.state_file), config->state_dir, "state");
  path_join(g_runtime.heartbeat_file, sizeof(g_runtime.heartbeat_file), config->state_dir, "heartbeat");
  event_log_path(config, g_runtime.event_log_file, sizeof(g_runtime.event_log_file));
  connections_path(config, g_runtime.connections_file, sizeof(g_runtime.connections_file));
  path_join(g_runtime.pf_token_file, sizeof(g_runtime.pf_token_file), config->state_dir, "pf_token");
  if (!ensure_state_dir(config->state_dir)) {
    perror("state dir");
    return 1;
  }
  if (!config->foreground) {
    pid_t pid = fork();
    if (pid < 0) {
      perror("fork");
      return 1;
    }
    if (pid > 0) {
      printf("started pid=%d\n", pid);
      return 0;
    }
    setsid();
    redirect_stdio_to_devnull();
  }

  signal(SIGTERM, signal_handler);
  signal(SIGINT, signal_handler);
  signal(SIGHUP, signal_handler);
  snapshot_initial_network(config->state_dir);
  touch_file(g_runtime.heartbeat_file);
  log_event(config, "开启 TUN");

  if (config->ifname[0] == '\0' &&
      !route_get_interface(config->cpe, g_runtime.physical_ifname, sizeof(g_runtime.physical_ifname))) {
    fprintf(stderr, "failed to detect physical interface\n");
    return start_fail(&g_runtime, "failed to detect physical interface", false);
  }
  if (config->ifname[0] != '\0') {
    snprintf(g_runtime.physical_ifname, sizeof(g_runtime.physical_ifname), "%s", config->ifname);
  }
  if (!get_interface_mac_ip(g_runtime.physical_ifname, g_runtime.local_mac, &g_runtime.physical_ip)) {
    fprintf(stderr, "failed to read physical interface address\n");
    return start_fail(&g_runtime, "failed to read physical interface address", false);
  }
  if (!install_pf_rule(&g_runtime)) {
    fprintf(stderr, "failed to install pf rule\n");
    return start_fail(&g_runtime,
                      g_runtime.last_error[0] == '\0' ? "failed to install pf rule" : g_runtime.last_error,
                      true);
  }
  if (!resolve_cpe_mac(config->cpe, g_runtime.cpe_mac)) {
    fprintf(stderr, "failed to resolve CPE MAC\n");
    return start_fail(&g_runtime, "failed to resolve CPE MAC", true);
  }
  struct in_addr cpe_addr;
  if (inet_pton(AF_INET, config->cpe, &cpe_addr) != 1) {
    fprintf(stderr, "invalid CPE address\n");
    return start_fail(&g_runtime, "invalid CPE address", true);
  }
  g_runtime.cpe_ip = ntohl(cpe_addr.s_addr);
  struct in_addr tun_addr;
  inet_pton(AF_INET, config->tun_local, &tun_addr);
  g_runtime.tun_ip = ntohl(tun_addr.s_addr);
  g_runtime.tun_fd = create_utun(g_runtime.utun_ifname, sizeof(g_runtime.utun_ifname));
  if (g_runtime.tun_fd < 0) {
    perror("utun");
    return start_fail(&g_runtime, "failed to create utun", true);
  }
  if (!configure_routes(&g_runtime)) {
    return start_fail(&g_runtime, "failed to configure routes", true);
  }
  unsigned int bpf_len = 0;
  g_runtime.bpf_fd = open_bpf(g_runtime.physical_ifname, &bpf_len);
  if (g_runtime.bpf_fd < 0) {
    perror("bpf");
    return start_fail(&g_runtime, "failed to open bpf", true);
  }
  write_state(&g_runtime, "running", "running");
  return data_loop(&g_runtime);
}

static int read_pid_from_state(const HelperConfig *config) {
  char state_file[512];
  char pid_text[64];
  path_join(state_file, sizeof(state_file), config->state_dir, "state");
  if (!read_state_value(state_file, "pid", pid_text, sizeof(pid_text))) {
    return -1;
  }
  return atoi(pid_text);
}

static int command_stop(HelperConfig *config) {
  int root_check = require_root_identity("stop");
  if (root_check != 0) {
    return root_check;
  }
  int pid = read_pid_from_state(config);
  if (pid > 0) {
    kill(pid, SIGTERM);
    usleep(300000);
  }
  (void)system("/usr/bin/pkill -f 'sdwan-macos-helper start' >/dev/null 2>&1");
  (void)system("/usr/bin/pkill -f 'com.sdwan.verge.helper start' >/dev/null 2>&1");
  memset(&g_runtime, 0, sizeof(g_runtime));
  g_runtime.tun_fd = -1;
  g_runtime.bpf_fd = -1;
  g_runtime.config = *config;
  path_join(g_runtime.pf_token_file, sizeof(g_runtime.pf_token_file), config->state_dir, "pf_token");
  char value[IFNAMSIZ];
  char state_file[512];
  path_join(state_file, sizeof(state_file), config->state_dir, "state");
  if (read_state_value(state_file, "utun", value, sizeof(value))) {
    snprintf(g_runtime.utun_ifname, sizeof(g_runtime.utun_ifname), "%s", value);
  }
  cleanup_routes(&g_runtime);
  log_event(config, "关闭 TUN");
  write_state(&g_runtime, "stopped", "stopped");
  return 0;
}

static bool copy_file(const char *src, const char *dst) {
  FILE *in = fopen(src, "rb");
  if (in == NULL) {
    return false;
  }
  FILE *out = fopen(dst, "wb");
  if (out == NULL) {
    fclose(in);
    return false;
  }
  char buffer[16384];
  size_t n = 0;
  bool ok = true;
  while ((n = fread(buffer, 1, sizeof(buffer), in)) > 0) {
    if (fwrite(buffer, 1, n, out) != n) {
      ok = false;
      break;
    }
  }
  if (ferror(in)) {
    ok = false;
  }
  fclose(in);
  if (fclose(out) != 0) {
    ok = false;
  }
  return ok;
}

static int command_install(const char *self_path) {
  int root_check = require_root_identity("install");
  if (root_check != 0) {
    return root_check;
  }
  if (mkdir(INSTALLED_HELPER_DIR, 0755) != 0 && errno != EEXIST) {
    perror("mkdir");
    return 1;
  }
  if (!copy_file(self_path, INSTALLED_HELPER_PATH)) {
    perror("copy helper");
    return 1;
  }
  if (chown(INSTALLED_HELPER_PATH, 0, 0) != 0) {
    perror("chown");
    return 1;
  }
  if (chmod(INSTALLED_HELPER_PATH, 04755) != 0) {
    perror("chmod");
    return 1;
  }
  printf("installed=%s\n", INSTALLED_HELPER_PATH);
  return 0;
}

static int command_uninstall(HelperConfig *config) {
  int root_check = require_root_identity("uninstall");
  if (root_check != 0) {
    return root_check;
  }
  (void)command_stop(config);
  if (unlink(INSTALLED_HELPER_PATH) != 0 && errno != ENOENT) {
    perror("unlink");
    return 1;
  }
  printf("uninstalled=%s\n", INSTALLED_HELPER_PATH);
  return 0;
}

static void print_status(HelperConfig *config) {
  char state_file[512];
  char heartbeat_file[512];
  char state[64] = "stopped";
  char message[512] = "";
  char tx_bytes[64] = "0";
  char rx_bytes[64] = "0";
  char tx_rate[64] = "0";
  char rx_rate[64] = "0";
  char permission[64] = "ready";
  path_join(state_file, sizeof(state_file), config->state_dir, "state");
  path_join(heartbeat_file, sizeof(heartbeat_file), config->state_dir, "heartbeat");
  (void)read_state_value(state_file, "state", state, sizeof(state));
  (void)read_state_value(state_file, "message", message, sizeof(message));
  (void)read_state_value(state_file, "permission", permission, sizeof(permission));
  (void)read_state_value(state_file, "tx_bytes", tx_bytes, sizeof(tx_bytes));
  (void)read_state_value(state_file, "rx_bytes", rx_bytes, sizeof(rx_bytes));
  (void)read_state_value(state_file, "tx_rate", tx_rate, sizeof(tx_rate));
  (void)read_state_value(state_file, "rx_rate", rx_rate, sizeof(rx_rate));
  if (strcmp(state, "running") != 0) {
    snprintf(tx_rate, sizeof(tx_rate), "0");
    snprintf(rx_rate, sizeof(rx_rate), "0");
  }
  bool reachable = ping_cpe(config->cpe);
  bool service_ready = reachable && dns_probe_cpe(config->cpe);
  if (strcmp(state, "autoRecovered") == 0 && service_ready) {
    snprintf(state, sizeof(state), "stopped");
    message[0] = '\0';
  }
  if (strcmp(message, "running") == 0 || strcmp(message, "stopped") == 0) {
    message[0] = '\0';
  }
  touch_file(heartbeat_file);
  printf("state=%s\n", state);
  printf("adapterName=IPv4 TUN 虚拟网卡\n");
  printf("permission=%s\n", permission);
  printf("host=%s\n", config->cpe);
  printf("reachable=%s\n", reachable ? "true" : "false");
  printf("serviceReady=%s\n", service_ready ? "true" : "false");
  printf("tx_bytes=%s\n", tx_bytes);
  printf("rx_bytes=%s\n", rx_bytes);
  printf("tx_rate=%s\n", tx_rate);
  printf("rx_rate=%s\n", rx_rate);
  printf("lastError=%s\n", message);
}

static void print_health(HelperConfig *config) {
  char heartbeat_file[512];
  path_join(heartbeat_file, sizeof(heartbeat_file), config->state_dir, "heartbeat");
  touch_file(heartbeat_file);
  bool l1 = ping_cpe(config->cpe);
  bool l3 = dns_probe_cpe(config->cpe);
  printf("host=%s\n", config->cpe);
  printf("reachable=%s\n", l1 ? "true" : "false");
  printf("serviceReady=%s\n", (l1 && l3) ? "true" : "false");
  printf("error=%s\n", l1 ? "" : "CPE ping failed");
}

static void print_logs(HelperConfig *config, int limit) {
  if (limit <= 0) {
    limit = 80;
  }
  if (limit > 300) {
    limit = 300;
  }
  char path[512];
  event_log_path(config, path, sizeof(path));
  FILE *file = fopen(path, "r");
  if (file == NULL) {
    return;
  }
  char lines[300][1024];
  int count = 0;
  char line[1024];
  while (fgets(line, sizeof(line), file) != NULL) {
    snprintf(lines[count % 300], sizeof(lines[count % 300]), "%s", line);
    count++;
  }
  fclose(file);
  int available = count < 300 ? count : 300;
  int start = available > limit ? available - limit : 0;
  for (int i = start; i < available; i++) {
    const char *raw = lines[(count - available + i) % 300];
    char *endptr = NULL;
    long ts = strtol(raw, &endptr, 10);
    while (endptr != NULL && (*endptr == ' ' || *endptr == '\t')) {
      endptr++;
    }
    if (ts <= 0 || endptr == NULL || *endptr == '\0') {
      fputs(raw, stdout);
      continue;
    }
    char time_text[32];
    char message[900];
    format_event_time((time_t)ts, time_text, sizeof(time_text));
    snprintf(message, sizeof(message), "%s", endptr);
    message[strcspn(message, "\r\n")] = '\0';
    printf("%s %s\n", time_text, message);
  }
}

static void print_connections(HelperConfig *config, int limit) {
  if (limit <= 0) {
    limit = 80;
  }
  if (limit > 300) {
    limit = 300;
  }
  char path[512];
  connections_path(config, path, sizeof(path));
  FILE *file = fopen(path, "r");
  if (file == NULL) {
    return;
  }
  char lines[300][1024];
  int count = 0;
  char line[1024];
  while (fgets(line, sizeof(line), file) != NULL) {
    snprintf(lines[count % 300], sizeof(lines[count % 300]), "%s", line);
    count++;
  }
  fclose(file);
  int available = count < 300 ? count : 300;
  int start = available > limit ? available - limit : 0;
  for (int i = start; i < available; i++) {
    fputs(lines[(count - available + i) % 300], stdout);
  }
}

static void make_udp_packet(uint8_t *packet, size_t *len, uint32_t src, uint32_t dst,
                            uint16_t sport, uint16_t dport) {
  memset(packet, 0, 28);
  packet[0] = 0x45;
  packet[8] = 64;
  packet[9] = IPPROTO_UDP;
  write_u16(packet + 2, 28);
  write_u32(packet + 12, src);
  write_u32(packet + 16, dst);
  write_u16(packet + 20, sport);
  write_u16(packet + 22, dport);
  write_u16(packet + 24, 8);
  fix_ipv4_checksum(packet, 28);
  fix_transport_checksum(packet, 28);
  *len = 28;
}

static void append_udp_payload(uint8_t *packet, size_t *len, const uint8_t *payload,
                               size_t payload_len) {
  memcpy(packet + 28, payload, payload_len);
  *len = 28 + payload_len;
  write_u16(packet + 2, (uint16_t)*len);
  write_u16(packet + 24, (uint16_t)(8 + payload_len));
  fix_ipv4_checksum(packet, *len);
  fix_transport_checksum(packet, *len);
}

static int command_self_test(void) {
  uint8_t packet[64];
  size_t len = 0;
  NatTable table;
  memset(&table, 0, sizeof(table));
  uint32_t tun_ip = 0x0aff0002;      // 10.255.0.2
  uint32_t physical_ip = 0xc0a80158; // 192.168.1.88
  uint32_t cpe_ip = 0xc0a8018c;      // 192.168.1.140
  uint32_t remote_ip = 0x08080808;   // 8.8.8.8
  uint8_t ipv6_packet[40];
  memset(ipv6_packet, 0, sizeof(ipv6_packet));
  ipv6_packet[0] = 0x60;
  if (nat_translate_outgoing(&table, ipv6_packet, sizeof(ipv6_packet), physical_ip, cpe_ip)) {
    fprintf(stderr, "ipv6 packet should not enter ipv4 tun nat\n");
    return 1;
  }
  make_udp_packet(packet, &len, tun_ip, remote_ip, 12345, 53);
  if (!nat_translate_outgoing(&table, packet, len, physical_ip, cpe_ip)) {
    fprintf(stderr, "nat outgoing failed\n");
    return 1;
  }
  if (read_u32(packet + 12) != physical_ip) {
    fprintf(stderr, "source NAT failed\n");
    return 1;
  }
  if (read_u16(packet + 20) < NAT_PORT_START || read_u16(packet + 20) > NAT_PORT_END) {
    fprintf(stderr, "dedicated NAT port failed\n");
    return 1;
  }
  if (read_u32(packet + 16) != cpe_ip) {
    fprintf(stderr, "dns redirect to cpe failed\n");
    return 1;
  }
  uint16_t translated_port = read_u16(packet + 20);
  uint8_t reply[64];
  make_udp_packet(reply, &len, cpe_ip, physical_ip, 53, translated_port);
  if (!nat_translate_incoming(&table, reply, len, physical_ip)) {
    fprintf(stderr, "nat incoming failed\n");
    return 1;
  }
  if (read_u32(reply + 16) != tun_ip) {
    fprintf(stderr, "destination restore failed\n");
    return 1;
  }
  if (read_u32(reply + 12) != remote_ip) {
    fprintf(stderr, "dns source restore failed\n");
    return 1;
  }
  if (read_u16(reply + 22) != 12345) {
    fprintf(stderr, "destination port restore failed\n");
    return 1;
  }
  uint8_t tcp_syn[64];
  memset(tcp_syn, 0, sizeof(tcp_syn));
  tcp_syn[0] = 0x45;
  tcp_syn[8] = 64;
  tcp_syn[9] = IPPROTO_TCP;
  write_u16(tcp_syn + 2, 44);
  write_u32(tcp_syn + 12, tun_ip);
  write_u32(tcp_syn + 16, remote_ip);
  write_u16(tcp_syn + 20, 44321);
  write_u16(tcp_syn + 22, 443);
  tcp_syn[32] = 0x60;
  tcp_syn[33] = 0x02;
  write_u16(tcp_syn + 34, 65535);
  tcp_syn[40] = 2;
  tcp_syn[41] = 4;
  write_u16(tcp_syn + 42, 1460);
  fix_ipv4_checksum(tcp_syn, 44);
  fix_transport_checksum(tcp_syn, 44);
  if (!clamp_tcp_mss(tcp_syn, 44, 1360) || read_u16(tcp_syn + 42) != 1360) {
    fprintf(stderr, "tcp mss clamp failed\n");
    return 1;
  }
  NatTable dns_table;
  memset(&dns_table, 0, sizeof(dns_table));
  const uint8_t dns_query_payload[] = {
      0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x07, 'e',  'x',  'a',
      'm',  'p',  'l',  'e',  0x03, 'c',  'o',  'm',
      0x00, 0x00, 0x01, 0x00, 0x01,
  };
  make_udp_packet(packet, &len, tun_ip, remote_ip, 12345, 53);
  append_udp_payload(packet, &len, dns_query_payload, sizeof(dns_query_payload));
  char query_domain[256];
  if (!dns_query_domain_from_packet(packet, len, query_domain, sizeof(query_domain)) ||
      strcmp(query_domain, "example.com") != 0) {
    fprintf(stderr, "dns query domain parse failed\n");
    return 1;
  }
  if (!nat_translate_outgoing(&dns_table, packet, len, physical_ip, cpe_ip)) {
    fprintf(stderr, "dns nat outgoing failed\n");
    return 1;
  }
  translated_port = read_u16(packet + 20);
  const uint8_t dns_response_payload[] = {
      0x12, 0x34, 0x81, 0x80, 0x00, 0x01, 0x00, 0x01,
      0x00, 0x00, 0x00, 0x00, 0x07, 'e',  'x',  'a',
      'm',  'p',  'l',  'e',  0x03, 'c',  'o',  'm',
      0x00, 0x00, 0x01, 0x00, 0x01, 0xc0, 0x0c, 0x00,
      0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x3c, 0x00,
      0x04, 0x5d, 0xb8, 0xd8, 0x22,
  };
  make_udp_packet(reply, &len, cpe_ip, physical_ip, 53, translated_port);
  append_udp_payload(reply, &len, dns_response_payload, sizeof(dns_response_payload));
  if (!nat_translate_incoming(&dns_table, reply, len, physical_ip)) {
    fprintf(stderr, "dns nat incoming failed\n");
    return 1;
  }
  if (strcmp(dns_cache_lookup(&dns_table, 0x5db8d822), "example.com") != 0) {
    fprintf(stderr, "dns cache lookup failed\n");
    return 1;
  }
  uint8_t dst[6] = {0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff};
  uint8_t src[6] = {0x00, 0x11, 0x22, 0x33, 0x44, 0x55};
  uint8_t frame[128];
  size_t frame_len = build_ethernet_frame(frame, sizeof(frame), dst, src, packet, len);
  if (frame_len != len + 14 || memcmp(frame, dst, 6) != 0 || frame[12] != 0x08 || frame[13] != 0x00) {
    fprintf(stderr, "ethernet frame failed\n");
    return 1;
  }
  int failures = 0;
  failures = update_health_failures(failures, false, false);
  failures = update_health_failures(failures, false, false);
  failures = update_health_failures(failures, false, false);
  if (failures != 3) {
    fprintf(stderr, "health failure counter failed\n");
    return 1;
  }
  failures = update_health_failures(failures, true, true);
  if (failures != 0) {
    fprintf(stderr, "health recovery reset failed\n");
    return 1;
  }
  uint8_t dns_query[128];
  size_t dns_len = build_dns_probe_query(dns_query, sizeof(dns_query), 0x1234);
  if (dns_len == 0 || dns_query[0] != 0x12 || dns_query[1] != 0x34 ||
      dns_query[5] != 1) {
    fprintf(stderr, "dns probe query failed\n");
    return 1;
  }
  Runtime rate_runtime;
  memset(&rate_runtime, 0, sizeof(rate_runtime));
  rate_runtime.tx_bytes = 1500;
  rate_runtime.rx_bytes = 3000;
  rate_runtime.last_tx_bytes = 500;
  rate_runtime.last_rx_bytes = 1000;
  rate_runtime.last_rate_at = 10;
  NatEntry *rate_entry = &rate_runtime.nat.entries[0];
  rate_entry->used = true;
  rate_entry->tx_bytes = 700;
  rate_entry->rx_bytes = 900;
  rate_entry->last_tx_bytes = 100;
  rate_entry->last_rx_bytes = 300;
  rate_entry->last_rate_at = 10;
  update_rates(&rate_runtime, 15);
  if (rate_runtime.tx_rate != 200 || rate_runtime.rx_rate != 400 ||
      rate_entry->tx_rate != 120 || rate_entry->rx_rate != 120) {
    fprintf(stderr, "traffic rate calculation failed\n");
    return 1;
  }
  printf("SELF_TEST_OK\n");
  return 0;
}

static void parse_args(int argc, char **argv, HelperConfig *config) {
  for (int i = 2; i < argc; i++) {
    if (strcmp(argv[i], "--cpe") == 0 && i + 1 < argc) {
      snprintf(config->cpe, sizeof(config->cpe), "%s", argv[++i]);
    } else if (strcmp(argv[i], "--ifname") == 0 && i + 1 < argc) {
      snprintf(config->ifname, sizeof(config->ifname), "%s", argv[++i]);
    } else if (strcmp(argv[i], "--utun") == 0 && i + 1 < argc) {
      snprintf(config->utun, sizeof(config->utun), "%s", argv[++i]);
    } else if (strcmp(argv[i], "--state-dir") == 0 && i + 1 < argc) {
      snprintf(config->state_dir, sizeof(config->state_dir), "%s", argv[++i]);
    } else if (strcmp(argv[i], "--foreground") == 0) {
      config->foreground = true;
    } else if (strcmp(argv[i], "--l3-host") == 0 && i + 1 < argc) {
      snprintf(config->l3_host, sizeof(config->l3_host), "%s", argv[++i]);
    } else if (strcmp(argv[i], "--l3-port") == 0 && i + 1 < argc) {
      config->l3_port = atoi(argv[++i]);
    }
  }
}

static void print_usage(void) {
  fprintf(stderr, "%s {plan|self-test|install|uninstall|start|stop|rollback|status|health|logs|connections} [options]\n", HELPER_NAME);
}

int main(int argc, char **argv) {
  if (argc < 2) {
    print_usage();
    return 2;
  }
  HelperConfig config;
  init_config(&config);
  parse_args(argc, argv, &config);
  if (strcmp(argv[1], "plan") == 0) {
    print_plan(&config);
    return 0;
  }
  if (strcmp(argv[1], "self-test") == 0) {
    return command_self_test();
  }
  if (strcmp(argv[1], "install") == 0) {
    return command_install(argv[0]);
  }
  if (strcmp(argv[1], "uninstall") == 0) {
    return command_uninstall(&config);
  }
  if (strcmp(argv[1], "start") == 0) {
    return command_start(&config);
  }
  if (strcmp(argv[1], "stop") == 0 || strcmp(argv[1], "rollback") == 0) {
    return command_stop(&config);
  }
  if (strcmp(argv[1], "status") == 0) {
    print_status(&config);
    return 0;
  }
  if (strcmp(argv[1], "health") == 0 || strcmp(argv[1], "healthCheck") == 0) {
    print_health(&config);
    return 0;
  }
  if (strcmp(argv[1], "logs") == 0) {
    int limit = argc > 2 ? atoi(argv[2]) : 80;
    print_logs(&config, limit);
    return 0;
  }
  if (strcmp(argv[1], "connections") == 0) {
    int limit = argc > 2 ? atoi(argv[2]) : 80;
    print_connections(&config, limit);
    return 0;
  }
  print_usage();
  return 2;
}
