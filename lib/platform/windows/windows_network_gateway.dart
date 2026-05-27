import '../../domain/network_status.dart';
import '../../domain/sdwan_profile.dart';
import '../command_runner.dart';
import '../network_platform_gateway.dart';
import 'windows_commands.dart';
import 'windows_parsers.dart';

class WindowsNetworkGateway implements NetworkPlatformGateway {
  WindowsNetworkGateway({required this.runner});

  final CommandRunner runner;

  @override
  Future<NetworkStatus> readStatus(SdwanProfile profile) async {
    final admin = await _isAdmin();
    final routeResult = await _run(WindowsCommands.routePrint());
    final routeOutput = routeResult.stdout;
    final interfaceIp = WindowsParsers.defaultRouteInterfaceIp(routeOutput);
    var interfaceName = interfaceIp;
    var dnsMode = DnsMode.unknown;
    var dnsServers = <String>[];

    if (interfaceIp != null) {
      final configResult = await _run(WindowsCommands.netshConfig());
      interfaceName =
          WindowsParsers.interfaceNameForIp(configResult.stdout, interfaceIp);
      if (interfaceName != null) {
        final dnsResult = await _run(WindowsCommands.dnsServers(interfaceName));
        final dns = WindowsParsers.dnsInfo(dnsResult.stdout);
        dnsMode = dns.mode;
        dnsServers = dns.servers;
      }
    }

    return NetworkStatus(
      platformName: 'Windows',
      capability: PlatformCapability.full,
      isAdmin: admin,
      accelerationEnabled:
          WindowsParsers.hasAccelerationRoutes(routeOutput, profile.cpeIp),
      activeInterfaceName: interfaceName,
      activeInterfaceIp: interfaceIp,
      dnsMode: dnsMode,
      dnsServers: dnsServers,
    );
  }

  @override
  Future<GatewayOperationResult> ensureAdminOrRelaunch() async {
    if (await _isAdmin()) {
      return const GatewayOperationResult(
        success: true,
        message: '管理员权限已就绪',
      );
    }
    return const GatewayOperationResult(
      success: false,
      message: '当前不是管理员权限，请通过 UAC 重新启动应用',
    );
  }

  @override
  Future<GatewayOperationResult> enableAcceleration(SdwanProfile profile) {
    return _runSequence('开启加速', WindowsCommands.enableAcceleration(profile));
  }

  @override
  Future<GatewayOperationResult> disableAcceleration(SdwanProfile profile) {
    return _runSequence('关闭加速', WindowsCommands.disableAcceleration());
  }

  @override
  Future<GatewayOperationResult> setDns(SdwanProfile profile) async {
    final status = await readStatus(profile);
    final name = status.activeInterfaceName;
    if (name == null || name.isEmpty) {
      return const GatewayOperationResult(
        success: false,
        message: '未找到活动网卡，无法设置 DNS',
      );
    }
    return _runSequence('设置 DNS', WindowsCommands.setDns(name, profile));
  }

  @override
  Future<GatewayOperationResult> restoreDns() async {
    final status = await readStatus(SdwanProfile.defaults());
    final name = status.activeInterfaceName;
    if (name == null || name.isEmpty) {
      return const GatewayOperationResult(
        success: false,
        message: '未找到活动网卡，无法恢复 DNS',
      );
    }
    return _runSequence('恢复 DNS', WindowsCommands.restoreDns(name));
  }

  Future<bool> _isAdmin() async {
    final result = await _run(WindowsCommands.adminCheck());
    return result.exitCode == 0;
  }

  Future<GatewayOperationResult> _runSequence(
    String action,
    List<WindowsCommand> commands,
  ) async {
    for (final command in commands) {
      final result = await _run(command);
      if (!result.succeeded) {
        final detail = result.stderr.trim().isEmpty
            ? result.stdout.trim()
            : result.stderr.trim();
        return GatewayOperationResult(
          success: false,
          message:
              '$action失败：${detail.isEmpty ? '命令退出码 ${result.exitCode}' : detail}',
          command: command.display,
          exitCode: result.exitCode,
        );
      }
    }
    return GatewayOperationResult(success: true, message: '$action成功');
  }

  Future<CommandResult> _run(WindowsCommand command) {
    return runner.run(command.executable, command.arguments);
  }
}
