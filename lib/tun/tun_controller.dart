import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'domain_resolver.dart';
import 'traffic_history_store.dart';
import 'tun_models.dart';
import 'tun_service.dart';

class TunController extends ChangeNotifier {
  TunController({
    required TunService service,
    TrafficHistoryStore? trafficHistoryStore,
    DomainResolver? domainResolver,
    LatencyProbeClient? latencyProbeClient,
    bool retainTrafficHistory = false,
    this.failureThreshold = 3,
    this.pollInterval = const Duration(seconds: 5),
    this.startTimeout = const Duration(seconds: 8),
  }) : _service = service,
       _domainResolver = domainResolver ?? const DefaultDomainResolver(),
       _latencyProbeClient =
           latencyProbeClient ?? _TunServiceLatencyProbeClient(service),
       _trafficHistoryStore = trafficHistoryStore,
       _retainTrafficHistory = retainTrafficHistory;

  final TunService _service;
  final DomainResolver _domainResolver;
  final LatencyProbeClient _latencyProbeClient;
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
  var _connectionSessionStartedAt = _epochSeconds();
  final Map<String, _ConnectionBaseline> _connectionBaselines = {};
  final Map<String, String> _domainCache = {};
  final Set<String> _domainLookupsInFlight = {};
  final List<LatencyTarget> _latencyTargets = LatencyTarget.defaults;
  List<LatencyProbeResult> _latencyResults = [
    for (final target in LatencyTarget.defaults)
      LatencyProbeResult.idle(target: target),
  ];
  var _latencyTesting = false;

  TunStatus get status => _status;
  List<TunEventLog> get logs => _logs;
  List<TunConnection> get connections => _connections;
  List<TrafficSample> get trafficSamples => List.unmodifiable(_trafficSamples);
  List<LatencyTarget> get latencyTargets => List.unmodifiable(_latencyTargets);
  List<LatencyProbeResult> get latencyResults =>
      List.unmodifiable(_latencyResults);
  bool get retainTrafficHistory => _retainTrafficHistory;
  bool get launchAtLogin => _launchAtLogin;
  bool get busy => _busy;
  bool get latencyTesting => _latencyTesting;

  Future<void> initialize() async {
    await _runBusy(() async {
      await _prepareTrafficHistory();
      if (!_retainTrafficHistory) {
        _resetConnectionSession();
      }
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
      _resetConnectionSession();
      await _trafficHistoryStore?.clear();
    } else {
      _trafficBaselineCaptured = false;
      _connectionBaselines.clear();
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
      final wasRunning = _status.state == TunState.running;
      _service.updateCpeHost(cpeHost);
      final health = await _service.healthCheck();
      if (wasRunning) {
        _status = _status.copyWith(state: TunState.stopping, cpe: health);
        notifyListeners();
        await _service.stop();
        if (!health.reachable) {
          _status = _status.copyWith(
            state: TunState.failed,
            cpe: health,
            lastError: health.error ?? '新 CPE 连接失败，已停止当前加速',
          );
          _stopPolling();
          _resetConnectionSession();
          return;
        }
        _status = _status.copyWith(state: TunState.starting, cpe: health);
        notifyListeners();
        await _service.start();
      }
      _resetConnectionSession();
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

      _consecutiveFailures = 0;
      if (!_status.helperInstalled) {
        _status = await _service.installHelper();
        if (!_status.helperInstalled) {
          _status = _status.copyWith(
            state: TunState.failed,
            lastError: _status.lastError ?? '虚拟网卡助手未安装，无法开启加速',
          );
          _stopPolling();
          return;
        }
      }

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
    final connections = await _service.connections(limit: limit);
    _connections = _withDisplayConnections(connections);
    notifyListeners();
    unawaited(_enrichMissingDomains(_connections));
  }

  Future<void> testLatencyTarget(LatencyTarget target) async {
    _latencyResults = [
      for (final result in _latencyResults)
        result.target.id == target.id
            ? LatencyProbeResult.testing(
                target: target,
                checkedAt: DateTime.now(),
              )
            : result,
    ];
    notifyListeners();

    final result = await _latencyProbeClient.probe(target);
    _latencyResults = [
      for (final item in _latencyResults)
        item.target.id == target.id ? result : item,
    ];
    _recordTrafficSample(_status.traffic);
    notifyListeners();
  }

  Future<void> testAllLatencyTargets() async {
    if (_latencyTesting) {
      return;
    }
    _latencyTesting = true;
    _latencyResults = [
      for (final target in _latencyTargets)
        LatencyProbeResult.testing(target: target, checkedAt: DateTime.now()),
    ];
    notifyListeners();
    try {
      final results = await Future.wait([
        for (final target in _latencyTargets) _latencyProbeClient.probe(target),
      ]);
      final byId = {for (final result in results) result.target.id: result};
      _latencyResults = [
        for (final target in _latencyTargets)
          byId[target.id] ?? LatencyProbeResult.idle(target: target),
      ];
      _recordTrafficSample(_status.traffic);
    } finally {
      _latencyTesting = false;
      notifyListeners();
    }
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
        rttMs: _averageLatencyMs(),
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

  int? _averageLatencyMs() {
    final values = [
      for (final result in _latencyResults)
        if (result.status == LatencyProbeStatus.success &&
            result.latencyMs != null)
          result.latencyMs!,
    ];
    if (values.isEmpty) {
      return null;
    }
    return (values.reduce((a, b) => a + b) / values.length).round();
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

  List<TunConnection> _withDisplayConnections(List<TunConnection> connections) {
    final adjusted = <TunConnection>[];
    for (final connection in connections) {
      if (!_retainTrafficHistory && _isStaleConnection(connection)) {
        continue;
      }
      adjusted.add(_withDisplayConnection(_withCachedDomain(connection)));
    }
    return adjusted;
  }

  TunConnection _withDisplayConnection(TunConnection connection) {
    if (_retainTrafficHistory) {
      return connection;
    }
    final key = _connectionKey(connection);
    final baseline = _connectionBaselines.putIfAbsent(
      key,
      () => _ConnectionBaseline(connection.txBytes, connection.rxBytes),
    );
    return connection.copyWith(
      txBytes: math.max(0, connection.txBytes - baseline.txBytes),
      rxBytes: math.max(0, connection.rxBytes - baseline.rxBytes),
    );
  }

  TunConnection _withCachedDomain(TunConnection connection) {
    final domain = connection.domain;
    final host = _hostFromEndpoint(connection.target);
    if (host == null) {
      return connection;
    }
    if (domain != null && domain.isNotEmpty) {
      _domainCache[host] = domain;
      return connection;
    }
    final cached = _domainCache[host];
    if (cached == null || cached.isEmpty) {
      return connection;
    }
    return connection.copyWith(domain: cached);
  }

  bool _isStaleConnection(TunConnection connection) {
    final lastSeen = int.tryParse(connection.lastSeen);
    return lastSeen != null && lastSeen < _connectionSessionStartedAt;
  }

  Future<void> _enrichMissingDomains(List<TunConnection> snapshot) async {
    final hosts = <String>{};
    for (final connection in snapshot) {
      if (connection.domain != null && connection.domain!.isNotEmpty) {
        continue;
      }
      final host = _hostFromEndpoint(connection.target);
      if (host != null && _looksLikeIpAddress(host)) {
        hosts.add(host);
      }
    }
    for (final host in hosts.take(12)) {
      if (_domainCache.containsKey(host) ||
          _domainLookupsInFlight.contains(host)) {
        continue;
      }
      _domainLookupsInFlight.add(host);
      try {
        final domain = await _domainResolver.reverseLookup(host);
        if (domain == null || domain.isEmpty) {
          continue;
        }
        _domainCache[host] = domain;
        var changed = false;
        _connections = [
          for (final connection in _connections)
            if (_hostFromEndpoint(connection.target) == host &&
                (connection.domain == null || connection.domain!.isEmpty))
              (() {
                changed = true;
                return connection.copyWith(domain: domain);
              })()
            else
              connection,
        ];
        if (changed) {
          notifyListeners();
        }
      } finally {
        _domainLookupsInFlight.remove(host);
      }
    }
  }

  void _resetConnectionSession() {
    _connectionSessionStartedAt = _epochSeconds();
    _connectionBaselines.clear();
    _domainCache.clear();
    _domainLookupsInFlight.clear();
    _connections = const [];
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

class _TunServiceLatencyProbeClient implements LatencyProbeClient {
  const _TunServiceLatencyProbeClient(this.service);

  final TunService service;

  @override
  Future<LatencyProbeResult> probe(
    LatencyTarget target, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    return service.probeLatency(target, timeout: timeout);
  }
}

class _ConnectionBaseline {
  const _ConnectionBaseline(this.txBytes, this.rxBytes);

  final int txBytes;
  final int rxBytes;
}

int _epochSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

String _connectionKey(TunConnection connection) {
  return '${connection.proto}|${connection.source}|${connection.target}|${connection.via}';
}

String? _hostFromEndpoint(String endpoint) {
  final text = endpoint.trim();
  if (text.isEmpty) {
    return null;
  }
  if (text.startsWith('[')) {
    final end = text.indexOf(']');
    if (end > 1) {
      return text.substring(1, end);
    }
  }
  final firstColon = text.indexOf(':');
  final lastColon = text.lastIndexOf(':');
  if (firstColon > 0 && firstColon == lastColon) {
    return text.substring(0, firstColon);
  }
  return text;
}

bool _looksLikeIpAddress(String host) {
  final ipv4Parts = host.split('.');
  if (ipv4Parts.length == 4) {
    return ipv4Parts.every((part) {
      final value = int.tryParse(part);
      return value != null && value >= 0 && value <= 255;
    });
  }
  return host.contains(':') && RegExp(r'^[0-9a-fA-F:]+$').hasMatch(host);
}
