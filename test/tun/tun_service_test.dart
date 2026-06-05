import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/tun/tun_models.dart';
import 'package:sdwan_client/tun/tun_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'test/tun';
  const channel = MethodChannel(channelName);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('maps native status response into TUN status', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'status');
          return {
            'state': 'running',
            'adapterName': 'Windows Half Route',
            'permission': 'ready',
            'helperInstalled': true,
            'txBytes': 1024,
            'rxBytes': 2048,
            'txRate': 128,
            'rxRate': 256,
            'txPackets': 10,
            'rxPackets': 8,
            'txDropped': 2,
            'rxDropped': 3,
            'natMisses': 4,
            'sendFailures': 5,
            'udp443Packets': 6,
            'cpe': {
              'host': '192.168.1.140',
              'reachable': true,
              'serviceReady': true,
            },
          };
        });
    final service = MethodChannelTunService(channel: channel);

    final status = await service.status();

    expect(status.state, TunState.running);
    expect(status.adapterName, 'Windows Half Route');
    expect(status.permission, TunPermission.ready);
    expect(status.helperInstalled, isTrue);
    expect(status.cpe.reachable, isTrue);
    expect(status.cpe.serviceReady, isTrue);
    expect(status.traffic.txBytes, 1024);
    expect(status.traffic.rxBytes, 2048);
    expect(status.traffic.txRate, 128);
    expect(status.traffic.rxRate, 256);
    expect(status.diagnostics.txPackets, 10);
    expect(status.diagnostics.rxPackets, 8);
    expect(status.diagnostics.txDropped, 2);
    expect(status.diagnostics.rxDropped, 3);
    expect(status.diagnostics.natMisses, 4);
    expect(status.diagnostics.sendFailures, 5);
    expect(status.diagnostics.udp443Packets, 6);
  });

  test('sends updated CPE host with native calls', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'healthCheck');
          expect(call.arguments, {'cpeHost': '192.168.1.150'});
          return {
            'host': '192.168.1.150',
            'reachable': true,
            'serviceReady': true,
          };
        });
    final service = MethodChannelTunService(channel: channel);

    service.updateCpeHost('192.168.1.150');
    final health = await service.healthCheck();

    expect(health.host, '192.168.1.150');
    expect(health.reachable, isTrue);
  });

  test('treats stale auto recovery as stopped when CPE is healthy', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'status');
          return {
            'state': 'autoRecovered',
            'permission': 'ready',
            'helperInstalled': true,
            'lastError': 'CPE 异常，已自动回切直连',
            'cpe': {
              'host': '192.168.1.140',
              'reachable': true,
              'serviceReady': true,
            },
          };
        });
    final service = MethodChannelTunService(channel: channel);

    final status = await service.status();

    expect(status.state, TunState.stopped);
    expect(status.lastError, isNull);
    expect(status.cpe.serviceReady, isTrue);
  });

  test('maps native connections response into connection list', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'connections');
          expect(call.arguments, {'limit': 1, 'cpeHost': '192.168.1.140'});
          return [
            {
              'lastSeen': '1717473607',
              'proto': 'TCP',
              'source': '10.255.0.2:50000',
              'target': '93.184.216.34:443',
              'domain': 'example.com',
              'via': '93.184.216.34:443',
              'txBytes': 120,
              'rxBytes': 240,
              'txRate': 11,
              'rxRate': 22,
              'dnsRedirect': false,
            },
          ];
        });
    final service = MethodChannelTunService(channel: channel);

    final connections = await service.connections(limit: 1);

    expect(connections, hasLength(1));
    expect(connections.first.proto, 'TCP');
    expect(connections.first.target, '93.184.216.34:443');
    expect(connections.first.domain, 'example.com');
    expect(connections.first.txBytes, 120);
    expect(connections.first.txRate, 11);
    expect(connections.first.rxRate, 22);
  });

  test('filters IPv6 connections from native response', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'connections');
          return [
            {
              'lastSeen': '1717473607',
              'proto': 'TCP',
              'source': '10.255.0.2:50000',
              'target': '93.184.216.34:443',
              'via': '93.184.216.34:443',
            },
            {
              'lastSeen': '1717473608',
              'proto': 'TCP',
              'source': '[2400:3200::1]:50000',
              'target': '[2606:4700:4700::1111]:443',
              'via': '[2606:4700:4700::1111]:443',
            },
            {
              'lastSeen': '1717473609',
              'proto': 'UDP',
              'source': 'fe80::1.5353',
              'target': 'ff02::fb.5353',
              'via': 'ff02::fb.5353',
            },
          ];
        });
    final service = MethodChannelTunService(channel: channel);

    final connections = await service.connections(limit: 80);

    expect(connections, hasLength(1));
    expect(connections.single.target, '93.184.216.34:443');
  });

  test('filters LAN target connections from native response', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'connections');
          return [
            {
              'lastSeen': '1717473607',
              'proto': 'TCP',
              'source': '192.168.1.25:50000',
              'target': '93.184.216.34:443',
              'via': '93.184.216.34:443',
            },
            {
              'lastSeen': '1717473608',
              'proto': 'TCP',
              'source': '192.168.1.25:50001',
              'target': '192.168.1.140:443',
              'via': '192.168.1.140:443',
            },
            {
              'lastSeen': '1717473609',
              'proto': 'UDP',
              'source': '192.168.1.25:50002',
              'target': '10.0.0.5:53',
              'via': '10.0.0.5:53',
            },
          ];
        });
    final service = MethodChannelTunService(channel: channel);

    final connections = await service.connections(limit: 80);

    expect(connections, hasLength(1));
    expect(connections.single.target, '93.184.216.34:443');
  });

  test('maps native logs response into event timeline', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'logs');
          expect(call.arguments, {'limit': 2, 'cpeHost': '192.168.1.140'});
          return [
            {'time': '2026-06-04 12:00:00', 'message': '开启半路由'},
            {'time': '', 'message': ''},
            {'time': '2026-06-04 12:00:03', 'message': ''},
            {'time': '2026-06-04 12:00:05', 'message': '自动回退'},
          ];
        });
    final service = MethodChannelTunService(channel: channel);

    final logs = await service.logs(limit: 2);

    expect(logs, hasLength(2));
    expect(logs.first.time, '2026-06-04 12:00:00');
    expect(logs.first.message, '开启半路由');
    expect(logs.last.message, '自动回退');
  });

  test('maps native launch-at-login status and update calls', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'launchAtLoginStatus') {
            expect(call.arguments, {'cpeHost': '192.168.1.140'});
            return true;
          }
          if (call.method == 'setLaunchAtLogin') {
            expect(call.arguments, {
              'enabled': false,
              'cpeHost': '192.168.1.140',
            });
            return false;
          }
          fail('unexpected method ${call.method}');
        });
    final service = MethodChannelTunService(channel: channel);

    expect(await service.launchAtLoginEnabled(), isTrue);
    expect(await service.setLaunchAtLogin(false), isFalse);
    expect(calls, ['launchAtLoginStatus', 'setLaunchAtLogin']);
  });

  test(
    'probes latency targets through native channel when available',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'probeLatency');
            expect(call.arguments, {
              'id': 'cloudflare',
              'name': 'Cloudflare',
              'url': 'http://cp.cloudflare.com/generate_204',
              'timeoutMs': 5000,
              'cpeHost': '192.168.1.140',
            });
            return {
              'status': 'success',
              'latencyMs': 123,
              'checkedAt': '2026-06-04T12:00:00.000',
            };
          });
      final service = MethodChannelTunService(channel: channel);

      final result = await service.probeLatency(LatencyTarget.defaults.first);

      expect(result.status, LatencyProbeStatus.success);
      expect(result.latencyMs, 123);
    },
  );

  test(
    'missing native channel reports unsupported instead of success',
    () async {
      final service = MethodChannelTunService(channel: channel);

      final status = await service.status();

      expect(status.permission, TunPermission.unsupported);
      expect(status.lastError, contains('TUN'));
    },
  );
}
