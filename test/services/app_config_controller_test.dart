import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/domain/app_config.dart';
import 'package:sdwan_client/domain/sdwan_profile.dart';
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

  test('saves traffic history retention preference', () async {
    final store = MemoryConfigStore();
    final controller = AppConfigController(configStore: store);

    await controller.initialize();
    final result = await controller.setRetainTrafficHistory(true);

    expect(result.success, isTrue);
    expect(controller.config.retainTrafficHistory, isTrue);
    expect(store.config.retainTrafficHistory, isTrue);
  });

  test('adds switches and deletes profiles', () async {
    final store = MemoryConfigStore();
    final controller = AppConfigController(configStore: store);
    await controller.initialize();

    final profile = SdwanProfile.openVpnDefaults().copyWith(
      id: 'vpn-1',
      name: '公司 UDP',
    );

    await controller.addProfile(profile);
    expect(
      controller.config.profiles.map((item) => item.id),
      contains('vpn-1'),
    );

    await controller.setActiveProfile('vpn-1');
    expect(controller.config.activeProfileId, 'vpn-1');

    await controller.deleteProfile('vpn-1');
    expect(controller.config.activeProfileId, 'default');
    expect(
      controller.config.profiles.map((item) => item.id),
      isNot(contains('vpn-1')),
    );
  });
}
