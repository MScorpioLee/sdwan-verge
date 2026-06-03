import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/domain/network_status.dart';
import 'package:sdwan_client/platform/linux/linux_parsers.dart';

void main() {
  test('parses default route interface and source ip', () {
    const output = '''
1.1.1.1 via 192.168.1.1 dev eth0 src 192.168.1.88 uid 501
    cache
''';

    final info = LinuxParsers.defaultRouteInfo(output);

    expect(info.interfaceName, 'eth0');
    expect(info.sourceIp, '192.168.1.88');
  });

  test('parses resolvectl dns output for an interface', () {
    const output = '''
Global:
Link 2 (eth0)
    Current Scopes: DNS
         DNS Servers: 223.5.5.5 114.114.114.114
Link 3 (wlan0)
         DNS Servers: 8.8.8.8
''';

    final dns = LinuxParsers.dnsInfo(output, 'eth0');

    expect(dns.mode, DnsMode.static);
    expect(dns.servers, ['223.5.5.5', '114.114.114.114']);
  });

  test('detects half routes in ip route output', () {
    const output = '''
default via 192.168.1.1 dev eth0 proto dhcp
0.0.0.0/1 via 192.168.1.140 dev eth0
128.0.0.0/1 via 192.168.1.140 dev eth0
''';

    expect(LinuxParsers.hasAccelerationRoutes(output, '192.168.1.140'), isTrue);
    expect(LinuxParsers.hasAccelerationRoutes(output, '192.168.1.99'), isFalse);
  });
}
