#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/releases"

mkdir -p "$DIST_DIR"

package_macos() {
  local app_path="$ROOT_DIR/build/macos/Build/Products/Release/SD-WAN Verge.app"
  local out_path="$DIST_DIR/sdwan-verge-macos-release.dmg"
  if [[ -d "$app_path" ]]; then
    local bundled_helper="$app_path/Contents/Resources/sdwan-macos-helper"
    if [[ ! -x "$bundled_helper" ]]; then
      echo "missing executable macOS helper in signed app bundle: $bundled_helper" >&2
      exit 1
    fi
    codesign --verify --deep --strict --verbose=4 "$app_path"
    rm -f "$out_path"
    hdiutil create -volname "SD-WAN Verge" -srcfolder "$app_path" -ov -format UDZO "$out_path"
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
  local out_path="$DIST_DIR/sdwan-verge-ios-release-unsigned.ipa"
  if [[ -d "$app_path" ]]; then
    local payload_dir="$DIST_DIR/ios-payload/Payload"
    rm -rf "$DIST_DIR/ios-payload" "$out_path"
    mkdir -p "$payload_dir"
    cp -R "$app_path" "$payload_dir/Runner.app"
    (cd "$DIST_DIR/ios-payload" && zip -qry "$out_path" Payload)
    rm -rf "$DIST_DIR/ios-payload"
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
