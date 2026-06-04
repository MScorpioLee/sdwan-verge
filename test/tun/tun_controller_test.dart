import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/tun/tun_controller.dart';
import 'package:sdwan_client/tun/tun_models.dart';
import 'package:sdwan_client/tun/tun_service.dart';

class FakeTunService implements TunService {
  FakeTunService({
    this.health = const CpeHealth(
      host: '192.168.1.140',
      reachable: true,
      serviceReady: true,
    ),
    List<CpeHealth>? healthSequence,
    this.currentStatus,
  }) : healthSequence = List<CpeHealth>.from(healthSequence ?? const []);

  final CpeHealth health;
  final List<CpeHealth> healthSequence;
  TunStatus? currentStatus;
  final calls = <String>[];

  @override
  Future<TunStatus> status() async {
    calls.add('status');
    return currentStatus ?? TunStatus.defaults();
  }

  @override
  Future<CpeHealth> healthCheck() async {
    calls.add('healthCheck');
    if (healthSequence.isNotEmpty) {
      return healthSequence.removeAt(0);
    }
    return health;
  }

  @override
  Future<TunStatus> start() async {
    calls.add('start');
    currentStatus = TunStatus.defaults().copyWith(
      state: TunState.running,
      permission: TunPermission.ready,
      cpe: health,
    );
    return currentStatus!;
  }

  @override
  Future<TunStatus> stop() async {
    calls.add('stop');
    currentStatus = TunStatus.defaults().copyWith(
      state: TunState.stopped,
      permission: TunPermission.ready,
    );
    return currentStatus!;
  }
}

void main() {
  test('start checks CPE before reporting running', () async {
    final service = FakeTunService();
    final controller = TunController(service: service);

    await controller.initialize();
    await controller.start();

    expect(service.calls, ['status', 'healthCheck', 'start', 'status']);
    expect(controller.status.state, TunState.running);
    expect(controller.status.cpe.reachable, isTrue);
  });

  test(
    'start fails without calling service start when CPE is unreachable',
    () async {
      final service = FakeTunService(
        health: const CpeHealth(host: '192.168.1.140', reachable: false),
      );
      final controller = TunController(service: service);

      await controller.initialize();
      await controller.start();

      expect(service.calls, ['status', 'healthCheck']);
      expect(controller.status.state, TunState.failed);
      expect(controller.status.lastError, contains('CPE'));
    },
  );

  test('stop delegates to service and refreshes status', () async {
    final service = FakeTunService(
      currentStatus: TunStatus.defaults().copyWith(state: TunState.running),
    );
    final controller = TunController(service: service);
    await controller.initialize();

    await controller.stop();

    expect(service.calls, ['status', 'stop', 'status']);
    expect(controller.status.state, TunState.stopped);
  });

  test('health monitor stops TUN after repeated CPE loss', () async {
    final service = FakeTunService(
      currentStatus: TunStatus.defaults().copyWith(
        state: TunState.running,
        permission: TunPermission.ready,
        cpe: const CpeHealth(
          host: '192.168.1.140',
          reachable: true,
          serviceReady: true,
        ),
      ),
      healthSequence: const [
        CpeHealth(host: '192.168.1.140', reachable: false),
        CpeHealth(host: '192.168.1.140', reachable: false),
        CpeHealth(host: '192.168.1.140', reachable: false),
      ],
    );
    final controller = TunController(service: service, failureThreshold: 3);
    await controller.initialize();

    await controller.checkHealthOnce();
    await controller.checkHealthOnce();
    await controller.checkHealthOnce();

    expect(service.calls, [
      'status',
      'healthCheck',
      'healthCheck',
      'healthCheck',
      'stop',
    ]);
    expect(controller.status.state, TunState.autoRecovered);
    expect(controller.status.cpe.reachable, isFalse);
    expect(controller.status.lastError, contains('CPE'));
  });
}
