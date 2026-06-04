# Windows Wintun CPE Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a real Windows TUN path equivalent to the verified macOS CPE path.

**Architecture:** Keep Flutter as the manager and move privileged Windows networking into a helper/service. The service owns Wintun adapter lifecycle, packet NAT, WinDivert/WFP physical-interface injection, health checks, cleanup, and telemetry. Flutter talks to the service through the existing `sdwan_client/tun` channel via a small native client.

**Tech Stack:** Flutter desktop, Windows C++ service/helper, Wintun, WinDivert or WFP, Inno Setup, GitHub Actions Windows runner.

---

## File Structure

- Create `windows/helper/`
  - Windows helper/service source.
  - Owns Wintun/WinDivert data plane.
- Create `windows/helper/tests/`
  - Packet NAT, route planning, state serialization, and cleanup tests.
- Modify `windows/runner/flutter_window.cpp`
  - Replace stub status with helper IPC client calls.
- Modify `windows/runner/CMakeLists.txt`
  - Link runner IPC client only, not privileged data plane.
- Modify `.github/workflows/release.yml`
  - Build helper, build Flutter app, build Windows installer, upload Release assets.
- Modify `windows/installer/sdwan-verge.iss`
  - Install app, helper service, Wintun DLL, and WinDivert/WFP dependencies.

## Task 1: Helper State And IPC

- [ ] Define helper commands: `install`, `uninstall`, `start`, `stop`, `status`, `health`, `logs`, `connections`.
- [ ] Write unit tests for state JSON fields matching Dart `TunStatus`.
- [ ] Implement named-pipe or localhost IPC between runner and service.
- [ ] Make Flutter channel return helper status rather than hard-coded unsupported.

## Task 2: Wintun Lifecycle

- [ ] Vendor or download official `wintun.dll` during Windows build.
- [ ] Dynamically load `WintunCreateAdapter`, `WintunStartSession`, `WintunReceivePacket`, `WintunSendPacket`, and cleanup APIs.
- [ ] Create `SD-WAN Verge` adapter and assign `10.255.0.2/30`.
- [ ] Add `/1` routes to Wintun with cleanup guards.
- [ ] Add CPE `/32` route through the physical interface to prevent CPE loopback.

## Task 3: WinDivert/WFP Data Plane

- [ ] Port the macOS NAT table behavior to Windows packet helpers.
- [ ] Reserve a Windows NAT source-port range.
- [ ] Read outbound IPv4 packets from Wintun.
- [ ] SNAT packets to the physical interface IP and reserved source port.
- [ ] Inject NATed packets through WinDivert/WFP on the physical interface toward CPE.
- [ ] Capture return packets for the reserved port range before the Windows TCP/IP stack owns them.
- [ ] Reverse NAT and write packets back through Wintun.
- [ ] Drop captured return packets from the kernel path so Windows does not emit TCP RST.

## Task 4: Health, Telemetry, And Recovery

- [ ] Implement L1 CPE reachability.
- [ ] Implement L3 data-plane probe through the Wintun/WinDivert path.
- [ ] Auto-clean after 3 consecutive failures.
- [ ] Write traffic counters, per-connection rows, event logs, and last error.
- [ ] Ensure service crash cleanup removes Wintun routes and closes driver handles.

## Task 5: Installer And GitHub Actions

- [ ] Build helper on `windows-latest`.
- [ ] Build Flutter Windows app.
- [ ] Build Inno Setup `.exe` installer.
- [ ] Upload direct GitHub Release assets, including Windows `.exe`.
- [ ] Keep Actions artifact upload as secondary evidence.

## Task 6: Windows Manual Verification

- [ ] Install on a Windows machine on the same LAN as CPE `192.168.1.140`.
- [ ] Confirm one-time UAC for service install.
- [ ] Start acceleration.
- [ ] Confirm `SD-WAN Verge` Wintun adapter exists.
- [ ] Confirm `/1` routes point at Wintun and CPE `/32` points at physical interface.
- [ ] Use Wireshark/WinDivert logs to confirm packets leave physical interface toward CPE.
- [ ] Confirm browser traffic works and出口 IP matches the CPE path.
- [ ] Make CPE unreachable and confirm automatic rollback.
