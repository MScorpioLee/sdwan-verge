# SD-WAN Cross-Platform Gateways Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the Flutter client beyond Windows by adding macOS and Linux local route/DNS gateways, and by making Web/iOS/Android explicitly behave as router-plugin management surfaces rather than pretending to modify local system routes.

**Architecture:** Keep the existing `NetworkPlatformGateway` boundary. Windows remains unchanged. macOS and Linux get platform-specific command builders, parsers, gateways, and tests. Mobile/Web use a remote-management capability status until a real authenticated OpenWrt/iStoreOS API client is added.

**Tech Stack:** Flutter/Dart, `dart:io` platform detection, process command runner, macOS `route`/`networksetup`, Linux `ip`/`resolvectl`/`pkexec`, Flutter widget tests.

---

## File Structure

- Create `lib/platform/macos/macos_commands.dart`
  - Command builders for route add/delete, DNS set/restore, cache flush, status reads, and AppleScript administrator execution.
- Create `lib/platform/macos/macos_parsers.dart`
  - Parse default interface, hardware port service name, DNS servers, and half-route presence.
- Create `lib/platform/macos/macos_network_gateway.dart`
  - Implements `NetworkPlatformGateway` for macOS.
- Create `lib/platform/linux/linux_commands.dart`
  - Command builders for `ip route`, `resolvectl`, and `pkexec sh -c`.
- Create `lib/platform/linux/linux_parsers.dart`
  - Parse Linux route, interface, source IP, DNS servers, and half-route presence.
- Create `lib/platform/linux/linux_network_gateway.dart`
  - Implements `NetworkPlatformGateway` for Linux.
- Modify `lib/platform/network_gateway_io.dart`
  - Route platform detection to Windows/macOS/Linux/mobile gateways.
- Modify `lib/platform/network_gateway_stub.dart`
  - Web becomes remote-management capability.
- Modify `lib/domain/network_status.dart`
  - Add `PlatformCapability.remoteManager` and factory for router-plugin management surfaces.
- Modify `lib/ui/dashboard_page.dart`
  - Disable local route/DNS buttons when platform is not local-full and show the platform message.
- Modify `lib/ui/help_page.dart`
  - Document Windows/macOS/Linux local behavior and Web/iOS/Android router-plugin path.

## Task 1: Capability Model and Mobile/Web Status

- [ ] **Step 1: Write tests or update existing expectations**

Add expectations through widget/service tests that non-full platforms show a message and local operation buttons are disabled.

- [ ] **Step 2: Implement `remoteManager` capability**

Add `PlatformCapability.remoteManager`, `NetworkStatus.remoteManager(platformName)`, and a remote-management gateway class.

## Task 2: macOS Gateway

- [ ] **Step 1: Write macOS command and parser tests**

Cover route command generation, AppleScript wrapping, service name parsing, DNS parsing, and route presence parsing.

- [ ] **Step 2: Implement macOS commands and parsers**

Use `route -n add/delete`, `networksetup`, `dscacheutil`, `killall -HUP mDNSResponder`, and `route -n get default`.

- [ ] **Step 3: Implement macOS gateway**

Read status through route and networksetup commands, execute route/DNS operations through administrator AppleScript commands, and return clear messages.

## Task 3: Linux Gateway

- [ ] **Step 1: Write Linux command and parser tests**

Cover `pkexec sh -c` command generation, `ip route` route presence, default route interface/source parsing, and `resolvectl dns` parsing.

- [ ] **Step 2: Implement Linux commands and parsers**

Use `ip route replace/del`, `resolvectl dns/revert/flush-caches`, and `ip route get`.

- [ ] **Step 3: Implement Linux gateway**

Read status with `ip route` and `resolvectl`, apply local route/DNS with `pkexec`, and return a clear message when Linux desktop dependencies are missing.

## Task 4: UI and Verification

- [ ] **Step 1: Update dashboard/help text**

Show `SD-WAN Verge`, disable local buttons for remote-only surfaces, and explain that mobile/Web control should happen through OpenWrt/iStoreOS plugin integration.

- [ ] **Step 2: Run verification**

Run:

```bash
bash router/openwrt/tests/static_test.sh
flutter test
flutter analyze
git diff --check
```

Expected:

- Router plugin static test passes.
- Flutter tests pass.
- Analyzer passes.
- No whitespace errors.
