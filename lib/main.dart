import 'package:flutter/material.dart';

import 'services/app_config_controller.dart';
import 'services/config_repository.dart';
import 'services/credential_store.dart';
import 'services/traffic_history_repository.dart';
import 'tun/tun_controller.dart';
import 'tun/tun_service.dart';
import 'ui/app_shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final configController = AppConfigController(configStore: ConfigRepository());
  await configController.initialize();
  const credentialStore = SharedPreferencesCredentialStore();
  final tunService = MethodChannelTunService(
    credentialStore: credentialStore,
    defaultCpeHost: configController.config.activeProfile.cpeIp,
  );
  tunService.updateProfile(configController.config.activeProfile);
  tunService.updateDnsSync(
    configController.config.activeProfile.syncDnsWithAcceleration,
  );
  final tunController = TunController(
    service: tunService,
    trafficHistoryStore: TrafficHistoryRepository(),
    retainTrafficHistory: configController.config.retainTrafficHistory,
    latencyTargets: configController.config.latencyTargets,
  );
  runApp(
    SdwanClientApp(
      configController: configController,
      tunController: tunController,
      credentialStore: credentialStore,
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    tunController.initialize();
  });
}

class SdwanClientApp extends StatelessWidget {
  const SdwanClientApp({
    super.key,
    required this.configController,
    required this.tunController,
    required this.credentialStore,
  });

  final AppConfigController configController;
  final TunController tunController;
  final CredentialStore credentialStore;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '国际网络加速工具',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
        ),
        visualDensity: VisualDensity.comfortable,
      ),
      home: AppShell(
        configController: configController,
        tunController: tunController,
        credentialStore: credentialStore,
      ),
    );
  }
}
