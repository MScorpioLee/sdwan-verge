import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/domain/app_config.dart';
import 'package:sdwan_client/domain/network_status.dart';
import 'package:sdwan_client/domain/sdwan_profile.dart';
import 'package:sdwan_client/platform/network_platform_gateway.dart';
import 'package:sdwan_client/services/config_repository.dart';
import 'package:sdwan_client/services/sdwan_controller.dart';
import 'package:sdwan_client/ui/app_shell.dart';

class FakeGateway implements NetworkPlatformGateway {
  @override
  Future<NetworkStatus> readStatus(SdwanProfile profile) async {
    return const NetworkStatus(
      platformName: 'Windows',
      capability: PlatformCapability.full,
      isAdmin: true,
      accelerationEnabled: false,
      activeInterfaceName: 'Ethernet',
      activeInterfaceIp: '192.168.1.88',
      dnsMode: DnsMode.static,
      dnsServers: ['223.5.5.5', '114.114.114.114'],
    );
  }

  @override
  Future<GatewayOperationResult> ensureAdminOrRelaunch() async =>
      const GatewayOperationResult(success: true, message: 'ok');

  @override
  Future<GatewayOperationResult> enableAcceleration(
    SdwanProfile profile,
  ) async => const GatewayOperationResult(success: true, message: '开启成功');

  @override
  Future<GatewayOperationResult> disableAcceleration(
    SdwanProfile profile,
  ) async => const GatewayOperationResult(success: true, message: '关闭成功');

  @override
  Future<GatewayOperationResult> setDns(SdwanProfile profile) async =>
      const GatewayOperationResult(success: true, message: 'DNS 成功');

  @override
  Future<GatewayOperationResult> restoreDns() async =>
      const GatewayOperationResult(success: true, message: 'DNS 已恢复');
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
  testWidgets('shows dashboard status and settings page', (tester) async {
    final controller = SdwanController(
      gateway: FakeGateway(),
      configStore: MemoryConfigStore(),
    );
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(home: AppShell(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('国际网络加速工具'), findsOneWidget);
    expect(find.text('未开启'), findsOneWidget);
    expect(find.text('Ethernet'), findsOneWidget);
    expect(find.text('开启加速'), findsOneWidget);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(find.text('CPE 网关'), findsOneWidget);
    expect(find.text('路由操作同步 DNS'), findsOneWidget);
  });
}
