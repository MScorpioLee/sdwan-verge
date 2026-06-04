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
}
