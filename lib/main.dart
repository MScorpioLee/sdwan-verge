import 'package:flutter/material.dart';

import 'platform/network_gateway.dart';
import 'services/config_repository.dart';
import 'services/sdwan_controller.dart';
import 'ui/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = SdwanController(
    gateway: createNetworkPlatformGateway(),
    configStore: ConfigRepository(),
  );
  await controller.initialize();
  runApp(SdwanClientApp(controller: controller));
}

class SdwanClientApp extends StatelessWidget {
  const SdwanClientApp({super.key, required this.controller});

  final SdwanController controller;

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
      home: AppShell(controller: controller),
    );
  }
}
