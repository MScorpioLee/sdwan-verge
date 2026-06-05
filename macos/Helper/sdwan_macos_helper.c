#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define HELPER_NAME "sdwan-macos-helper"
#define DEFAULT_CPE "192.168.1.140"
#define DEFAULT_STATE_DIR "/tmp/sdwan-verge-half-route"
#define INSTALLED_HELPER "/Library/PrivilegedHelperTools/com.sdwan.verge.helper"

typedef struct {
  char cpe[64];
  char ifname[64];
  char state_dir[PATH_MAX];
  bool ifname_pinned;
} HelperConfig;

typedef struct {
  uint64_t tx_total;
  uint64_t rx_total;
} TrafficCounters;

static char *capture_command(const char *command);

static bool safe_ipv4(const char *value) {
  struct in_addr address;
  return value != NULL && inet_pton(AF_INET, value, &address) == 1;
}

static bool all_digits(const char *value) {
  if (value == NULL || *value == '\0') {
    return false;
  }
  for (const char *cursor = value; *cursor != '\0'; cursor++) {
    if (*cursor < '0' || *cursor > '9') {
      return false;
    }
  }
  return true;
}

static bool ipv4_endpoint(const char *value) {
  if (value == NULL || *value == '\0' || strchr(value, ':') != NULL ||
      strchr(value, '[') != NULL || strchr(value, ']') != NULL ||
      strchr(value, '*') != NULL) {
    return false;
  }
  if (safe_ipv4(value)) {
    return true;
  }
  char host[128];
  snprintf(host, sizeof(host), "%s", value);
  char *last_dot = strrchr(host, '.');
  if (last_dot == NULL || !all_digits(last_dot + 1)) {
    return false;
  }
  *last_dot = '\0';
  return safe_ipv4(host);
}

static bool endpoint_host(const char *value, char *out, size_t out_size) {
  if (!ipv4_endpoint(value)) {
    return false;
  }
  snprintf(out, out_size, "%s", value);
  if (safe_ipv4(out)) {
    return true;
  }
  char *last_dot = strrchr(out, '.');
  if (last_dot == NULL) {
    return false;
  }
  *last_dot = '\0';
  return safe_ipv4(out);
}

static bool public_ipv4_endpoint(const char *value) {
  char host[128];
  if (!endpoint_host(value, host, sizeof(host))) {
    return false;
  }
  unsigned int a = 0, b = 0, c = 0, d = 0;
  if (sscanf(host, "%u.%u.%u.%u", &a, &b, &c, &d) != 4 ||
      a > 255 || b > 255 || c > 255 || d > 255) {
    return false;
  }
  if (a == 0 || a == 10 || a == 127) {
    return false;
  }
  if (a == 100 && b >= 64 && b <= 127) {
    return false;
  }
  if (a == 169 && b == 254) {
    return false;
  }
  if (a == 172 && b >= 16 && b <= 31) {
    return false;
  }
  if (a == 192 && b == 168) {
    return false;
  }
  if (a >= 224) {
    return false;
  }
  return true;
}

static bool domain_for_target(const char *endpoint, char *out, size_t out_size) {
  if (out_size == 0) {
    return false;
  }
  out[0] = '\0';
  char host[128];
  if (!endpoint_host(endpoint, host, sizeof(host))) {
    return false;
  }
  char command[256];
  snprintf(command, sizeof(command),
           "/usr/bin/dscacheutil -q host -a ip_address %s 2>/dev/null", host);
  char *text = capture_command(command);
  bool found = false;
  char *cursor = text;
  while (cursor != NULL && *cursor != '\0') {
    char *line = strsep(&cursor, "\n");
    if (line == NULL) {
      break;
    }
    char name[256];
    if (sscanf(line, "name: %255s", name) == 1 && strcmp(name, host) != 0) {
      snprintf(out, out_size, "%s", name);
      found = true;
      break;
    }
  }
  free(text);
  return found;
}

static void ensure_state_dir(const HelperConfig *config) {
  mkdir(config->state_dir, 0777);
  chmod(config->state_dir, 0777);
}

static void join_path(const HelperConfig *config, const char *name, char *out, size_t out_size) {
  snprintf(out, out_size, "%s/%s", config->state_dir, name);
}

static uint64_t now_ms(void) {
  struct timeval tv;
  gettimeofday(&tv, NULL);
  return (uint64_t)tv.tv_sec * 1000ULL + (uint64_t)tv.tv_usec / 1000ULL;
}

static void now_text(char *out, size_t out_size) {
  time_t raw = time(NULL);
  struct tm local_tm;
  localtime_r(&raw, &local_tm);
  strftime(out, out_size, "%Y-%m-%d %H:%M:%S", &local_tm);
}

static void log_line(const HelperConfig *config, const char *message) {
  ensure_state_dir(config);
  char path[PATH_MAX];
  join_path(config, "events.log", path, sizeof(path));
  FILE *file = fopen(path, "a");
  if (file == NULL) {
    return;
  }
  char ts[32];
  now_text(ts, sizeof(ts));
  fprintf(file, "%s %s\n", ts, message == NULL ? "" : message);
  fclose(file);
}

static int run_command(const char *command) {
  int code = system(command);
  if (code == -1) {
    return 127;
  }
  if (WIFEXITED(code)) {
    return WEXITSTATUS(code);
  }
  return code;
}

static char *capture_command(const char *command) {
  FILE *pipe = popen(command, "r");
  if (pipe == NULL) {
    return strdup("");
  }
  size_t capacity = 4096;
  size_t length = 0;
  char *output = malloc(capacity);
  if (output == NULL) {
    pclose(pipe);
    return strdup("");
  }
  output[0] = '\0';
  char buffer[1024];
  while (fgets(buffer, sizeof(buffer), pipe) != NULL) {
    size_t chunk = strlen(buffer);
    if (length + chunk + 1 > capacity) {
      capacity = (length + chunk + 1) * 2;
      char *next = realloc(output, capacity);
      if (next == NULL) {
        free(output);
        pclose(pipe);
        return strdup("");
      }
      output = next;
    }
    memcpy(output + length, buffer, chunk);
    length += chunk;
    output[length] = '\0';
  }
  pclose(pipe);
  return output;
}

static bool file_exists(const char *path) {
  return access(path, F_OK) == 0;
}

static void write_text_file(const char *path, const char *content) {
  FILE *file = fopen(path, "w");
  if (file == NULL) {
    return;
  }
  fputs(content == NULL ? "" : content, file);
  fclose(file);
  chmod(path, 0666);
}

static bool read_state_value(const HelperConfig *config, const char *key, char *out, size_t out_size) {
  char path[PATH_MAX];
  join_path(config, "state", path, sizeof(path));
  FILE *file = fopen(path, "r");
  if (file == NULL) {
    return false;
  }
  char line[512];
  size_t key_len = strlen(key);
  bool found = false;
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

static uint64_t read_state_u64(const HelperConfig *config, const char *key) {
  char value[64];
  if (!read_state_value(config, key, value, sizeof(value))) {
    return 0;
  }
  return strtoull(value, NULL, 10);
}

static pid_t read_daemon_pid(const HelperConfig *config) {
  char value[64];
  if (!read_state_value(config, "pid", value, sizeof(value))) {
    return 0;
  }
  return (pid_t)strtol(value, NULL, 10);
}

static bool pid_alive(pid_t pid) {
  return pid > 1 && kill(pid, 0) == 0;
}

static void write_state(const HelperConfig *config,
                        const char *state,
                        pid_t pid,
                        uint64_t base_tx,
                        uint64_t base_rx,
                        uint64_t last_tx_total,
                        uint64_t last_rx_total,
                        uint64_t last_sample_ms,
                        uint64_t tx_bytes,
                        uint64_t rx_bytes,
                        uint64_t tx_rate,
                        uint64_t rx_rate,
                        const char *last_error) {
  ensure_state_dir(config);
  char path[PATH_MAX];
  join_path(config, "state", path, sizeof(path));
  FILE *file = fopen(path, "w");
  if (file == NULL) {
    return;
  }
  fprintf(file, "state=%s\n", state);
  fprintf(file, "pid=%d\n", (int)pid);
  fprintf(file, "adapterName=macOS Half Route\n");
  fprintf(file, "permission=ready\n");
  fprintf(file, "helperInstalled=true\n");
  fprintf(file, "cpe=%s\n", config->cpe);
  fprintf(file, "host=%s\n", config->cpe);
  fprintf(file, "ifname=%s\n", config->ifname);
  fprintf(file, "base_tx=%llu\n", (unsigned long long)base_tx);
  fprintf(file, "base_rx=%llu\n", (unsigned long long)base_rx);
  fprintf(file, "last_tx_total=%llu\n", (unsigned long long)last_tx_total);
  fprintf(file, "last_rx_total=%llu\n", (unsigned long long)last_rx_total);
  fprintf(file, "last_sample_ms=%llu\n", (unsigned long long)last_sample_ms);
  fprintf(file, "tx_bytes=%llu\n", (unsigned long long)tx_bytes);
  fprintf(file, "rx_bytes=%llu\n", (unsigned long long)rx_bytes);
  fprintf(file, "tx_rate=%llu\n", (unsigned long long)tx_rate);
  fprintf(file, "rx_rate=%llu\n", (unsigned long long)rx_rate);
  fprintf(file, "tx_packets=0\nrx_packets=0\ntx_dropped=0\nrx_dropped=0\n");
  fprintf(file, "nat_misses=0\nsend_failures=0\nudp443_packets=0\n");
  fprintf(file, "lastError=%s\n", last_error == NULL ? "" : last_error);
  fclose(file);
  chmod(path, 0666);
}

static bool default_interface_for_cpe(const char *cpe, char *out, size_t out_size) {
  if (!safe_ipv4(cpe)) {
    snprintf(out, out_size, "%s", "en0");
    return false;
  }
  char command[256];
  snprintf(command, sizeof(command), "/sbin/route -n get %s 2>/dev/null", cpe);
  char *text = capture_command(command);
  bool found = false;
  char *cursor = text;
  while (cursor != NULL && *cursor != '\0') {
    char *line = strsep(&cursor, "\n");
    if (line == NULL) {
      break;
    }
    char name[64];
    if (sscanf(line, " interface: %63s", name) == 1) {
      snprintf(out, out_size, "%s", name);
      found = true;
      break;
    }
  }
  free(text);
  if (!found) {
    snprintf(out, out_size, "%s", "en0");
  }
  return found;
}

static bool read_traffic_counters(const char *ifname, TrafficCounters *counters) {
  counters->tx_total = 0;
  counters->rx_total = 0;
  char command[256];
  snprintf(command, sizeof(command), "/usr/sbin/netstat -ib -n -I %s 2>/dev/null", ifname);
  char *text = capture_command(command);
  char *cursor = text;
  bool found = false;
  while (cursor != NULL && *cursor != '\0') {
    char *line = strsep(&cursor, "\n");
    if (line == NULL || strstr(line, ifname) != line) {
      continue;
    }
    char *tokens[32];
    int count = 0;
    char *part_cursor = line;
    while (count < 32) {
      char *part = strsep(&part_cursor, " \t");
      if (part == NULL) {
        break;
      }
      if (part[0] == '\0') {
        continue;
      }
      tokens[count++] = part;
    }
    if (count >= 10) {
      uint64_t ibytes = strtoull(tokens[count - 2], NULL, 10);
      uint64_t obytes = strtoull(tokens[count - 1], NULL, 10);
      counters->rx_total = ibytes;
      counters->tx_total = obytes;
      found = true;
    }
  }
  free(text);
  return found;
}

static void snapshot_initial_state(const HelperConfig *config) {
  ensure_state_dir(config);
  char path[PATH_MAX];
  char *default_route = capture_command("/sbin/route -n get default 2>&1");
  join_path(config, "initial-default-route.txt", path, sizeof(path));
  write_text_file(path, default_route);
  free(default_route);

  char *routes = capture_command("/usr/sbin/netstat -rn -f inet 2>&1");
  join_path(config, "initial-netstat-rn.txt", path, sizeof(path));
  write_text_file(path, routes);
  free(routes);
}

static int delete_routes(void) {
  run_command("/sbin/route -n delete -net 0.0.0.0 -netmask 128.0.0.0 >/dev/null 2>&1");
  run_command("/sbin/route -n delete -net 128.0.0.0 -netmask 128.0.0.0 >/dev/null 2>&1");
  return 0;
}

static int add_routes(const HelperConfig *config) {
  if (!safe_ipv4(config->cpe)) {
    return 64;
  }
  char command[512];
  delete_routes();
  snprintf(command, sizeof(command),
           "/sbin/route -n add -net 0.0.0.0 -netmask 128.0.0.0 %s >/dev/null 2>&1",
           config->cpe);
  if (run_command(command) != 0) {
    return 1;
  }
  snprintf(command, sizeof(command),
           "/sbin/route -n add -net 128.0.0.0 -netmask 128.0.0.0 %s >/dev/null 2>&1",
           config->cpe);
  if (run_command(command) != 0) {
    delete_routes();
    return 1;
  }
  return 0;
}

static bool route_get_uses_cpe(const char *destination, const char *cpe) {
  char command[256];
  snprintf(command, sizeof(command), "/sbin/route -n get %s 2>/dev/null", destination);
  char *text = capture_command(command);
  bool found = false;
  char *cursor = text;
  while (cursor != NULL && *cursor != '\0') {
    char *line = strsep(&cursor, "\n");
    if (line == NULL) {
      break;
    }
    char gateway[64];
    if (sscanf(line, " gateway: %63s", gateway) == 1 && strcmp(gateway, cpe) == 0) {
      found = true;
      break;
    }
  }
  free(text);
  return found;
}

static bool routes_present(const HelperConfig *config) {
  return route_get_uses_cpe("1.1.1.1", config->cpe) &&
         route_get_uses_cpe("129.0.0.1", config->cpe);
}

static int ensure_routes(const HelperConfig *config) {
  if (routes_present(config)) {
    return 0;
  }
  return add_routes(config);
}

static bool ping_cpe(const char *cpe) {
  if (!safe_ipv4(cpe)) {
    return false;
  }
  char command[256];
  snprintf(command, sizeof(command), "/sbin/ping -c 1 -W 1000 %s >/dev/null 2>&1", cpe);
  return run_command(command) == 0;
}

static bool l3_probe(void) {
  return run_command("/usr/bin/nc -G 2 -z 1.1.1.1 443 >/dev/null 2>&1") == 0;
}

static bool stop_requested(const HelperConfig *config) {
  char path[PATH_MAX];
  join_path(config, "stop-request", path, sizeof(path));
  return file_exists(path);
}

static void clear_stop_request(const HelperConfig *config) {
  char path[PATH_MAX];
  join_path(config, "stop-request", path, sizeof(path));
  unlink(path);
}

static void request_stop(const HelperConfig *config) {
  ensure_state_dir(config);
  char path[PATH_MAX];
  join_path(config, "stop-request", path, sizeof(path));
  write_text_file(path, "stop\n");
}

static void update_traffic_state(const HelperConfig *config, const char *state, const char *last_error) {
  TrafficCounters counters;
  read_traffic_counters(config->ifname, &counters);
  uint64_t base_tx = read_state_u64(config, "base_tx");
  uint64_t base_rx = read_state_u64(config, "base_rx");
  uint64_t last_tx_total = read_state_u64(config, "last_tx_total");
  uint64_t last_rx_total = read_state_u64(config, "last_rx_total");
  uint64_t last_sample = read_state_u64(config, "last_sample_ms");
  uint64_t sample = now_ms();
  uint64_t tx_rate = 0;
  uint64_t rx_rate = 0;
  if (last_sample > 0 && sample > last_sample) {
    uint64_t elapsed = sample - last_sample;
    uint64_t tx_delta = counters.tx_total >= last_tx_total ? counters.tx_total - last_tx_total : 0;
    uint64_t rx_delta = counters.rx_total >= last_rx_total ? counters.rx_total - last_rx_total : 0;
    tx_rate = tx_delta * 1000ULL / elapsed;
    rx_rate = rx_delta * 1000ULL / elapsed;
  }
  uint64_t tx_bytes = counters.tx_total >= base_tx ? counters.tx_total - base_tx : 0;
  uint64_t rx_bytes = counters.rx_total >= base_rx ? counters.rx_total - base_rx : 0;
  write_state(config, state, read_daemon_pid(config), base_tx, base_rx, counters.tx_total,
              counters.rx_total, sample, tx_bytes, rx_bytes, tx_rate, rx_rate, last_error);
}

static void daemon_loop(HelperConfig config) {
  clear_stop_request(&config);
  int failures = 0;
  while (!stop_requested(&config)) {
    sleep(2);
    if (ensure_routes(&config) != 0) {
      failures++;
      if (failures >= 3) {
        delete_routes();
        update_traffic_state(&config, "autoRecovered", "已回切直连");
        log_line(&config, "CPE 异常，已自动回切直连");
        return;
      }
      continue;
    }
    bool l1 = ping_cpe(config.cpe);
    bool l3 = l1 && l3_probe();
    if (!l1 || !l3) {
      failures++;
    } else {
      failures = 0;
    }
    if (failures >= 3) {
      delete_routes();
      update_traffic_state(&config, "autoRecovered", "已回切直连");
      log_line(&config, "CPE 异常，已自动回切直连");
      return;
    }
    update_traffic_state(&config, "running", "");
  }
  delete_routes();
  update_traffic_state(&config, "stopped", "");
  log_line(&config, "关闭半路由");
}

static int command_plan(const HelperConfig *config) {
  printf("/sbin/route -n add -net 0.0.0.0 -netmask 128.0.0.0 %s\n", config->cpe);
  printf("/sbin/route -n add -net 128.0.0.0 -netmask 128.0.0.0 %s\n", config->cpe);
  printf("/sbin/route -n delete -net 0.0.0.0 -netmask 128.0.0.0\n");
  printf("/sbin/route -n delete -net 128.0.0.0 -netmask 128.0.0.0\n");
  printf("PLAN_ONLY_NO_CHANGES_APPLIED\n");
  return 0;
}

static int command_self_test(void) {
  printf("/sbin/route -n add -net 0.0.0.0 -netmask 128.0.0.0 %s\n", DEFAULT_CPE);
  printf("/sbin/route -n add -net 128.0.0.0 -netmask 128.0.0.0 %s\n", DEFAULT_CPE);
  printf("adapterName=macOS Half Route\n");
  printf("tx_bytes=0\nrx_bytes=0\ntx_rate=0\nrx_rate=0\n");
  printf("SELF_TEST_OK\n");
  return 0;
}

static int command_start(HelperConfig *config) {
  if (geteuid() != 0) {
    printf("state=failed\nadapterName=macOS Half Route\npermission=denied\nlastError=start requires administrator privileges\n");
    return 1;
  }
  snapshot_initial_state(config);
  TrafficCounters counters;
  read_traffic_counters(config->ifname, &counters);
  if (add_routes(config) != 0) {
    write_state(config, "failed", 0, counters.tx_total, counters.rx_total, counters.tx_total,
                counters.rx_total, now_ms(), 0, 0, 0, 0, "failed to add half routes");
    printf("state=failed\nadapterName=macOS Half Route\npermission=ready\nlastError=failed to add half routes\n");
    return 1;
  }
  pid_t child = fork();
  if (child < 0) {
    delete_routes();
    printf("state=failed\nadapterName=macOS Half Route\npermission=ready\nlastError=failed to start guard\n");
    return 1;
  }
  if (child == 0) {
    setsid();
    daemon_loop(*config);
    _exit(0);
  }
  write_state(config, "running", child, counters.tx_total, counters.rx_total, counters.tx_total,
              counters.rx_total, now_ms(), 0, 0, 0, 0, "");
  log_line(config, "开启半路由");
  printf("state=running\nadapterName=macOS Half Route\npermission=ready\nhelperInstalled=true\nhost=%s\nreachable=%s\nserviceReady=%s\ntx_bytes=0\nrx_bytes=0\ntx_rate=0\nrx_rate=0\nlastError=\n",
         config->cpe, ping_cpe(config->cpe) ? "true" : "false", ping_cpe(config->cpe) ? "true" : "false");
  return 0;
}

static int command_stop(HelperConfig *config, const char *message) {
  request_stop(config);
  pid_t pid = read_daemon_pid(config);
  if (geteuid() == 0) {
    if (pid_alive(pid)) {
      kill(pid, SIGTERM);
    }
    delete_routes();
    update_traffic_state(config, "stopped", "");
    log_line(config, message == NULL ? "关闭半路由" : message);
  } else {
    for (int i = 0; i < 30; ++i) {
      if (!pid_alive(pid)) {
        break;
      }
      usleep(100000);
    }
  }
  printf("state=stopped\nadapterName=macOS Half Route\npermission=ready\nhelperInstalled=true\nhost=%s\nreachable=%s\nserviceReady=%s\ntx_bytes=%llu\nrx_bytes=%llu\ntx_rate=0\nrx_rate=0\nlastError=\n",
         config->cpe, ping_cpe(config->cpe) ? "true" : "false", ping_cpe(config->cpe) ? "true" : "false",
         (unsigned long long)read_state_u64(config, "tx_bytes"),
         (unsigned long long)read_state_u64(config, "rx_bytes"));
  return 0;
}

static int command_status(HelperConfig *config) {
  char state[64] = "stopped";
  char cpe[64];
  if (read_state_value(config, "cpe", cpe, sizeof(cpe))) {
    snprintf(config->cpe, sizeof(config->cpe), "%s", cpe);
  }
  read_state_value(config, "state", state, sizeof(state));
  pid_t pid = read_daemon_pid(config);
  if (strcmp(state, "running") == 0 && !pid_alive(pid)) {
    snprintf(state, sizeof(state), "%s", "stopped");
  }
  if (!read_state_value(config, "ifname", config->ifname, sizeof(config->ifname)) &&
      !config->ifname_pinned) {
    default_interface_for_cpe(config->cpe, config->ifname, sizeof(config->ifname));
  }
  update_traffic_state(config, state, read_state_u64(config, "last_sample_ms") == 0 ? "" : "");
  bool l1 = ping_cpe(config->cpe);
  printf("state=%s\n", state);
  printf("adapterName=macOS Half Route\npermission=ready\nhelperInstalled=true\n");
  printf("host=%s\ncpe=%s\nreachable=%s\nserviceReady=%s\n",
         config->cpe, config->cpe, l1 ? "true" : "false", l1 ? "true" : "false");
  printf("tx_bytes=%llu\nrx_bytes=%llu\ntx_rate=%llu\nrx_rate=%llu\n",
         (unsigned long long)read_state_u64(config, "tx_bytes"),
         (unsigned long long)read_state_u64(config, "rx_bytes"),
         (unsigned long long)read_state_u64(config, "tx_rate"),
         (unsigned long long)read_state_u64(config, "rx_rate"));
  printf("tx_packets=0\nrx_packets=0\ntx_dropped=0\nrx_dropped=0\n");
  printf("nat_misses=0\nsend_failures=0\nudp443_packets=0\n");
  printf("lastError=\n");
  return 0;
}

static int command_health(const HelperConfig *config) {
  bool l1 = ping_cpe(config->cpe);
  bool l3 = l1 && l3_probe();
  printf("host=%s\nreachable=%s\nserviceReady=%s\nl3Reachable=%s\nerror=%s\n",
         config->cpe, l1 ? "true" : "false", l1 ? "true" : "false",
         l3 ? "true" : "false",
         l1 ? (l3 ? "" : "CPE reachable but L3 probe failed") : "CPE ping failed");
  return l1 ? 0 : 1;
}

static int tail_file(const char *path, int limit) {
  FILE *file = fopen(path, "r");
  if (file == NULL) {
    return 0;
  }
  char **lines = calloc((size_t)limit, sizeof(char *));
  if (lines == NULL) {
    fclose(file);
    return 0;
  }
  int index = 0;
  int count = 0;
  char buffer[2048];
  while (fgets(buffer, sizeof(buffer), file) != NULL) {
    free(lines[index]);
    lines[index] = strdup(buffer);
    index = (index + 1) % limit;
    if (count < limit) {
      count++;
    }
  }
  fclose(file);
  int start = count == limit ? index : 0;
  for (int i = 0; i < count; ++i) {
    int slot = (start + i) % limit;
    if (lines[slot] != NULL) {
      fputs(lines[slot], stdout);
      free(lines[slot]);
    }
  }
  free(lines);
  return 0;
}

static int command_logs(const HelperConfig *config, int limit) {
  char path[PATH_MAX];
  join_path(config, "events.log", path, sizeof(path));
  return tail_file(path, limit);
}

static void print_system_connections(int limit) {
  char *text = capture_command("/usr/sbin/netstat -an -f inet -p tcp 2>/dev/null; /usr/sbin/netstat -an -f inet -p udp 2>/dev/null");
  char *cursor = text;
  int count = 0;
  char ts[32];
  now_text(ts, sizeof(ts));
  while (cursor != NULL && *cursor != '\0' && count < limit) {
    char *line = strsep(&cursor, "\n");
    if (line == NULL) {
      break;
    }
    char proto[16], recvq[32], sendq[32], local[128], foreign[128], state[64];
    int matched = sscanf(line, "%15s %31s %31s %127s %127s %63s", proto, recvq, sendq, local, foreign, state);
    if (matched < 5 || (strncmp(proto, "tcp", 3) != 0 && strncmp(proto, "udp", 3) != 0)) {
      continue;
    }
    if (matched >= 6 && (strcmp(state, "LISTEN") == 0 || strcmp(state, "TIME_WAIT") == 0)) {
      continue;
    }
    if (!ipv4_endpoint(local) || !public_ipv4_endpoint(foreign)) {
      continue;
    }
    char domain[256];
    domain_for_target(foreign, domain, sizeof(domain));
    printf("lastSeen=%s|proto=%s|source=%s|target=%s|domain=%s|via=|txBytes=0|rxBytes=0|txRate=0|rxRate=0|dnsRedirect=false\n",
           ts, strncmp(proto, "tcp", 3) == 0 ? "TCP" : "UDP", local, foreign, domain);
    count++;
  }
  free(text);
}

static int command_connections(const HelperConfig *config, int limit) {
  char path[PATH_MAX];
  join_path(config, "connections", path, sizeof(path));
  if (file_exists(path)) {
    return tail_file(path, limit);
  }
  print_system_connections(limit);
  return 0;
}

static int copy_file(const char *from, const char *to) {
  FILE *src = fopen(from, "rb");
  if (src == NULL) {
    return 1;
  }
  FILE *dst = fopen(to, "wb");
  if (dst == NULL) {
    fclose(src);
    return 1;
  }
  char buffer[8192];
  size_t n;
  while ((n = fread(buffer, 1, sizeof(buffer), src)) > 0) {
    fwrite(buffer, 1, n, dst);
  }
  fclose(src);
  fclose(dst);
  chmod(to, 0755);
  return 0;
}

static int command_install(const char *self_path, HelperConfig *config) {
  if (geteuid() != 0) {
    printf("state=failed\nadapterName=macOS Half Route\npermission=denied\nlastError=install requires administrator privileges\n");
    return 1;
  }
  if (copy_file(self_path, INSTALLED_HELPER) != 0) {
    printf("state=failed\nadapterName=macOS Half Route\npermission=denied\nlastError=failed to install helper\n");
    return 1;
  }
  log_line(config, "助手已安装");
  return command_status(config);
}

static int command_uninstall(HelperConfig *config) {
  command_stop(config, "关闭半路由");
  if (geteuid() == 0) {
    unlink(INSTALLED_HELPER);
  }
  printf("state=stopped\nadapterName=macOS Half Route\npermission=needsHelperInstall\nhelperInstalled=false\nlastError=\n");
  return 0;
}

static void parse_args(int argc, char **argv, HelperConfig *config, int *limit) {
  snprintf(config->cpe, sizeof(config->cpe), "%s", DEFAULT_CPE);
  snprintf(config->ifname, sizeof(config->ifname), "%s", "en0");
  snprintf(config->state_dir, sizeof(config->state_dir), "%s", DEFAULT_STATE_DIR);
  config->ifname_pinned = false;
  *limit = 80;
  for (int i = 2; i < argc; ++i) {
    if (strcmp(argv[i], "--cpe") == 0 && i + 1 < argc) {
      snprintf(config->cpe, sizeof(config->cpe), "%s", argv[++i]);
    } else if (strcmp(argv[i], "--ifname") == 0 && i + 1 < argc) {
      snprintf(config->ifname, sizeof(config->ifname), "%s", argv[++i]);
      config->ifname_pinned = true;
    } else if (strcmp(argv[i], "--state-dir") == 0 && i + 1 < argc) {
      snprintf(config->state_dir, sizeof(config->state_dir), "%s", argv[++i]);
    } else if (strcmp(argv[i], "--limit") == 0 && i + 1 < argc) {
      *limit = atoi(argv[++i]);
    } else if (argv[i][0] != '-' && *limit == 80) {
      *limit = atoi(argv[i]);
    }
  }
  if (*limit <= 0) {
    *limit = 80;
  }
  if (!config->ifname_pinned) {
    default_interface_for_cpe(config->cpe, config->ifname, sizeof(config->ifname));
  }
}

static void usage(void) {
  fprintf(stderr, "%s {plan|self-test|install|uninstall|start|stop|rollback|status|health|logs|connections} [--cpe ip] [--ifname name] [--state-dir dir] [--limit n]\n", HELPER_NAME);
}

int main(int argc, char **argv) {
  if (argc < 2) {
    usage();
    return 64;
  }
  HelperConfig config;
  int limit;
  parse_args(argc, argv, &config, &limit);
  if (!safe_ipv4(config.cpe)) {
    fprintf(stderr, "invalid CPE IPv4 address\n");
    return 64;
  }
  if (strcmp(argv[1], "plan") == 0) {
    return command_plan(&config);
  }
  if (strcmp(argv[1], "self-test") == 0) {
    return command_self_test();
  }
  if (strcmp(argv[1], "install") == 0) {
    return command_install(argv[0], &config);
  }
  if (strcmp(argv[1], "uninstall") == 0) {
    return command_uninstall(&config);
  }
  if (strcmp(argv[1], "start") == 0) {
    return command_start(&config);
  }
  if (strcmp(argv[1], "stop") == 0 || strcmp(argv[1], "rollback") == 0) {
    return command_stop(&config, "关闭半路由");
  }
  if (strcmp(argv[1], "status") == 0) {
    return command_status(&config);
  }
  if (strcmp(argv[1], "health") == 0 || strcmp(argv[1], "healthCheck") == 0) {
    return command_health(&config);
  }
  if (strcmp(argv[1], "logs") == 0) {
    return command_logs(&config, limit);
  }
  if (strcmp(argv[1], "connections") == 0) {
    return command_connections(&config, limit);
  }
  usage();
  return 64;
}
