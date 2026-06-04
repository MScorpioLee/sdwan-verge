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
grep -q "PLAN_ONLY_NO_CHANGES_APPLIED" <<<"$PLAN_OUTPUT"

/usr/libexec/PlistBuddy -c "Print :com.apple.security.network.client" \
  "$ROOT_DIR/macos/Runner/Release.entitlements" | grep -q "true"
/usr/libexec/PlistBuddy -c "Print :com.apple.security.network.client" \
  "$ROOT_DIR/macos/Runner/DebugProfile.entitlements" | grep -q "true"
