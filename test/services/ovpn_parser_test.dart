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
    expect(
      result.profile.openVpn.inlineBlocks['ca'],
      contains('BEGIN CERTIFICATE'),
    );
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
