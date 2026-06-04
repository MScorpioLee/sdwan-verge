# macOS utun CPE Trial Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS-only helper and Flutter bridge that can be delivered for user-side true-machine trial of utun-to-CPE forwarding without changing this development machine's network during Codex verification.

**Architecture:** A root helper owns privileged work: utun creation, half-route add/delete, CPE host-route protection, BPF/NAT packet forwarding, health monitoring, and rollback. The Flutter macOS MethodChannel calls the helper through sudo/administrator execution for start/stop and unprivileged commands for status/health. Non-macOS platform shells stay untouched.

**Tech Stack:** C helper compiled with clang, macOS utun/BPF/socket APIs, Swift AppDelegate MethodChannel, Flutter/Dart tests, shell self-tests, macOS packaging scripts.

---

## Safety Boundary

- Codex must not run helper `start`, add `0.0.0.0/1`, add `128.0.0.0/1`, change DNS, change default gateway, or otherwise route traffic through utun on this machine.
- Codex may compile the helper, run helper `self-test`, run helper `plan`, run Flutter tests/analyze/build, and run read-only commands.
- True traffic verification is explicitly delegated to the user in an independent test environment.

## Files

- Create `macos/Helper/sdwan_macos_helper.c`
  - CLI helper with `plan`, `self-test`, `start`, `stop`, `rollback`, `status`, and `health`.
- Create `scripts/build_macos_helper.sh`
  - Compiles the helper into `build/macos/helper/sdwan-macos-helper`.
- Modify `scripts/package_releases.sh`
  - Builds and embeds the helper into `SD-WAN Verge.app/Contents/Resources/`.
- Modify `macos/Runner/AppDelegate.swift`
  - Calls the embedded helper for `sdwan_client/tun` MethodChannel methods.
- Create `test/macos_helper/helper_self_test.sh`
  - Builds helper, runs `self-test`, and asserts generated route commands without applying them.
- Create `docs/macos-tun-cpe-trial-guide.md`
  - User-side true-machine trial, observation, rollback, and emergency commands.

## Task 1: Helper Safety Tests

- [ ] Write `test/macos_helper/helper_self_test.sh`.
- [ ] Run it and verify it fails because helper/build script does not exist.
- [ ] Implement helper `self-test` covering checksum, NAT rewrite, Ethernet frame build, route-plan generation, and auto-rollback state transitions without touching the host network.
- [ ] Run `bash test/macos_helper/helper_self_test.sh`; expected PASS.

## Task 2: macOS Helper Core

- [ ] Implement `plan` command that prints the exact commands `start` would execute, including CPE host route and half routes, without executing them.
- [ ] Implement state files under `/var/run/sdwan-verge/` and `/var/log/sdwan-verge-helper.log`.
- [ ] Implement `start` to snapshot routes/DNS, create utun, configure point-to-point address, add CPE host route, add half routes, daemonize, and register signal/exit rollback.
- [ ] Implement BPF egress injection with CPE destination MAC and local interface source MAC.
- [ ] Implement NAT mapping and return-path BPF capture that rewrites replies back to the utun address.
- [ ] Implement L1 CPE ping and L3 TCP probe with three-failure auto rollback.
- [ ] Implement `stop` and `rollback` to delete half routes, delete CPE host route, bring utun down, and terminate daemon.

## Task 3: Flutter macOS Bridge

- [ ] Replace macOS `unsupported` channel response with helper-backed `status`, `healthCheck`, `start`, and `stop`.
- [ ] Start uses AppleScript administrator privileges to launch the embedded helper.
- [ ] Stop uses AppleScript administrator privileges to call helper rollback/stop.
- [ ] Status and health call helper without privilege and parse JSON-like key-value output.
- [ ] Other platform files remain unchanged.

## Task 4: Packaging and Non-Destructive Verification

- [ ] Run `bash scripts/build_macos_helper.sh`.
- [ ] Run `bash test/macos_helper/helper_self_test.sh`.
- [ ] Run `flutter test`.
- [ ] Run `flutter analyze`.
- [ ] Run `flutter build macos --release`.
- [ ] Run `bash scripts/package_releases.sh`.
- [ ] Do not run helper `start` on this machine.

## Task 5: User Trial Guide

- [ ] Document install/start/stop commands.
- [ ] Document success checks: `curl ifconfig.me`, `sudo tcpdump -i en0 host 192.168.1.140`, helper status, and UI status.
- [ ] Document auto-rollback trial procedure for independent test environment.
- [ ] Document emergency rollback:
  - `sudo route delete 0.0.0.0/1`
  - `sudo route delete 128.0.0.0/1`
  - `sudo route delete 192.168.1.140`
  - `sudo pkill -f sdwan-macos-helper`

