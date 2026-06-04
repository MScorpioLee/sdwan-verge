import 'package:flutter/material.dart';

import 'services/app_config_controller.dart';
import 'services/config_repository.dart';
import 'tun/tun_controller.dart';
import 'tun/tun_service.dart';
import 'ui/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final configController = AppConfigController(configStore: ConfigRepository());
  final tunController = TunController(service: MethodChannelTunService());
  await configController.initialize();
  await tunController.initialize();
  runApp(
    SdwanClientApp(
      configController: configController,
      tunController: tunController,
    ),
  );
}

class SdwanClientApp extends StatelessWidget {
  const SdwanClientApp({
    super.key,
    required this.configController,
    required this.tunController,
  });

  final AppConfigController configController;
  final TunController tunController;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '国际网络加速工具',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        useMaterial3: true,
        cardTheme: const CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      ),
      home: AppShell(
        configController: configController,
        tunController: tunController,
      ),
    );
  }
}
