import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String readHelper() =>
      File('windows/helper/sdwan_windows_helper.cpp').readAsStringSync();

  test('Windows helper uses IPv4-only TUN stability settings', () {
    final helper = readHelper();

    expect(helper, contains('constexpr int kTunMtu = 1400;'));
    expect(helper, contains('constexpr uint16_t kTcpMssClamp = 1360;'));
    expect(helper, contains('constexpr uint16_t kNatPortStart = 30000;'));
    expect(helper, contains('constexpr uint16_t kNatPortEnd = 48999;'));
    expect(helper, contains('constexpr size_t kMaxNat = 16384;'));
    expect(helper, contains('netsh interface ipv4 set subinterface'));
    expect(helper, contains('mtu=1400'));
    expect(helper, contains('ClampTcpMss'));
    expect(helper, contains('IsIpv4Packet'));
  });

  test(
    'Windows helper starts packet loops before installing capture routes',
    () {
      final helper = readHelper();

      expect(
        helper.indexOf('std::thread(TunReadLoop'),
        lessThan(helper.indexOf('if (!ConfigureWintunRoutes')),
      );
      expect(helper, contains('ConfigureWintunAddress'));
      expect(helper, contains('ConfigureWintunRoutes'));
    },
  );

  test('Windows helper exposes data plane diagnostic counters', () {
    final helper = readHelper();

    expect(helper, contains('txDropped='));
    expect(helper, contains('rxDropped='));
    expect(helper, contains('natMisses='));
    expect(helper, contains('sendFailures='));
    expect(helper, contains('udp443Packets='));
    expect(helper, contains('natActive='));
    expect(helper, contains('natCapacity='));
  });

  test('Windows health rollback is based on CPE reachability', () {
    final helper = readHelper();

    expect(helper, contains('if (!l1)'));
    expect(helper, contains('CPE reachable but L3 probe failed'));
  });

  test('Windows return filter and NAT include ICMP echo replies', () {
    final helper = readHelper();

    expect(helper, contains('icmp and icmp.Type == 0'));
    expect(
      helper,
      contains(
        'const uint16_t local_port = proto == IPPROTO_ICMP ? src_port : dst_port;',
      ),
    );
    expect(helper, contains('icmp nat restore failed'));
  });

  test(
    'Windows NAT recycles short-lived TCP flows under connection pressure',
    () {
      final helper = readHelper();

      expect(helper, contains('constexpr int kTcpSynTimeoutSeconds = 20;'));
      expect(helper, contains('constexpr int kTcpClosingTimeoutSeconds = 5;'));
      expect(helper, contains('bool TcpShouldClose'));
      expect(helper, contains('NatReapExpired'));
      expect(helper, contains('NatClear(&g_runtime.nat)'));
      expect(helper, contains('NatActiveCount'));
      expect(helper, contains('entry->tcp_established'));
      expect(helper, contains('entry->closing'));
      expect(
        helper,
        contains(
          'NatAllocatePort(NatTable* table, uint8_t proto, uint16_t original_port, uint32_t remote_ip,',
        ),
      );
      expect(helper, contains('tcp nat closing reap failed'));
      expect(helper, contains('nat port reuse by remote tuple failed'));
    },
  );
}
