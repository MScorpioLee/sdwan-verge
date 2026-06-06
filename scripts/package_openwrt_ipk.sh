#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_DIR="$ROOT_DIR/router/openwrt"
DIST_DIR="$ROOT_DIR/dist/releases"
WORK_DIR="$ROOT_DIR/build/openwrt-ipk"

PKG_NAME="luci-app-sdwan-verge"
PKG_VERSION="0.1.0"
PKG_RELEASE="1"
PKG_ARCH="all"
OUT_PATH="$DIST_DIR/${PKG_NAME}_${PKG_VERSION}-${PKG_RELEASE}_${PKG_ARCH}.ipk"

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "missing required file: $1" >&2
    exit 1
  fi
}

require_file "$PKG_DIR/Makefile"
require_file "$PKG_DIR/files/etc/config/sdwan_verge"
require_file "$PKG_DIR/files/etc/init.d/sdwan-verge"
require_file "$PKG_DIR/files/usr/libexec/sdwan-verge/sdwan-verge-core"
require_file "$PKG_DIR/files/usr/share/luci/menu.d/luci-app-sdwan-verge.json"
require_file "$PKG_DIR/files/usr/share/rpcd/acl.d/luci-app-sdwan-verge.json"
require_file "$PKG_DIR/files/www/luci-static/resources/view/sdwan-verge/status.js"

command -v python3 >/dev/null 2>&1 || {
  echo "missing python3 command" >&2
  exit 1
}

rm -rf "$WORK_DIR"
mkdir -p "$DIST_DIR" "$WORK_DIR/control" "$WORK_DIR/data"

cp -R "$PKG_DIR/files/." "$WORK_DIR/data/"
chmod 755 "$WORK_DIR/data/etc/init.d/sdwan-verge"
chmod 755 "$WORK_DIR/data/usr/libexec/sdwan-verge/sdwan-verge-core"

cat >"$WORK_DIR/control/control" <<EOF
Package: $PKG_NAME
Version: $PKG_VERSION-$PKG_RELEASE
Architecture: all
Maintainer: Leslie <leslie@example.local>
Section: luci
Priority: optional
Depends: luci-base, rpcd, uci, dnsmasq, ip-tiny
Description: SD-WAN Verge LuCI plugin for OpenWrt/iStoreOS half-route acceleration.
EOF

cat >"$WORK_DIR/control/conffiles" <<'EOF'
/etc/config/sdwan_verge
EOF

cat >"$WORK_DIR/control/postinst" <<'EOF'
#!/bin/sh
[ -n "$IPKG_INSTROOT" ] && exit 0
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
exit 0
EOF
chmod 755 "$WORK_DIR/control/postinst"

cat >"$WORK_DIR/control/postrm" <<'EOF'
#!/bin/sh
[ -n "$IPKG_INSTROOT" ] && exit 0
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
exit 0
EOF
chmod 755 "$WORK_DIR/control/postrm"

printf '2.0\n' >"$WORK_DIR/debian-binary"

(cd "$WORK_DIR/control" && tar -czf "$WORK_DIR/control.tar.gz" .)
(cd "$WORK_DIR/data" && tar -czf "$WORK_DIR/data.tar.gz" .)

rm -f "$OUT_PATH"
python3 - "$OUT_PATH" \
  "$WORK_DIR/debian-binary" \
  "$WORK_DIR/control.tar.gz" \
  "$WORK_DIR/data.tar.gz" <<'PY'
import os
import sys

out_path = sys.argv[1]
members = sys.argv[2:]

with open(out_path, "wb") as archive:
    archive.write(b"!<arch>\n")
    for member in members:
        name = os.path.basename(member)
        with open(member, "rb") as source:
            data = source.read()
        header = (
            name.ljust(16)
            + "0".ljust(12)
            + "0".ljust(6)
            + "0".ljust(6)
            + format(0o100644, "o").ljust(8)
            + str(len(data)).ljust(10)
            + "`\n"
        )
        if len(header) != 60:
            raise SystemExit(f"invalid ar header for {name}: {len(header)} bytes")
        archive.write(header.encode("ascii"))
        archive.write(data)
        if len(data) % 2:
            archive.write(b"\n")
PY

echo "packaged $OUT_PATH"
