#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPER="$ROOT_DIR/build/macos/helper/sdwan-macos-helper"

"$ROOT_DIR/scripts/build_macos_helper.sh" >/dev/null

"$HELPER" self-test | grep -q "SELF_TEST_OK"

PLAN_OUTPUT="$("$HELPER" plan --cpe 192.168.1.140 --ifname en0 --utun utun9)"

grep -q "/sbin/route -n add -host 192.168.1.140 -interface en0" <<<"$PLAN_OUTPUT"
grep -q "/sbin/route -n add 0.0.0.0/1 -interface utun9" <<<"$PLAN_OUTPUT"
grep -q "/sbin/route -n add 128.0.0.0/1 -interface utun9" <<<"$PLAN_OUTPUT"
grep -q "/sbin/pfctl -a com.apple/sdwan-verge -f -" <<<"$PLAN_OUTPUT"
grep -q "block in quick on en0 proto { tcp udp } from any to <physical_ip> port 42000:42999" <<<"$PLAN_OUTPUT"
grep -q "PLAN_ONLY_NO_CHANGES_APPLIED" <<<"$PLAN_OUTPUT"

STATUS_OUTPUT="$("$HELPER" status)"
grep -q "permission=ready" <<<"$STATUS_OUTPUT"
grep -q "tx_bytes=" <<<"$STATUS_OUTPUT"
grep -q "rx_bytes=" <<<"$STATUS_OUTPUT"
grep -q "tx_rate=" <<<"$STATUS_OUTPUT"
grep -q "rx_rate=" <<<"$STATUS_OUTPUT"

TMP_STATE="$(mktemp -d)"
trap 'rm -rf "$TMP_STATE"' EXIT
cat >"$TMP_STATE/events.log" <<'LOGS'
1717473600 开启 TUN
1717473605 自动回退
LOGS
LOG_OUTPUT="$("$HELPER" logs 2 --state-dir "$TMP_STATE")"
grep -q "2024-06-04 12:00:00 开启 TUN" <<<"$LOG_OUTPUT"
grep -q "2024-06-04 12:00:05 自动回退" <<<"$LOG_OUTPUT"

cat >"$TMP_STATE/connections" <<'CONNECTIONS'
lastSeen=1717473606|proto=UDP|source=10.255.0.2:12345|target=8.8.8.8:53|domain=example.com|via=192.168.1.140:53|txBytes=60|rxBytes=72|txRate=6|rxRate=7|dnsRedirect=true
lastSeen=1717473607|proto=TCP|source=10.255.0.2:50000|target=93.184.216.34:443|domain=example.com|via=93.184.216.34:443|txBytes=120|rxBytes=240|txRate=11|rxRate=22|dnsRedirect=false
CONNECTIONS
CONNECTION_OUTPUT="$("$HELPER" connections 1 --state-dir "$TMP_STATE")"
grep -q "lastSeen=1717473607|proto=TCP|source=10.255.0.2:50000|target=93.184.216.34:443|domain=example.com|via=93.184.216.34:443|txBytes=120|rxBytes=240|txRate=11|rxRate=22|dnsRedirect=false" <<<"$CONNECTION_OUTPUT"

/usr/libexec/PlistBuddy -c "Print :com.apple.security.network.client" \
  "$ROOT_DIR/macos/Runner/Release.entitlements" | grep -q "true"
/usr/libexec/PlistBuddy -c "Print :com.apple.security.network.client" \
  "$ROOT_DIR/macos/Runner/DebugProfile.entitlements" | grep -q "true"
/usr/libexec/PlistBuddy -c "Print :com.apple.security.network.server" \
  "$ROOT_DIR/macos/Runner/Release.entitlements" | grep -q "true"
/usr/libexec/PlistBuddy -c "Print :com.apple.security.network.server" \
  "$ROOT_DIR/macos/Runner/DebugProfile.entitlements" | grep -q "true"

if /usr/libexec/PlistBuddy -c "Print :com.apple.security.app-sandbox" \
  "$ROOT_DIR/macos/Runner/Release.entitlements" >/dev/null 2>&1; then
  echo "Release.entitlements must not enable App Sandbox" >&2
  exit 1
fi
if /usr/libexec/PlistBuddy -c "Print :com.apple.security.app-sandbox" \
  "$ROOT_DIR/macos/Runner/DebugProfile.entitlements" >/dev/null 2>&1; then
  echo "DebugProfile.entitlements must not enable App Sandbox" >&2
  exit 1
fi
