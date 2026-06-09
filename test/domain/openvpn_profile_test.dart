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
