import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String readHelper() =>
      File('macos/Helper/sdwan_macos_helper.c').readAsStringSync();

  test('macOS helper reads traffic only from the CPE egress interface', () {
    final helper = readHelper();

    expect(helper, contains('default_interface_for_cpe'));
    expect(helper, contains('/sbin/route -n get %s'));
    expect(helper, contains('read_traffic_counters(config->ifname'));
  });

  test(
    'macOS helper enriches domains and avoids target-as-via duplication',
    () {
      final helper = readHelper();

      expect(helper, contains('domain_for_target'));
      expect(helper, contains('/usr/bin/dscacheutil -q host -a ip_address'));
      expect(helper, isNot(contains('|domain=|via=%s')));
    },
  );
}
