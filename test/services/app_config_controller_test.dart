import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/domain/app_config.dart';
import 'package:sdwan_client/domain/sdwan_profile.dart';
import 'package:sdwan_client/services/app_config_controller.dart';
import 'package:sdwan_client/services/config_repository.dart';
import 'package:sdwan_client/tun/tun_models.dart';

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
      openVpn: SdwanProfile.openVpnDefaults().openVpn.copyWith(
        inlineBlocks: const {'ca': '-----BEGIN CERTIFICATE-----'},
      ),
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

  test('adds updates and deletes custom latency targets', () async {
    final store = MemoryConfigStore();
    final controller = AppConfigController(configStore: store);
    await controller.initialize();

    final added = await controller.addLatencyTarget(
      name: 'Codex',
      url: 'https://chatgpt.com/',
    );

    expect(added.success, isTrue);
    final target = controller.config.latencyTargets.singleWhere(
      (item) => item.name == 'Codex',
    );
    expect(target.url, 'https://chatgpt.com/');
    expect(store.config.latencyTargets, contains(target));

    final updated = await controller.updateLatencyTarget(
      target.copyWith(name: 'ChatGPT', url: 'https://chatgpt.com/backend-api'),
    );

    expect(updated.success, isTrue);
    expect(
      controller.config.latencyTargets
          .singleWhere((item) => item.id == target.id)
          .name,
      'ChatGPT',
    );

    final deleted = await controller.deleteLatencyTarget(target.id);

    expect(deleted.success, isTrue);
    expect(
      controller.config.latencyTargets.map((item) => item.id),
      isNot(contains(target.id)),
    );
  });

  test('rejects invalid latency target url', () async {
    final store = MemoryConfigStore();
    final controller = AppConfigController(configStore: store);
    await controller.initialize();

    final result = await controller.addLatencyTarget(
      name: 'Bad',
      url: 'ftp://example.com',
    );

    expect(result.success, isFalse);
    expect(result.message, contains('http'));
  });

  test('restores default latency targets', () async {
    final store = MemoryConfigStore()
      ..config = AppConfig.defaults().copyWith(
        latencyTargets: const [
          LatencyTarget(
            id: 'custom-only',
            name: 'Custom',
            url: 'https://example.com',
          ),
        ],
      );
    final controller = AppConfigController(configStore: store);
    await controller.initialize();

    await controller.restoreDefaultLatencyTargets();

    expect(controller.config.latencyTargets, LatencyTarget.defaults);
    expect(store.config.latencyTargets, LatencyTarget.defaults);
  });
}
