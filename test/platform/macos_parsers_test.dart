import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/domain/network_status.dart';
import 'package:sdwan_client/platform/macos/macos_parsers.dart';

void main() {
  test('parses default interface from route get output', () {
    const output = '''
   route to: default
destination: default
       mask: default
    gateway: 192.168.1.1
  interface: en0
''';

    expect(MacosParsers.defaultInterface(output), 'en0');
  });

  test('maps hardware device to network service name', () {
    const output = '''
Hardware Port: Wi-Fi
Device: en0
Ethernet Address: 00:11:22:33:44:55

Hardware Port: USB 10/100/1000 LAN
Device: en7
Ethernet Address: 66:77:88:99:aa:bb
''';

    expect(MacosParsers.serviceNameForDevice(output, 'en0'), 'Wi-Fi');
    expect(MacosParsers.serviceNameForDevice(output, 'en7'), 'USB 10/100/1000 LAN');
  });

  test('parses static and dhcp dns output', () {
    final staticDns = MacosParsers.dnsInfo('223.5.5.5\n114.114.114.114\n');
    final dhcpDns = MacosParsers.dnsInfo(
      'There aren\'t any DNS Servers set on Wi-Fi.\n',
    );

    expect(staticDns.mode, DnsMode.static);
    expect(staticDns.servers, ['223.5.5.5', '114.114.114.114']);
    expect(dhcpDns.mode, DnsMode.dhcp);
    expect(dhcpDns.servers, isEmpty);
  });

  test('detects half routes in netstat output', () {
    const output = '''
Destination        Gateway            Flags
default            192.168.1.1        UGSc
0/1                192.168.1.140      UGSc
128.0/1            192.168.1.140      UGSc
''';

    expect(MacosParsers.hasAccelerationRoutes(output, '192.168.1.140'), isTrue);
    expect(MacosParsers.hasAccelerationRoutes(output, '192.168.1.99'), isFalse);
  });
}
