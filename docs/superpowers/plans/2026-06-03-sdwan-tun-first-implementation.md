# SD-WAN TUN First Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn SD-WAN Verge from a route/DNS-first client into a TUN-only app with automatic CPE-loss recovery, then produce release artifacts for macOS, Windows, Linux, Android, iOS, and Web.

**Architecture:** Flutter owns UI, configuration, and logs. A new Dart `TunService` models the TUN lifecycle, CPE health state, and automatic recovery. Route/DNS gateway and system proxy actions are removed from the primary App UI. Native TUN backends are added incrementally: macOS Network Extension first, then Windows Wintun service, Linux `/dev/net/tun`, Android `VpnService`, and iOS `NEPacketTunnelProvider`.

**2026-06-04 progress:** The Flutter TUN-only shell, shared Dart TUN state layer, automatic CPE-loss recovery logic, desktop/mobile MethodChannel boundaries, local package script, and release workflow have been implemented. The current native handlers intentionally return `unsupported` rather than fake a working TUN. Real packet tunnel forwarding backends remain next.

**Tech Stack:** Flutter/Dart, XCTest/Xcode project files, Apple Network Extension, Windows Wintun, Linux tun helper, Android VpnService, iOS Packet Tunnel, GitHub Actions release builds.

---

## File Structure

- Create `lib/tun/tun_models.dart`
  - `TunMode`, `TunState`, `TunPermission`, `CpeHealth`, `TunStatus`.
- Create `lib/tun/tun_service.dart`
  - `TunService` interface and temporary local health-check implementation.
- Create `lib/tun/tun_controller.dart`
  - UI-facing state controller that starts/stops TUN and polls health.
- Modify `lib/ui/dashboard_page.dart`
  - Main buttons become TUN start/stop.
  - Route/DNS and system proxy actions are not shown.
- Modify `lib/ui/help_page.dart`
  - Explain TUN-only behavior and automatic recovery.
- Create `test/tun/tun_models_test.dart`
- Create `test/tun/tun_controller_test.dart`
- Add native TUN backends after channel boundary is stable:
  - macOS Packet Tunnel extension target files.
  - Windows Wintun service.
  - Linux `/dev/net/tun` helper.
  - Android `VpnService`.
  - iOS `NEPacketTunnelProvider`.
- Create `.github/workflows/release.yml`
  - Build macOS, Windows, Linux, Android, Web, and unsigned iOS artifacts.
- Create `scripts/package_releases.sh`
  - Local packaging helper for artifacts built on the current host.

## Task 1: Dart TUN State Layer

**Files:**
- Create: `lib/tun/tun_models.dart`
- Create: `lib/tun/tun_service.dart`
- Create: `lib/tun/tun_controller.dart`
- Create: `test/tun/tun_models_test.dart`
- Create: `test/tun/tun_controller_test.dart`

- [x] **Step 1: Write failing model tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/tun/tun_models.dart';

void main() {
  test('default TUN status is stopped and points at CPE', () {
    final status = TunStatus.defaults();

    expect(status.mode, TunMode.tun);
    expect(status.state, TunState.stopped);
    expect(status.permission, TunPermission.needsVpnConsent);
    expect(status.cpe.host, '192.168.1.140');
    expect(status.cpe.reachable, isFalse);
  });
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `flutter test test/tun/tun_models_test.dart`

Expected: FAIL because `lib/tun/tun_models.dart` does not exist.

- [x] **Step 3: Implement TUN models**

Implement enums and immutable model classes:

- `TunMode.tun`
- `TunState.stopped`
- `TunState.starting`
- `TunState.running`
- `TunState.stopping`
- `TunState.failed`
- `TunState.autoRecovered`
- `TunPermission.ready`
- `TunPermission.needsVpnConsent`
- `TunPermission.needsHelperInstall`
- `TunPermission.denied`
- `TunPermission.unsupported`

- [x] **Step 4: Run model tests**

Run: `flutter test test/tun/tun_models_test.dart`

Expected: PASS.

- [x] **Step 5: Write failing controller test**

```dart
test('start checks CPE before reporting running', () async {
  final service = FakeTunService(
    health: const CpeHealth(host: '192.168.1.140', reachable: true),
  );
  final controller = TunController(service: service);

  await controller.initialize();
  await controller.start();

  expect(service.calls, ['status', 'healthCheck', 'start', 'status']);
  expect(controller.status.state, TunState.running);
});
```

- [x] **Step 6: Implement `TunService` and `TunController`**

`TunController.start()` must call health check before start. If CPE is unreachable, it must set state `failed` and never call service start.

- [x] **Step 7: Run controller tests**

Run: `flutter test test/tun/tun_controller_test.dart`

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/tun test/tun
git commit -m "feat: add tun state layer"
```

## Task 2: Flutter UI Uses TUN As The Only Mode

**Files:**
- Modify: `lib/ui/dashboard_page.dart`
- Modify: `lib/ui/help_page.dart`
- Modify: `lib/main.dart` or app composition if controller injection is needed.
- Modify: `test/widget/app_shell_test.dart`

- [x] **Step 1: Write failing widget expectations**

Dashboard must show:

- `TUN 状态`
- `CPE 状态`
- `开启 TUN`
- `关闭 TUN`
- no route/DNS or system proxy primary action.

- [x] **Step 2: Implement UI changes**

Remove route/DNS and system proxy actions from the main UI. Main CTA must be TUN.

- [x] **Step 3: Run widget tests**

Run: `flutter test test/widget/app_shell_test.dart`

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/ui lib/main.dart test/widget/app_shell_test.dart
git commit -m "feat: make tun the primary app mode"
```

## Task 3: Native TUN Backend MVP

**Files:**
- Create: `macos/TunnelProvider/PacketTunnelProvider.swift`
- Create: `macos/TunnelProvider/Info.plist`
- Modify: `macos/Runner.xcodeproj/project.pbxproj`
- Modify: `macos/Runner/DebugProfile.entitlements`
- Modify: `macos/Runner/Release.entitlements`
- Create: `lib/tun/macos_tun_bridge.dart`
- Create: `test/tun/macos_tun_bridge_test.dart`

- [x] **Step 1: Add shared MethodChannel bridge tests**

Test that native MethodChannel status maps to `TunStatus`, preserves errors, and reports unsupported instead of success when no backend exists.

- [x] **Step 2: Add platform MethodChannel boundaries**

Expose `status`, `healthCheck`, `start`, and `stop` on macOS, Windows, Linux, Android, and iOS. Current native handlers return explicit `unsupported` until real backends are wired.

- [ ] **Step 3: Add Packet Tunnel Provider target**

The provider must:

- Accept `192.168.1.140` from provider configuration.
- Create a packet tunnel network settings object.
- Start and stop cleanly.
- Log CPE health result.
- Avoid changing physical network service settings.

- [x] **Step 4: Wire Flutter to platform method channels**

Expose:

- `status`
- `start`
- `stop`
- `healthCheck`

- [x] **Step 5: Verify macOS build**

Run:

```bash
flutter build macos --release
```

Expected: Release app builds with the TUN MethodChannel boundary. Network Extension target remains a follow-up.

- [ ] **Step 6: Commit**

```bash
git add macos lib/tun test/tun
git commit -m "feat: add macos tun native mvp"
```

## Task 4: Release Automation For All Platforms

**Files:**
- Create: `.github/workflows/release.yml`
- Create: `scripts/package_releases.sh`

- [x] **Step 1: Add local packaging script**

The script packages host-built outputs into `dist/releases`.

- [x] **Step 2: Add GitHub Actions release workflow**

Jobs:

- macOS: `flutter build macos --release`, `flutter build ios --release --no-codesign`
- Windows: `flutter build windows --release`
- Linux: `flutter build linux --release`
- Android: `flutter build apk --release --target-platform android-arm64`
- Web: `flutter build web`

- [x] **Step 3: Run local script on macOS**

Run: `bash scripts/package_releases.sh`

Expected: Packages macOS, Web, Android arm64, and unsigned iOS when available.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/release.yml scripts/package_releases.sh
git commit -m "ci: add cross-platform release builds"
```

## Task 5: Final Verification

Run:

```bash
flutter test
flutter analyze
bash router/openwrt/tests/static_test.sh
bash scripts/package_releases.sh
git diff --check
```

Expected:

- Flutter tests pass.
- Analyzer has no issues.
- OpenWrt static test passes.
- Local macOS-host artifacts are present in `dist/releases`.
- Windows/Linux artifacts are produced by the release workflow, not by macOS local cross-compilation.
