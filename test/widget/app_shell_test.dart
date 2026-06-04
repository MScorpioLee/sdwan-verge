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
  String cpeHost = '192.168.1.140';
  bool launchAtLogin = false;
  final CpeHealth health;
  final List<TunEventLog> eventLogs = const [
    TunEventLog(time: '2026-06-04 12:00:00', message: '开启 TUN'),
    TunEventLog(time: '2026-06-04 12:00:05', message: '自动回退'),
  ];
  List<TunConnection> get connectionLogs {
    final now = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    return [
      TunConnection(
        lastSeen: now,
        proto: 'TCP',
        source: '10.255.0.2:50000',
        target: '93.184.216.34:443',
        domain: 'example.com',
        via: '93.184.216.34:443',
        txBytes: 120,
        rxBytes: 240,
        txRate: 11,
        rxRate: 22,
      ),
      TunConnection(
        lastSeen: now,
        proto: 'UDP',
        source: '10.255.0.2:50001',
        target: '8.8.8.8:53',
        domain: 'dns.google',
        via: '192.168.1.140:53',
        txBytes: 60,
        rxBytes: 72,
        txRate: 7,
        rxRate: 8,
        dnsRedirect: true,
      ),
    ];
  }

  @override
  void updateCpeHost(String host) {
    cpeHost = host;
  }

  @override
  Future<TunStatus> status() async {
    final status =
        currentStatus ??
        TunStatus.defaults(cpeHost: cpeHost).copyWith(
          traffic: const TrafficStats(
            txBytes: 1024,
            rxBytes: 2048,
            txRate: 128,
            rxRate: 256,
          ),
        );
    return status.copyWith(cpe: status.cpe.copyWith(host: cpeHost));
  }

  @override
  Future<CpeHealth> healthCheck() async => health.copyWith(host: cpeHost);

  @override
  Future<TunStatus> start() async {
    final helperInstalled = currentStatus?.helperInstalled ?? false;
    currentStatus = TunStatus.defaults(cpeHost: cpeHost).copyWith(
      state: TunState.running,
      permission: TunPermission.ready,
      helperInstalled: helperInstalled,
      cpe: health.copyWith(host: cpeHost),
    );
    return currentStatus!;
  }

  @override
  Future<TunStatus> stop() async {
    currentStatus = TunStatus.defaults(
      cpeHost: cpeHost,
    ).copyWith(state: TunState.stopped, permission: TunPermission.ready);
    return currentStatus!;
  }

  @override
  Future<List<TunEventLog>> logs({int limit = 80}) async => eventLogs;

  @override
  Future<List<TunConnection>> connections({int limit = 80}) async =>
      connectionLogs;

  @override
  Future<TunStatus> installHelper() async {
    currentStatus = (currentStatus ?? TunStatus.defaults(cpeHost: cpeHost))
        .copyWith(helperInstalled: true, permission: TunPermission.ready);
    return currentStatus!;
  }

  @override
  Future<TunStatus> uninstallHelper() async {
    currentStatus = TunStatus.defaults(
      cpeHost: cpeHost,
    ).copyWith(helperInstalled: false, permission: TunPermission.ready);
    return currentStatus!;
  }

  @override
  Future<bool> launchAtLoginEnabled() async => launchAtLogin;

  @override
  Future<bool> setLaunchAtLogin(bool enabled) async {
    launchAtLogin = enabled;
    return launchAtLogin;
  }
}

void main() {
  testWidgets('仪表盘展示加速状态并能切换到设置页', (tester) async {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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

    // 侧边栏品牌 + 仪表盘主卡
    expect(find.text('SD-WAN'), findsOneWidget);
    expect(find.text('国际网络加速'), findsOneWidget);
    expect(find.text('CPE 网关'), findsOneWidget);
    expect(find.text('流量统计'), findsOneWidget);
    expect(find.text('上行速率'), findsWidgets);
    expect(find.text('下行速率'), findsWidgets);
    expect(find.text('开启加速'), findsOneWidget);
    // 旧文案不应再出现
    expect(find.text('开启 TUN'), findsNothing);

    // 日志页使用同一套侧边栏风格，只展示 helper 事件时间线。
    await tester.tap(find.text('日志'));
    await tester.pumpAndSettle();
    expect(find.text('事件日志'), findsOneWidget);
    expect(find.text('连接统计'), findsNothing);
    expect(find.text('开启 TUN'), findsOneWidget);

    // 连接统计独立成页，不混在事件日志里。
    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();
    expect(find.text('连接统计'), findsOneWidget);
    expect(find.text('上下行速率'), findsOneWidget);
    expect(find.text('平均值'), findsWidgets);
    expect(find.text('全部'), findsWidgets);
    expect(find.text('1小时'), findsOneWidget);
    expect(find.text('24小时'), findsOneWidget);
    expect(find.textContaining('延迟'), findsNothing);
    expect(find.text('域名统计'), findsOneWidget);
    expect(find.text('example.com'), findsWidgets);
    expect(find.text('dns.google'), findsWidgets);
    expect(find.textContaining('11 B/s'), findsWidgets);
    expect(find.textContaining('93.184.216.34:443'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'TCP'));
    await tester.pumpAndSettle();
    expect(find.text('example.com'), findsWidgets);
    expect(find.text('dns.google'), findsNothing);

    await tester.enterText(find.byType(TextField), '93.184');
    await tester.pumpAndSettle();
    expect(find.text('example.com'), findsWidgets);

    // 点侧边栏「设置」切换页面
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('CPE 地址'), findsOneWidget);
    expect(find.text('公司名称'), findsNothing);
    expect(find.text('保留历史流量统计'), findsOneWidget);
    expect(find.text('开机自动启动'), findsOneWidget);

    await tester.tap(find.text('帮助'));
    await tester.pumpAndSettle();
    expect(find.text('TUN 模式'), findsOneWidget);
    expect(find.text('桌面端'), findsNothing);
    expect(find.text('手机端'), findsNothing);
    expect(find.text('OpenWrt/iStoreOS 插件'), findsNothing);
  });

  testWidgets('后端不支持时禁用开启按钮并显示错误', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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
      find.widgetWithText(FilledButton, '开启加速'),
    );
    expect(startButton.onPressed, isNull);
    expect(find.text('不支持'), findsOneWidget);
  });

  testWidgets('首页未安装助手时显示待安装，安装后显示卸载图标', (tester) async {
    final configController = AppConfigController(
      configStore: MemoryConfigStore(),
    );
    final tunController = TunController(
      service: FakeTunService(
        currentStatus: TunStatus.defaults().copyWith(
          permission: TunPermission.ready,
          helperInstalled: false,
          cpe: const CpeHealth(host: '192.168.1.140', reachable: true),
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

    expect(find.text('待安装助手'), findsOneWidget);
    expect(find.byTooltip('卸载助手'), findsNothing);

    await tunController.installHelper();
    await tester.pumpAndSettle();

    expect(find.text('已授权'), findsOneWidget);
    expect(find.byTooltip('卸载助手'), findsOneWidget);
  });
}
