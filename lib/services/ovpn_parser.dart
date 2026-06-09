import '../domain/acceleration_mode.dart';
import '../domain/openvpn_profile.dart';
import '../domain/sdwan_profile.dart';

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
    var tunName = 'auto';
    var pullFilterIpv6 = false;
    final custom = <String>[];
    final blocks = <String, String>{};

    String? blockName;
    final blockLines = <String>[];

    for (final raw in lines) {
      final line = raw.trimRight();
      final trimmed = line.trim();
      if (blockName != null) {
        if (trimmed.toLowerCase() == '</$blockName>') {
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

      if (trimmed.isEmpty) {
        continue;
      }
      if (trimmed.startsWith('#') || trimmed.startsWith(';')) {
        custom.add(line);
        continue;
      }

      final parts = trimmed.split(RegExp(r'\s+'));
      final key = parts.first.toLowerCase();
      switch (key) {
        case 'dev':
          if (parts.length > 1) {
            tunName = parts[1];
          }
        case 'proto':
          protocol = OpenVpnProtocol.fromJson(
            parts.length > 1 ? parts[1] : null,
          );
        case 'remote':
          if (parts.length > 1) {
            remoteHost = parts[1];
          }
          if (parts.length > 2) {
            remotePort = int.tryParse(parts[2]) ?? remotePort;
          }
        case 'redirect-gateway':
          final value = parts.skip(1).join(' ').trim();
          redirectGateway = value.isEmpty ? 'def1' : value;
        case 'auth-user-pass':
          authUserPass = true;
        case 'pull-filter':
          if (trimmed.contains('ifconfig-ipv6') ||
              trimmed.contains('route-ipv6')) {
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
      tunName: tunName,
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
