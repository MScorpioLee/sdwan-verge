import 'package:flutter/foundation.dart';

import '../domain/app_config.dart';
import '../domain/sdwan_profile.dart';
import '../domain/validation.dart';
import 'config_repository.dart';

class ConfigControllerResult {
  const ConfigControllerResult({required this.success, required this.message});

  final bool success;
  final String message;
}

class AppConfigController extends ChangeNotifier {
  AppConfigController({required this.configStore});

  final ConfigStore configStore;

  AppConfig _config = AppConfig.defaults();

  AppConfig get config => _config;

  Future<void> initialize() async {
    _config = await configStore.load();
    notifyListeners();
  }

  Future<ConfigControllerResult> saveProfile(SdwanProfile profile) async {
    final errors = validateProfile(profile);
    if (errors.isNotEmpty) {
      return ConfigControllerResult(success: false, message: errors.join('\n'));
    }
    final profiles = _config.profiles
        .map((item) => item.id == profile.id ? profile : item)
        .toList();
    _config = _config.copyWith(profiles: profiles);
    await configStore.save(_config);
    notifyListeners();
    return const ConfigControllerResult(success: true, message: '配置已保存');
  }

  Future<ConfigControllerResult> addProfile(SdwanProfile profile) async {
    final errors = validateProfile(profile);
    if (errors.isNotEmpty) {
      return ConfigControllerResult(success: false, message: errors.join('\n'));
    }
    final idExists = _config.profiles.any((item) => item.id == profile.id);
    if (idExists) {
      return const ConfigControllerResult(success: false, message: '配置 ID 已存在');
    }
    _config = _config.copyWith(
      activeProfileId: profile.id,
      profiles: [..._config.profiles, profile],
    );
    await configStore.save(_config);
    notifyListeners();
    return const ConfigControllerResult(success: true, message: '配置已添加');
  }

  Future<ConfigControllerResult> setActiveProfile(String profileId) async {
    final exists = _config.profiles.any((profile) => profile.id == profileId);
    if (!exists) {
      return const ConfigControllerResult(success: false, message: '配置不存在');
    }
    _config = _config.copyWith(activeProfileId: profileId);
    await configStore.save(_config);
    notifyListeners();
    return const ConfigControllerResult(success: true, message: '已切换配置');
  }

  Future<ConfigControllerResult> deleteProfile(String profileId) async {
    if (_config.profiles.length == 1) {
      return const ConfigControllerResult(success: false, message: '至少保留一个配置');
    }
    final profiles = _config.profiles
        .where((profile) => profile.id != profileId)
        .toList();
    if (profiles.length == _config.profiles.length) {
      return const ConfigControllerResult(success: false, message: '配置不存在');
    }
    final active = _config.activeProfileId == profileId
        ? profiles.first.id
        : _config.activeProfileId;
    _config = _config.copyWith(activeProfileId: active, profiles: profiles);
    await configStore.save(_config);
    notifyListeners();
    return const ConfigControllerResult(success: true, message: '配置已删除');
  }

  Future<ConfigControllerResult> setRetainTrafficHistory(bool retain) async {
    _config = _config.copyWith(retainTrafficHistory: retain);
    await configStore.save(_config);
    notifyListeners();
    return ConfigControllerResult(
      success: true,
      message: retain ? '已开启历史流量统计保留' : '已关闭历史流量统计保留',
    );
  }
}
