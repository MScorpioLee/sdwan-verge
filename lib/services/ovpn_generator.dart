import '../domain/acceleration_mode.dart';
import '../domain/sdwan_profile.dart';

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
        authFilePath == null
            ? 'auth-user-pass'
            : 'auth-user-pass $authFilePath',
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
