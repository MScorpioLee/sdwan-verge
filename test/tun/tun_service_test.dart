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
            'permission': 'ready',
            'helperInstalled': true,
            'txBytes': 1024,
            'rxBytes': 2048,
            'txRate': 128,
            'rxRate': 256,
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
    expect(status.permission, TunPermission.ready);
    expect(status.helperInstalled, isTrue);
    expect(status.cpe.reachable, isTrue);
    expect(status.cpe.serviceReady, isTrue);
    expect(status.traffic.txBytes, 1024);
    expect(status.traffic.rxBytes, 2048);
    expect(status.traffic.txRate, 128);
    expect(status.traffic.rxRate, 256);
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

  test('maps native logs response into event timeline', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'logs');
          expect(call.arguments, {'limit': 2, 'cpeHost': '192.168.1.140'});
          return [
            {'time': '2026-06-04 12:00:00', 'message': '开启 TUN'},
            {'time': '2026-06-04 12:00:05', 'message': '自动回退'},
          ];
        });
    final service = MethodChannelTunService(channel: channel);

    final logs = await service.logs(limit: 2);

    expect(logs, hasLength(2));
    expect(logs.first.time, '2026-06-04 12:00:00');
    expect(logs.first.message, '开启 TUN');
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
    'missing native channel reports unsupported instead of success',
    () async {
      final service = MethodChannelTunService(channel: channel);

      final status = await service.status();

      expect(status.permission, TunPermission.unsupported);
      expect(status.lastError, contains('TUN'));
    },
  );
}
