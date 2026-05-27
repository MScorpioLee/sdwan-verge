import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/domain/network_status.dart';
import 'package:sdwan_client/platform/windows/windows_parsers.dart';

void main() {
  const routePrint = '''
IPv4 Route Table
===========================================================================
Active Routes:
Network Destination        Netmask          Gateway       Interface  Metric
          0.0.0.0          0.0.0.0    192.168.1.1   192.168.1.88     25
          0.0.0.0        128.0.0.0  192.168.1.140   192.168.1.88     26
        128.0.0.0        128.0.0.0  192.168.1.140   192.168.1.88     26
''';

  const netshConfig = '''
Configuration for interface "Ethernet"
    DHCP enabled:                         Yes
    IP Address:                           192.168.1.88

Configuration for interface "Wi-Fi"
    DHCP enabled:                         Yes
    IP Address:                           10.0.0.12
''';

  test('finds active interface IP from default route', () {
    expect(WindowsParsers.defaultRouteInterfaceIp(routePrint), '192.168.1.88');
  });

  test('detects acceleration routes for profile CPE', () {
    expect(
      WindowsParsers.hasAccelerationRoutes(routePrint, '192.168.1.140'),
      isTrue,
    );
    expect(
      WindowsParsers.hasAccelerationRoutes(routePrint, '192.168.1.200'),
      isFalse,
    );
  });

  test('finds interface name by IP from netsh config', () {
    expect(
      WindowsParsers.interfaceNameForIp(netshConfig, '192.168.1.88'),
      'Ethernet',
    );
  });

  test('parses DHCP DNS mode', () {
    const output = '''
Configuration for interface "Ethernet"
    DNS servers configured through DHCP:  192.168.1.1
''';

    final parsed = WindowsParsers.dnsInfo(output);

    expect(parsed.mode, DnsMode.dhcp);
    expect(parsed.servers, ['192.168.1.1']);
  });

  test('parses static DNS servers', () {
    const output = '''
Configuration for interface "Ethernet"
    Statically Configured DNS Servers:    223.5.5.5
                                           114.114.114.114
''';

    final parsed = WindowsParsers.dnsInfo(output);

    expect(parsed.mode, DnsMode.static);
    expect(parsed.servers, ['223.5.5.5', '114.114.114.114']);
  });
}
