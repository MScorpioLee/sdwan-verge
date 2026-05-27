# SD-WAN Flutter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Flutter multi-platform SD-WAN client that replaces the current Windows BAT workflow on Windows first, while keeping macOS, Web, iOS, and Android usable with platform-limited messaging.

**Architecture:** Flutter owns UI, local configuration, logs, and operation orchestration. Platform-specific network changes are isolated behind a `NetworkPlatformGateway` interface, with a real Windows implementation and safe unsupported-platform implementations elsewhere.

**Tech Stack:** Flutter stable, Dart, Material 3, `shared_preferences` for cross-platform local config, Dart `Process` for Windows command execution through a testable command runner.

---

## Scope Check

The approved spec spans UI, local config, Windows system commands, unsupported platform messaging, tests, and docs. These are related pieces of one app and can be implemented in one plan because each task produces working, testable software:

- Tasks 1-3 create the project, domain model, and local config.
- Tasks 4-6 implement the platform gateway contract, Windows command generation/parsing, and gateway behavior.
- Tasks 7-9 build the application service and Flutter UI.
- Tasks 10-11 add docs, build checks, and Windows handoff notes.

## File Structure

Create or modify these files:

- `pubspec.yaml`  
  Flutter metadata and dependencies. Add `shared_preferences`.

- `lib/main.dart`  
  App bootstrap, Material 3 theme, dependency construction, and top-level widget.

- `lib/domain/sdwan_profile.dart`  
  User-editable profile model with default company, CPE, DNS, and sync toggle.

- `lib/domain/app_config.dart`  
  Config root with `activeProfileId` and a profiles list.

- `lib/domain/network_status.dart`  
  Current platform, admin, acceleration route, active interface, and DNS state.

- `lib/domain/operation_log.dart`  
  In-memory log record model for user-visible execution history.

- `lib/domain/validation.dart`  
  IPv4 and profile validation helpers.

- `lib/platform/command_runner.dart`  
  Testable abstraction over `Process.run`.

- `lib/platform/network_platform_gateway.dart`  
  Gateway interface and result types used by application code.

- `lib/platform/network_gateway.dart`  
  Conditional export for web versus IO implementations.

- `lib/platform/network_gateway_stub.dart`  
  Safe web implementation that reports unsupported platform capability.

- `lib/platform/network_gateway_io.dart`  
  IO factory selecting Windows implementation or unsupported IO implementation.

- `lib/platform/windows/windows_commands.dart`  
  Pure command builders for `route`, `netsh`, `ipconfig`, admin checks, and UAC relaunch.

- `lib/platform/windows/windows_parsers.dart`  
  Pure parsers for `route print`, `netsh interface ip show config`, and DNS output.

- `lib/platform/windows/windows_network_gateway.dart`  
  Windows implementation of status reads and route/DNS operations using `CommandRunner`.

- `lib/services/config_repository.dart`  
  `shared_preferences` storage for `AppConfig`.

- `lib/services/sdwan_controller.dart`  
  App service that loads config/status, runs gateway operations, validates inputs, and records logs.

- `lib/ui/app_shell.dart`  
  Main responsive shell with Dashboard, Settings, Logs, and Help destinations.

- `lib/ui/dashboard_page.dart`  
  Status cards, operation buttons, and profile summary.

- `lib/ui/settings_page.dart`  
  Editable company/CPE/DNS/sync settings with validation.

- `lib/ui/logs_page.dart`  
  User-visible operation logs and copy button.

- `lib/ui/help_page.dart`  
  Permission, platform support, DNS sync, and troubleshooting copy.

- `test/domain/validation_test.dart`  
  IPv4/profile validation tests.

- `test/domain/config_model_test.dart`  
  Config serialization and default profile tests.

- `test/platform/windows_commands_test.dart`  
  Windows command builder tests.

- `test/platform/windows_parsers_test.dart`  
  Windows parser tests.

- `test/services/sdwan_controller_test.dart`  
  Controller orchestration tests with fake gateway and fake repository.

- `test/widget/app_shell_test.dart`  
  Dashboard/settings/logs widget smoke tests.

- `docs/windows-manual-acceptance.md`  
  Windows manual verification checklist.

## Task 1: Scaffold Flutter Project

**Files:**
- Create: Flutter-generated project files in `/Users/leslielsb/Desktop/sdwan软件`
- Modify: `pubspec.yaml`
- Test: scaffold `test/widget_test.dart`, then replace it with focused tests in Task 8

- [ ] **Step 1: Scaffold the project**

Run:

```bash
flutter create --project-name sdwan_client --platforms=windows,macos,linux,web,ios,android .
```

Expected: Flutter creates `lib/`, `test/`, platform folders, `pubspec.yaml`, and reports project creation success. If Flutter warns about existing files, inspect the file list and keep the existing `docs/`, `.gitignore`, and BAT script intact.

- [ ] **Step 2: Add config storage dependency**

Run:

```bash
flutter pub add shared_preferences
```

Expected: `pubspec.yaml` and `pubspec.lock` include `shared_preferences`.

- [ ] **Step 3: Run baseline tests**

Run:

```bash
flutter test
```

Expected: the scaffold widget test passes.

- [ ] **Step 4: Commit scaffold**

Run:

```bash
git add pubspec.yaml pubspec.lock lib test android ios macos web windows linux .metadata analysis_options.yaml README.md
git commit -m "chore: scaffold flutter sdwan client"
```

Expected: commit succeeds. Do not add the original BAT script unless the user explicitly asks to track it.

## Task 2: Add Domain Models and Validation

**Files:**
- Create: `lib/domain/sdwan_profile.dart`
- Create: `lib/domain/app_config.dart`
- Create: `lib/domain/network_status.dart`
- Create: `lib/domain/operation_log.dart`
- Create: `lib/domain/validation.dart`
- Create: `test/domain/validation_test.dart`
- Create: `test/domain/config_model_test.dart`

- [ ] **Step 1: Write failing validation tests**

Create `test/domain/validation_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/domain/sdwan_profile.dart';
import 'package:sdwan_client/domain/validation.dart';

void main() {
  test('accepts valid IPv4 addresses', () {
    expect(isValidIpv4('192.168.1.140'), isTrue);
    expect(isValidIpv4('223.5.5.5'), isTrue);
    expect(isValidIpv4('114.114.114.114'), isTrue);
  });

  test('rejects invalid IPv4 addresses', () {
    expect(isValidIpv4(''), isFalse);
    expect(isValidIpv4('192.168.1'), isFalse);
    expect(isValidIpv4('192.168.1.999'), isFalse);
    expect(isValidIpv4('abc.def.1.1'), isFalse);
    expect(isValidIpv4('192.168.1.-1'), isFalse);
  });

  test('validates profile fields with Chinese messages', () {
    final profile = SdwanProfile.defaults().copyWith(cpeIp: 'bad');

    final errors = validateProfile(profile);

    expect(errors, contains('CPE 网关地址格式不正确'));
  });

  test('valid default profile has no validation errors', () {
    expect(validateProfile(SdwanProfile.defaults()), isEmpty);
  });
}
```

- [ ] **Step 2: Write failing config model tests**

Create `test/domain/config_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/domain/app_config.dart';
import 'package:sdwan_client/domain/sdwan_profile.dart';

void main() {
  test('default config uses BAT defaults and one active profile', () {
    final config = AppConfig.defaults();
    final active = config.activeProfile;

    expect(config.activeProfileId, 'default');
    expect(config.profiles, hasLength(1));
    expect(active.companyName, '宁波市富金园艺灌溉设备有限公司');
    expect(active.cpeIp, '192.168.1.140');
    expect(active.primaryDns, '223.5.5.5');
    expect(active.secondaryDns, '114.114.114.114');
    expect(active.syncDnsWithAcceleration, isFalse);
  });

  test('serializes and deserializes app config', () {
    final config = AppConfig.defaults().copyWith(
      profiles: [
        SdwanProfile.defaults().copyWith(
          cpeIp: '10.0.0.1',
          syncDnsWithAcceleration: true,
        ),
      ],
    );

    final restored = AppConfig.fromJson(config.toJson());

    expect(restored.activeProfile.cpeIp, '10.0.0.1');
    expect(restored.activeProfile.syncDnsWithAcceleration, isTrue);
  });
}
```

- [ ] **Step 3: Run tests and verify they fail**

Run:

```bash
flutter test test/domain/validation_test.dart test/domain/config_model_test.dart
```

Expected: FAIL with missing imports or missing model functions.

- [ ] **Step 4: Implement profile model**

Create `lib/domain/sdwan_profile.dart`:

```dart
class SdwanProfile {
  const SdwanProfile({
    required this.id,
    required this.name,
    required this.companyName,
    required this.cpeIp,
    required this.primaryDns,
    required this.secondaryDns,
    required this.syncDnsWithAcceleration,
  });

  factory SdwanProfile.defaults() => const SdwanProfile(
        id: 'default',
        name: '默认加速配置',
        companyName: '宁波市富金园艺灌溉设备有限公司',
        cpeIp: '192.168.1.140',
        primaryDns: '223.5.5.5',
        secondaryDns: '114.114.114.114',
        syncDnsWithAcceleration: false,
      );

  factory SdwanProfile.fromJson(Map<String, Object?> json) => SdwanProfile(
        id: json['id'] as String? ?? 'default',
        name: json['name'] as String? ?? '默认加速配置',
        companyName:
            json['companyName'] as String? ?? '宁波市富金园艺灌溉设备有限公司',
        cpeIp: json['cpeIp'] as String? ?? '192.168.1.140',
        primaryDns: json['primaryDns'] as String? ?? '223.5.5.5',
        secondaryDns: json['secondaryDns'] as String? ?? '114.114.114.114',
        syncDnsWithAcceleration:
            json['syncDnsWithAcceleration'] as bool? ?? false,
      );

  final String id;
  final String name;
  final String companyName;
  final String cpeIp;
  final String primaryDns;
  final String secondaryDns;
  final bool syncDnsWithAcceleration;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'companyName': companyName,
        'cpeIp': cpeIp,
        'primaryDns': primaryDns,
        'secondaryDns': secondaryDns,
        'syncDnsWithAcceleration': syncDnsWithAcceleration,
      };

  SdwanProfile copyWith({
    String? id,
    String? name,
    String? companyName,
    String? cpeIp,
    String? primaryDns,
    String? secondaryDns,
    bool? syncDnsWithAcceleration,
  }) {
    return SdwanProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      companyName: companyName ?? this.companyName,
      cpeIp: cpeIp ?? this.cpeIp,
      primaryDns: primaryDns ?? this.primaryDns,
      secondaryDns: secondaryDns ?? this.secondaryDns,
      syncDnsWithAcceleration:
          syncDnsWithAcceleration ?? this.syncDnsWithAcceleration,
    );
  }
}
```

- [ ] **Step 5: Implement config model**

Create `lib/domain/app_config.dart`:

```dart
import 'sdwan_profile.dart';

class AppConfig {
  const AppConfig({
    required this.activeProfileId,
    required this.profiles,
  });

  factory AppConfig.defaults() => AppConfig(
        activeProfileId: 'default',
        profiles: [SdwanProfile.defaults()],
      );

  factory AppConfig.fromJson(Map<String, Object?> json) {
    final profilesJson = json['profiles'];
    final profiles = profilesJson is List
        ? profilesJson
            .whereType<Map>()
            .map((item) => SdwanProfile.fromJson(Map<String, Object?>.from(item)))
            .toList()
        : <SdwanProfile>[];

    final resolvedProfiles =
        profiles.isEmpty ? [SdwanProfile.defaults()] : profiles;
    final requestedActive = json['activeProfileId'] as String? ?? 'default';
    final hasActive =
        resolvedProfiles.any((profile) => profile.id == requestedActive);

    return AppConfig(
      activeProfileId: hasActive ? requestedActive : resolvedProfiles.first.id,
      profiles: resolvedProfiles,
    );
  }

  final String activeProfileId;
  final List<SdwanProfile> profiles;

  SdwanProfile get activeProfile => profiles.firstWhere(
        (profile) => profile.id == activeProfileId,
        orElse: () => profiles.first,
      );

  Map<String, Object?> toJson() => {
        'activeProfileId': activeProfileId,
        'profiles': profiles.map((profile) => profile.toJson()).toList(),
      };

  AppConfig copyWith({
    String? activeProfileId,
    List<SdwanProfile>? profiles,
  }) {
    return AppConfig(
      activeProfileId: activeProfileId ?? this.activeProfileId,
      profiles: profiles ?? this.profiles,
    );
  }
}
```

- [ ] **Step 6: Implement status and log models**

Create `lib/domain/network_status.dart`:

```dart
enum PlatformCapability { full, unsupported }

enum DnsMode { dhcp, static, unknown }

class NetworkStatus {
  const NetworkStatus({
    required this.platformName,
    required this.capability,
    required this.isAdmin,
    required this.accelerationEnabled,
    this.activeInterfaceName,
    this.activeInterfaceIp,
    this.dnsMode = DnsMode.unknown,
    this.dnsServers = const [],
    this.message,
  });

  factory NetworkStatus.unsupported(String platformName) => NetworkStatus(
        platformName: platformName,
        capability: PlatformCapability.unsupported,
        isAdmin: false,
        accelerationEnabled: false,
        message: '$platformName 暂不支持直接修改系统路由和 DNS',
      );

  final String platformName;
  final PlatformCapability capability;
  final bool isAdmin;
  final bool accelerationEnabled;
  final String? activeInterfaceName;
  final String? activeInterfaceIp;
  final DnsMode dnsMode;
  final List<String> dnsServers;
  final String? message;

  NetworkStatus copyWith({
    String? platformName,
    PlatformCapability? capability,
    bool? isAdmin,
    bool? accelerationEnabled,
    String? activeInterfaceName,
    String? activeInterfaceIp,
    DnsMode? dnsMode,
    List<String>? dnsServers,
    String? message,
  }) {
    return NetworkStatus(
      platformName: platformName ?? this.platformName,
      capability: capability ?? this.capability,
      isAdmin: isAdmin ?? this.isAdmin,
      accelerationEnabled: accelerationEnabled ?? this.accelerationEnabled,
      activeInterfaceName: activeInterfaceName ?? this.activeInterfaceName,
      activeInterfaceIp: activeInterfaceIp ?? this.activeInterfaceIp,
      dnsMode: dnsMode ?? this.dnsMode,
      dnsServers: dnsServers ?? this.dnsServers,
      message: message ?? this.message,
    );
  }
}
```

Create `lib/domain/operation_log.dart`:

```dart
class OperationLog {
  const OperationLog({
    required this.timestamp,
    required this.action,
    required this.message,
    required this.success,
    this.command,
    this.exitCode,
  });

  final DateTime timestamp;
  final String action;
  final String message;
  final bool success;
  final String? command;
  final int? exitCode;

  String get displayTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
```

- [ ] **Step 7: Implement validation helpers**

Create `lib/domain/validation.dart`:

```dart
import 'sdwan_profile.dart';

bool isValidIpv4(String value) {
  final parts = value.trim().split('.');
  if (parts.length != 4) {
    return false;
  }
  for (final part in parts) {
    if (part.isEmpty || !RegExp(r'^\d+$').hasMatch(part)) {
      return false;
    }
    final number = int.tryParse(part);
    if (number == null || number < 0 || number > 255) {
      return false;
    }
  }
  return true;
}

List<String> validateProfile(SdwanProfile profile) {
  final errors = <String>[];
  if (profile.companyName.trim().isEmpty) {
    errors.add('公司名称不能为空');
  }
  if (!isValidIpv4(profile.cpeIp)) {
    errors.add('CPE 网关地址格式不正确');
  }
  if (!isValidIpv4(profile.primaryDns)) {
    errors.add('主 DNS 地址格式不正确');
  }
  if (!isValidIpv4(profile.secondaryDns)) {
    errors.add('备用 DNS 地址格式不正确');
  }
  return errors;
}
```

- [ ] **Step 8: Run domain tests**

Run:

```bash
flutter test test/domain/validation_test.dart test/domain/config_model_test.dart
```

Expected: all domain tests pass.

- [ ] **Step 9: Commit domain models**

Run:

```bash
git add lib/domain test/domain
git commit -m "feat: add sdwan domain models"
```

Expected: commit succeeds.

## Task 3: Add Local Config Repository

**Files:**
- Create: `lib/services/config_repository.dart`
- Create: `test/services/config_repository_test.dart`

- [ ] **Step 1: Write failing repository tests**

Create `test/services/config_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sdwan_client/domain/app_config.dart';
import 'package:sdwan_client/services/config_repository.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('returns default config when storage is empty', () async {
    final repository = ConfigRepository();

    final config = await repository.load();

    expect(config.activeProfile.cpeIp, '192.168.1.140');
  });

  test('saves and loads config JSON', () async {
    final repository = ConfigRepository();
    final config = AppConfig.defaults().copyWith(
      profiles: [AppConfig.defaults().activeProfile.copyWith(cpeIp: '10.1.1.1')],
    );

    await repository.save(config);
    final loaded = await repository.load();

    expect(loaded.activeProfile.cpeIp, '10.1.1.1');
  });

  test('falls back to defaults when stored JSON is corrupted', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(ConfigRepository.storageKey, '{bad-json');
    final repository = ConfigRepository();

    final loaded = await repository.load();

    expect(loaded.activeProfile.cpeIp, '192.168.1.140');
  });
}
```

- [ ] **Step 2: Run repository tests and verify failure**

Run:

```bash
flutter test test/services/config_repository_test.dart
```

Expected: FAIL because `ConfigRepository` does not exist.

- [ ] **Step 3: Implement repository**

Create `lib/services/config_repository.dart`:

```dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/app_config.dart';

class ConfigRepository {
  static const storageKey = 'sdwan_client_config_v1';

  Future<AppConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) {
      return AppConfig.defaults();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        return AppConfig.fromJson(decoded);
      }
      if (decoded is Map) {
        return AppConfig.fromJson(Map<String, Object?>.from(decoded));
      }
    } catch (_) {
      return AppConfig.defaults();
    }
    return AppConfig.defaults();
  }

  Future<void> save(AppConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(config.toJson()));
  }
}
```

- [ ] **Step 4: Run repository tests**

Run:

```bash
flutter test test/services/config_repository_test.dart
```

Expected: all repository tests pass.

- [ ] **Step 5: Commit repository**

Run:

```bash
git add lib/services/config_repository.dart test/services/config_repository_test.dart pubspec.yaml pubspec.lock
git commit -m "feat: persist sdwan configuration"
```

Expected: commit succeeds.

## Task 4: Add Platform Gateway Contract and Windows Command Builders

**Files:**
- Create: `lib/platform/command_runner.dart`
- Create: `lib/platform/network_platform_gateway.dart`
- Create: `lib/platform/windows/windows_commands.dart`
- Create: `test/platform/windows_commands_test.dart`

- [ ] **Step 1: Write failing Windows command tests**

Create `test/platform/windows_commands_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/domain/sdwan_profile.dart';
import 'package:sdwan_client/platform/windows/windows_commands.dart';

void main() {
  final profile = SdwanProfile.defaults();

  test('builds route add commands from profile CPE', () {
    final commands = WindowsCommands.enableAcceleration(profile);

    expect(commands, [
      const WindowsCommand('route', ['add', '0.0.0.0/1', '192.168.1.140', '-p']),
      const WindowsCommand('route', ['add', '128.0.0.0/1', '192.168.1.140', '-p']),
      const WindowsCommand('ipconfig', ['/flushdns']),
    ]);
  });

  test('builds route delete commands', () {
    final commands = WindowsCommands.disableAcceleration();

    expect(commands, [
      const WindowsCommand('route', ['delete', '0.0.0.0/1']),
      const WindowsCommand('route', ['delete', '128.0.0.0/1']),
      const WindowsCommand('ipconfig', ['/flushdns']),
    ]);
  });

  test('builds static DNS commands', () {
    final commands = WindowsCommands.setDns('Ethernet', profile);

    expect(commands, [
      const WindowsCommand('netsh', [
        'interface',
        'ip',
        'set',
        'dnsserver',
        'Ethernet',
        'static',
        '223.5.5.5',
        'primary',
      ]),
      const WindowsCommand('netsh', [
        'interface',
        'ip',
        'add',
        'dnsserver',
        'Ethernet',
        '114.114.114.114',
        'index=2',
      ]),
      const WindowsCommand('ipconfig', ['/flushdns']),
    ]);
  });

  test('builds restore DNS command', () {
    expect(WindowsCommands.restoreDns('Ethernet'), [
      const WindowsCommand('netsh', [
        'interface',
        'ip',
        'set',
        'dnsserver',
        'Ethernet',
        'dhcp',
      ]),
      const WindowsCommand('ipconfig', ['/flushdns']),
    ]);
  });

  test('formats command for logs', () {
    const command = WindowsCommand('route', ['delete', '0.0.0.0/1']);

    expect(command.display, 'route delete 0.0.0.0/1');
  });
}
```

- [ ] **Step 2: Run command tests and verify failure**

Run:

```bash
flutter test test/platform/windows_commands_test.dart
```

Expected: FAIL because command classes do not exist.

- [ ] **Step 3: Implement command runner contract**

Create `lib/platform/command_runner.dart`:

```dart
import 'dart:io';

class CommandResult {
  const CommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get succeeded => exitCode == 0;
}

abstract class CommandRunner {
  Future<CommandResult> run(String executable, List<String> arguments);
}

class ProcessCommandRunner implements CommandRunner {
  @override
  Future<CommandResult> run(String executable, List<String> arguments) async {
    final result = await Process.run(executable, arguments, runInShell: true);
    return CommandResult(
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
  }
}
```

- [ ] **Step 4: Implement gateway contract**

Create `lib/platform/network_platform_gateway.dart`:

```dart
import '../domain/network_status.dart';
import '../domain/sdwan_profile.dart';

class GatewayOperationResult {
  const GatewayOperationResult({
    required this.success,
    required this.message,
    this.command,
    this.exitCode,
  });

  final bool success;
  final String message;
  final String? command;
  final int? exitCode;
}

abstract class NetworkPlatformGateway {
  Future<NetworkStatus> readStatus(SdwanProfile profile);

  Future<GatewayOperationResult> ensureAdminOrRelaunch();

  Future<GatewayOperationResult> enableAcceleration(SdwanProfile profile);

  Future<GatewayOperationResult> disableAcceleration(SdwanProfile profile);

  Future<GatewayOperationResult> setDns(SdwanProfile profile);

  Future<GatewayOperationResult> restoreDns();
}
```

- [ ] **Step 5: Implement Windows command builders**

Create `lib/platform/windows/windows_commands.dart`:

```dart
import '../../domain/sdwan_profile.dart';

class WindowsCommand {
  const WindowsCommand(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;

  String get display => [executable, ...arguments].join(' ');

  @override
  bool operator ==(Object other) {
    return other is WindowsCommand &&
        other.executable == executable &&
        _listEquals(other.arguments, arguments);
  }

  @override
  int get hashCode => Object.hash(executable, Object.hashAll(arguments));

  @override
  String toString() => display;
}

class WindowsCommands {
  static WindowsCommand adminCheck() => const WindowsCommand('net', ['session']);

  static WindowsCommand routePrint() => const WindowsCommand('route', ['print', '-4']);

  static WindowsCommand netshConfig() => const WindowsCommand(
        'netsh',
        ['interface', 'ip', 'show', 'config'],
      );

  static WindowsCommand dnsServers(String interfaceName) => WindowsCommand(
        'netsh',
        ['interface', 'ip', 'show', 'dnsservers', interfaceName],
      );

  static List<WindowsCommand> enableAcceleration(SdwanProfile profile) => [
        WindowsCommand('route', ['add', '0.0.0.0/1', profile.cpeIp, '-p']),
        WindowsCommand('route', ['add', '128.0.0.0/1', profile.cpeIp, '-p']),
        const WindowsCommand('ipconfig', ['/flushdns']),
      ];

  static List<WindowsCommand> disableAcceleration() => const [
        WindowsCommand('route', ['delete', '0.0.0.0/1']),
        WindowsCommand('route', ['delete', '128.0.0.0/1']),
        WindowsCommand('ipconfig', ['/flushdns']),
      ];

  static List<WindowsCommand> setDns(
    String interfaceName,
    SdwanProfile profile,
  ) =>
      [
        WindowsCommand('netsh', [
          'interface',
          'ip',
          'set',
          'dnsserver',
          interfaceName,
          'static',
          profile.primaryDns,
          'primary',
        ]),
        WindowsCommand('netsh', [
          'interface',
          'ip',
          'add',
          'dnsserver',
          interfaceName,
          profile.secondaryDns,
          'index=2',
        ]),
        const WindowsCommand('ipconfig', ['/flushdns']),
      ];

  static List<WindowsCommand> restoreDns(String interfaceName) => [
        WindowsCommand('netsh', [
          'interface',
          'ip',
          'set',
          'dnsserver',
          interfaceName,
          'dhcp',
        ]),
        const WindowsCommand('ipconfig', ['/flushdns']),
      ];
}

bool _listEquals(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) {
      return false;
    }
  }
  return true;
}
```

- [ ] **Step 6: Run command tests**

Run:

```bash
flutter test test/platform/windows_commands_test.dart
```

Expected: all command tests pass.

- [ ] **Step 7: Commit gateway contract and commands**

Run:

```bash
git add lib/platform test/platform/windows_commands_test.dart
git commit -m "feat: add network gateway contract"
```

Expected: commit succeeds.

## Task 5: Add Windows Parsers

**Files:**
- Create: `lib/platform/windows/windows_parsers.dart`
- Create: `test/platform/windows_parsers_test.dart`

- [ ] **Step 1: Write failing parser tests**

Create `test/platform/windows_parsers_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/domain/network_status.dart';
import 'package:sdwan_client/platform/windows/windows_parsers.dart';

void main() {
  const routePrint = '''
IPv4 Route Table
===========================================================================
Active Routes:
Network Destination        Netmask          Gateway       Interface  Metric
          0.0.0.0          0.0.0.0    192.168.1.1   192.168.1.88     25
          0.0.0.0        128.0.0.0  192.168.1.140   192.168.1.88     26
        128.0.0.0        128.0.0.0  192.168.1.140   192.168.1.88     26
''';

  const netshConfig = '''
Configuration for interface "Ethernet"
    DHCP enabled:                         Yes
    IP Address:                           192.168.1.88

Configuration for interface "Wi-Fi"
    DHCP enabled:                         Yes
    IP Address:                           10.0.0.12
''';

  test('finds active interface IP from default route', () {
    expect(WindowsParsers.defaultRouteInterfaceIp(routePrint), '192.168.1.88');
  });

  test('detects acceleration routes for profile CPE', () {
    expect(WindowsParsers.hasAccelerationRoutes(routePrint, '192.168.1.140'), isTrue);
    expect(WindowsParsers.hasAccelerationRoutes(routePrint, '192.168.1.200'), isFalse);
  });

  test('finds interface name by IP from netsh config', () {
    expect(WindowsParsers.interfaceNameForIp(netshConfig, '192.168.1.88'), 'Ethernet');
  });

  test('parses DHCP DNS mode', () {
    const output = '''
Configuration for interface "Ethernet"
    DNS servers configured through DHCP:  192.168.1.1
''';

    final parsed = WindowsParsers.dnsInfo(output);

    expect(parsed.mode, DnsMode.dhcp);
    expect(parsed.servers, ['192.168.1.1']);
  });

  test('parses static DNS servers', () {
    const output = '''
Configuration for interface "Ethernet"
    Statically Configured DNS Servers:    223.5.5.5
                                           114.114.114.114
''';

    final parsed = WindowsParsers.dnsInfo(output);

    expect(parsed.mode, DnsMode.static);
    expect(parsed.servers, ['223.5.5.5', '114.114.114.114']);
  });
}
```

- [ ] **Step 2: Run parser tests and verify failure**

Run:

```bash
flutter test test/platform/windows_parsers_test.dart
```

Expected: FAIL because `WindowsParsers` does not exist.

- [ ] **Step 3: Implement parsers**

Create `lib/platform/windows/windows_parsers.dart`:

```dart
import '../../domain/network_status.dart';

class ParsedDnsInfo {
  const ParsedDnsInfo({
    required this.mode,
    required this.servers,
  });

  final DnsMode mode;
  final List<String> servers;
}

class WindowsParsers {
  static String? defaultRouteInterfaceIp(String routePrint) {
    for (final line in routePrint.split('\n')) {
      final columns = _columns(line);
      if (columns.length >= 5 && columns[0] == '0.0.0.0' && columns[1] == '0.0.0.0') {
        return columns[3];
      }
    }
    return null;
  }

  static bool hasAccelerationRoutes(String routePrint, String cpeIp) {
    var hasLowerHalf = false;
    var hasUpperHalf = false;
    for (final line in routePrint.split('\n')) {
      final columns = _columns(line);
      if (columns.length < 4) {
        continue;
      }
      final destination = columns[0];
      final netmask = columns[1];
      final gateway = columns[2];
      if (gateway != cpeIp || netmask != '128.0.0.0') {
        continue;
      }
      if (destination == '0.0.0.0') {
        hasLowerHalf = true;
      }
      if (destination == '128.0.0.0') {
        hasUpperHalf = true;
      }
    }
    return hasLowerHalf && hasUpperHalf;
  }

  static String? interfaceNameForIp(String netshConfig, String ip) {
    String? currentInterface;
    for (final rawLine in netshConfig.split('\n')) {
      final line = rawLine.trim();
      final match = RegExp(r'^Configuration for interface "?(.+?)"?$').firstMatch(line);
      if (match != null) {
        currentInterface = match.group(1);
        continue;
      }
      if (currentInterface != null && line.contains('IP Address:')) {
        final value = line.split(':').last.trim();
        if (value == ip) {
          return currentInterface;
        }
      }
      if (line.isEmpty) {
        currentInterface = null;
      }
    }
    return null;
  }

  static ParsedDnsInfo dnsInfo(String output) {
    final servers = <String>[];
    var mode = DnsMode.unknown;
    final ipPattern = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b');

    for (final rawLine in output.split('\n')) {
      final line = rawLine.trim();
      if (line.contains('DHCP')) {
        mode = DnsMode.dhcp;
      }
      if (line.contains('Statically Configured DNS Servers')) {
        mode = DnsMode.static;
      }
      for (final match in ipPattern.allMatches(line)) {
        servers.add(match.group(0)!);
      }
    }

    return ParsedDnsInfo(mode: mode, servers: servers);
  }

  static List<String> _columns(String line) {
    return line.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
  }
}
```

- [ ] **Step 4: Run parser tests**

Run:

```bash
flutter test test/platform/windows_parsers_test.dart
```

Expected: all parser tests pass.

- [ ] **Step 5: Commit parsers**

Run:

```bash
git add lib/platform/windows/windows_parsers.dart test/platform/windows_parsers_test.dart
git commit -m "feat: parse windows network status"
```

Expected: commit succeeds.

## Task 6: Implement Platform Gateways

**Files:**
- Create: `lib/platform/network_gateway.dart`
- Create: `lib/platform/network_gateway_stub.dart`
- Create: `lib/platform/network_gateway_io.dart`
- Create: `lib/platform/windows/windows_network_gateway.dart`
- Create: `test/platform/windows_network_gateway_test.dart`

- [ ] **Step 1: Write failing Windows gateway tests**

Create `test/platform/windows_network_gateway_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/domain/network_status.dart';
import 'package:sdwan_client/domain/sdwan_profile.dart';
import 'package:sdwan_client/platform/command_runner.dart';
import 'package:sdwan_client/platform/windows/windows_network_gateway.dart';

class FakeCommandRunner implements CommandRunner {
  final calls = <String>[];
  final Map<String, CommandResult> responses = {};

  @override
  Future<CommandResult> run(String executable, List<String> arguments) async {
    final key = [executable, ...arguments].join(' ');
    calls.add(key);
    return responses[key] ?? const CommandResult(exitCode: 0, stdout: '', stderr: '');
  }
}

void main() {
  test('enable acceleration runs route commands and flushes DNS', () async {
    final runner = FakeCommandRunner();
    final gateway = WindowsNetworkGateway(runner: runner);

    final result = await gateway.enableAcceleration(SdwanProfile.defaults());

    expect(result.success, isTrue);
    expect(runner.calls, [
      'route add 0.0.0.0/1 192.168.1.140 -p',
      'route add 128.0.0.0/1 192.168.1.140 -p',
      'ipconfig /flushdns',
    ]);
  });

  test('stops command sequence on failure', () async {
    final runner = FakeCommandRunner();
    runner.responses['route add 0.0.0.0/1 192.168.1.140 -p'] =
        const CommandResult(exitCode: 1, stdout: '', stderr: 'failed');
    final gateway = WindowsNetworkGateway(runner: runner);

    final result = await gateway.enableAcceleration(SdwanProfile.defaults());

    expect(result.success, isFalse);
    expect(result.command, 'route add 0.0.0.0/1 192.168.1.140 -p');
    expect(runner.calls, ['route add 0.0.0.0/1 192.168.1.140 -p']);
  });

  test('readStatus combines route, interface, and DNS output', () async {
    final runner = FakeCommandRunner();
    runner.responses['net session'] =
        const CommandResult(exitCode: 0, stdout: '', stderr: '');
    runner.responses['route print -4'] = const CommandResult(
      exitCode: 0,
      stderr: '',
      stdout: '''
Network Destination        Netmask          Gateway       Interface  Metric
          0.0.0.0          0.0.0.0    192.168.1.1   192.168.1.88     25
          0.0.0.0        128.0.0.0  192.168.1.140   192.168.1.88     26
        128.0.0.0        128.0.0.0  192.168.1.140   192.168.1.88     26
''',
    );
    runner.responses['netsh interface ip show config'] = const CommandResult(
      exitCode: 0,
      stderr: '',
      stdout: '''
Configuration for interface "Ethernet"
    IP Address:                           192.168.1.88
''',
    );
    runner.responses['netsh interface ip show dnsservers Ethernet'] =
        const CommandResult(
      exitCode: 0,
      stderr: '',
      stdout: '''
Configuration for interface "Ethernet"
    Statically Configured DNS Servers:    223.5.5.5
                                           114.114.114.114
''',
    );
    final gateway = WindowsNetworkGateway(runner: runner);

    final status = await gateway.readStatus(SdwanProfile.defaults());

    expect(status.platformName, 'Windows');
    expect(status.capability, PlatformCapability.full);
    expect(status.isAdmin, isTrue);
    expect(status.accelerationEnabled, isTrue);
    expect(status.activeInterfaceName, 'Ethernet');
    expect(status.activeInterfaceIp, '192.168.1.88');
    expect(status.dnsMode, DnsMode.static);
    expect(status.dnsServers, ['223.5.5.5', '114.114.114.114']);
  });
}
```

- [ ] **Step 2: Run gateway tests and verify failure**

Run:

```bash
flutter test test/platform/windows_network_gateway_test.dart
```

Expected: FAIL because gateway implementation files do not exist.

- [ ] **Step 3: Add conditional gateway factory files**

Create `lib/platform/network_gateway.dart`:

```dart
export 'network_gateway_stub.dart'
    if (dart.library.io) 'network_gateway_io.dart';
```

Create `lib/platform/network_gateway_stub.dart`:

```dart
import '../domain/network_status.dart';
import '../domain/sdwan_profile.dart';
import 'network_platform_gateway.dart';

NetworkPlatformGateway createNetworkPlatformGateway() => UnsupportedNetworkGateway('Web');

class UnsupportedNetworkGateway implements NetworkPlatformGateway {
  UnsupportedNetworkGateway(this.platformName);

  final String platformName;

  @override
  Future<NetworkStatus> readStatus(SdwanProfile profile) async {
    return NetworkStatus.unsupported(platformName);
  }

  @override
  Future<GatewayOperationResult> ensureAdminOrRelaunch() async {
    return GatewayOperationResult(
      success: false,
      message: '$platformName 暂不支持管理员提权',
    );
  }

  @override
  Future<GatewayOperationResult> enableAcceleration(SdwanProfile profile) async {
    return _unsupported('开启加速');
  }

  @override
  Future<GatewayOperationResult> disableAcceleration(SdwanProfile profile) async {
    return _unsupported('关闭加速');
  }

  @override
  Future<GatewayOperationResult> setDns(SdwanProfile profile) async {
    return _unsupported('设置 DNS');
  }

  @override
  Future<GatewayOperationResult> restoreDns() async {
    return _unsupported('恢复 DNS');
  }

  GatewayOperationResult _unsupported(String action) => GatewayOperationResult(
        success: false,
        message: '$platformName 暂不支持$action，请使用 Windows 客户端',
      );
}
```

Create `lib/platform/network_gateway_io.dart`:

```dart
import 'dart:io';

import 'command_runner.dart';
import 'network_gateway_stub.dart';
import 'network_platform_gateway.dart';
import 'windows/windows_network_gateway.dart';

NetworkPlatformGateway createNetworkPlatformGateway() {
  if (Platform.isWindows) {
    return WindowsNetworkGateway(runner: ProcessCommandRunner());
  }
  if (Platform.isMacOS) {
    return UnsupportedNetworkGateway('macOS');
  }
  if (Platform.isIOS) {
    return UnsupportedNetworkGateway('iOS');
  }
  if (Platform.isAndroid) {
    return UnsupportedNetworkGateway('Android');
  }
  if (Platform.isLinux) {
    return UnsupportedNetworkGateway('Linux');
  }
  return UnsupportedNetworkGateway('当前平台');
}
```

- [ ] **Step 4: Implement Windows gateway**

Create `lib/platform/windows/windows_network_gateway.dart`:

```dart
import '../../domain/network_status.dart';
import '../../domain/sdwan_profile.dart';
import '../command_runner.dart';
import '../network_platform_gateway.dart';
import 'windows_commands.dart';
import 'windows_parsers.dart';

class WindowsNetworkGateway implements NetworkPlatformGateway {
  WindowsNetworkGateway({required this.runner});

  final CommandRunner runner;

  @override
  Future<NetworkStatus> readStatus(SdwanProfile profile) async {
    final admin = await _isAdmin();
    final routeResult = await _run(WindowsCommands.routePrint());
    final routeOutput = routeResult.stdout;
    final interfaceIp = WindowsParsers.defaultRouteInterfaceIp(routeOutput);
    var interfaceName = interfaceIp == null ? null : interfaceIp;
    var dnsMode = DnsMode.unknown;
    var dnsServers = <String>[];

    if (interfaceIp != null) {
      final configResult = await _run(WindowsCommands.netshConfig());
      interfaceName =
          WindowsParsers.interfaceNameForIp(configResult.stdout, interfaceIp);
      if (interfaceName != null) {
        final dnsResult = await _run(WindowsCommands.dnsServers(interfaceName));
        final dns = WindowsParsers.dnsInfo(dnsResult.stdout);
        dnsMode = dns.mode;
        dnsServers = dns.servers;
      }
    }

    return NetworkStatus(
      platformName: 'Windows',
      capability: PlatformCapability.full,
      isAdmin: admin,
      accelerationEnabled:
          WindowsParsers.hasAccelerationRoutes(routeOutput, profile.cpeIp),
      activeInterfaceName: interfaceName,
      activeInterfaceIp: interfaceIp,
      dnsMode: dnsMode,
      dnsServers: dnsServers,
    );
  }

  @override
  Future<GatewayOperationResult> ensureAdminOrRelaunch() async {
    if (await _isAdmin()) {
      return const GatewayOperationResult(success: true, message: '管理员权限已就绪');
    }
    return const GatewayOperationResult(
      success: false,
      message: '当前不是管理员权限，请通过 UAC 重新启动应用',
    );
  }

  @override
  Future<GatewayOperationResult> enableAcceleration(SdwanProfile profile) {
    return _runSequence('开启加速', WindowsCommands.enableAcceleration(profile));
  }

  @override
  Future<GatewayOperationResult> disableAcceleration(SdwanProfile profile) {
    return _runSequence('关闭加速', WindowsCommands.disableAcceleration());
  }

  @override
  Future<GatewayOperationResult> setDns(SdwanProfile profile) async {
    final status = await readStatus(profile);
    final name = status.activeInterfaceName;
    if (name == null || name.isEmpty) {
      return const GatewayOperationResult(
        success: false,
        message: '未找到活动网卡，无法设置 DNS',
      );
    }
    return _runSequence('设置 DNS', WindowsCommands.setDns(name, profile));
  }

  @override
  Future<GatewayOperationResult> restoreDns() async {
    final status = await readStatus(SdwanProfile.defaults());
    final name = status.activeInterfaceName;
    if (name == null || name.isEmpty) {
      return const GatewayOperationResult(
        success: false,
        message: '未找到活动网卡，无法恢复 DNS',
      );
    }
    return _runSequence('恢复 DNS', WindowsCommands.restoreDns(name));
  }

  Future<bool> _isAdmin() async {
    final result = await _run(WindowsCommands.adminCheck());
    return result.exitCode == 0;
  }

  Future<GatewayOperationResult> _runSequence(
    String action,
    List<WindowsCommand> commands,
  ) async {
    for (final command in commands) {
      final result = await _run(command);
      if (!result.succeeded) {
        final detail = result.stderr.trim().isEmpty
            ? result.stdout.trim()
            : result.stderr.trim();
        return GatewayOperationResult(
          success: false,
          message: '$action失败：${detail.isEmpty ? '命令退出码 ${result.exitCode}' : detail}',
          command: command.display,
          exitCode: result.exitCode,
        );
      }
    }
    return GatewayOperationResult(success: true, message: '$action成功');
  }

  Future<CommandResult> _run(WindowsCommand command) {
    return runner.run(command.executable, command.arguments);
  }
}
```

- [ ] **Step 5: Run gateway tests**

Run:

```bash
flutter test test/platform/windows_network_gateway_test.dart
```

Expected: all gateway tests pass.

- [ ] **Step 6: Commit platform gateways**

Run:

```bash
git add lib/platform test/platform/windows_network_gateway_test.dart
git commit -m "feat: implement platform network gateways"
```

Expected: commit succeeds.

## Task 7: Add SD-WAN Controller

**Files:**
- Create: `lib/services/sdwan_controller.dart`
- Create: `test/services/sdwan_controller_test.dart`

- [ ] **Step 1: Write failing controller tests**

Create `test/services/sdwan_controller_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/domain/app_config.dart';
import 'package:sdwan_client/domain/network_status.dart';
import 'package:sdwan_client/domain/sdwan_profile.dart';
import 'package:sdwan_client/platform/network_platform_gateway.dart';
import 'package:sdwan_client/services/config_repository.dart';
import 'package:sdwan_client/services/sdwan_controller.dart';

class FakeGateway implements NetworkPlatformGateway {
  final calls = <String>[];
  NetworkStatus status = const NetworkStatus(
    platformName: 'Windows',
    capability: PlatformCapability.full,
    isAdmin: true,
    accelerationEnabled: false,
  );

  @override
  Future<NetworkStatus> readStatus(SdwanProfile profile) async {
    calls.add('readStatus');
    return status;
  }

  @override
  Future<GatewayOperationResult> ensureAdminOrRelaunch() async {
    calls.add('ensureAdminOrRelaunch');
    return const GatewayOperationResult(success: true, message: 'ok');
  }

  @override
  Future<GatewayOperationResult> enableAcceleration(SdwanProfile profile) async {
    calls.add('enableAcceleration');
    return const GatewayOperationResult(success: true, message: 'enabled');
  }

  @override
  Future<GatewayOperationResult> disableAcceleration(SdwanProfile profile) async {
    calls.add('disableAcceleration');
    return const GatewayOperationResult(success: true, message: 'disabled');
  }

  @override
  Future<GatewayOperationResult> setDns(SdwanProfile profile) async {
    calls.add('setDns');
    return const GatewayOperationResult(success: true, message: 'dns set');
  }

  @override
  Future<GatewayOperationResult> restoreDns() async {
    calls.add('restoreDns');
    return const GatewayOperationResult(success: true, message: 'dns restored');
  }
}

class MemoryConfigStore implements ConfigStore {
  AppConfig config = AppConfig.defaults();

  @override
  Future<AppConfig> load() async => config;

  @override
  Future<void> save(AppConfig config) async {
    this.config = config;
  }
}

void main() {
  test('initializes config and status', () async {
    final controller = SdwanController(
      gateway: FakeGateway(),
      configStore: MemoryConfigStore(),
    );

    await controller.initialize();

    expect(controller.config.activeProfile.cpeIp, '192.168.1.140');
    expect(controller.status.platformName, 'Windows');
  });

  test('enable acceleration sets DNS when profile sync is enabled', () async {
    final gateway = FakeGateway();
    final store = MemoryConfigStore();
    store.config = AppConfig.defaults().copyWith(
      profiles: [
        AppConfig.defaults().activeProfile.copyWith(syncDnsWithAcceleration: true),
      ],
    );
    final controller = SdwanController(gateway: gateway, configStore: store);
    await controller.initialize();

    await controller.enableAcceleration();

    expect(gateway.calls, containsAllInOrder(['enableAcceleration', 'setDns', 'readStatus']));
    expect(controller.logs.last.success, isTrue);
  });

  test('rejects invalid profile update', () async {
    final controller = SdwanController(
      gateway: FakeGateway(),
      configStore: MemoryConfigStore(),
    );
    await controller.initialize();

    final result = await controller.saveProfile(
      controller.config.activeProfile.copyWith(cpeIp: 'bad'),
    );

    expect(result.success, isFalse);
    expect(result.message, contains('CPE 网关地址格式不正确'));
  });
}
```

- [ ] **Step 2: Run controller tests and verify failure**

Run:

```bash
flutter test test/services/sdwan_controller_test.dart
```

Expected: FAIL because `SdwanController` and `ConfigStore` do not exist.

- [ ] **Step 3: Update config repository to implement a store interface**

Modify `lib/services/config_repository.dart` so the top of the file includes the interface:

```dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/app_config.dart';

abstract class ConfigStore {
  Future<AppConfig> load();

  Future<void> save(AppConfig config);
}

class ConfigRepository implements ConfigStore {
  static const storageKey = 'sdwan_client_config_v1';

  @override
  Future<AppConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) {
      return AppConfig.defaults();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        return AppConfig.fromJson(decoded);
      }
      if (decoded is Map) {
        return AppConfig.fromJson(Map<String, Object?>.from(decoded));
      }
    } catch (_) {
      return AppConfig.defaults();
    }
    return AppConfig.defaults();
  }

  @override
  Future<void> save(AppConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(config.toJson()));
  }
}
```

- [ ] **Step 4: Implement controller**

Create `lib/services/sdwan_controller.dart`:

```dart
import 'package:flutter/foundation.dart';

import '../domain/app_config.dart';
import '../domain/network_status.dart';
import '../domain/operation_log.dart';
import '../domain/sdwan_profile.dart';
import '../domain/validation.dart';
import '../platform/network_platform_gateway.dart';
import 'config_repository.dart';

class ControllerResult {
  const ControllerResult({
    required this.success,
    required this.message,
  });

  final bool success;
  final String message;
}

class SdwanController extends ChangeNotifier {
  SdwanController({
    required this.gateway,
    required this.configStore,
  });

  final NetworkPlatformGateway gateway;
  final ConfigStore configStore;

  AppConfig _config = AppConfig.defaults();
  NetworkStatus _status = NetworkStatus.unsupported('初始化中');
  final List<OperationLog> _logs = [];
  bool _busy = false;

  AppConfig get config => _config;
  NetworkStatus get status => _status;
  List<OperationLog> get logs => List.unmodifiable(_logs);
  bool get busy => _busy;

  Future<void> initialize() async {
    _config = await configStore.load();
    await refreshStatus();
  }

  Future<void> refreshStatus() async {
    _busy = true;
    notifyListeners();
    _status = await gateway.readStatus(_config.activeProfile);
    _busy = false;
    notifyListeners();
  }

  Future<ControllerResult> saveProfile(SdwanProfile profile) async {
    final errors = validateProfile(profile);
    if (errors.isNotEmpty) {
      return ControllerResult(success: false, message: errors.join('\n'));
    }
    final profiles = _config.profiles
        .map((item) => item.id == profile.id ? profile : item)
        .toList();
    _config = _config.copyWith(profiles: profiles);
    await configStore.save(_config);
    notifyListeners();
    return const ControllerResult(success: true, message: '配置已保存');
  }

  Future<ControllerResult> enableAcceleration() async {
    return _perform('开启加速', () async {
      final result = await gateway.enableAcceleration(_config.activeProfile);
      if (!result.success) {
        return result;
      }
      if (_config.activeProfile.syncDnsWithAcceleration) {
        return gateway.setDns(_config.activeProfile);
      }
      return result;
    });
  }

  Future<ControllerResult> disableAcceleration() async {
    return _perform('关闭加速', () async {
      final result = await gateway.disableAcceleration(_config.activeProfile);
      if (!result.success) {
        return result;
      }
      if (_config.activeProfile.syncDnsWithAcceleration) {
        return gateway.restoreDns();
      }
      return result;
    });
  }

  Future<ControllerResult> setDns() {
    return _perform('设置 DNS', () => gateway.setDns(_config.activeProfile));
  }

  Future<ControllerResult> restoreDns() {
    return _perform('恢复 DNS', gateway.restoreDns);
  }

  Future<ControllerResult> _perform(
    String action,
    Future<GatewayOperationResult> Function() operation,
  ) async {
    _busy = true;
    notifyListeners();
    final result = await operation();
    _logs.insert(
      0,
      OperationLog(
        timestamp: DateTime.now(),
        action: action,
        message: result.message,
        success: result.success,
        command: result.command,
        exitCode: result.exitCode,
      ),
    );
    _status = await gateway.readStatus(_config.activeProfile);
    _busy = false;
    notifyListeners();
    return ControllerResult(success: result.success, message: result.message);
  }
}
```

- [ ] **Step 5: Run controller tests**

Run:

```bash
flutter test test/services/sdwan_controller_test.dart test/services/config_repository_test.dart
```

Expected: all service tests pass.

- [ ] **Step 6: Commit controller**

Run:

```bash
git add lib/services test/services
git commit -m "feat: orchestrate sdwan operations"
```

Expected: commit succeeds.

## Task 8: Build Flutter UI Shell and Pages

**Files:**
- Replace: `lib/main.dart`
- Create: `lib/ui/app_shell.dart`
- Create: `lib/ui/dashboard_page.dart`
- Create: `lib/ui/settings_page.dart`
- Create: `lib/ui/logs_page.dart`
- Create: `lib/ui/help_page.dart`
- Create: `test/widget/app_shell_test.dart`
- Remove or replace: scaffold `test/widget_test.dart`

- [ ] **Step 1: Write failing widget smoke test**

Create `test/widget/app_shell_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/domain/network_status.dart';
import 'package:sdwan_client/platform/network_platform_gateway.dart';
import 'package:sdwan_client/services/config_repository.dart';
import 'package:sdwan_client/services/sdwan_controller.dart';
import 'package:sdwan_client/ui/app_shell.dart';
import 'package:sdwan_client/domain/app_config.dart';
import 'package:sdwan_client/domain/sdwan_profile.dart';

class FakeGateway implements NetworkPlatformGateway {
  @override
  Future<NetworkStatus> readStatus(SdwanProfile profile) async {
    return const NetworkStatus(
      platformName: 'Windows',
      capability: PlatformCapability.full,
      isAdmin: true,
      accelerationEnabled: false,
      activeInterfaceName: 'Ethernet',
      activeInterfaceIp: '192.168.1.88',
      dnsMode: DnsMode.static,
      dnsServers: ['223.5.5.5', '114.114.114.114'],
    );
  }

  @override
  Future<GatewayOperationResult> ensureAdminOrRelaunch() async =>
      const GatewayOperationResult(success: true, message: 'ok');

  @override
  Future<GatewayOperationResult> enableAcceleration(SdwanProfile profile) async =>
      const GatewayOperationResult(success: true, message: '开启成功');

  @override
  Future<GatewayOperationResult> disableAcceleration(SdwanProfile profile) async =>
      const GatewayOperationResult(success: true, message: '关闭成功');

  @override
  Future<GatewayOperationResult> setDns(SdwanProfile profile) async =>
      const GatewayOperationResult(success: true, message: 'DNS 成功');

  @override
  Future<GatewayOperationResult> restoreDns() async =>
      const GatewayOperationResult(success: true, message: 'DNS 已恢复');
}

class MemoryConfigStore implements ConfigStore {
  AppConfig config = AppConfig.defaults();

  @override
  Future<AppConfig> load() async => config;

  @override
  Future<void> save(AppConfig config) async {
    this.config = config;
  }
}

void main() {
  testWidgets('shows dashboard status and settings page', (tester) async {
    final controller = SdwanController(
      gateway: FakeGateway(),
      configStore: MemoryConfigStore(),
    );
    await controller.initialize();

    await tester.pumpWidget(MaterialApp(home: AppShell(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('国际网络加速工具'), findsOneWidget);
    expect(find.text('未开启'), findsOneWidget);
    expect(find.text('Ethernet'), findsOneWidget);
    expect(find.text('开启加速'), findsOneWidget);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(find.text('CPE 网关'), findsOneWidget);
    expect(find.text('路由操作同步 DNS'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run widget test and verify failure**

Run:

```bash
flutter test test/widget/app_shell_test.dart
```

Expected: FAIL because UI files do not exist.

- [ ] **Step 3: Replace app bootstrap**

Replace `lib/main.dart` with:

```dart
import 'package:flutter/material.dart';

import 'platform/network_gateway.dart';
import 'services/config_repository.dart';
import 'services/sdwan_controller.dart';
import 'ui/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = SdwanController(
    gateway: createNetworkPlatformGateway(),
    configStore: ConfigRepository(),
  );
  await controller.initialize();
  runApp(SdwanClientApp(controller: controller));
}

class SdwanClientApp extends StatelessWidget {
  const SdwanClientApp({super.key, required this.controller});

  final SdwanController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '国际网络加速工具',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        useMaterial3: true,
        cardTheme: const CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      ),
      home: AppShell(controller: controller),
    );
  }
}
```

- [ ] **Step 4: Implement app shell**

Create `lib/ui/app_shell.dart`:

```dart
import 'package:flutter/material.dart';

import '../services/sdwan_controller.dart';
import 'dashboard_page.dart';
import 'help_page.dart';
import 'logs_page.dart';
import 'settings_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});

  final SdwanController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(controller: widget.controller),
      SettingsPage(controller: widget.controller),
      LogsPage(controller: widget.controller),
      const HelpPage(),
    ];

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (value) => setState(() => _index = value),
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: Text('仪表盘'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: Text('设置'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long),
                  label: Text('日志'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.help_outline),
                  selectedIcon: Icon(Icons.help),
                  label: Text('帮助'),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: pages[_index]),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Implement dashboard page**

Create `lib/ui/dashboard_page.dart`:

```dart
import 'package:flutter/material.dart';

import '../domain/network_status.dart';
import '../services/sdwan_controller.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.controller});

  final SdwanController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final status = controller.status;
        final profile = controller.config.activeProfile;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('国际网络加速工具', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _StatusCard(
                  title: '加速状态',
                  value: status.accelerationEnabled ? '已开启' : '未开启',
                  icon: Icons.speed,
                ),
                _StatusCard(
                  title: '活动网卡',
                  value: status.activeInterfaceName ?? '未检测到',
                  subtitle: status.activeInterfaceIp,
                  icon: Icons.lan,
                ),
                _StatusCard(
                  title: '当前 DNS',
                  value: _dnsModeText(status.dnsMode),
                  subtitle: status.dnsServers.join(' / '),
                  icon: Icons.dns,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: controller.busy ? null : controller.enableAcceleration,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('开启加速'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: controller.busy ? null : controller.disableAcceleration,
                  icon: const Icon(Icons.stop),
                  label: const Text('关闭加速'),
                ),
                const SizedBox(width: 12),
                IconButton.filledTonal(
                  onPressed: controller.busy ? null : controller.refreshStatus,
                  icon: const Icon(Icons.refresh),
                  tooltip: '刷新状态',
                ),
              ],
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '当前配置：CPE ${profile.cpeIp}，DNS ${profile.primaryDns} / ${profile.secondaryDns}，'
                  '同步 DNS：${profile.syncDnsWithAcceleration ? '开启' : '关闭'}',
                ),
              ),
            ),
            if (status.message != null) ...[
              const SizedBox(height: 12),
              Text(status.message!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        );
      },
    );
  }

  String _dnsModeText(DnsMode mode) {
    return switch (mode) {
      DnsMode.dhcp => '自动获取',
      DnsMode.static => '静态 DNS',
      DnsMode.unknown => '未知',
    };
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.title,
    required this.value,
    required this.icon,
    this.subtitle,
  });

  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(value, style: Theme.of(context).textTheme.titleLarge),
              if (subtitle != null && subtitle!.isNotEmpty) Text(subtitle!),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Implement settings page**

Create `lib/ui/settings_page.dart`:

```dart
import 'package:flutter/material.dart';

import '../domain/sdwan_profile.dart';
import '../services/sdwan_controller.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});

  final SdwanController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _company;
  late final TextEditingController _cpe;
  late final TextEditingController _primaryDns;
  late final TextEditingController _secondaryDns;
  late bool _syncDns;
  String? _message;

  @override
  void initState() {
    super.initState();
    final profile = widget.controller.config.activeProfile;
    _company = TextEditingController(text: profile.companyName);
    _cpe = TextEditingController(text: profile.cpeIp);
    _primaryDns = TextEditingController(text: profile.primaryDns);
    _secondaryDns = TextEditingController(text: profile.secondaryDns);
    _syncDns = profile.syncDnsWithAcceleration;
  }

  @override
  void dispose() {
    _company.dispose();
    _cpe.dispose();
    _primaryDns.dispose();
    _secondaryDns.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('设置', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 20),
        _Field(label: '公司名称', controller: _company),
        _Field(label: 'CPE 网关', controller: _cpe),
        _Field(label: '主 DNS', controller: _primaryDns),
        _Field(label: '备用 DNS', controller: _secondaryDns),
        SwitchListTile(
          title: const Text('路由操作同步 DNS'),
          subtitle: const Text('开启加速时设置 DNS，关闭加速时恢复自动获取'),
          value: _syncDns,
          onChanged: (value) => setState(() => _syncDns = value),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('保存配置'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _restoreDefaults,
              icon: const Icon(Icons.restore),
              label: const Text('恢复默认'),
            ),
          ],
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(_message!),
        ],
      ],
    );
  }

  Future<void> _save() async {
    final current = widget.controller.config.activeProfile;
    final result = await widget.controller.saveProfile(
      current.copyWith(
        companyName: _company.text.trim(),
        cpeIp: _cpe.text.trim(),
        primaryDns: _primaryDns.text.trim(),
        secondaryDns: _secondaryDns.text.trim(),
        syncDnsWithAcceleration: _syncDns,
      ),
    );
    setState(() => _message = result.message);
  }

  void _restoreDefaults() {
    final defaults = SdwanProfile.defaults();
    _company.text = defaults.companyName;
    _cpe.text = defaults.cpeIp;
    _primaryDns.text = defaults.primaryDns;
    _secondaryDns.text = defaults.secondaryDns;
    setState(() {
      _syncDns = defaults.syncDnsWithAcceleration;
      _message = '已恢复默认值，请点击保存配置';
    });
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: Implement logs and help pages**

Create `lib/ui/logs_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/sdwan_controller.dart';

class LogsPage extends StatelessWidget {
  const LogsPage({super.key, required this.controller});

  final SdwanController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final logs = controller.logs;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Text('日志', style: Theme.of(context).textTheme.headlineMedium),
                const Spacer(),
                IconButton.filledTonal(
                  tooltip: '复制日志',
                  onPressed: logs.isEmpty
                      ? null
                      : () => Clipboard.setData(ClipboardData(
                            text: logs
                                .map((log) =>
                                    '${log.displayTime} ${log.action} ${log.success ? '成功' : '失败'} ${log.message}')
                                .join('\n'),
                          )),
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (logs.isEmpty) const Text('暂无操作日志'),
            for (final log in logs)
              ListTile(
                leading: Icon(log.success ? Icons.check_circle : Icons.error),
                title: Text('${log.displayTime} ${log.action}'),
                subtitle: Text([
                  log.message,
                  if (log.command != null) '命令：${log.command}',
                  if (log.exitCode != null) '退出码：${log.exitCode}',
                ].join('\n')),
              ),
          ],
        );
      },
    );
  }
}
```

Create `lib/ui/help_page.dart`:

```dart
import 'package:flutter/material.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    const items = [
      ('为什么需要管理员权限', 'Windows 修改持久路由和网卡 DNS 需要管理员权限。软件启动时会自动触发 UAC。'),
      ('开启加速做了什么', '软件会添加 0.0.0.0/1 和 128.0.0.0/1 两条路由到配置的 CPE 网关，并刷新 DNS 缓存。'),
      ('关闭加速做了什么', '软件会删除两条加速路由，并刷新 DNS 缓存。'),
      ('DNS 同步开关', '默认关闭。开启后，开启加速会设置主备 DNS，关闭加速会恢复 DNS 自动获取。'),
      ('其它平台', '第一版 Windows 完整支持。macOS、Web、iOS、Android 会显示能力说明，不直接修改系统路由。'),
    ];

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('帮助', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        for (final item in items)
          Card(
            child: ListTile(
              title: Text(item.$1),
              subtitle: Text(item.$2),
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 8: Remove scaffold widget test**

Run:

```bash
rm test/widget_test.dart
```

Expected: scaffold counter test is removed because the counter app no longer exists.

- [ ] **Step 9: Run widget tests**

Run:

```bash
flutter test test/widget/app_shell_test.dart
```

Expected: widget smoke test passes.

- [ ] **Step 10: Commit UI**

Run:

```bash
git add lib/main.dart lib/ui test/widget test/widget_test.dart
git commit -m "feat: build sdwan flutter interface"
```

Expected: commit succeeds. If `test/widget_test.dart` was removed, `git add test/widget_test.dart` stages the deletion.

## Task 9: Wire Admin Relaunch Behavior on Windows

**Files:**
- Modify: `lib/platform/windows/windows_commands.dart`
- Modify: `lib/platform/windows/windows_network_gateway.dart`
- Modify: `lib/main.dart`
- Modify: `test/platform/windows_commands_test.dart`
- Modify: `test/platform/windows_network_gateway_test.dart`

- [ ] **Step 1: Extend command tests for UAC relaunch command**

Add this test to `test/platform/windows_commands_test.dart`:

```dart
test('builds PowerShell UAC relaunch command', () {
  final command = WindowsCommands.relaunchAsAdmin('C:\\Program Files\\Sdwan\\sdwan.exe');

  expect(command.executable, 'powershell');
  expect(command.arguments, [
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-Command',
    'Start-Process -FilePath "C:\\Program Files\\Sdwan\\sdwan.exe" -Verb RunAs',
  ]);
});
```

- [ ] **Step 2: Extend gateway tests for relaunch and old-process exit**

Add this test to `test/platform/windows_network_gateway_test.dart`:

```dart
test('ensureAdminOrRelaunch starts elevated copy and exits current process', () async {
  final runner = FakeCommandRunner();
  runner.responses['net session'] =
      const CommandResult(exitCode: 1, stdout: '', stderr: 'access denied');
  var exitCode = -1;
  final gateway = WindowsNetworkGateway(
    runner: runner,
    executablePath: 'C:\\app\\sdwan.exe',
    exitProcess: (code) => exitCode = code,
  );

  final result = await gateway.ensureAdminOrRelaunch();

  expect(result.success, isTrue);
  expect(exitCode, 0);
  expect(runner.calls, [
    'net session',
    'powershell -NoProfile -ExecutionPolicy Bypass -Command Start-Process -FilePath "C:\\app\\sdwan.exe" -Verb RunAs',
  ]);
});
```

- [ ] **Step 3: Run tests and verify failure**

Run:

```bash
flutter test test/platform/windows_commands_test.dart test/platform/windows_network_gateway_test.dart
```

Expected: FAIL because `relaunchAsAdmin`, `executablePath`, and `exitProcess` do not exist.

- [ ] **Step 4: Add UAC command builder**

Add this method inside `WindowsCommands` in `lib/platform/windows/windows_commands.dart`:

```dart
static WindowsCommand relaunchAsAdmin(String executablePath) {
  final escaped = executablePath.replaceAll('"', r'\"');
  return WindowsCommand('powershell', [
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-Command',
    'Start-Process -FilePath "$escaped" -Verb RunAs',
  ]);
}
```

- [ ] **Step 5: Implement relaunch path in gateway**

Update `WindowsNetworkGateway` constructor and `ensureAdminOrRelaunch()` in `lib/platform/windows/windows_network_gateway.dart`:

```dart
import 'dart:io' show exit;

class WindowsNetworkGateway implements NetworkPlatformGateway {
  WindowsNetworkGateway({
    required this.runner,
    this.executablePath,
    this.exitProcess = exit,
  });

  final CommandRunner runner;
  final String? executablePath;
  final void Function(int code) exitProcess;

  @override
  Future<GatewayOperationResult> ensureAdminOrRelaunch() async {
    if (await _isAdmin()) {
      return const GatewayOperationResult(success: true, message: '管理员权限已就绪');
    }
    final path = executablePath;
    if (path == null || path.isEmpty) {
      return const GatewayOperationResult(
        success: false,
        message: '当前不是管理员权限，请右键以管理员身份运行',
      );
    }
    final command = WindowsCommands.relaunchAsAdmin(path);
    final result = await _run(command);
    if (result.succeeded) {
      exitProcess(0);
    }
    return GatewayOperationResult(
      success: result.succeeded,
      message: result.succeeded ? '已请求管理员权限重新启动' : '请求管理员权限失败',
      command: command.display,
      exitCode: result.exitCode,
    );
  }
```

Also update `lib/platform/network_gateway_io.dart` Windows construction:

```dart
return WindowsNetworkGateway(
  runner: ProcessCommandRunner(),
  executablePath: Platform.resolvedExecutable,
);
```

- [ ] **Step 6: Call admin check during app startup**

Modify `main()` in `lib/main.dart`:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = SdwanController(
    gateway: createNetworkPlatformGateway(),
    configStore: ConfigRepository(),
  );
  await controller.gateway.ensureAdminOrRelaunch();
  await controller.initialize();
  runApp(SdwanClientApp(controller: controller));
}
```

- [ ] **Step 7: Run platform tests**

Run:

```bash
flutter test test/platform/windows_commands_test.dart test/platform/windows_network_gateway_test.dart
```

Expected: all platform tests pass.

- [ ] **Step 8: Commit admin relaunch**

Run:

```bash
git add lib/main.dart lib/platform test/platform
git commit -m "feat: request windows administrator relaunch"
```

Expected: commit succeeds.

## Task 10: Add Documentation and Windows Manual Acceptance

**Files:**
- Create: `docs/windows-manual-acceptance.md`
- Modify: `README.md`

- [ ] **Step 1: Create Windows acceptance checklist**

Create `docs/windows-manual-acceptance.md`:

```markdown
# Windows Manual Acceptance

Use this checklist on a Windows machine with Flutter desktop enabled.

## Preconditions

- The machine is connected to the same network as the SD-WAN CPE.
- The CPE gateway IP is known. Default: `192.168.1.140`.
- Flutter can build Windows desktop apps.

## Checks

1. Run the app normally.
   - Expected: Windows UAC appears and asks to relaunch as administrator.

2. Open the app as administrator.
   - Expected: Dashboard shows Windows full capability.

3. Click `开启加速`.
   - Expected: Dashboard changes to enabled, or logs explain why it failed.
   - Verify in an administrator terminal:

   ```bat
   route print -4
   ```

   Expected routes:

   - Destination `0.0.0.0`, netmask `128.0.0.0`, gateway configured CPE.
   - Destination `128.0.0.0`, netmask `128.0.0.0`, gateway configured CPE.

4. Click `关闭加速`.
   - Expected: Dashboard changes to disabled.
   - Verify with `route print -4` that the two acceleration routes are gone.

5. Enable `路由操作同步 DNS`, save, then click `开启加速`.
   - Verify:

   ```bat
   netsh interface ip show dnsservers
   ```

   Expected: active interface shows configured primary and secondary DNS.

6. Click `关闭加速`.
   - Expected: DNS is restored to automatic acquisition.

7. Disconnect network and refresh status.
   - Expected: app shows a Chinese message explaining that no active interface was found.
```

- [ ] **Step 2: Replace README content**

Replace `README.md`:

```markdown
# SD-WAN Client

Flutter multi-platform client for the SD-WAN acceleration workflow currently represented by the BAT script in this directory.

## First Release Scope

- Windows desktop is the primary supported platform.
- Windows can add and remove the acceleration routes from the original BAT script.
- Windows can set or restore DNS on the active network interface.
- macOS, Web, iOS, Android, and Linux launch with platform capability messaging.

## Default Configuration

- Company: 宁波市富金园艺灌溉设备有限公司
- CPE gateway: `192.168.1.140`
- Primary DNS: `223.5.5.5`
- Secondary DNS: `114.114.114.114`

## Development

```bash
flutter pub get
flutter test
flutter analyze
flutter build macos --debug
```

Run Windows manual acceptance on a Windows machine:

```text
docs/windows-manual-acceptance.md
```
```

- [ ] **Step 3: Commit docs**

Run:

```bash
git add README.md docs/windows-manual-acceptance.md
git commit -m "docs: add sdwan usage and windows acceptance"
```

Expected: commit succeeds.

## Task 11: Final Verification

**Files:**
- All project files

- [ ] **Step 1: Format Dart code**

Run:

```bash
dart format lib test
```

Expected: command exits 0 and formats files.

- [ ] **Step 2: Run analyzer**

Run:

```bash
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 3: Run full tests**

Run:

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 4: Build local macOS debug app for compile verification**

Run:

```bash
flutter build macos --debug
```

Expected: macOS build exits 0. This proves the shared Flutter app compiles on the current Mac, but it does not prove Windows route/DNS behavior.

- [ ] **Step 5: Build web for unsupported-platform verification**

Run:

```bash
flutter build web
```

Expected: web build exits 0, proving the conditional imports avoid `dart:io` on web.

- [ ] **Step 6: Check git whitespace**

Run:

```bash
git diff --check
```

Expected: no whitespace errors.

- [ ] **Step 7: Commit final formatting if needed**

If formatting changed files, run:

```bash
git add lib test README.md docs pubspec.yaml pubspec.lock
git commit -m "chore: verify sdwan client"
```

Expected: commit succeeds only if there are changes.

- [ ] **Step 8: Report Windows verification boundary**

Report that Windows route/DNS behavior still needs to be run on a Windows machine using `docs/windows-manual-acceptance.md`. Do not claim Windows system changes are verified unless that checklist has been executed on Windows.
