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
README="$ROOT/README.md"

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
assert_file "$README"

sh -n "$CORE"
sh -n "$INIT"

python3 -m json.tool "$MENU" >/dev/null
python3 -m json.tool "$ACL" >/dev/null

if command -v node >/dev/null 2>&1; then
  node --check "$VIEW"
fi

assert_contains "PKG_NAME:=luci-app-sdwan-verge" "$MAKEFILE"
assert_contains '$(INSTALL_BIN)' "$MAKEFILE"
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
assert_contains "iStoreOS" "$README"
