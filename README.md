# SD-WAN Verge

Flutter multi-platform client for the CPE-based SD-WAN acceleration workflow.

## Current Platform Status

- macOS: real TUN-first CPE acceleration backend is wired through `sdwan-macos-helper`.
- Windows: Flutter shell and native channel are build-ready; real Wintun/service backend is still pending.
- Linux: Flutter shell and native channel are build-ready; real `/dev/net/tun` helper is still pending.
- Android: Flutter shell and native channel are build-ready; real `VpnService` backend is still pending.
- iOS: Flutter shell and native channel are build-ready; real Packet Tunnel extension and signing entitlements are still pending.
- Web: build artifact for UI preview only; it cannot own a system TUN device.

Non-macOS platforms intentionally return `unsupported` until their real packet backends are implemented. This avoids a false "accelerated" state that would black-hole traffic.

## Default Configuration

- CPE gateway: `192.168.1.140`
- TUN mode only; route/DNS command mode is no longer the primary path.

## Local Development

```bash
flutter pub get
flutter analyze
flutter test
bash test/macos_helper/helper_self_test.sh
flutter build macos --release
```

## Release Builds

GitHub Actions workflow: `.github/workflows/release.yml`

It can be triggered manually with `workflow_dispatch` or by pushing a tag named `v*`. It uploads:

- `sdwan-verge-macos-release.zip`
- `sdwan-verge-windows-x64-release.zip`
- `sdwan-verge-linux-x64-release.tar.gz`
- `sdwan-verge-android-arm64-release.apk`
- `sdwan-verge-ios-release-unsigned.zip`
- `sdwan-verge-web-release.zip`

iOS output is unsigned and is not directly installable on devices without Apple signing assets.
