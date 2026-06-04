#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/releases"

mkdir -p "$DIST_DIR"

package_macos() {
  local app_path="$ROOT_DIR/build/macos/Build/Products/Release/SD-WAN Verge.app"
  local out_path="$DIST_DIR/sdwan-verge-macos-release.zip"
  if [[ -d "$app_path" ]]; then
    local helper_path
    helper_path="$("$ROOT_DIR/scripts/build_macos_helper.sh")"
    cp "$helper_path" "$app_path/Contents/Resources/sdwan-macos-helper"
    chmod 755 "$app_path/Contents/Resources/sdwan-macos-helper"
    (cd "$(dirname "$app_path")" && zip -qry "$out_path" "$(basename "$app_path")")
    echo "packaged $out_path"
  fi
}

package_web() {
  local web_path="$ROOT_DIR/build/web"
  local out_path="$DIST_DIR/sdwan-verge-web-release.zip"
  if [[ -d "$web_path" ]]; then
    (cd "$web_path" && zip -qry "$out_path" .)
    echo "packaged $out_path"
  fi
}

package_android() {
  local apk_path="$ROOT_DIR/build/app/outputs/flutter-apk/app-release.apk"
  local out_path="$DIST_DIR/sdwan-verge-android-arm64-release.apk"
  if [[ -f "$apk_path" ]]; then
    cp "$apk_path" "$out_path"
    echo "packaged $out_path"
  fi
}

package_ios() {
  local app_path="$ROOT_DIR/build/ios/iphoneos/Runner.app"
  local out_path="$DIST_DIR/sdwan-verge-ios-release-unsigned.zip"
  if [[ -d "$app_path" ]]; then
    (cd "$(dirname "$app_path")" && zip -qry "$out_path" "$(basename "$app_path")")
    echo "packaged $out_path"
  fi
}

package_windows() {
  local app_path="$ROOT_DIR/build/windows/x64/runner/Release"
  local out_path="$DIST_DIR/sdwan-verge-windows-x64-release.zip"
  if [[ -d "$app_path" ]]; then
    (cd "$app_path" && zip -qry "$out_path" .)
    echo "packaged $out_path"
  fi
}

package_linux() {
  local app_path="$ROOT_DIR/build/linux/x64/release/bundle"
  local out_path="$DIST_DIR/sdwan-verge-linux-x64-release.tar.gz"
  if [[ -d "$app_path" ]]; then
    tar -C "$app_path" -czf "$out_path" .
    echo "packaged $out_path"
  fi
}

package_macos
package_web
package_android
package_ios
package_windows
package_linux
