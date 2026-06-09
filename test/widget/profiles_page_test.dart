import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/domain/app_config.dart';
import 'package:sdwan_client/domain/sdwan_profile.dart';
import 'package:sdwan_client/services/app_config_controller.dart';
import 'package:sdwan_client/services/config_repository.dart';
import 'package:sdwan_client/ui/profiles_page.dart';

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
  testWidgets('profiles page lists and switches profiles', (tester) async {
    final store = MemoryConfigStore()
      ..config = AppConfig.defaults().copyWith(
        profiles: [
          SdwanProfile.defaults(),
          SdwanProfile.openVpnDefaults().copyWith(id: 'vpn', name: '公司 UDP'),
        ],
      );
    final controller = AppConfigController(configStore: store);
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(home: ProfilesPage(controller: controller)),
    );

    expect(find.text('配置'), findsOneWidget);
    expect(find.text('默认加速配置'), findsOneWidget);
    expect(find.text('公司 UDP'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, '使用').last);
    await tester.pumpAndSettle();

    expect(controller.config.activeProfileId, 'vpn');
  });

  testWidgets('editor exposes protocol and custom directives', (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final store = MemoryConfigStore()
      ..config = AppConfig.defaults().copyWith(
        profiles: [SdwanProfile.openVpnDefaults()],
        activeProfileId: 'openvpn-default',
      );
    final controller = AppConfigController(configStore: store);
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(home: ProfilesPage(controller: controller)),
    );
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    expect(find.text('UDP IPv4'), findsOneWidget);
    expect(find.text('TCP IPv4'), findsOneWidget);
    expect(find.text('OpenVPN 自定义配置'), findsOneWidget);
  });
}
