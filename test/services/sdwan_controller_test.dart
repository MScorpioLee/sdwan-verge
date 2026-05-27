import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/domain/app_config.dart';
import 'package:sdwan_client/domain/network_status.dart';
import 'package:sdwan_client/domain/sdwan_profile.dart';
import 'package:sdwan_client/platform/network_platform_gateway.dart';
import 'package:sdwan_client/services/config_repository.dart';
import 'package:sdwan_client/services/sdwan_controller.dart';

class FakeGateway implements NetworkPlatformGateway {
  final calls = <String>[];
  NetworkStatus status = const NetworkStatus(
    platformName: 'Windows',
    capability: PlatformCapability.full,
    isAdmin: true,
    accelerationEnabled: false,
  );

  @override
  Future<NetworkStatus> readStatus(SdwanProfile profile) async {
    calls.add('readStatus');
    return status;
  }

  @override
  Future<GatewayOperationResult> ensureAdminOrRelaunch() async {
    calls.add('ensureAdminOrRelaunch');
    return const GatewayOperationResult(success: true, message: 'ok');
  }

  @override
  Future<GatewayOperationResult> enableAcceleration(
    SdwanProfile profile,
  ) async {
    calls.add('enableAcceleration');
    return const GatewayOperationResult(success: true, message: 'enabled');
  }

  @override
  Future<GatewayOperationResult> disableAcceleration(
    SdwanProfile profile,
  ) async {
    calls.add('disableAcceleration');
    return const GatewayOperationResult(success: true, message: 'disabled');
  }

  @override
  Future<GatewayOperationResult> setDns(SdwanProfile profile) async {
    calls.add('setDns');
    return const GatewayOperationResult(success: true, message: 'dns set');
  }

  @override
  Future<GatewayOperationResult> restoreDns() async {
    calls.add('restoreDns');
    return const GatewayOperationResult(success: true, message: 'dns restored');
  }
}

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
  test('initializes config and status', () async {
    final controller = SdwanController(
      gateway: FakeGateway(),
      configStore: MemoryConfigStore(),
    );

    await controller.initialize();

    expect(controller.config.activeProfile.cpeIp, '192.168.1.140');
    expect(controller.status.platformName, 'Windows');
  });

  test('enable acceleration sets DNS when profile sync is enabled', () async {
    final gateway = FakeGateway();
    final store = MemoryConfigStore();
    store.config = AppConfig.defaults().copyWith(
      profiles: [
        AppConfig.defaults().activeProfile.copyWith(
          syncDnsWithAcceleration: true,
        ),
      ],
    );
    final controller = SdwanController(gateway: gateway, configStore: store);
    await controller.initialize();

    await controller.enableAcceleration();

    expect(
      gateway.calls,
      containsAllInOrder(['enableAcceleration', 'setDns', 'readStatus']),
    );
    expect(controller.logs.last.success, isTrue);
  });

  test('rejects invalid profile update', () async {
    final controller = SdwanController(
      gateway: FakeGateway(),
      configStore: MemoryConfigStore(),
    );
    await controller.initialize();

    final result = await controller.saveProfile(
      controller.config.activeProfile.copyWith(cpeIp: 'bad'),
    );

    expect(result.success, isFalse);
    expect(result.message, contains('CPE 网关地址格式不正确'));
  });
}
