import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/app_config.dart';

abstract class ConfigStore {
  Future<AppConfig> load();

  Future<void> save(AppConfig config);
}

class ConfigRepository implements ConfigStore {
  static const storageKey = 'sdwan_client_config_v1';

  @override
  Future<AppConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) {
      return AppConfig.defaults();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        return AppConfig.fromJson(decoded);
      }
      if (decoded is Map) {
        return AppConfig.fromJson(Map<String, Object?>.from(decoded));
      }
    } catch (_) {
      return AppConfig.defaults();
    }
    return AppConfig.defaults();
  }

  @override
  Future<void> save(AppConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(config.toJson()));
  }
}
