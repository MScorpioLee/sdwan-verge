import 'package:flutter/services.dart';

import '../domain/openvpn_profile.dart';
import '../domain/sdwan_profile.dart';
export 'latency_probe.dart';

import 'latency_probe.dart';
import 'tun_models.dart';

abstract interface class TunService {
  void updateProfile(SdwanProfile profile);
  void updateCpeHost(String host);
  void updateDnsSync(bool enabled);
  Future<TunStatus> status();
  Future<CpeHealth> healthCheck();
  Future<List<TunEventLog>> logs({int limit = 80});
  Future<List<TunConnection>> connections({int limit = 80});
  Future<TunStatus> installHelper();
  Future<TunStatus> uninstallHelper();
  Future<TunStatus> start();
  Future<TunStatus> stop();
  Future<bool> launchAtLoginEnabled();
  Future<bool> setLaunchAtLogin(bool enabled);
  Future<LatencyProbeResult> probeLatency(
    LatencyTarget target, {
    Duration timeout = const Duration(seconds: 5),
  });
}

class MethodChannelTunService implements TunService {
  MethodChannelTunService({
    MethodChannel? channel,
    LatencyProbeClient? latencyProbeClient,
    String defaultCpeHost = '192.168.1.140',
  }) : _channel = channel ?? const MethodChannel('sdwan_client/tun'),
       _latencyProbeClient =
           latencyProbeClient ?? const DefaultLatencyProbeClient(),
       _cpeHost = defaultCpeHost,
       _activeProfile = SdwanProfile.defaults().copyWith(
         cpeIp: defaultCpeHost,
         openVpn: OpenVpnProfile.defaults().copyWith(
           remoteHost: defaultCpeHost,
         ),
       );

  final MethodChannel _channel;
  final LatencyProbeClient _latencyProbeClient;
  String _cpeHost;
  bool _syncDns = false;
  SdwanProfile _activeProfile;

  String get defaultCpeHost => _cpeHost;

  @override
  void updateProfile(SdwanProfile profile) {
    _activeProfile = profile;
    _cpeHost = profile.cpeIp;
    _syncDns = profile.syncDnsWithAcceleration;
  }

  @override
  void updateCpeHost(String host) {
    final trimmed = host.trim();
    if (trimmed.isNotEmpty) {
      _cpeHost = trimmed;
      _activeProfile = _activeProfile.copyWith(
        cpeIp: trimmed,
        openVpn: _activeProfile.openVpn.copyWith(remoteHost: trimmed),
      );
    }
  }

  @override
  void updateDnsSync(bool enabled) {
    _syncDns = enabled;
    _activeProfile = _activeProfile.copyWith(syncDnsWithAcceleration: enabled);
  }

  @override
  Future<TunStatus> status() async {
    try {
      final result = await _channel.invokeMethod<Object?>(
        'status',
        _baseArguments(),
      );
      return _statusFromMap(result);
    } on MissingPluginException {
      return TunStatus.defaults(cpeHost: defaultCpeHost).copyWith(
        permission: TunPermission.unsupported,
        lastError: '当前平台 TUN 原生服务还未接入',
      );
    } on PlatformException catch (error) {
      return TunStatus.defaults(cpeHost: defaultCpeHost).copyWith(
        state: TunState.failed,
        lastError: error.message ?? error.code,
      );
    }
  }

  @override
  Future<CpeHealth> healthCheck() async {
    try {
      final result = await _channel.invokeMethod<Object?>(
        'healthCheck',
        _baseArguments(),
      );
      return _healthFromMap(result);
    } on MissingPluginException {
      return CpeHealth(
        host: defaultCpeHost,
        reachable: false,
        error: '当前平台 TUN 原生服务还未接入',
      );
    } on PlatformException catch (error) {
      return CpeHealth(
        host: defaultCpeHost,
        reachable: false,
        error: error.message ?? error.code,
      );
    }
  }

  @override
  Future<List<TunEventLog>> logs({int limit = 80}) async {
    try {
      final result = await _channel.invokeMethod<Object?>('logs', {
        'limit': limit,
        ..._baseArguments(),
      });
      return _logsFromList(result);
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  @override
  Future<List<TunConnection>> connections({int limit = 80}) async {
    try {
      final result = await _channel.invokeMethod<Object?>('connections', {
        'limit': limit,
        ..._baseArguments(),
      });
      return _connectionsFromList(result);
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  @override
  Future<TunStatus> installHelper() async {
    try {
      final result = await _channel.invokeMethod<Object?>(
        'installHelper',
        _baseArguments(),
      );
      return _statusFromMap(result);
    } on MissingPluginException {
      return TunStatus.defaults(cpeHost: defaultCpeHost).copyWith(
        state: TunState.failed,
        permission: TunPermission.unsupported,
        lastError: '当前平台 TUN 原生服务还未接入',
      );
    } on PlatformException catch (error) {
      return TunStatus.defaults(cpeHost: defaultCpeHost).copyWith(
        state: TunState.failed,
        lastError: error.message ?? error.code,
      );
    }
  }

  @override
  Future<TunStatus> uninstallHelper() async {
    try {
      final result = await _channel.invokeMethod<Object?>(
        'uninstallHelper',
        _baseArguments(),
      );
      return _statusFromMap(result);
    } on MissingPluginException {
      return TunStatus.defaults(
        cpeHost: defaultCpeHost,
      ).copyWith(permission: TunPermission.unsupported);
    } on PlatformException catch (error) {
      return TunStatus.defaults(cpeHost: defaultCpeHost).copyWith(
        state: TunState.failed,
        lastError: error.message ?? error.code,
      );
    }
  }

  @override
  Future<TunStatus> start() async {
    try {
      final result = await _channel.invokeMethod<Object?>(
        'start',
        _baseArguments(),
      );
      return _statusFromMap(result);
    } on MissingPluginException {
      return TunStatus.defaults(cpeHost: defaultCpeHost).copyWith(
        state: TunState.failed,
        permission: TunPermission.unsupported,
        lastError: '当前平台 TUN 原生服务还未接入',
      );
    } on PlatformException catch (error) {
      return TunStatus.defaults(cpeHost: defaultCpeHost).copyWith(
        state: TunState.failed,
        lastError: error.message ?? error.code,
      );
    }
  }

  @override
  Future<TunStatus> stop() async {
    try {
      final result = await _channel.invokeMethod<Object?>(
        'stop',
        _baseArguments(),
      );
      return _statusFromMap(result);
    } on MissingPluginException {
      return TunStatus.defaults(
        cpeHost: defaultCpeHost,
      ).copyWith(permission: TunPermission.unsupported);
    } on PlatformException catch (error) {
      return TunStatus.defaults(cpeHost: defaultCpeHost).copyWith(
        state: TunState.failed,
        lastError: error.message ?? error.code,
      );
    }
  }

  @override
  Future<bool> launchAtLoginEnabled() async {
    try {
      final result = await _channel.invokeMethod<Object?>(
        'launchAtLoginStatus',
        _baseArguments(),
      );
      return _boolFromValue(result);
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> setLaunchAtLogin(bool enabled) async {
    try {
      final result = await _channel.invokeMethod<Object?>('setLaunchAtLogin', {
        'enabled': enabled,
        ..._baseArguments(),
      });
      return _boolFromValue(result);
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<LatencyProbeResult> probeLatency(
    LatencyTarget target, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      final result = await _channel.invokeMethod<Object?>('probeLatency', {
        'id': target.id,
        'name': target.name,
        'url': target.url,
        'timeoutMs': timeout.inMilliseconds,
        ..._baseArguments(),
      });
      return _latencyResultFromMap(target, result);
    } on MissingPluginException {
      return _latencyProbeClient.probe(target, timeout: timeout);
    } on PlatformException {
      return _latencyProbeClient.probe(target, timeout: timeout);
    }
  }

  TunStatus _statusFromMap(Object? rawValue) {
    final value = _stringMap(rawValue);
    if (value == null) {
      return TunStatus.defaults(cpeHost: defaultCpeHost);
    }

    final cpe = _healthFromMap(value['cpe']);
    final rawState = _stateFromString(value['state'] as String?);
    final recoveredButHealthy =
        rawState == TunState.autoRecovered && cpe.reachable && cpe.serviceReady;

    return TunStatus.defaults(cpeHost: defaultCpeHost).copyWith(
      adapterName: value['adapterName']?.toString(),
      state: recoveredButHealthy ? TunState.stopped : rawState,
      permission: _permissionFromString(value['permission'] as String?),
      cpe: cpe,
      helperInstalled: value['helperInstalled'] as bool? ?? false,
      traffic: TrafficStats(
        txBytes: _intFromValue(value['txBytes']),
        rxBytes: _intFromValue(value['rxBytes']),
        txRate: _intFromValue(value['txRate']),
        rxRate: _intFromValue(value['rxRate']),
      ),
      diagnostics: TunDiagnostics(
        txPackets: _intFromValue(value['txPackets']),
        rxPackets: _intFromValue(value['rxPackets']),
        txDropped: _intFromValue(value['txDropped']),
        rxDropped: _intFromValue(value['rxDropped']),
        natMisses: _intFromValue(value['natMisses']),
        sendFailures: _intFromValue(value['sendFailures']),
        udp443Packets: _intFromValue(value['udp443Packets']),
      ),
      lastError: recoveredButHealthy ? null : value['lastError'] as String?,
    );
  }

  CpeHealth _healthFromMap(Object? rawValue) {
    final value = _stringMap(rawValue);
    if (value == null) {
      return CpeHealth(host: defaultCpeHost, reachable: false);
    }

    return CpeHealth(
      host: value['host'] as String? ?? defaultCpeHost,
      reachable: value['reachable'] as bool? ?? false,
      serviceReady: value['serviceReady'] as bool? ?? false,
      error: value['error'] as String?,
    );
  }

  TunState _stateFromString(String? value) {
    return switch (value) {
      'starting' => TunState.starting,
      'running' => TunState.running,
      'stopping' => TunState.stopping,
      'failed' => TunState.failed,
      'autoRecovered' => TunState.autoRecovered,
      _ => TunState.stopped,
    };
  }

  TunPermission _permissionFromString(String? value) {
    return switch (value) {
      'ready' => TunPermission.ready,
      'needsHelperInstall' => TunPermission.needsHelperInstall,
      'denied' => TunPermission.denied,
      'unsupported' => TunPermission.unsupported,
      _ => TunPermission.needsVpnConsent,
    };
  }

  Map<String, Object?>? _stringMap(Object? value) {
    if (value is! Map) {
      return null;
    }
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  List<TunEventLog> _logsFromList(Object? rawValue) {
    if (rawValue is! List) {
      return const [];
    }
    final logs = <TunEventLog>[];
    for (final item in rawValue) {
      final value = _stringMap(item);
      if (value == null) {
        continue;
      }
      final time = value['time']?.toString().trim() ?? '';
      final message = value['message']?.toString().trim() ?? '';
      if (time.isEmpty || message.isEmpty) {
        continue;
      }
      logs.add(TunEventLog(time: time, message: message));
    }
    return logs;
  }

  List<TunConnection> _connectionsFromList(Object? rawValue) {
    if (rawValue is! List) {
      return const [];
    }
    final connections = <TunConnection>[];
    for (final item in rawValue) {
      final value = _stringMap(item);
      if (value == null) {
        continue;
      }
      final source = value['source']?.toString() ?? '';
      final target = value['target']?.toString() ?? '';
      final via = value['via']?.toString() ?? '';
      if (!_isIpv4Endpoint(source) || !_isPublicIpv4Endpoint(target)) {
        continue;
      }
      if (via.isNotEmpty && !_isIpv4Endpoint(via)) {
        continue;
      }
      connections.add(
        TunConnection(
          lastSeen: value['lastSeen']?.toString() ?? '',
          proto: value['proto']?.toString() ?? '',
          source: source,
          target: target,
          domain: _emptyToNull(value['domain']?.toString()),
          via: via,
          txBytes: _intFromValue(value['txBytes']),
          rxBytes: _intFromValue(value['rxBytes']),
          txRate: _intFromValue(value['txRate']),
          rxRate: _intFromValue(value['rxRate']),
          dnsRedirect: value['dnsRedirect'] as bool? ?? false,
        ),
      );
    }
    return connections;
  }

  LatencyProbeResult _latencyResultFromMap(
    LatencyTarget target,
    Object? rawValue,
  ) {
    final value = _stringMap(rawValue);
    if (value == null) {
      return LatencyProbeResult.failure(
        target: target,
        checkedAt: DateTime.now(),
        error: 'invalid latency response',
      );
    }
    final checkedAt =
        DateTime.tryParse(value['checkedAt']?.toString() ?? '') ??
        DateTime.now();
    final status = value['status']?.toString();
    return switch (status) {
      'success' => LatencyProbeResult.success(
        target: target,
        latencyMs: _intFromValue(value['latencyMs']),
        checkedAt: checkedAt,
      ),
      'timeout' => LatencyProbeResult.timeout(
        target: target,
        checkedAt: checkedAt,
      ),
      _ => LatencyProbeResult.failure(
        target: target,
        checkedAt: checkedAt,
        error: value['error']?.toString() ?? 'latency probe failed',
      ),
    };
  }

  int _intFromValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _boolFromValue(Object? value) {
    if (value is bool) {
      return value;
    }
    return value?.toString() == 'true';
  }

  String? _emptyToNull(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  Map<String, Object?> _baseArguments() {
    final profile = _activeProfile;
    final openVpn = profile.openVpn;
    return {
      'profileId': profile.id,
      'profileName': profile.name,
      'mode': profile.mode.json,
      'cpeHost': _cpeHost,
      'syncDns': _syncDns,
      'openvpnRemoteHost': openVpn.remoteHost,
      'openvpnRemotePort': openVpn.remotePort,
      'openvpnProtocol': openVpn.protocol.ovpnValue,
      'openvpnAuthUserPass': openVpn.authUserPass,
      'openvpnCredentialRef': openVpn.credentialRef,
      'openvpnIpv4Only': openVpn.ipv4Only,
      'openvpnCustomDirectives': openVpn.customDirectives,
    };
  }
}

bool _isIpv4Endpoint(String endpoint) {
  final host = _endpointHost(endpoint);
  return host != null && _isIpv4Address(host);
}

String? _endpointHost(String endpoint) {
  final text = endpoint.trim();
  if (text.isEmpty || text.startsWith('[') || text.contains(']')) {
    return null;
  }
  final firstColon = text.indexOf(':');
  if (firstColon >= 0) {
    if (firstColon != text.lastIndexOf(':')) {
      return null;
    }
    return text.substring(0, firstColon);
  }
  final dotParts = text.split('.');
  if (dotParts.length >= 5 && int.tryParse(dotParts.last) != null) {
    return dotParts.take(4).join('.');
  }
  return text;
}

bool _isIpv4Address(String host) {
  final parts = host.split('.');
  if (parts.length != 4) {
    return false;
  }
  return parts.every((part) {
    if (part.isEmpty) {
      return false;
    }
    final value = int.tryParse(part);
    return value != null && value >= 0 && value <= 255;
  });
}

bool _isPublicIpv4Endpoint(String endpoint) {
  final host = _endpointHost(endpoint);
  if (host == null || !_isIpv4Address(host)) {
    return false;
  }
  final parts = host.split('.').map(int.parse).toList(growable: false);
  final first = parts[0];
  final second = parts[1];
  if (first == 0 || first == 10 || first == 127) {
    return false;
  }
  if (first == 100 && second >= 64 && second <= 127) {
    return false;
  }
  if (first == 169 && second == 254) {
    return false;
  }
  if (first == 172 && second >= 16 && second <= 31) {
    return false;
  }
  if (first == 192 && second == 168) {
    return false;
  }
  if (first >= 224) {
    return false;
  }
  return true;
}
