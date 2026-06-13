# OpenVPN Profile Config Center Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first desktop-ready SD-WAN Verge configuration center with multiple profiles, `.ovpn` import/edit/export, editable UDP/TCP OpenVPN settings, secure credential boundaries, and OpenVPN-oriented start arguments.

**Architecture:** Extend the existing `SdwanProfile` configuration model into mode-specific profile data while preserving current Half Route behavior as a migrated default. Keep parsing/generation in pure Dart for testability, keep Flutter UI state in `AppConfigController`, and pass a structured active profile to the existing `sdwan_client/tun` MethodChannel so native helpers can add OpenVPN mode without breaking Half Route/TUN.

**Tech Stack:** Flutter/Dart, shared_preferences for config and local credentials, file_selector for desktop file import/export, existing macOS Swift/Windows C++/Linux GTK MethodChannel helpers.

---

## Scope

This plan implements the first desktop MVP from the spec:

- Multi-profile configuration model.
- `.ovpn` import, editable protocol, custom OpenVPN directives, and export.
- Configuration page UI similar to Clash profile management.
- Secure credential abstraction and UI state; native secure-store wiring can start as MethodChannel-backed with test fakes.
- Start/stop/status arguments carry active profile mode and OpenVPN fields.
- Native helpers return clear “OpenVPN binary missing/not configured” errors until process management is implemented in the follow-up task group.

This plan does not trigger GitHub Actions, does not package releases, and does not perform real network takeover on this Mac.

## Files And Responsibilities

- Create `lib/domain/acceleration_mode.dart`: enum and JSON parsing for `openvpn`, `halfRoute`, and `legacyTun`.
- Create `lib/domain/openvpn_profile.dart`: OpenVPN-specific protocol, endpoint, custom directives, and redacted export model.
- Modify `lib/domain/sdwan_profile.dart`: add mode-specific fields while preserving old JSON keys.
- Modify `lib/domain/app_config.dart`: store active profile list and subscription metadata.
- Modify `lib/domain/validation.dart`: validate profile mode, endpoint, protocol, and unsafe custom directives.
- Create `lib/services/ovpn_parser.dart`: pure Dart `.ovpn` parser.
- Create `lib/services/ovpn_generator.dart`: pure Dart `.ovpn` generator with redaction and conflict prevention.
- Create `lib/services/profile_import_export_service.dart`: import/export orchestration around file content.
- Create `lib/services/credential_store.dart`: secure credential interface and method-channel/default implementation.
- Modify `lib/services/app_config_controller.dart`: add profile CRUD, active profile switching, import/export, and credential state actions.
- Modify `lib/tun/tun_service.dart`: pass active profile arguments to native helpers.
- Modify `lib/tun/tun_controller.dart`: apply selected profile before start, update latency targets, and keep old CPE methods compatible.
- Modify `lib/ui/app_shell.dart`: add “配置” navigation item.
- Create `lib/ui/profiles_page.dart`: profile list, current profile, file import/add/edit/export/delete actions.
- Create `lib/ui/profile_editor_page.dart`: profile editor with OpenVPN protocol, endpoint, auth, DNS, MTU, and custom directives.
- Modify `lib/ui/dashboard_page.dart`: show active profile name, mode, and remote.
- Modify `lib/ui/settings_page.dart`: leave only global settings; move connection fields to profile editor.
- Modify `macos/Runner/AppDelegate.swift`: accept profile arguments and return OpenVPN-specific unsupported status.
- Modify `windows/runner/flutter_window.cpp`: forward profile arguments and return OpenVPN-specific unsupported status.
- Modify `linux/runner/my_application.cc`: forward profile arguments and return OpenVPN-specific unsupported status.
- Test files under `test/domain`, `test/services`, `test/tun`, `test/widget`, and `test/platform`.

---

### Task 1: Dependencies And Domain Model

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/domain/acceleration_mode.dart`
- Create: `lib/domain/openvpn_profile.dart`
- Modify: `lib/domain/sdwan_profile.dart`
- Modify: `lib/domain/app_config.dart`
- Modify: `lib/domain/validation.dart`
- Test: `test/domain/config_model_test.dart`
- Test: `test/domain/openvpn_profile_test.dart`
- Test: `test/domain/validation_test.dart`

- [ ] **Step 1: Add dependency commands to the implementation notes**

Run:

```bash
flutter pub add file_selector
```

Expected: `pubspec.yaml` and `pubspec.lock` gain the two packages. If Linux desktop dependency resolution reports a native package warning, keep the Dart dependency and handle runtime support through platform checks.

- [ ] **Step 2: Write failing model tests**

Add to `test/domain/openvpn_profile_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/domain/acceleration_mode.dart';
import 'package:sdwan_client/domain/openvpn_profile.dart';

void main() {
  test('openvpn profile defaults to udp4 ipv4 only', () {
    final profile = OpenVpnProfile.defaults();

    expect(profile.protocol, OpenVpnProtocol.udp4);
    expect(profile.remoteHost, '192.168.1.140');
    expect(profile.remotePort, 10189);
    expect(profile.ipv4Only, isTrue);
    expect(profile.authUserPass, isTrue);
    expect(profile.customDirectives, contains('verb 3'));
  });

  test('protocol parses legacy tcp and udp spellings', () {
    expect(OpenVpnProtocol.fromJson('udp'), OpenVpnProtocol.udp4);
    expect(OpenVpnProtocol.fromJson('udp4'), OpenVpnProtocol.udp4);
    expect(OpenVpnProtocol.fromJson('tcp'), OpenVpnProtocol.tcpClient);
    expect(OpenVpnProtocol.fromJson('tcp-client'), OpenVpnProtocol.tcpClient);
  });

  test('serializes mode specific profile data', () {
    final profile = OpenVpnProfile.defaults().copyWith(
      protocol: OpenVpnProtocol.tcpClient,
      remoteHost: '10.0.0.2',
      remotePort: 443,
      customDirectives: const ['verb 4', 'nobind'],
    );

    final restored = OpenVpnProfile.fromJson(profile.toJson());

    expect(restored.protocol, OpenVpnProtocol.tcpClient);
    expect(restored.remoteHost, '10.0.0.2');
    expect(restored.remotePort, 443);
    expect(restored.customDirectives, ['verb 4', 'nobind']);
  });

  test('acceleration mode parser preserves old tun wording', () {
    expect(AccelerationMode.fromJson('openvpn'), AccelerationMode.openVpn);
    expect(AccelerationMode.fromJson('halfRoute'), AccelerationMode.halfRoute);
    expect(AccelerationMode.fromJson('tun'), AccelerationMode.legacyTun);
  });
}
```

Update `test/domain/config_model_test.dart` to assert old configs migrate to Half Route:

```dart
test('legacy profile migrates to half route mode', () {
  final restored = AppConfig.fromJson({
    'activeProfileId': 'default',
    'profiles': [
      {
        'id': 'default',
        'name': '默认加速配置',
        'companyName': '',
        'cpeIp': '192.168.1.140',
        'primaryDns': '223.5.5.5',
        'secondaryDns': '114.114.114.114',
      },
    ],
  });

  expect(restored.activeProfile.mode, AccelerationMode.halfRoute);
  expect(restored.activeProfile.openVpn, isNotNull);
  expect(restored.activeProfile.cpeIp, '192.168.1.140');
});
```

- [ ] **Step 3: Run tests and verify failure**

Run:

```bash
flutter test test/domain/openvpn_profile_test.dart test/domain/config_model_test.dart
```

Expected: fail because `AccelerationMode`, `OpenVpnProfile`, and new `SdwanProfile.mode` are not defined.

- [ ] **Step 4: Implement `AccelerationMode`**

Create `lib/domain/acceleration_mode.dart`:

```dart
enum AccelerationMode {
  openVpn('openvpn'),
  halfRoute('halfRoute'),
  legacyTun('legacyTun');

  const AccelerationMode(this.json);

  final String json;

  static AccelerationMode fromJson(Object? value) {
    final text = value?.toString().trim();
    return switch (text) {
      'openvpn' || 'openVpn' || 'open_vpn' => AccelerationMode.openVpn,
      'halfRoute' || 'half-route' || 'route' => AccelerationMode.halfRoute,
      'legacyTun' || 'tun' || 'wintun' => AccelerationMode.legacyTun,
      _ => AccelerationMode.halfRoute,
    };
  }
}
```

- [ ] **Step 5: Implement `OpenVpnProfile`**

Create `lib/domain/openvpn_profile.dart`:

```dart
enum OpenVpnProtocol {
  udp4('udp4', 'UDP IPv4'),
  tcpClient('tcp-client', 'TCP IPv4');

  const OpenVpnProtocol(this.ovpnValue, this.label);

  final String ovpnValue;
  final String label;

  static OpenVpnProtocol fromJson(Object? value) {
    final text = value?.toString().trim().toLowerCase();
    return switch (text) {
      'tcp' || 'tcp4' || 'tcp-client' => OpenVpnProtocol.tcpClient,
      _ => OpenVpnProtocol.udp4,
    };
  }
}

class OpenVpnProfile {
  const OpenVpnProfile({
    required this.remoteHost,
    required this.remotePort,
    required this.protocol,
    required this.authUserPass,
    required this.credentialRef,
    required this.configRef,
    required this.redirectGateway,
    required this.tunName,
    required this.mtu,
    required this.mssfix,
    required this.ipv4Only,
    required this.pullFilterIpv6,
    required this.customDirectives,
    required this.inlineBlocks,
  });

  factory OpenVpnProfile.defaults() => const OpenVpnProfile(
    remoteHost: '192.168.1.140',
    remotePort: 10189,
    protocol: OpenVpnProtocol.udp4,
    authUserPass: true,
    credentialRef: null,
    configRef: null,
    redirectGateway: 'def1',
    tunName: 'auto',
    mtu: 'auto',
    mssfix: 'auto',
    ipv4Only: true,
    pullFilterIpv6: true,
    customDirectives: ['verb 3', 'resolv-retry infinite', 'nobind'],
    inlineBlocks: {},
  );

  factory OpenVpnProfile.fromJson(Map<String, Object?> json) {
    final directives = json['customDirectives'];
    final blocks = json['inlineBlocks'];
    return OpenVpnProfile(
      remoteHost: json['remoteHost'] as String? ?? '192.168.1.140',
      remotePort: (json['remotePort'] as num?)?.toInt() ?? 10189,
      protocol: OpenVpnProtocol.fromJson(json['protocol']),
      authUserPass: json['authUserPass'] as bool? ?? true,
      credentialRef: json['credentialRef'] as String?,
      configRef: json['configRef'] as String?,
      redirectGateway: json['redirectGateway'] as String? ?? 'def1',
      tunName: json['tunName'] as String? ?? 'auto',
      mtu: json['mtu'] as String? ?? 'auto',
      mssfix: json['mssfix'] as String? ?? 'auto',
      ipv4Only: json['ipv4Only'] as bool? ?? true,
      pullFilterIpv6: json['pullFilterIpv6'] as bool? ?? true,
      customDirectives: directives is List
          ? directives.map((item) => item.toString()).toList()
          : OpenVpnProfile.defaults().customDirectives,
      inlineBlocks: blocks is Map
          ? blocks.map((key, value) => MapEntry(key.toString(), value.toString()))
          : const {},
    );
  }

  final String remoteHost;
  final int remotePort;
  final OpenVpnProtocol protocol;
  final bool authUserPass;
  final String? credentialRef;
  final String? configRef;
  final String redirectGateway;
  final String tunName;
  final String mtu;
  final String mssfix;
  final bool ipv4Only;
  final bool pullFilterIpv6;
  final List<String> customDirectives;
  final Map<String, String> inlineBlocks;

  Map<String, Object?> toJson() => {
    'remoteHost': remoteHost,
    'remotePort': remotePort,
    'protocol': protocol.ovpnValue,
    'authUserPass': authUserPass,
    'credentialRef': credentialRef,
    'configRef': configRef,
    'redirectGateway': redirectGateway,
    'tunName': tunName,
    'mtu': mtu,
    'mssfix': mssfix,
    'ipv4Only': ipv4Only,
    'pullFilterIpv6': pullFilterIpv6,
    'customDirectives': customDirectives,
    'inlineBlocks': inlineBlocks,
  };

  OpenVpnProfile copyWith({
    String? remoteHost,
    int? remotePort,
    OpenVpnProtocol? protocol,
    bool? authUserPass,
    Object? credentialRef = _unset,
    Object? configRef = _unset,
    String? redirectGateway,
    String? tunName,
    String? mtu,
    String? mssfix,
    bool? ipv4Only,
    bool? pullFilterIpv6,
    List<String>? customDirectives,
    Map<String, String>? inlineBlocks,
  }) {
    return OpenVpnProfile(
      remoteHost: remoteHost ?? this.remoteHost,
      remotePort: remotePort ?? this.remotePort,
      protocol: protocol ?? this.protocol,
      authUserPass: authUserPass ?? this.authUserPass,
      credentialRef: credentialRef == _unset ? this.credentialRef : credentialRef as String?,
      configRef: configRef == _unset ? this.configRef : configRef as String?,
      redirectGateway: redirectGateway ?? this.redirectGateway,
      tunName: tunName ?? this.tunName,
      mtu: mtu ?? this.mtu,
      mssfix: mssfix ?? this.mssfix,
      ipv4Only: ipv4Only ?? this.ipv4Only,
      pullFilterIpv6: pullFilterIpv6 ?? this.pullFilterIpv6,
      customDirectives: customDirectives ?? this.customDirectives,
      inlineBlocks: inlineBlocks ?? this.inlineBlocks,
    );
  }
}

const _unset = Object();
```

- [ ] **Step 6: Extend `SdwanProfile` and `AppConfig`**

Modify `lib/domain/sdwan_profile.dart` to import the new model and add fields:

```dart
import 'acceleration_mode.dart';
import 'openvpn_profile.dart';

class SdwanProfile {
  const SdwanProfile({
    required this.id,
    required this.name,
    required this.companyName,
    required this.cpeIp,
    required this.primaryDns,
    required this.secondaryDns,
    required this.syncDnsWithAcceleration,
    required this.mode,
    required this.openVpn,
  });

  factory SdwanProfile.defaults() => SdwanProfile(
    id: 'default',
    name: '默认加速配置',
    companyName: '',
    cpeIp: '192.168.1.140',
    primaryDns: '223.5.5.5',
    secondaryDns: '114.114.114.114',
    syncDnsWithAcceleration: true,
    mode: AccelerationMode.halfRoute,
    openVpn: OpenVpnProfile.defaults(),
  );

  factory SdwanProfile.openVpnDefaults() => SdwanProfile.defaults().copyWith(
    id: 'openvpn-default',
    name: 'OpenVPN UDP',
    mode: AccelerationMode.openVpn,
  );
}
```

Keep existing constructor fields and add `mode/openVpn` to `fromJson`, `toJson`, and `copyWith`. In `fromJson`, old JSON without `mode` must default to `AccelerationMode.halfRoute`.

- [ ] **Step 7: Add validation rules**

Update `lib/domain/validation.dart`:

```dart
const _blockedOpenVpnDirectivePrefixes = {
  'proto',
  'remote',
  'auth-user-pass',
  'redirect-gateway',
  'script-security',
  'up',
  'down',
  'route-up',
  'client-connect',
};

List<String> validateOpenVpnDirectives(List<String> directives) {
  final errors = <String>[];
  for (final raw in directives) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) {
      continue;
    }
    final key = line.split(RegExp(r'\s+')).first.toLowerCase();
    if (_blockedOpenVpnDirectivePrefixes.contains(key)) {
      errors.add('OpenVPN 自定义配置不允许重复或危险指令：$key');
    }
  }
  return errors;
}
```

Update `validateProfile` to validate `openVpn.remoteHost` non-empty, `remotePort` between 1 and 65535, and call `validateOpenVpnDirectives`.

- [ ] **Step 8: Run domain tests**

Run:

```bash
flutter test test/domain/openvpn_profile_test.dart test/domain/config_model_test.dart test/domain/validation_test.dart
```

Expected: pass.

- [ ] **Step 9: Commit domain model**

```bash
git add pubspec.yaml pubspec.lock lib/domain test/domain
git commit -m "feat: add configurable acceleration profiles"
```

---

### Task 2: OVPN Parser And Generator

**Files:**
- Create: `lib/services/ovpn_parser.dart`
- Create: `lib/services/ovpn_generator.dart`
- Test: `test/services/ovpn_parser_test.dart`
- Test: `test/services/ovpn_generator_test.dart`

- [ ] **Step 1: Write parser tests**

Create `test/services/ovpn_parser_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/domain/openvpn_profile.dart';
import 'package:sdwan_client/services/ovpn_parser.dart';

void main() {
  test('parses tcp ovpn with auth user pass and inline ca', () {
    const input = '''
dev tunkj
proto tcp
remote 192.168.1.140 10189
redirect-gateway def1
auth-user-pass
verb 3
<ca>
-----BEGIN CERTIFICATE-----
redacted
-----END CERTIFICATE-----
</ca>
''';

    final result = OvpnParser().parse(input, fallbackName: '配置文件');

    expect(result.profile.name, '配置文件');
    expect(result.profile.mode.name, 'openVpn');
    expect(result.profile.openVpn.protocol, OpenVpnProtocol.tcpClient);
    expect(result.profile.openVpn.remoteHost, '192.168.1.140');
    expect(result.profile.openVpn.remotePort, 10189);
    expect(result.profile.openVpn.authUserPass, isTrue);
    expect(result.profile.openVpn.inlineBlocks['ca'], contains('BEGIN CERTIFICATE'));
    expect(result.profile.openVpn.customDirectives, contains('verb 3'));
  });

  test('moves udp4 and unknown safe directives into profile fields', () {
    const input = '''
proto udp4
remote vpn.example.com 1194
nobind
persist-tun
pull-filter ignore "route-ipv6"
''';

    final result = OvpnParser().parse(input, fallbackName: 'UDP');

    expect(result.profile.openVpn.protocol, OpenVpnProtocol.udp4);
    expect(result.profile.openVpn.remoteHost, 'vpn.example.com');
    expect(result.profile.openVpn.remotePort, 1194);
    expect(result.profile.openVpn.pullFilterIpv6, isTrue);
    expect(result.profile.openVpn.customDirectives, contains('nobind'));
    expect(result.profile.openVpn.customDirectives, contains('persist-tun'));
  });
}
```

- [ ] **Step 2: Write generator tests**

Create `test/services/ovpn_generator_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/domain/acceleration_mode.dart';
import 'package:sdwan_client/domain/openvpn_profile.dart';
import 'package:sdwan_client/domain/sdwan_profile.dart';
import 'package:sdwan_client/services/ovpn_generator.dart';

void main() {
  test('generates udp4 ovpn without password', () {
    final profile = SdwanProfile.openVpnDefaults().copyWith(
      openVpn: OpenVpnProfile.defaults().copyWith(
        remoteHost: '192.168.1.140',
        remotePort: 10189,
        protocol: OpenVpnProtocol.udp4,
        customDirectives: const ['verb 3', 'nobind'],
      ),
    );

    final text = OvpnGenerator().generate(profile);

    expect(text, contains('proto udp4'));
    expect(text, contains('remote 192.168.1.140 10189'));
    expect(text, contains('auth-user-pass'));
    expect(text, contains('pull-filter ignore "route-ipv6"'));
    expect(text, contains('verb 3'));
    expect(text, isNot(contains('password')));
  });

  test('rejects non openvpn profile', () {
    final profile = SdwanProfile.defaults().copyWith(
      mode: AccelerationMode.halfRoute,
    );

    expect(() => OvpnGenerator().generate(profile), throwsArgumentError);
  });
}
```

- [ ] **Step 3: Run tests and verify failure**

Run:

```bash
flutter test test/services/ovpn_parser_test.dart test/services/ovpn_generator_test.dart
```

Expected: fail because parser and generator do not exist.

- [ ] **Step 4: Implement parser**

Create `lib/services/ovpn_parser.dart` with a line parser that:

- Normalizes CRLF.
- Tracks inline blocks between `<name>` and `</name>`.
- Converts `proto`, `remote`, `redirect-gateway`, `auth-user-pass`, and IPv6 pull filters into `OpenVpnProfile`.
- Preserves safe ordinary lines in `customDirectives`.

The public API:

```dart
class OvpnImportResult {
  const OvpnImportResult({required this.profile});

  final SdwanProfile profile;
}

class OvpnParser {
  OvpnImportResult parse(String input, {required String fallbackName}) {
    final lines = input.replaceAll('\r\n', '\n').split('\n');
    var protocol = OpenVpnProtocol.udp4;
    var remoteHost = '192.168.1.140';
    var remotePort = 10189;
    var authUserPass = false;
    var redirectGateway = 'def1';
    var pullFilterIpv6 = false;
    final custom = <String>[];
    final blocks = <String, String>{};

    String? blockName;
    final blockLines = <String>[];

    for (final raw in lines) {
      final line = raw.trimRight();
      final trimmed = line.trim();
      if (blockName != null) {
        if (trimmed == '</$blockName>') {
          blocks[blockName] = blockLines.join('\n');
          blockName = null;
          blockLines.clear();
        } else {
          blockLines.add(line);
        }
        continue;
      }
      final blockStart = RegExp(r'^<([A-Za-z0-9_-]+)>$').firstMatch(trimmed);
      if (blockStart != null) {
        blockName = blockStart.group(1)!.toLowerCase();
        continue;
      }
      if (trimmed.isEmpty || trimmed.startsWith('#') || trimmed.startsWith(';')) {
        if (trimmed.isNotEmpty) {
          custom.add(line);
        }
        continue;
      }
      final parts = trimmed.split(RegExp(r'\s+'));
      final key = parts.first.toLowerCase();
      switch (key) {
        case 'proto':
          protocol = OpenVpnProtocol.fromJson(parts.length > 1 ? parts[1] : null);
        case 'remote':
          if (parts.length > 1) {
            remoteHost = parts[1];
          }
          if (parts.length > 2) {
            remotePort = int.tryParse(parts[2]) ?? remotePort;
          }
        case 'redirect-gateway':
          redirectGateway = parts.skip(1).join(' ').trim().isEmpty
              ? 'def1'
              : parts.skip(1).join(' ');
        case 'auth-user-pass':
          authUserPass = true;
        case 'pull-filter':
          if (trimmed.contains('ifconfig-ipv6') || trimmed.contains('route-ipv6')) {
            pullFilterIpv6 = true;
          } else {
            custom.add(line);
          }
        default:
          custom.add(line);
      }
    }

    final openVpn = OpenVpnProfile.defaults().copyWith(
      remoteHost: remoteHost,
      remotePort: remotePort,
      protocol: protocol,
      authUserPass: authUserPass,
      redirectGateway: redirectGateway,
      pullFilterIpv6: pullFilterIpv6,
      customDirectives: custom,
      inlineBlocks: blocks,
    );
    final profile = SdwanProfile.openVpnDefaults().copyWith(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: fallbackName,
      cpeIp: remoteHost,
      mode: AccelerationMode.openVpn,
      openVpn: openVpn,
    );
    return OvpnImportResult(profile: profile);
  }
}
```

- [ ] **Step 5: Implement generator**

Create `lib/services/ovpn_generator.dart`:

```dart
class OvpnGenerator {
  String generate(SdwanProfile profile, {String? authFilePath}) {
    if (profile.mode != AccelerationMode.openVpn) {
      throw ArgumentError('only OpenVPN profiles can be exported as ovpn');
    }
    final openVpn = profile.openVpn;
    final lines = <String>[
      'dev ${openVpn.tunName == 'auto' ? 'tun' : openVpn.tunName}',
      'proto ${openVpn.protocol.ovpnValue}',
      'remote ${openVpn.remoteHost} ${openVpn.remotePort}',
      if (openVpn.redirectGateway.isNotEmpty)
        'redirect-gateway ${openVpn.redirectGateway}',
      if (openVpn.authUserPass)
        authFilePath == null ? 'auth-user-pass' : 'auth-user-pass $authFilePath',
      if (openVpn.ipv4Only) 'pull-filter ignore "ifconfig-ipv6"',
      if (openVpn.pullFilterIpv6) 'pull-filter ignore "route-ipv6"',
      if (openVpn.mtu != 'auto') 'tun-mtu ${openVpn.mtu}',
      if (openVpn.mssfix != 'auto') 'mssfix ${openVpn.mssfix}',
      ...openVpn.customDirectives,
    ];
    for (final entry in openVpn.inlineBlocks.entries) {
      lines.add('<${entry.key}>');
      lines.add(entry.value);
      lines.add('</${entry.key}>');
    }
    return '${lines.join('\n')}\n';
  }
}
```

- [ ] **Step 6: Run parser/generator tests**

Run:

```bash
flutter test test/services/ovpn_parser_test.dart test/services/ovpn_generator_test.dart
```

Expected: pass.

- [ ] **Step 7: Commit parser/generator**

```bash
git add lib/services/ovpn_parser.dart lib/services/ovpn_generator.dart test/services/ovpn_parser_test.dart test/services/ovpn_generator_test.dart
git commit -m "feat: parse and generate openvpn profiles"
```

---

### Task 3: Profile Controller, Import/Export, And Credentials

**Files:**
- Create: `lib/services/profile_import_export_service.dart`
- Create: `lib/services/credential_store.dart`
- Modify: `lib/services/app_config_controller.dart`
- Test: `test/services/app_config_controller_test.dart`
- Test: `test/services/profile_import_export_service_test.dart`
- Test: `test/services/credential_store_test.dart`

- [ ] **Step 1: Write service tests**

Create `test/services/profile_import_export_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/domain/openvpn_profile.dart';
import 'package:sdwan_client/services/profile_import_export_service.dart';

void main() {
  test('imports ovpn content as editable openvpn profile', () {
    const content = 'proto tcp\nremote 192.168.1.140 10189\nauth-user-pass\n';

    final result = ProfileImportExportService().importOvpnContent(
      content,
      fileName: 'cpe.ovpn',
    );

    expect(result.name, 'cpe');
    expect(result.openVpn.protocol, OpenVpnProtocol.tcpClient);
    expect(result.openVpn.authUserPass, isTrue);
  });

  test('exports profile without credentials', () {
    final profile = ProfileImportExportService().importOvpnContent(
      'proto udp4\nremote 192.168.1.140 10189\nauth-user-pass\n',
      fileName: 'cpe.ovpn',
    );

    final exported = ProfileImportExportService().exportOvpnContent(profile);

    expect(exported, contains('auth-user-pass'));
    expect(exported, isNot(contains('password')));
  });
}
```

- [ ] **Step 2: Extend config controller tests**

Add to `test/services/app_config_controller_test.dart`:

```dart
test('adds switches and deletes profiles', () async {
  final store = MemoryConfigStore();
  final controller = AppConfigController(configStore: store);
  await controller.initialize();

  final profile = SdwanProfile.openVpnDefaults().copyWith(
    id: 'vpn-1',
    name: '公司 UDP',
  );

  await controller.addProfile(profile);
  expect(controller.config.profiles.map((item) => item.id), contains('vpn-1'));

  await controller.setActiveProfile('vpn-1');
  expect(controller.config.activeProfileId, 'vpn-1');

  await controller.deleteProfile('vpn-1');
  expect(controller.config.activeProfileId, 'default');
  expect(controller.config.profiles.map((item) => item.id), isNot(contains('vpn-1')));
});
```

- [ ] **Step 3: Run tests and verify failure**

Run:

```bash
flutter test test/services/profile_import_export_service_test.dart test/services/app_config_controller_test.dart
```

Expected: fail because new service and controller methods do not exist.

- [ ] **Step 4: Implement import/export service**

Create `lib/services/profile_import_export_service.dart`:

```dart
import '../domain/sdwan_profile.dart';
import 'ovpn_generator.dart';
import 'ovpn_parser.dart';

class ProfileImportExportService {
  SdwanProfile importOvpnContent(String content, {required String fileName}) {
    final name = fileName.replaceAll(RegExp(r'\.ovpn$', caseSensitive: false), '');
    return OvpnParser().parse(content, fallbackName: name).profile;
  }

  String exportOvpnContent(SdwanProfile profile) {
    return OvpnGenerator().generate(profile);
  }
}
```

- [ ] **Step 5: Implement credential abstraction**

Create `lib/services/credential_store.dart`:

```dart
import 'package:flutter/services.dart';

class OpenVpnCredential {
  const OpenVpnCredential({required this.username, required this.password});

  final String username;
  final String password;
}

abstract interface class CredentialStore {
  Future<void> save(String ref, OpenVpnCredential credential);
  Future<OpenVpnCredential?> read(String ref);
  Future<void> delete(String ref);
}

class MethodChannelCredentialStore implements CredentialStore {
  MethodChannelCredentialStore({
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel('sdwan_client/credentials');

  final MethodChannel _channel;

  @override
  Future<void> save(String ref, OpenVpnCredential credential) async {
    await _channel.invokeMethod<void>('saveOpenVpnCredential', {
      'ref': ref,
      'username': credential.username,
      'password': credential.password,
    });
  }

  @override
  Future<OpenVpnCredential?> read(String ref) async {
    final result = await _channel.invokeMethod<Object?>('readOpenVpnCredential', {
      'ref': ref,
    });
    if (result is! Map) {
      return null;
    }
    return OpenVpnCredential(
      username: result['username']?.toString() ?? '',
      password: result['password']?.toString() ?? '',
    );
  }

  @override
  Future<void> delete(String ref) async {
    await _channel.invokeMethod<void>('deleteOpenVpnCredential', {'ref': ref});
  }
}
```

- [ ] **Step 6: Implement controller methods**

Add to `AppConfigController`:

```dart
Future<ConfigControllerResult> addProfile(SdwanProfile profile) async {
  final errors = validateProfile(profile);
  if (errors.isNotEmpty) {
    return ConfigControllerResult(success: false, message: errors.join('\n'));
  }
  _config = _config.copyWith(
    activeProfileId: profile.id,
    profiles: [..._config.profiles, profile],
  );
  await configStore.save(_config);
  notifyListeners();
  return const ConfigControllerResult(success: true, message: '配置已添加');
}

Future<ConfigControllerResult> setActiveProfile(String profileId) async {
  final exists = _config.profiles.any((profile) => profile.id == profileId);
  if (!exists) {
    return const ConfigControllerResult(success: false, message: '配置不存在');
  }
  _config = _config.copyWith(activeProfileId: profileId);
  await configStore.save(_config);
  notifyListeners();
  return const ConfigControllerResult(success: true, message: '已切换配置');
}

Future<ConfigControllerResult> deleteProfile(String profileId) async {
  if (_config.profiles.length == 1) {
    return const ConfigControllerResult(success: false, message: '至少保留一个配置');
  }
  final profiles = _config.profiles
      .where((profile) => profile.id != profileId)
      .toList();
  final active = _config.activeProfileId == profileId
      ? profiles.first.id
      : _config.activeProfileId;
  _config = _config.copyWith(activeProfileId: active, profiles: profiles);
  await configStore.save(_config);
  notifyListeners();
  return const ConfigControllerResult(success: true, message: '配置已删除');
}
```

- [ ] **Step 7: Run service tests**

Run:

```bash
flutter test test/services/profile_import_export_service_test.dart test/services/app_config_controller_test.dart
```

Expected: pass.

- [ ] **Step 8: Commit services**

```bash
git add lib/services test/services
git commit -m "feat: manage profile import export and credentials"
```

---

### Task 4: Flutter Config Center UI

**Files:**
- Create: `lib/ui/profiles_page.dart`
- Create: `lib/ui/profile_editor_page.dart`
- Modify: `lib/ui/app_shell.dart`
- Modify: `lib/ui/dashboard_page.dart`
- Modify: `lib/ui/settings_page.dart`
- Test: `test/widget/app_shell_test.dart`
- Test: `test/widget/profiles_page_test.dart`

- [ ] **Step 1: Write widget tests**

Create `test/widget/profiles_page_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/domain/app_config.dart';
import 'package:sdwan_client/domain/sdwan_profile.dart';
import 'package:sdwan_client/services/app_config_controller.dart';
import 'package:sdwan_client/services/config_repository.dart';
import 'package:sdwan_client/ui/profiles_page.dart';

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
  testWidgets('profiles page lists and switches profiles', (tester) async {
    final store = MemoryConfigStore()
      ..config = AppConfig.defaults().copyWith(
        profiles: [
          SdwanProfile.defaults(),
          SdwanProfile.openVpnDefaults().copyWith(id: 'vpn', name: '公司 UDP'),
        ],
      );
    final controller = AppConfigController(configStore: store);
    await controller.initialize();

    await tester.pumpWidget(MaterialApp(home: ProfilesPage(controller: controller)));

    expect(find.text('配置'), findsOneWidget);
    expect(find.text('默认加速配置'), findsOneWidget);
    expect(find.text('公司 UDP'), findsOneWidget);

    await tester.tap(find.text('使用').last);
    await tester.pumpAndSettle();

    expect(controller.config.activeProfileId, 'vpn');
  });

  testWidgets('editor exposes protocol and custom directives', (tester) async {
    final store = MemoryConfigStore()
      ..config = AppConfig.defaults().copyWith(
        profiles: [SdwanProfile.openVpnDefaults()],
        activeProfileId: 'openvpn-default',
      );
    final controller = AppConfigController(configStore: store);
    await controller.initialize();

    await tester.pumpWidget(MaterialApp(home: ProfilesPage(controller: controller)));
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    expect(find.text('UDP IPv4'), findsOneWidget);
    expect(find.text('TCP IPv4'), findsOneWidget);
    expect(find.text('OpenVPN 自定义配置'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run widget tests and verify failure**

Run:

```bash
flutter test test/widget/profiles_page_test.dart
```

Expected: fail because `ProfilesPage` does not exist.

- [ ] **Step 3: Create `ProfilesPage`**

Create `lib/ui/profiles_page.dart` with a list-first layout using existing `panelDecoration()` and `AppColors`:

```dart
import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../domain/acceleration_mode.dart';
import '../domain/sdwan_profile.dart';
import '../services/profile_import_export_service.dart';

class ProfilesPage extends StatelessWidget {
  ProfilesPage({
    super.key,
    required this.controller,
    ProfileImportExportService? importExportService,
  }) : importExportService =
           importExportService ?? ProfileImportExportService();

  final AppConfigController controller;
  final ProfileImportExportService importExportService;

  static const _ovpnTypeGroup = XTypeGroup(
    label: 'OpenVPN',
    extensions: ['ovpn'],
  );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final config = controller.config;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Text('配置', style: Theme.of(context).textTheme.headlineMedium),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () => _importOvpn(context),
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('导入 .ovpn'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: () async {
                    final profile = SdwanProfile.openVpnDefaults().copyWith(
                      id: DateTime.now().microsecondsSinceEpoch.toString(),
                      name: 'OpenVPN UDP',
                    );
                    await controller.addProfile(profile);
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('添加配置'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            for (final profile in config.profiles)
              _ProfileCard(
                profile: profile,
                active: profile.id == config.activeProfileId,
                onUse: () => controller.setActiveProfile(profile.id),
                onEdit: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProfileEditorPage(
                        controller: controller,
                        profile: profile,
                      ),
                    ),
                  );
                },
                onExport: profile.mode == AccelerationMode.openVpn
                    ? () => _exportOvpn(context, profile)
                    : null,
                onDelete: () => controller.deleteProfile(profile.id),
              ),
          ],
        );
      },
    );
  }

  Future<void> _importOvpn(BuildContext context) async {
    final file = await openFile(acceptedTypeGroups: [_ovpnTypeGroup]);
    if (file == null) {
      return;
    }
    final content = await file.readAsString();
    final profile = importExportService.importOvpnContent(
      content,
      fileName: file.name,
    );
    final result = await controller.addProfile(profile);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    }
  }

  Future<void> _exportOvpn(BuildContext context, SdwanProfile profile) async {
    final location = await getSaveLocation(
      acceptedTypeGroups: [_ovpnTypeGroup],
      suggestedName: '${profile.name}.ovpn',
    );
    if (location == null) {
      return;
    }
    final content = importExportService.exportOvpnContent(profile);
    await File(location.path).writeAsString(content);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('配置已导出，未包含密码')),
      );
    }
  }
}
```

Complete `_ProfileCard` in the same file. It must show profile name, mode label, remote endpoint for OpenVPN, CPE gateway for Half Route, and actions `使用`, `编辑`, `导出`, `删除`. Its `onExport` parameter must be nullable so non-OpenVPN profiles show a disabled export button rather than pretending they can be exported as `.ovpn`.

- [ ] **Step 4: Create `ProfileEditorPage`**

Create `lib/ui/profile_editor_page.dart`:

```dart
class ProfileEditorPage extends StatefulWidget {
  const ProfileEditorPage({
    super.key,
    required this.controller,
    required this.profile,
  });

  final AppConfigController controller;
  final SdwanProfile profile;

  @override
  State<ProfileEditorPage> createState() => _ProfileEditorPageState();
}
```

The editor state must expose:

- Name `TextEditingController`.
- Remote host `TextEditingController`.
- Remote port `TextEditingController`.
- Protocol segmented control with `UDP IPv4` and `TCP IPv4`.
- IPv4-only switch.
- Auth-user-pass switch.
- DNS follow CPE switch.
- Custom directives multiline `TextField`.
- Save button calling `controller.saveProfile(updatedProfile)`.

- [ ] **Step 5: Wire navigation**

Modify `lib/ui/app_shell.dart`:

```dart
import 'profiles_page.dart';

static const _items = [
  _NavMeta('仪表盘', Icons.dashboard_rounded),
  _NavMeta('配置', Icons.folder_copy_rounded),
  _NavMeta('连接', Icons.hub_rounded),
  _NavMeta('测速', Icons.speed_rounded),
  _NavMeta('日志', Icons.receipt_long_rounded),
  _NavMeta('设置', Icons.tune_rounded),
  _NavMeta('帮助', Icons.help_rounded),
];
```

Insert `ProfilesPage(controller: widget.configController)` as the second page.

- [ ] **Step 6: Update dashboard and settings**

Modify `DashboardPage` to show:

- Active profile name.
- Mode label: `OpenVPN`, `Half Route`, or `Legacy TUN`.
- Remote endpoint for OpenVPN.

Modify `SettingsPage` so CPE address and DNS sync fields are removed from global settings once the Profile editor owns them. Keep helper install, retain history, launch at login.

- [ ] **Step 7: Run widget tests**

Run:

```bash
flutter test test/widget/profiles_page_test.dart test/widget/app_shell_test.dart
```

Expected: pass after updating old tests to account for the new “配置” nav item and moved settings fields.

- [ ] **Step 8: Commit UI**

```bash
git add lib/ui test/widget
git commit -m "feat: add profile configuration center UI"
```

---

### Task 5: Profile-Aware Tun Service Arguments

**Files:**
- Modify: `lib/tun/tun_models.dart`
- Modify: `lib/tun/tun_service.dart`
- Modify: `lib/tun/tun_controller.dart`
- Modify: `lib/main.dart`
- Test: `test/tun/tun_service_test.dart`
- Test: `test/tun/tun_controller_test.dart`

- [ ] **Step 1: Write service argument tests**

Create or extend `test/tun/tun_service_test.dart` with a fake method channel:

```dart
test('start sends active openvpn profile arguments', () async {
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('sdwan_client/tun'), (call) async {
    calls.add(call);
    return {
      'state': 'stopped',
      'mode': 'openvpn',
      'adapterName': 'OpenVPN',
      'permission': 'ready',
      'helperInstalled': true,
      'cpe': {'host': '192.168.1.140', 'reachable': true, 'serviceReady': true},
    };
  });

  final service = MethodChannelTunService();
  service.updateProfile(SdwanProfile.openVpnDefaults());
  await service.start();

  final args = calls.singleWhere((call) => call.method == 'start').arguments as Map;
  expect(args['mode'], 'openvpn');
  expect(args['openvpnProtocol'], 'udp4');
  expect(args['openvpnRemoteHost'], '192.168.1.140');
  expect(args['openvpnRemotePort'], 10189);
});
```

- [ ] **Step 2: Run test and verify failure**

Run:

```bash
flutter test test/tun/tun_service_test.dart
```

Expected: fail because `updateProfile` and profile arguments do not exist.

- [ ] **Step 3: Extend `TunService`**

Add to `TunService`:

```dart
void updateProfile(SdwanProfile profile);
```

Add an `_activeProfile` field to `MethodChannelTunService`, initialized from `SdwanProfile.defaults()`. Update `_baseArguments()`:

```dart
Map<String, Object?> _baseArguments() {
  final profile = _activeProfile;
  final openVpn = profile.openVpn;
  return {
    'profileId': profile.id,
    'profileName': profile.name,
    'mode': profile.mode.json,
    'cpeHost': profile.cpeIp,
    'syncDns': profile.syncDnsWithAcceleration,
    'openvpnRemoteHost': openVpn.remoteHost,
    'openvpnRemotePort': openVpn.remotePort,
    'openvpnProtocol': openVpn.protocol.ovpnValue,
    'openvpnAuthUserPass': openVpn.authUserPass,
    'openvpnCredentialRef': openVpn.credentialRef,
    'openvpnIpv4Only': openVpn.ipv4Only,
    'openvpnCustomDirectives': openVpn.customDirectives,
  };
}
```

Keep `updateCpeHost` and `updateDnsSync` by copying the active profile with updated legacy fields.

- [ ] **Step 4: Update controller and main**

Modify `main.dart` after loading config:

```dart
tunService.updateProfile(configController.config.activeProfile);
```

Modify `TunController.start()` to call `_service.updateProfile(activeProfile)` through a new `setActiveProfile(SdwanProfile profile)` method before health checks. Wire `AppConfigController` changes in `AppShell` by calling this when profile switches, or pass the current active profile into `DashboardPage` start button flow.

- [ ] **Step 5: Run tun tests**

Run:

```bash
flutter test test/tun/tun_service_test.dart test/tun/tun_controller_test.dart
```

Expected: pass.

- [ ] **Step 6: Commit service arguments**

```bash
git add lib/tun lib/main.dart test/tun
git commit -m "feat: pass active profiles to native helpers"
```

---

### Task 6: Native Helper OpenVPN Mode Stubs

**Files:**
- Modify: `macos/Runner/AppDelegate.swift`
- Modify: `windows/runner/flutter_window.cpp`
- Modify: `linux/runner/my_application.cc`
- Test: `test/platform/macos_runner_test.dart`
- Test: `test/platform/windows_runner_test.dart`
- Test: `test/platform/linux_runner_test.dart`

- [ ] **Step 1: Write platform text tests**

Add tests that inspect source files for OpenVPN argument keys and mode-specific status. Example for macOS:

```dart
test('macos runner handles openvpn mode arguments', () {
  final source = File('macos/Runner/AppDelegate.swift').readAsStringSync();

  expect(source, contains('"mode"'));
  expect(source, contains('"openvpnRemoteHost"'));
  expect(source, contains('OpenVPN'));
  expect(source, contains('openvpn binary not configured'));
});
```

Repeat equivalent checks for `windows/runner/flutter_window.cpp` and `linux/runner/my_application.cc`.

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
flutter test test/platform/macos_runner_test.dart test/platform/windows_runner_test.dart test/platform/linux_runner_test.dart
```

Expected: fail until native runners understand OpenVPN keys.

- [ ] **Step 3: Implement macOS OpenVPN mode status**

In `AppDelegate.swift`, parse `mode` and OpenVPN fields from arguments. If `mode == "openvpn"`:

- `status` returns `adapterName = "OpenVPN"`, `permission = "ready"` if helper installed, and `lastError = "openvpn binary not configured"` until process management lands.
- `start` returns `state = failed` with same clear error.
- `stop` returns stopped OpenVPN status.

Do not call `route` or helper half-route commands for OpenVPN mode.

- [ ] **Step 4: Implement Windows OpenVPN mode status**

In `windows/runner/flutter_window.cpp`, read `mode`. If OpenVPN:

- Return `adapterName=OpenVPN`.
- Return `lastError=openvpn binary not configured`.
- Do not run `sdwan_windows_helper.exe start` half-route commands.

- [ ] **Step 5: Implement Linux OpenVPN mode status**

In `linux/runner/my_application.cc`, read `mode`. If OpenVPN:

- Return `adapterName=OpenVPN`.
- Return `lastError=openvpn binary not configured`.
- Keep Half Route behavior unchanged for `halfRoute`.

- [ ] **Step 6: Run platform tests**

Run:

```bash
flutter test test/platform/macos_runner_test.dart test/platform/windows_runner_test.dart test/platform/linux_runner_test.dart
```

Expected: pass.

- [ ] **Step 7: Commit native stubs**

```bash
git add macos/Runner/AppDelegate.swift windows/runner/flutter_window.cpp linux/runner/my_application.cc test/platform
git commit -m "feat: add openvpn mode native status stubs"
```

---

### Task 7: Verification Pass

**Files:**
- No new files.

- [ ] **Step 1: Run analyzer**

Run:

```bash
flutter analyze
```

Expected: `No issues found`.

- [ ] **Step 2: Run all tests**

Run:

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 3: Check git diff**

Run:

```bash
git diff --check
git status --short
```

Expected: no whitespace errors. `git status --short` should show only files intentionally changed after the last task commit, or be clean if each task was committed.

- [ ] **Step 4: Manual non-network UI smoke test**

Run:

```bash
flutter run -d macos
```

Expected:

- App opens with existing Clash-style UI.
- Sidebar includes “配置”.
- Config page lists at least one migrated Half Route profile.
- User can add an OpenVPN UDP profile.
- User can switch UDP/TCP in the editor.
- User can edit custom directives.
- Clicking start on OpenVPN mode shows a clear OpenVPN setup error rather than starting Half Route.

Stop the app from the UI; do not start real OpenVPN or route takeover in this smoke test.

- [ ] **Step 5: Final commit if needed**

If verification changed snapshots, generated files, or minor fixes:

```bash
git add <changed-files>
git commit -m "test: verify openvpn profile config center"
```

---

## Follow-Up Plan Boundary

After this plan passes, write a second implementation plan for real OpenVPN process management:

- Bundle or locate `openvpn` on macOS/Windows/Linux.
- Generate runtime `.ovpn` and temporary auth file.
- Store credentials in Keychain/Credential Manager/Secret Service.
- Start/stop OpenVPN process through helper/service.
- Parse OpenVPN logs and expose running status, traffic, health, and reconnect events.

That second plan is intentionally separate because it touches privileged process control and platform packaging.
