import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/domain/app_config.dart';
import 'package:sdwan_client/services/app_config_controller.dart';
import 'package:sdwan_client/services/config_repository.dart';
import 'package:sdwan_client/tun/tun_controller.dart';
import 'package:sdwan_client/tun/tun_models.dart';
import 'package:sdwan_client/tun/tun_service.dart';
import 'package:sdwan_client/ui/app_shell.dart';

class MemoryConfigStore implements ConfigStore {
  AppConfig config = AppConfig.defaults();

  @override
  Future<AppConfig> load() async => config;

  @override
  Future<void> save(AppConfig config) async {
    this.config = config;
  }
}

class FakeTunService implements TunService {
  FakeTunService({
    this.currentStatus,
    this.health = const CpeHealth(
      host: '192.168.1.140',
      reachable: true,
      serviceReady: true,
    ),
  });

  TunStatus? currentStatus;
  final CpeHealth health;

  @override
  Future<TunStatus> status() async {
    return currentStatus ?? TunStatus.defaults();
  }

  @override
  Future<CpeHealth> healthCheck() async => health;

  @override
  Future<TunStatus> start() async {
    currentStatus = TunStatus.defaults().copyWith(
      state: TunState.running,
      permission: TunPermission.ready,
      cpe: health,
    );
    return currentStatus!;
  }

  @override
  Future<TunStatus> stop() async {
    currentStatus = TunStatus.defaults().copyWith(
      state: TunState.stopped,
      permission: TunPermission.ready,
    );
    return currentStatus!;
  }
}

void main() {
  testWidgets('shows dashboard status and settings page', (tester) async {
    final configController = AppConfigController(
      configStore: MemoryConfigStore(),
    );
    final tunController = TunController(service: FakeTunService());
    await configController.initialize();
    await tunController.initialize();

    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          configController: configController,
          tunController: tunController,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SD-WAN Verge'), findsOneWidget);
    expect(find.text('TUN 状态'), findsOneWidget);
    expect(find.text('CPE 状态'), findsOneWidget);
    expect(find.text('开启 TUN'), findsOneWidget);
    expect(find.text('关闭 TUN'), findsOneWidget);
    expect(find.text('开启加速'), findsNothing);
    expect(find.text('当前 DNS'), findsNothing);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(find.text('CPE 地址'), findsOneWidget);
    expect(find.text('路由操作同步 DNS'), findsNothing);
  });

  testWidgets('disables start when TUN backend is unsupported', (tester) async {
    final configController = AppConfigController(
      configStore: MemoryConfigStore(),
    );
    final tunController = TunController(
      service: FakeTunService(
        currentStatus: TunStatus.defaults().copyWith(
          permission: TunPermission.unsupported,
          lastError: '不支持',
        ),
      ),
    );
    await configController.initialize();
    await tunController.initialize();

    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          configController: configController,
          tunController: tunController,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final startButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '开启 TUN'),
    );
    final stopButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '关闭 TUN'),
    );

    expect(startButton.onPressed, isNull);
    expect(stopButton.onPressed, isNotNull);
    expect(find.textContaining('当前平台暂未接入 TUN 原生服务'), findsOneWidget);
  });
}
