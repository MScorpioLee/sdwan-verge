import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/domain/app_config.dart';
import 'package:sdwan_client/services/app_config_controller.dart';
import 'package:sdwan_client/services/config_repository.dart';

class MemoryConfigStore implements ConfigStore {
  AppConfig config = AppConfig.defaults();

  @override
  Future<AppConfig> load() async => config;

  @override
  Future<void> save(AppConfig config) async {
    this.config = config;
  }
}

void main() {
  test('loads and saves CPE profile without a network gateway', () async {
    final store = MemoryConfigStore();
    final controller = AppConfigController(configStore: store);

    await controller.initialize();
    final result = await controller.saveProfile(
      controller.config.activeProfile.copyWith(cpeIp: '192.168.1.150'),
    );

    expect(result.success, isTrue);
    expect(controller.config.activeProfile.cpeIp, '192.168.1.150');
    expect(store.config.activeProfile.cpeIp, '192.168.1.150');
  });
}
