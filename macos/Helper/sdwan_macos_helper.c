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
#include <time.h>
#include <unistd.h>

#ifndef UTUN_CONTROL_NAME
#define UTUN_CONTROL_NAME "com.apple.net.utun_control"
#endif

#ifndef UTUN_OPT_IFNAME
#define UTUN_OPT_IFNAME 2
#endif

#define DEFAULT_CPE "192.168.1.140"
#define DEFAULT_TUN_LOCAL "10.255.0.2"
#define DEFAULT_TUN_PEER "10.255.0.1"
#define DEFAULT_L3_HOST "1.1.1.1"
#define DEFAULT_L3_PORT 53
#define DEFAULT_STATE_DIR "/var/run/sdwan-verge"
#define DEFAULT_LOG_FILE "/var/log/sdwan-verge-helper.log"
#define HELPER_NAME "sdwan-macos-helper"
#define MAX_PACKET 2000
#define MAX_FRAME 2200
#define MAX_NAT 4096
#define HEARTBEAT_TIMEOUT_SEC 30

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
  uint32_t original_src_ip;
  uint16_t original_src_port;
  uint16_t translated_port;
  uint16_t remote_port;
  time_t last_seen;
} NatEntry;

typedef struct {
  NatEntry entries[MAX_NAT];
} NatTable;

typedef struct {
  int tun_fd;
  int bpf_fd;
  HelperConfig config;
  char state_file[512];
  char heartbeat_file[512];
  char physical_ifname[IFNAMSIZ];
  char utun_ifname[IFNAMSIZ];
  uint8_t local_mac[6];
  uint8_t cpe_mac[6];
  uint32_t physical_ip;
  uint32_t tun_ip;
  bool routes_added;
  bool auto_recovered;
  NatTable nat;
} Runtime;

static Runtime g_runtime;
static volatile sig_atomic_t g_stop_requested = 0;

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

static int run_command(const char *command) {
  log_line(command);
  return system(command);
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

static uint16_t read_u16(const uint8_t *p) {
  return (uint16_t)((p[0] << 8) | p[1]);
}

static uint32_t read_u32(const uint8_t *p) {
  return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3];
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

static NatEntry *nat_find_slot(NatTable *table, uint8_t proto, uint32_t remote_ip,
                               uint16_t translated_port, uint16_t remote_port) {
  NatEntry *free_slot = NULL;
  for (size_t i = 0; i < MAX_NAT; i++) {
    NatEntry *entry = &table->entries[i];
    if (!entry->used) {
      if (free_slot == NULL) {
        free_slot = entry;
      }
      continue;
    }
    if (entry->proto == proto && entry->remote_ip == remote_ip &&
        entry->translated_port == translated_port && entry->remote_port == remote_port) {
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

static bool nat_translate_outgoing(NatTable *table, uint8_t *packet, size_t len, uint32_t physical_ip) {
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
  uint32_t remote_ip = read_u32(packet + 16);
  NatEntry *entry = nat_find_slot(table, proto, remote_ip, src_port, dst_port);
  if (entry == NULL) {
    return false;
  }
  entry->used = true;
  entry->proto = proto;
  entry->remote_ip = remote_ip;
  entry->original_src_ip = original_src_ip;
  entry->original_src_port = src_port;
  entry->translated_port = src_port;
  entry->remote_port = dst_port;
  entry->last_seen = time(NULL);
  write_u32(packet + 12, physical_ip);
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
  write_u32(packet + 16, entry->original_src_ip);
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
  printf("/sbin/ifconfig %s inet %s %s mtu 1500 up\n", utun, config->tun_local, config->tun_peer);
  printf("/sbin/route -n add -host %s -interface %s\n", config->cpe, ifname);
  printf("/sbin/route -n add 0.0.0.0/1 -interface %s\n", utun);
  printf("/sbin/route -n add 128.0.0.0/1 -interface %s\n", utun);
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

static void write_state(Runtime *runtime, const char *state, const char *message) {
  char content[2048];
  snprintf(content, sizeof(content),
           "pid=%d\nstate=%s\npermission=ready\ncpe=%s\nifname=%s\nutun=%s\nmessage=%s\n",
           getpid(), state, runtime->config.cpe, runtime->physical_ifname,
           runtime->utun_ifname, message == NULL ? "" : message);
  write_text_file(runtime->state_file, content);
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
  snprintf(command, sizeof(command), "/sbin/route -n delete 0.0.0.0/1 >/dev/null 2>&1");
  (void)run_command(command);
  snprintf(command, sizeof(command), "/sbin/route -n delete 128.0.0.0/1 >/dev/null 2>&1");
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

static bool tcp_probe(const char *host, int port) {
  int fd = socket(AF_INET, SOCK_STREAM, 0);
  if (fd < 0) {
    return false;
  }
  int flags = fcntl(fd, F_GETFL, 0);
  (void)fcntl(fd, F_SETFL, flags | O_NONBLOCK);
  struct sockaddr_in addr;
  memset(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET;
  addr.sin_port = htons((uint16_t)port);
  if (inet_pton(AF_INET, host, &addr.sin_addr) != 1) {
    close(fd);
    return false;
  }
  int rc = connect(fd, (struct sockaddr *)&addr, sizeof(addr));
  if (rc == 0) {
    close(fd);
    return true;
  }
  if (errno != EINPROGRESS) {
    close(fd);
    return false;
  }
  fd_set writefds;
  FD_ZERO(&writefds);
  FD_SET(fd, &writefds);
  struct timeval timeout;
  timeout.tv_sec = 2;
  timeout.tv_usec = 0;
  rc = select(fd + 1, NULL, &writefds, NULL, &timeout);
  if (rc <= 0) {
    close(fd);
    return false;
  }
  int err = 0;
  socklen_t err_len = sizeof(err);
  getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &err_len);
  close(fd);
  return err == 0;
}

static int update_health_failures(int current_failures, bool l1_ok, bool l3_ok) {
  return (l1_ok && l3_ok) ? 0 : current_failures + 1;
}

static bool configure_routes(Runtime *runtime) {
  char command[512];
  snprintf(command, sizeof(command), "/sbin/ifconfig %s inet %s %s mtu 1500 up",
           runtime->utun_ifname, runtime->config.tun_local, runtime->config.tun_peer);
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
  uint8_t packet[MAX_PACKET];
  memcpy(packet, buffer + 4, len - 4);
  size_t packet_len = len - 4;
  if (!nat_translate_outgoing(&runtime->nat, packet, packet_len, runtime->physical_ip)) {
    return;
  }
  uint8_t frame[MAX_FRAME];
  size_t frame_len = build_ethernet_frame(frame, sizeof(frame), runtime->cpe_mac,
                                          runtime->local_mac, packet, packet_len);
  if (frame_len > 0) {
    (void)write(runtime->bpf_fd, frame, frame_len);
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
  (void)write_packet_to_utun(runtime->tun_fd, packet, packet_len);
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
    if (now - last_health >= 5) {
      bool l1_ok = ping_cpe(runtime->config.cpe);
      bool l3_ok = l1_ok && tcp_probe(runtime->config.l3_host, runtime->config.l3_port);
      health_failures = update_health_failures(health_failures, l1_ok, l3_ok);
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
  if (geteuid() != 0) {
    fprintf(stderr, "start requires root\n");
    return 77;
  }
  memset(&g_runtime, 0, sizeof(g_runtime));
  g_runtime.tun_fd = -1;
  g_runtime.bpf_fd = -1;
  g_runtime.config = *config;
  path_join(g_runtime.state_file, sizeof(g_runtime.state_file), config->state_dir, "state");
  path_join(g_runtime.heartbeat_file, sizeof(g_runtime.heartbeat_file), config->state_dir, "heartbeat");
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
  }

  signal(SIGTERM, signal_handler);
  signal(SIGINT, signal_handler);
  signal(SIGHUP, signal_handler);
  snapshot_initial_network(config->state_dir);
  touch_file(g_runtime.heartbeat_file);

  if (config->ifname[0] == '\0' &&
      !route_get_interface(config->cpe, g_runtime.physical_ifname, sizeof(g_runtime.physical_ifname))) {
    fprintf(stderr, "failed to detect physical interface\n");
    return 1;
  }
  if (config->ifname[0] != '\0') {
    snprintf(g_runtime.physical_ifname, sizeof(g_runtime.physical_ifname), "%s", config->ifname);
  }
  if (!get_interface_mac_ip(g_runtime.physical_ifname, g_runtime.local_mac, &g_runtime.physical_ip)) {
    fprintf(stderr, "failed to read physical interface address\n");
    return 1;
  }
  if (!resolve_cpe_mac(config->cpe, g_runtime.cpe_mac)) {
    fprintf(stderr, "failed to resolve CPE MAC\n");
    return 1;
  }
  struct in_addr tun_addr;
  inet_pton(AF_INET, config->tun_local, &tun_addr);
  g_runtime.tun_ip = ntohl(tun_addr.s_addr);
  g_runtime.tun_fd = create_utun(g_runtime.utun_ifname, sizeof(g_runtime.utun_ifname));
  if (g_runtime.tun_fd < 0) {
    perror("utun");
    return 1;
  }
  if (!configure_routes(&g_runtime)) {
    cleanup_routes(&g_runtime);
    return 1;
  }
  unsigned int bpf_len = 0;
  g_runtime.bpf_fd = open_bpf(g_runtime.physical_ifname, &bpf_len);
  if (g_runtime.bpf_fd < 0) {
    cleanup_routes(&g_runtime);
    perror("bpf");
    return 1;
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
  if (geteuid() != 0) {
    fprintf(stderr, "stop requires root\n");
    return 77;
  }
  int pid = read_pid_from_state(config);
  if (pid > 0) {
    kill(pid, SIGTERM);
    usleep(300000);
  }
  memset(&g_runtime, 0, sizeof(g_runtime));
  g_runtime.tun_fd = -1;
  g_runtime.bpf_fd = -1;
  g_runtime.config = *config;
  char value[IFNAMSIZ];
  char state_file[512];
  path_join(state_file, sizeof(state_file), config->state_dir, "state");
  if (read_state_value(state_file, "utun", value, sizeof(value))) {
    snprintf(g_runtime.utun_ifname, sizeof(g_runtime.utun_ifname), "%s", value);
  }
  cleanup_routes(&g_runtime);
  write_state(&g_runtime, "stopped", "stopped");
  return 0;
}

static void print_status(HelperConfig *config) {
  char state_file[512];
  char heartbeat_file[512];
  char state[64] = "stopped";
  char message[512] = "";
  path_join(state_file, sizeof(state_file), config->state_dir, "state");
  path_join(heartbeat_file, sizeof(heartbeat_file), config->state_dir, "heartbeat");
  (void)read_state_value(state_file, "state", state, sizeof(state));
  (void)read_state_value(state_file, "message", message, sizeof(message));
  touch_file(heartbeat_file);
  printf("state=%s\n", state);
  printf("permission=%s\n", geteuid() == 0 ? "ready" : "needsHelperInstall");
  printf("host=%s\n", config->cpe);
  printf("reachable=%s\n", ping_cpe(config->cpe) ? "true" : "false");
  printf("serviceReady=%s\n", strcmp(state, "running") == 0 ? "true" : "false");
  printf("lastError=%s\n", message);
}

static void print_health(HelperConfig *config) {
  char heartbeat_file[512];
  path_join(heartbeat_file, sizeof(heartbeat_file), config->state_dir, "heartbeat");
  touch_file(heartbeat_file);
  bool l1 = ping_cpe(config->cpe);
  bool l3 = tcp_probe(config->l3_host, config->l3_port);
  printf("host=%s\n", config->cpe);
  printf("reachable=%s\n", l1 ? "true" : "false");
  printf("serviceReady=%s\n", (l1 && l3) ? "true" : "false");
  printf("error=%s\n", l1 ? "" : "CPE ping failed");
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

static int command_self_test(void) {
  uint8_t packet[64];
  size_t len = 0;
  NatTable table;
  memset(&table, 0, sizeof(table));
  uint32_t tun_ip = 0x0aff0002;      // 10.255.0.2
  uint32_t physical_ip = 0xc0a80158; // 192.168.1.88
  uint32_t remote_ip = 0x08080808;   // 8.8.8.8
  make_udp_packet(packet, &len, tun_ip, remote_ip, 12345, 53);
  if (!nat_translate_outgoing(&table, packet, len, physical_ip)) {
    fprintf(stderr, "nat outgoing failed\n");
    return 1;
  }
  if (read_u32(packet + 12) != physical_ip) {
    fprintf(stderr, "source NAT failed\n");
    return 1;
  }
  uint8_t reply[64];
  make_udp_packet(reply, &len, remote_ip, physical_ip, 53, 12345);
  if (!nat_translate_incoming(&table, reply, len, physical_ip)) {
    fprintf(stderr, "nat incoming failed\n");
    return 1;
  }
  if (read_u32(reply + 16) != tun_ip) {
    fprintf(stderr, "destination restore failed\n");
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
  fprintf(stderr, "%s {plan|self-test|start|stop|rollback|status|health} [options]\n", HELPER_NAME);
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
  print_usage();
  return 2;
}
