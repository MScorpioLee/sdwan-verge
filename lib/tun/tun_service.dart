import 'package:flutter/services.dart';

import 'tun_models.dart';

abstract interface class TunService {
  Future<TunStatus> status();
  Future<CpeHealth> healthCheck();
  Future<TunStatus> start();
  Future<TunStatus> stop();
}

class MethodChannelTunService implements TunService {
  MethodChannelTunService({
    MethodChannel? channel,
    this.defaultCpeHost = '192.168.1.140',
  }) : _channel = channel ?? const MethodChannel('sdwan_client/tun');

  final MethodChannel _channel;
  final String defaultCpeHost;

  @override
  Future<TunStatus> status() async {
    try {
      final result = await _channel.invokeMethod<Object?>('status');
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
      final result = await _channel.invokeMethod<Object?>('healthCheck');
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
  Future<TunStatus> start() async {
    try {
      final result = await _channel.invokeMethod<Object?>('start');
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
      final result = await _channel.invokeMethod<Object?>('stop');
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

  TunStatus _statusFromMap(Object? rawValue) {
    final value = _stringMap(rawValue);
    if (value == null) {
      return TunStatus.defaults(cpeHost: defaultCpeHost);
    }

    return TunStatus.defaults(cpeHost: defaultCpeHost).copyWith(
      state: _stateFromString(value['state'] as String?),
      permission: _permissionFromString(value['permission'] as String?),
      cpe: _healthFromMap(value['cpe']),
      lastError: value['lastError'] as String?,
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
}
