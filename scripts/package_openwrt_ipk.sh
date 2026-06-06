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
rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache /tmp/luci-*cache* 2>/dev/null || true
exit 0
EOF

cat >"$WORK_DIR/control/postrm" <<'EOF'
#!/bin/sh
rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache /tmp/luci-*cache* 2>/dev/null || true
exit 0
EOF

chmod 755 "$WORK_DIR/control/postinst" "$WORK_DIR/control/postrm"

printf '2.0\n' >"$WORK_DIR/debian-binary"

python3 - "$WORK_DIR/control" "$WORK_DIR/control.tar.gz" <<'PY'
import gzip
import os
import sys
import tarfile

source_dir, out_path = sys.argv[1], sys.argv[2]

with gzip.GzipFile(out_path, "wb", mtime=0) as gzip_file:
    with tarfile.open(fileobj=gzip_file, mode="w", format=tarfile.USTAR_FORMAT) as archive:
        for root, dirs, files in os.walk(source_dir):
            dirs.sort()
            files.sort()
            rel_root = os.path.relpath(root, source_dir)
            for file_name in files:
                path = os.path.join(root, file_name)
                rel_path = file_name if rel_root == "." else os.path.join(rel_root, file_name)
                info = archive.gettarinfo(path, arcname="./" + rel_path)
                info.uid = info.gid = 0
                info.uname = info.gname = "root"
                info.mtime = 0
                with open(path, "rb") as handle:
                    archive.addfile(info, handle)
PY

python3 - "$WORK_DIR/data" "$WORK_DIR/data.tar.gz" <<'PY'
import gzip
import os
import stat
import sys
import tarfile

source_dir, out_path = sys.argv[1], sys.argv[2]

def add_dir(archive, rel_path):
    info = tarfile.TarInfo("./" + rel_path + "/")
    info.type = tarfile.DIRTYPE
    info.mode = 0o755
    info.uid = info.gid = 0
    info.uname = info.gname = "root"
    info.mtime = 0
    archive.addfile(info)

with gzip.GzipFile(out_path, "wb", mtime=0) as gzip_file:
    with tarfile.open(fileobj=gzip_file, mode="w", format=tarfile.USTAR_FORMAT) as archive:
        for root, dirs, files in os.walk(source_dir):
            dirs.sort()
            files.sort()
            rel_root = os.path.relpath(root, source_dir)
            if rel_root != ".":
                add_dir(archive, rel_root)
            for file_name in files:
                path = os.path.join(root, file_name)
                rel_path = file_name if rel_root == "." else os.path.join(rel_root, file_name)
                info = archive.gettarinfo(path, arcname="./" + rel_path)
                info.uid = info.gid = 0
                info.uname = info.gname = "root"
                info.mtime = 0
                mode = stat.S_IMODE(info.mode)
                info.mode = 0o755 if mode & 0o111 else 0o644
                with open(path, "rb") as handle:
                    archive.addfile(info, handle)
PY

rm -f "$OUT_PATH"
python3 - "$WORK_DIR" "$OUT_PATH" <<'PY'
import gzip
import sys
import tarfile

work_dir, out_path = sys.argv[1], sys.argv[2]
outer_members = ["debian-binary", "data.tar.gz", "control.tar.gz"]

with gzip.GzipFile(out_path, "wb", mtime=0) as gzip_file:
    with tarfile.open(fileobj=gzip_file, mode="w", format=tarfile.USTAR_FORMAT) as archive:
        for name in outer_members:
            path = f"{work_dir}/{name}"
            info = archive.gettarinfo(path, arcname="./" + name)
            info.uid = info.gid = 0
            info.uname = info.gname = "root"
            info.mode = 0o644
            info.mtime = 0
            with open(path, "rb") as handle:
                archive.addfile(info, handle)
PY

echo "packaged $OUT_PATH"
