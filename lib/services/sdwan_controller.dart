import 'package:flutter/foundation.dart';

import '../domain/app_config.dart';
import '../domain/network_status.dart';
import '../domain/operation_log.dart';
import '../domain/sdwan_profile.dart';
import '../domain/validation.dart';
import '../platform/network_platform_gateway.dart';
import 'config_repository.dart';

class ControllerResult {
  const ControllerResult({required this.success, required this.message});

  final bool success;
  final String message;
}

class SdwanController extends ChangeNotifier {
  SdwanController({required this.gateway, required this.configStore});

  final NetworkPlatformGateway gateway;
  final ConfigStore configStore;

  AppConfig _config = AppConfig.defaults();
  NetworkStatus _status = NetworkStatus.unsupported('初始化中');
  final List<OperationLog> _logs = [];
  bool _busy = false;

  AppConfig get config => _config;
  NetworkStatus get status => _status;
  List<OperationLog> get logs => List.unmodifiable(_logs);
  bool get busy => _busy;

  Future<void> initialize() async {
    _config = await configStore.load();
    await refreshStatus();
  }

  Future<void> refreshStatus() async {
    _busy = true;
    notifyListeners();
    _status = await gateway.readStatus(_config.activeProfile);
    _busy = false;
    notifyListeners();
  }

  Future<ControllerResult> saveProfile(SdwanProfile profile) async {
    final errors = validateProfile(profile);
    if (errors.isNotEmpty) {
      return ControllerResult(success: false, message: errors.join('\n'));
    }
    final profiles = _config.profiles
        .map((item) => item.id == profile.id ? profile : item)
        .toList();
    _config = _config.copyWith(profiles: profiles);
    await configStore.save(_config);
    notifyListeners();
    return const ControllerResult(success: true, message: '配置已保存');
  }

  Future<ControllerResult> enableAcceleration() async {
    return _perform('开启加速', () async {
      final result = await gateway.enableAcceleration(_config.activeProfile);
      if (!result.success) {
        return result;
      }
      if (_config.activeProfile.syncDnsWithAcceleration) {
        return gateway.setDns(_config.activeProfile);
      }
      return result;
    });
  }

  Future<ControllerResult> disableAcceleration() async {
    return _perform('关闭加速', () async {
      final result = await gateway.disableAcceleration(_config.activeProfile);
      if (!result.success) {
        return result;
      }
      if (_config.activeProfile.syncDnsWithAcceleration) {
        return gateway.restoreDns();
      }
      return result;
    });
  }

  Future<ControllerResult> setDns() {
    return _perform('设置 DNS', () => gateway.setDns(_config.activeProfile));
  }

  Future<ControllerResult> restoreDns() {
    return _perform('恢复 DNS', gateway.restoreDns);
  }

  Future<ControllerResult> _perform(
    String action,
    Future<GatewayOperationResult> Function() operation,
  ) async {
    _busy = true;
    notifyListeners();
    final result = await operation();
    _logs.insert(
      0,
      OperationLog(
        timestamp: DateTime.now(),
        action: action,
        message: result.message,
        success: result.success,
        command: result.command,
        exitCode: result.exitCode,
      ),
    );
    _status = await gateway.readStatus(_config.activeProfile);
    _busy = false;
    notifyListeners();
    return ControllerResult(success: result.success, message: result.message);
  }
}
