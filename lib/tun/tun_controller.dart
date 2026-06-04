import 'dart:async';

import 'package:flutter/foundation.dart';

import 'tun_models.dart';
import 'tun_service.dart';

class TunController extends ChangeNotifier {
  TunController({
    required TunService service,
    this.failureThreshold = 3,
    this.pollInterval = const Duration(seconds: 5),
  }) : _service = service;

  final TunService _service;
  final int failureThreshold;
  final Duration pollInterval;

  TunStatus _status = TunStatus.defaults();
  Timer? _healthTimer;
  var _busy = false;
  var _consecutiveFailures = 0;

  TunStatus get status => _status;
  bool get busy => _busy;

  Future<void> initialize() async {
    await _runBusy(() async {
      _status = await _service.status();
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
      _status = (await _service.start()).copyWith(cpe: health, lastError: null);
      _status = await _service.status();
      _syncPollingWithState();
    });
  }

  Future<void> stop() async {
    await _runBusy(() async {
      _status = _status.copyWith(state: TunState.stopping, lastError: null);
      notifyListeners();

      await _service.stop();
      _status = await _service.status();
      _consecutiveFailures = 0;
      _stopPolling();
    });
  }

  Future<void> checkHealthOnce() async {
    if (_status.state != TunState.running) {
      return;
    }

    final health = await _service.healthCheck();
    if (health.reachable) {
      _consecutiveFailures = 0;
      _status = _status.copyWith(cpe: health, lastError: null);
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
