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
