# OpenWrt SD-WAN Verge Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first repo-local OpenWrt/iStoreOS plugin skeleton for SD-WAN Verge, including package metadata, UCI config, init script, shell core, LuCI view, tests, and build notes.

**Architecture:** The plugin is independent from the Flutter app and lives under `router/openwrt/`. A shell core applies or removes the two BAT-derived half routes and optional dnsmasq DNS settings. LuCI edits the UCI config and invokes the core through rpcd ACL-controlled `fs.exec()`.

**Tech Stack:** OpenWrt package Makefile, rc.common init script, UCI config, BusyBox POSIX shell, LuCI JavaScript view, static shell/JSON/JS verification.

---

## File Structure

- Create `router/openwrt/Makefile`
  - OpenWrt package recipe for `luci-app-sdwan-verge`.
  - Installs config, init script, shell core, LuCI menu, ACL, and view assets.
- Create `router/openwrt/files/etc/config/sdwan_verge`
  - UCI default config with CPE `192.168.1.140`, DNS `223.5.5.5` and `114.114.114.114`, and disabled-by-default switch.
- Create `router/openwrt/files/etc/init.d/sdwan-verge`
  - rc.common wrapper that delegates `start`, `stop`, `restart`, `reload`, and `status` to the shell core.
- Create `router/openwrt/files/usr/libexec/sdwan-verge/sdwan-verge-core`
  - POSIX shell command entrypoint: `start`, `stop`, `restart`, `status`, `set-dns`, `restore-dns`, `logs`, `doctor`.
  - Owns route replacement/deletion, DNS backup/restore, validation, logging, and safety rollback.
- Create `router/openwrt/files/usr/share/luci/menu.d/luci-app-sdwan-verge.json`
  - Adds `Services > SD-WAN Verge`.
- Create `router/openwrt/files/usr/share/rpcd/acl.d/luci-app-sdwan-verge.json`
  - Grants LuCI access to UCI config and core execution.
- Create `router/openwrt/files/www/luci-static/resources/view/sdwan-verge/status.js`
  - LuCI config/status page with start/stop/restart buttons.
- Create `router/openwrt/tests/static_test.sh`
  - Verifies shell syntax, JSON validity, key route/DNS behavior strings, package install paths, and optional LuCI JS syntax.
- Create `router/openwrt/README.md`
  - Explains package layout, SDK build copy command, install command, runtime commands, and safety notes.

## Task 1: Static Test Harness

**Files:**
- Create: `router/openwrt/tests/static_test.sh`

- [ ] **Step 1: Write the failing static test**

```sh
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE="$ROOT/files/usr/libexec/sdwan-verge/sdwan-verge-core"
INIT="$ROOT/files/etc/init.d/sdwan-verge"
MAKEFILE="$ROOT/Makefile"
CONFIG="$ROOT/files/etc/config/sdwan_verge"
MENU="$ROOT/files/usr/share/luci/menu.d/luci-app-sdwan-verge.json"
ACL="$ROOT/files/usr/share/rpcd/acl.d/luci-app-sdwan-verge.json"
VIEW="$ROOT/files/www/luci-static/resources/view/sdwan-verge/status.js"

assert_file() {
  test -f "$1" || {
    echo "missing file: $1" >&2
    exit 1
  }
}

assert_contains() {
  local needle="$1"
  local file="$2"
  grep -Fq "$needle" "$file" || {
    echo "missing '$needle' in $file" >&2
    exit 1
  }
}

assert_file "$CORE"
assert_file "$INIT"
assert_file "$MAKEFILE"
assert_file "$CONFIG"
assert_file "$MENU"
assert_file "$ACL"
assert_file "$VIEW"

sh -n "$CORE"
sh -n "$INIT"

python3 -m json.tool "$MENU" >/dev/null
python3 -m json.tool "$ACL" >/dev/null

if command -v node >/dev/null 2>&1; then
  node --check "$VIEW"
fi

assert_contains "PKG_NAME:=luci-app-sdwan-verge" "$MAKEFILE"
assert_contains "$(INSTALL_BIN)" "$MAKEFILE"
assert_contains "config settings 'main'" "$CONFIG"
assert_contains "option cpe_gateway '192.168.1.140'" "$CONFIG"
assert_contains "list dns_server '223.5.5.5'" "$CONFIG"
assert_contains "list dns_server '114.114.114.114'" "$CONFIG"
assert_contains "ip route replace 0.0.0.0/1 via" "$CORE"
assert_contains "ip route replace 128.0.0.0/1 via" "$CORE"
assert_contains "uci add_list dhcp.@dnsmasq[0].server" "$CORE"
assert_contains "/etc/init.d/dnsmasq restart" "$CORE"
assert_contains "restore_dns" "$CORE"
assert_contains "sdwan-verge-core" "$INIT"
assert_contains "admin/services/sdwan-verge" "$MENU"
assert_contains "luci-app-sdwan-verge" "$ACL"
assert_contains "SD-WAN Verge" "$VIEW"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash router/openwrt/tests/static_test.sh`

Expected: FAIL with missing `router/openwrt` files.

## Task 2: Package, Config, Core, and Init

**Files:**
- Create: `router/openwrt/Makefile`
- Create: `router/openwrt/files/etc/config/sdwan_verge`
- Create: `router/openwrt/files/etc/init.d/sdwan-verge`
- Create: `router/openwrt/files/usr/libexec/sdwan-verge/sdwan-verge-core`

- [ ] **Step 1: Implement package Makefile**

Create the package recipe with `PKG_NAME:=luci-app-sdwan-verge`, `PKG_VERSION:=0.1.0`, `DEPENDS:=+luci-base +rpcd +uci +dnsmasq +ip-tiny`, empty `Build/Compile`, conffile `/etc/config/sdwan_verge`, and install rules for config, init, core, menu, ACL, and LuCI view.

- [ ] **Step 2: Implement UCI defaults**

Create a disabled-by-default config:

```text
config settings 'main'
        option enabled '0'
        option cpe_gateway '192.168.1.140'
        option sync_dns '1'
        list dns_server '223.5.5.5'
        list dns_server '114.114.114.114'
```

- [ ] **Step 3: Implement shell core**

Implement:

- `start`: validate gateway, add both half routes with `ip route replace`, optionally backup and set dnsmasq DNS, mark state, rollback routes on DNS failure.
- `stop`: delete both routes, restore backed-up dnsmasq DNS, clear state.
- `status`: print JSON containing enabled, active, gateway, DNS servers, and route presence.
- `doctor`: validate presence of `ip`, `uci`, dnsmasq init script, and configured gateway.
- `logs`: print `/tmp/sdwan-verge/sdwan-verge.log`.

- [ ] **Step 4: Implement init wrapper**

Use `#!/bin/sh /etc/rc.common`, `START=95`, `STOP=10`, and delegate runtime commands to `/usr/libexec/sdwan-verge/sdwan-verge-core`.

- [ ] **Step 5: Run test to verify it still fails only on LuCI files**

Run: `bash router/openwrt/tests/static_test.sh`

Expected: FAIL with missing menu, ACL, or view files.

## Task 3: LuCI Page and ACL

**Files:**
- Create: `router/openwrt/files/usr/share/luci/menu.d/luci-app-sdwan-verge.json`
- Create: `router/openwrt/files/usr/share/rpcd/acl.d/luci-app-sdwan-verge.json`
- Create: `router/openwrt/files/www/luci-static/resources/view/sdwan-verge/status.js`

- [ ] **Step 1: Add menu JSON**

Create a LuCI menu entry at `admin/services/sdwan-verge` with view path `sdwan-verge/status` and ACL dependency `luci-app-sdwan-verge`.

- [ ] **Step 2: Add rpcd ACL JSON**

Grant read/write UCI access for `sdwan_verge` and exec access for `/usr/libexec/sdwan-verge/sdwan-verge-core`.

- [ ] **Step 3: Add LuCI JS view**

Use `view`, `form`, `fs`, `uci`, `ui`, and `poll`. Render status, config fields, and buttons calling core actions `start`, `stop`, `restart`, `doctor`, and `logs`.

- [ ] **Step 4: Run static test to verify pass**

Run: `bash router/openwrt/tests/static_test.sh`

Expected: PASS.

## Task 4: README and Verification

**Files:**
- Create: `router/openwrt/README.md`
- Modify if needed: files from Tasks 1-3

- [ ] **Step 1: Add README**

Document:

- Target layout and package purpose.
- SDK copy/build example.
- IPK install command.
- Runtime commands.
- Safety notes about default gateway, CPE subnet, DNS restore, and emergency stop.
- iStoreOS packaging note.

- [ ] **Step 2: Run focused verification**

Run:

```bash
bash router/openwrt/tests/static_test.sh
flutter test
git diff --check
```

Expected:

- Static OpenWrt test passes.
- Flutter tests pass.
- No whitespace errors.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/plans/2026-06-03-openwrt-sdwan-verge-plugin.md router/openwrt
git commit -m "feat: add openwrt sdwan verge plugin skeleton"
```
