import 'dart:async';

import 'package:flutter/foundation.dart';

import 'traffic_history_store.dart';
import 'tun_models.dart';
import 'tun_service.dart';

class TunController extends ChangeNotifier {
  TunController({
    required TunService service,
    TrafficHistoryStore? trafficHistoryStore,
    bool retainTrafficHistory = false,
    this.failureThreshold = 3,
    this.pollInterval = const Duration(seconds: 5),
    this.startTimeout = const Duration(seconds: 8),
  }) : _service = service,
       _trafficHistoryStore = trafficHistoryStore,
       _retainTrafficHistory = retainTrafficHistory;

  final TunService _service;
  final TrafficHistoryStore? _trafficHistoryStore;
  final int failureThreshold;
  final Duration pollInterval;
  final Duration startTimeout;

  TunStatus _status = TunStatus.defaults();
  List<TunEventLog> _logs = const [];
  List<TunConnection> _connections = const [];
  Timer? _healthTimer;
  var _busy = false;
  var _consecutiveFailures = 0;
  final List<TrafficSample> _trafficSamples = [];
  var _retainTrafficHistory = false;
  var _trafficHistoryPrepared = false;
  var _trafficBaselineCaptured = false;
  var _trafficBaselineTxBytes = 0;
  var _trafficBaselineRxBytes = 0;
  var _launchAtLogin = false;

  TunStatus get status => _status;
  List<TunEventLog> get logs => _logs;
  List<TunConnection> get connections => _connections;
  List<TrafficSample> get trafficSamples => List.unmodifiable(_trafficSamples);
  bool get retainTrafficHistory => _retainTrafficHistory;
  bool get launchAtLogin => _launchAtLogin;
  bool get busy => _busy;

  Future<void> initialize() async {
    await _runBusy(() async {
      await _prepareTrafficHistory();
      _status = _withDisplayTraffic(await _service.status());
      _recordTrafficSample(_status.traffic);
      _syncPollingWithState();
    });
  }

  Future<void> refreshLaunchAtLogin() async {
    _launchAtLogin = await _service.launchAtLoginEnabled();
    notifyListeners();
  }

  Future<void> setLaunchAtLogin(bool enabled) async {
    _launchAtLogin = await _service.setLaunchAtLogin(enabled);
    notifyListeners();
  }

  Future<void> setRetainTrafficHistory(bool retain) async {
    _retainTrafficHistory = retain;
    _trafficHistoryPrepared = true;
    if (!retain) {
      _trafficSamples.clear();
      _trafficBaselineCaptured = false;
      await _trafficHistoryStore?.clear();
    } else {
      _trafficBaselineCaptured = false;
      await _trafficHistoryStore?.save(_trafficSamples);
    }
    notifyListeners();
  }

  Future<void> updateCpeHost(String host) async {
    final cpeHost = host.trim();
    if (cpeHost.isEmpty) {
      return;
    }
    await _runBusy(() async {
      _service.updateCpeHost(cpeHost);
      _connections = const [];
      final health = await _service.healthCheck();
      final refreshed = _withDisplayTraffic(await _service.status());
      _status = refreshed.copyWith(cpe: health);
      _recordTrafficSample(_status.traffic);
      _syncPollingWithState();
    });
  }

  Future<void> start() async {
    await _runBusy(() async {
      _status = _status.copyWith(state: TunState.starting, lastError: null);
      notifyListeners();

      final health = await _service.healthCheck();
      if (!health.reachable) {
        _consecutiveFailures = failureThreshold;
        _status = _status.copyWith(
          state: TunState.failed,
          cpe: health,
          lastError: health.error ?? 'CPE 连接失败，未启动 TUN',
        );
        _stopPolling();
        return;
      }

      _consecutiveFailures = 0;
      if (!_status.helperInstalled) {
        _status = await _service.installHelper();
        if (!_status.helperInstalled) {
          _status = _status.copyWith(
            state: TunState.failed,
            cpe: health,
            lastError: _status.lastError ?? '虚拟网卡助手未安装，无法开启加速',
          );
          _stopPolling();
          return;
        }
      }
      final started = await _service.start().timeout(
        startTimeout,
        onTimeout: () => TunStatus.defaults(cpeHost: health.host).copyWith(
          state: TunState.failed,
          permission: _status.permission,
          cpe: health,
          helperInstalled: _status.helperInstalled,
          lastError: 'TUN 启动超时，请先停止或卸载助手后重试',
        ),
      );
      if (started.state == TunState.failed) {
        _status = started.copyWith(cpe: health);
        _recordTrafficSample(_status.traffic);
        _stopPolling();
        return;
      }
      _status = started.copyWith(cpe: health, lastError: null);
      final refreshed = _withDisplayTraffic(await _service.status());
      if (refreshed.state == TunState.running) {
        _status = refreshed;
      } else {
        _status = refreshed.copyWith(
          state: TunState.failed,
          cpe: health,
          lastError: refreshed.lastError ?? 'TUN 未进入运行状态，请查看日志',
        );
      }
      _recordTrafficSample(_status.traffic);
      _syncPollingWithState();
    });
  }

  Future<void> stop() async {
    await _runBusy(() async {
      _status = _status.copyWith(state: TunState.stopping, lastError: null);
      notifyListeners();

      await _service.stop();
      _status = _withDisplayTraffic(await _service.status());
      _recordTrafficSample(_status.traffic);
      _consecutiveFailures = 0;
      _stopPolling();
    });
  }

  Future<void> refreshLogs({int limit = 80}) async {
    _logs = await _service.logs(limit: limit);
    notifyListeners();
  }

  Future<void> refreshConnections({int limit = 80}) async {
    _connections = await _service.connections(limit: limit);
    notifyListeners();
  }

  Future<void> installHelper() async {
    await _runBusy(() async {
      _status = await _service.installHelper();
      _recordTrafficSample(_status.traffic);
      _syncPollingWithState();
    });
  }

  Future<void> uninstallHelper() async {
    await _runBusy(() async {
      _status = await _service.uninstallHelper();
      _connections = const [];
      _recordTrafficSample(_status.traffic);
      _syncPollingWithState();
    });
  }

  Future<void> checkHealthOnce() async {
    if (_status.state != TunState.running) {
      return;
    }

    final health = await _service.healthCheck();
    if (health.reachable) {
      _consecutiveFailures = 0;
      _status = _withDisplayTraffic(await _service.status());
      _recordTrafficSample(_status.traffic);
      await refreshConnections();
      notifyListeners();
      return;
    }

    _consecutiveFailures += 1;
    _status = _status.copyWith(
      cpe: health,
      lastError: health.error ?? 'CPE 连接丢失',
    );

    if (_consecutiveFailures >= failureThreshold) {
      await _service.stop();
      _status = _status.copyWith(
        state: TunState.autoRecovered,
        cpe: health,
        lastError: health.error ?? 'CPE 连接丢失，已自动停止 TUN 并切回直连',
      );
      _recordTrafficSample(_status.traffic);
      _stopPolling();
    }

    notifyListeners();
  }

  void startHealthPolling() {
    _stopPolling();
    _healthTimer = Timer.periodic(pollInterval, (_) {
      unawaited(checkHealthOnce());
    });
  }

  void _syncPollingWithState() {
    if (_status.state == TunState.running) {
      startHealthPolling();
    } else {
      _stopPolling();
    }
  }

  void _stopPolling() {
    _healthTimer?.cancel();
    _healthTimer = null;
  }

  void _recordTrafficSample(TrafficStats traffic) {
    _trafficSamples.add(
      TrafficSample(
        at: DateTime.now(),
        txRate: traffic.txRate,
        rxRate: traffic.rxRate,
      ),
    );
    if (_trafficSamples.length > 120) {
      _trafficSamples.removeRange(0, _trafficSamples.length - 120);
    }
    final store = _trafficHistoryStore;
    if (_retainTrafficHistory && store != null) {
      unawaited(store.save(_trafficSamples));
    }
  }

  TunStatus _withDisplayTraffic(TunStatus status) {
    if (_retainTrafficHistory) {
      return status;
    }
    if (!_trafficBaselineCaptured) {
      _trafficBaselineTxBytes = status.traffic.txBytes;
      _trafficBaselineRxBytes = status.traffic.rxBytes;
      _trafficBaselineCaptured = true;
    }
    final txBytes = status.traffic.txBytes - _trafficBaselineTxBytes;
    final rxBytes = status.traffic.rxBytes - _trafficBaselineRxBytes;
    return status.copyWith(
      traffic: TrafficStats(
        txBytes: txBytes < 0 ? 0 : txBytes,
        rxBytes: rxBytes < 0 ? 0 : rxBytes,
        txRate: status.traffic.txRate,
        rxRate: status.traffic.rxRate,
      ),
    );
  }

  Future<void> _prepareTrafficHistory() async {
    if (_trafficHistoryPrepared) {
      return;
    }
    _trafficHistoryPrepared = true;
    final store = _trafficHistoryStore;
    if (store == null) {
      return;
    }
    if (!_retainTrafficHistory) {
      _trafficSamples.clear();
      await store.clear();
      return;
    }
    _trafficSamples
      ..clear()
      ..addAll(await store.load());
    if (_trafficSamples.length > 120) {
      _trafficSamples.removeRange(0, _trafficSamples.length - 120);
    }
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    _busy = true;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      _status = _status.copyWith(
        state: TunState.failed,
        lastError: error.toString(),
      );
      _stopPolling();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }
}
