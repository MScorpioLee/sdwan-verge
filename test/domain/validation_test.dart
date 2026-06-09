import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/domain/acceleration_mode.dart';
import 'package:sdwan_client/domain/openvpn_profile.dart';
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

  test('company name is optional', () {
    final profile = SdwanProfile.defaults().copyWith(companyName: '');

    expect(validateProfile(profile), isEmpty);
  });

  test('validates openvpn endpoint and custom directives', () {
    final profile = SdwanProfile.openVpnDefaults().copyWith(
      mode: AccelerationMode.openVpn,
      openVpn: OpenVpnProfile.defaults().copyWith(
        remoteHost: '',
        remotePort: 70000,
        customDirectives: const [
          'proto tcp',
          'script-security invalid',
          'up run.sh',
        ],
      ),
    );

    final errors = validateProfile(profile);

    expect(errors, contains('OpenVPN 服务器地址不能为空'));
    expect(errors, contains('OpenVPN 端口必须在 1-65535 之间'));
    expect(errors, contains('OpenVPN 自定义配置不允许重复或危险指令：proto'));
    expect(errors, contains('OpenVPN 自定义配置不允许重复或危险指令：script-security'));
    expect(errors, contains('OpenVPN 自定义配置不允许重复或危险指令：up'));
  });

  test('allows script-security levels when script hooks remain blocked', () {
    final errors = validateOpenVpnDirectives(const [
      'script-security 0',
      'script-security 1',
      'script-security 2',
      'script-security 3',
    ]);

    expect(errors, isEmpty);
  });

  test('requires OpenVPN trust material before starting', () {
    final missingCa = SdwanProfile.openVpnDefaults().copyWith(
      mode: AccelerationMode.openVpn,
      openVpn: OpenVpnProfile.defaults().copyWith(inlineBlocks: const {}),
    );
    final inlineCa = missingCa.copyWith(
      openVpn: missingCa.openVpn.copyWith(
        inlineBlocks: const {'ca': '-----BEGIN CERTIFICATE-----'},
      ),
    );
    final caPath = missingCa.copyWith(
      openVpn: missingCa.openVpn.copyWith(
        customDirectives: const ['ca ca.crt'],
      ),
    );

    expect(
      validateProfile(missingCa),
      contains('OpenVPN 配置缺少服务端 CA，请重新导入完整 .ovpn 或添加 ca/capath；不需要客户端证书'),
    );
    expect(validateProfile(inlineCa), isEmpty);
    expect(validateProfile(caPath), isEmpty);
  });
}
