import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sdwan_client/domain/app_config.dart';
import 'package:sdwan_client/services/config_repository.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('returns default config when storage is empty', () async {
    final repository = ConfigRepository();

    final config = await repository.load();

    expect(config.activeProfile.cpeIp, '192.168.1.140');
  });

  test('saves and loads config JSON', () async {
    final repository = ConfigRepository();
    final config = AppConfig.defaults().copyWith(
      profiles: [
        AppConfig.defaults().activeProfile.copyWith(cpeIp: '10.1.1.1'),
      ],
    );

    await repository.save(config);
    final loaded = await repository.load();

    expect(loaded.activeProfile.cpeIp, '10.1.1.1');
  });

  test('falls back to defaults when stored JSON is corrupted', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(ConfigRepository.storageKey, '{bad-json');
    final repository = ConfigRepository();

    final loaded = await repository.load();

    expect(loaded.activeProfile.cpeIp, '192.168.1.140');
  });
}
