import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/tun/tun_controller.dart';
import 'package:sdwan_client/tun/traffic_history_store.dart';
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
    this.hangStart = false,
  }) : healthSequence = List<CpeHealth>.from(healthSequence ?? const []);

  final CpeHealth health;
  final List<CpeHealth> healthSequence;
  final bool hangStart;
  String cpeHost = '192.168.1.140';
  bool launchAtLogin = false;
  TunStatus? currentStatus;
  final calls = <String>[];

  @override
  void updateCpeHost(String host) {
    calls.add('updateCpeHost:$host');
    cpeHost = host;
  }

  @override
  Future<TunStatus> status() async {
    calls.add('status');
    final status = currentStatus ?? TunStatus.defaults(cpeHost: cpeHost);
    return status.copyWith(cpe: status.cpe.copyWith(host: cpeHost));
  }

  @override
  Future<CpeHealth> healthCheck() async {
    calls.add('healthCheck');
    if (healthSequence.isNotEmpty) {
      final next = healthSequence.removeAt(0);
      return next.copyWith(host: cpeHost);
    }
    return health.copyWith(host: cpeHost);
  }

  @override
  Future<TunStatus> start() async {
    calls.add('start');
    if (hangStart) {
      return Completer<TunStatus>().future;
    }
    final helperInstalled = currentStatus?.helperInstalled ?? false;
    currentStatus = TunStatus.defaults(cpeHost: cpeHost).copyWith(
      state: TunState.running,
      permission: TunPermission.ready,
      helperInstalled: helperInstalled,
      cpe: health.copyWith(host: cpeHost),
    );
    return currentStatus!;
  }

  @override
  Future<TunStatus> stop() async {
    calls.add('stop');
    currentStatus = TunStatus.defaults(
      cpeHost: cpeHost,
    ).copyWith(state: TunState.stopped, permission: TunPermission.ready);
    return currentStatus!;
  }

  @override
  Future<List<TunEventLog>> logs({int limit = 80}) async {
    calls.add('logs');
    return const [];
  }

  @override
  Future<List<TunConnection>> connections({int limit = 80}) async {
    calls.add('connections');
    return const [];
  }

  @override
  Future<TunStatus> installHelper() async {
    calls.add('installHelper');
    currentStatus = TunStatus.defaults(
      cpeHost: cpeHost,
    ).copyWith(helperInstalled: true, permission: TunPermission.ready);
    return currentStatus!;
  }

  @override
  Future<TunStatus> uninstallHelper() async {
    calls.add('uninstallHelper');
    currentStatus = TunStatus.defaults(
      cpeHost: cpeHost,
    ).copyWith(helperInstalled: false, permission: TunPermission.ready);
    return currentStatus!;
  }

  @override
  Future<bool> launchAtLoginEnabled() async {
    calls.add('launchAtLoginEnabled');
    return launchAtLogin;
  }

  @override
  Future<bool> setLaunchAtLogin(bool enabled) async {
    calls.add('setLaunchAtLogin:$enabled');
    launchAtLogin = enabled;
    return launchAtLogin;
  }
}

class MemoryTrafficHistoryStore implements TrafficHistoryStore {
  MemoryTrafficHistoryStore([List<TrafficSample>? samples])
    : samples = List<TrafficSample>.from(samples ?? const []);

  List<TrafficSample> samples;
  var cleared = false;

  @override
  Future<void> clear() async {
    cleared = true;
    samples = const [];
  }

  @override
  Future<List<TrafficSample>> load() async => samples;

  @override
  Future<void> save(List<TrafficSample> samples) async {
    this.samples = List<TrafficSample>.from(samples);
  }
}

void main() {
  test('start checks CPE before reporting running', () async {
    final service = FakeTunService(
      currentStatus: TunStatus.defaults().copyWith(helperInstalled: true),
    );
    final controller = TunController(service: service);

    await controller.initialize();
    await controller.start();

    expect(service.calls, ['status', 'healthCheck', 'start', 'status']);
    expect(controller.status.state, TunState.running);
    expect(controller.status.cpe.reachable, isTrue);
  });

  test(
    'start installs helper before starting when helper is missing',
    () async {
      final service = FakeTunService(
        currentStatus: TunStatus.defaults().copyWith(
          permission: TunPermission.ready,
          helperInstalled: false,
        ),
      );
      final controller = TunController(service: service);

      await controller.initialize();
      await controller.start();

      expect(service.calls, [
        'status',
        'healthCheck',
        'installHelper',
        'start',
        'status',
      ]);
      expect(controller.status.state, TunState.running);
    },
  );

  test('start times out instead of staying in starting forever', () async {
    final service = FakeTunService(
      currentStatus: TunStatus.defaults().copyWith(helperInstalled: true),
      hangStart: true,
    );
    final controller = TunController(
      service: service,
      startTimeout: const Duration(milliseconds: 20),
    );

    await controller.initialize();
    await controller.start();

    expect(service.calls, ['status', 'healthCheck', 'start']);
    expect(controller.busy, isFalse);
    expect(controller.status.state, TunState.failed);
    expect(controller.status.lastError, contains('启动超时'));
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

  test(
    'changing CPE host re-runs health and status with new address',
    () async {
      final service = FakeTunService(
        currentStatus: TunStatus.defaults().copyWith(
          permission: TunPermission.ready,
          helperInstalled: true,
        ),
      );
      final controller = TunController(service: service);
      await controller.initialize();

      await controller.updateCpeHost('192.168.1.150');

      expect(service.calls, [
        'status',
        'updateCpeHost:192.168.1.150',
        'healthCheck',
        'status',
      ]);
      expect(controller.status.cpe.host, '192.168.1.150');
      expect(controller.status.cpe.reachable, isTrue);
    },
  );

  test('records bandwidth samples when status is refreshed', () async {
    final service = FakeTunService(
      currentStatus: TunStatus.defaults().copyWith(
        traffic: const TrafficStats(txRate: 123, rxRate: 456),
      ),
    );
    final controller = TunController(service: service);

    await controller.initialize();

    expect(controller.trafficSamples, hasLength(1));
    expect(controller.trafficSamples.single.txRate, 123);
    expect(controller.trafficSamples.single.rxRate, 456);
  });

  test(
    'clears persisted traffic history on launch when retention is off',
    () async {
      final store = MemoryTrafficHistoryStore([
        TrafficSample(at: DateTime(2026), txRate: 1, rxRate: 2),
      ]);
      final service = FakeTunService(
        currentStatus: TunStatus.defaults().copyWith(
          traffic: const TrafficStats(
            txBytes: 1000,
            rxBytes: 2000,
            txRate: 123,
            rxRate: 456,
          ),
        ),
      );
      final controller = TunController(
        service: service,
        trafficHistoryStore: store,
        retainTrafficHistory: false,
      );

      await controller.initialize();

      expect(store.cleared, isTrue);
      expect(controller.trafficSamples, hasLength(1));
      expect(controller.trafficSamples.single.txRate, 123);
      expect(controller.status.traffic.txBytes, 0);
      expect(controller.status.traffic.rxBytes, 0);
      expect(store.samples, isEmpty);
    },
  );

  test(
    'restores persisted traffic history on launch when retention is on',
    () async {
      final oldSample = TrafficSample(at: DateTime(2026), txRate: 1, rxRate: 2);
      final store = MemoryTrafficHistoryStore([oldSample]);
      final service = FakeTunService(
        currentStatus: TunStatus.defaults().copyWith(
          traffic: const TrafficStats(
            txBytes: 1000,
            rxBytes: 2000,
            txRate: 123,
            rxRate: 456,
          ),
        ),
      );
      final controller = TunController(
        service: service,
        trafficHistoryStore: store,
        retainTrafficHistory: true,
      );

      await controller.initialize();

      expect(store.cleared, isFalse);
      expect(controller.trafficSamples.first, oldSample);
      expect(controller.trafficSamples.last.txRate, 123);
      expect(controller.status.traffic.txBytes, 1000);
      expect(controller.status.traffic.rxBytes, 2000);
      expect(store.samples, hasLength(2));
    },
  );

  test(
    'turning traffic history retention off clears current history',
    () async {
      final store = MemoryTrafficHistoryStore();
      final controller = TunController(
        service: FakeTunService(),
        trafficHistoryStore: store,
        retainTrafficHistory: true,
      );
      await controller.initialize();

      await controller.setRetainTrafficHistory(false);

      expect(store.cleared, isTrue);
      expect(controller.trafficSamples, isEmpty);
    },
  );

  test('refreshes and toggles launch-at-login preference', () async {
    final service = FakeTunService()..launchAtLogin = true;
    final controller = TunController(service: service);

    await controller.refreshLaunchAtLogin();

    expect(controller.launchAtLogin, isTrue);

    await controller.setLaunchAtLogin(false);

    expect(controller.launchAtLogin, isFalse);
    expect(service.calls, ['launchAtLoginEnabled', 'setLaunchAtLogin:false']);
  });
}
