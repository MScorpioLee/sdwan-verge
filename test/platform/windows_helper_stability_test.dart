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

  test('Windows helper keeps route and connection diagnostics IPv4 only', () {
    final helper = readHelper();

    expect(helper, contains('route print -4'));
    expect(helper, contains('IsIpv4Endpoint'));
    expect(helper, contains('if (!IsIpv4Endpoint(source)'));
    expect(helper, isNot(contains('tcpv6')));
    expect(helper, isNot(contains('udpv6')));
  });

  test('Windows helper excludes LAN targets from connection diagnostics', () {
    final helper = readHelper();

    expect(helper, contains('IsPublicIpv4Endpoint'));
    expect(helper, contains('if (!IsPublicIpv4Endpoint(target))'));
  });

  test('Windows helper prefers IPv4 while acceleration is running', () {
    final helper = readHelper();

    expect(helper, contains('netsh interface ipv6 show prefixpolicies'));
    expect(
      helper,
      contains('netsh interface ipv6 set prefixpolicy ::ffff:0:0/96 60 4'),
    );
    expect(helper, contains('RestoreIpv6PrefixPolicy'));
    final startIndex = helper.indexOf('bool StartAcceleration');
    final startAcceleration = helper.substring(
      startIndex,
      helper.indexOf('void StopAcceleration', startIndex),
    );
    expect(
      startAcceleration.indexOf('PreferIpv4PrefixPolicy();'),
      lessThan(startAcceleration.indexOf('ConfigureHalfRoutes(cpe')),
    );
  });

  test('Windows helper enriches connection domains from DNS cache', () {
    final helper = readHelper();

    expect(helper, contains('ipconfig /displaydns'));
    expect(helper, contains('DnsCacheDomainsByIp'));
    expect(helper, contains('DomainForTarget'));
    expect(helper, contains('|domain=" << domain'));
  });

  test('Windows helper keeps SDK headers in a warning-clean order', () {
    final helper = readHelper();

    expect(helper, isNot(contains('#define UNICODE')));
    expect(
      helper.indexOf('#include <iphlpapi.h>'),
      lessThan(helper.indexOf('#include <icmpapi.h>')),
    );
  });

  test('Windows helper treats missing service as install-needed state', () {
    final helper = readHelper();

    expect(helper, contains('permission=needsHelperInstall'));
    expect(helper, contains('helperInstalled=false'));
    expect(
      helper,
      isNot(contains('Windows helper service is not installed or not running')),
    );
  });

  test('Windows service pipe is accessible from the desktop app', () {
    final helper = readHelper();

    expect(
      helper,
      contains('ConvertStringSecurityDescriptorToSecurityDescriptorW'),
    );
    expect(helper, contains('A;;GA;;;IU'));
    expect(helper, contains('CreateNamedPipeW'));
  });

  test(
    'Windows install refreshes existing service and waits for pipe readiness',
    () {
      final helper = readHelper();

      expect(helper, contains('StopServiceIfRunning'));
      expect(helper, contains('StartServiceAndWait'));
      expect(helper, contains('WaitForPipeReady'));
    },
  );

  test('Windows health rollback is based on CPE reachability', () {
    final helper = readHelper();

    expect(helper, contains('if (!l1)'));
    expect(
      helper,
      contains('CPE health failed, half-route rollback completed'),
    );
  });
}
