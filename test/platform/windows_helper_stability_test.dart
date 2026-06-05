import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String readHelper() =>
      File('windows/helper/sdwan_windows_helper.cpp').readAsStringSync();

  test('Windows helper uses half-route data plane instead of Wintun NAT', () {
    final helper = readHelper();

    expect(helper, contains('route add 0.0.0.0 mask 128.0.0.0'));
    expect(helper, contains('route add 128.0.0.0 mask 128.0.0.0'));
    expect(helper, contains('route delete 0.0.0.0 mask 128.0.0.0'));
    expect(helper, contains('route delete 128.0.0.0 mask 128.0.0.0'));
    expect(helper, isNot(contains('Wintun')));
    expect(helper, isNot(contains('WinDivert')));
    expect(helper, isNot(contains('NatTranslate')));
  });

  test('Windows helper exposes half-route diagnostics and telemetry', () {
    final helper = readHelper();

    expect(helper, contains('adapterName=Windows Half Route'));
    expect(helper, contains('txBytes='));
    expect(helper, contains('rxBytes='));
    expect(helper, contains('netstat -ano -p tcp'));
    expect(helper, contains('GetIfTable2'));
  });

  test('Windows health rollback is based on CPE reachability', () {
    final helper = readHelper();

    expect(helper, contains('if (!l1)'));
    expect(helper, contains('CPE health failed, half-route rollback completed'));
  });
}
