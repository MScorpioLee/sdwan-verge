import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String readHelper() =>
      File('macos/Helper/sdwan_macos_helper.c').readAsStringSync();
  String readAppDelegate() =>
      File('macos/Runner/AppDelegate.swift').readAsStringSync();

  test('macOS helper uses IPv4 TUN stability settings', () {
    final helper = readHelper();

    expect(helper, contains('#define TUN_MTU 1400'));
    expect(helper, contains('#define TCP_MSS_CLAMP 1360'));
    expect(helper, contains('#define NAT_PORT_START 30000'));
    expect(helper, contains('#define NAT_PORT_END 48999'));
    expect(helper, contains('#define MAX_NAT 16384'));
  });

  test('macOS helper exposes NAT capacity diagnostics', () {
    final helper = readHelper();
    final appDelegate = readAppDelegate();

    expect(helper, contains('nat_active='));
    expect(helper, contains('nat_capacity='));
    expect(
      appDelegate,
      contains('"natActive": intFromPair(pairs["nat_active"])'),
    );
    expect(
      appDelegate,
      contains('"natCapacity": intFromPair(pairs["nat_capacity"])'),
    );
  });

  test('macOS NAT recycles short-lived TCP flows under connection pressure', () {
    final helper = readHelper();

    expect(helper, contains('#define TCP_SYN_TIMEOUT_SEC 20'));
    expect(helper, contains('#define TCP_CLOSING_TIMEOUT_SEC 5'));
    expect(helper, contains('static bool tcp_should_close'));
    expect(helper, contains('nat_reap_expired'));
    expect(helper, contains('nat_active_count'));
    expect(helper, contains('nat_clear(&g_runtime.nat)'));
    expect(helper, contains('entry->tcp_established'));
    expect(helper, contains('entry->closing'));
    expect(
      helper,
      contains(
        'nat_allocate_port(NatTable *table, uint8_t proto, uint16_t original_port, uint32_t remote_ip,',
      ),
    );
    expect(helper, contains('tcp nat closing reap failed'));
    expect(helper, contains('nat port reuse by remote tuple failed'));
  });
}
