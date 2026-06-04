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
    expect(status.cpe.reachable, isTrue);
    expect(status.cpe.serviceReady, isTrue);
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
