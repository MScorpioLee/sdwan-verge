import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String readHelper() =>
      File('windows/helper/sdwan_windows_helper.cpp').readAsStringSync();

  test('Windows helper uses IPv4-only TUN stability settings', () {
    final helper = readHelper();

    expect(helper, contains('constexpr int kTunMtu = 1400;'));
    expect(helper, contains('constexpr uint16_t kTcpMssClamp = 1360;'));
    expect(helper, contains('netsh interface ipv4 set subinterface'));
    expect(helper, contains('mtu=1400'));
    expect(helper, contains('ClampTcpMss'));
    expect(helper, contains('IsIpv4Packet'));
  });

  test('Windows health rollback is based on CPE reachability', () {
    final helper = readHelper();

    expect(helper, contains('if (!l1)'));
    expect(helper, contains('CPE reachable but L3 probe failed'));
  });
}
