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

  test('company name is optional', () {
    final profile = SdwanProfile.defaults().copyWith(companyName: '');

    expect(validateProfile(profile), isEmpty);
  });
}
