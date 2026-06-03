import '../../domain/network_status.dart';
import '../../domain/sdwan_profile.dart';
import '../command_runner.dart';
import '../network_platform_gateway.dart';
import 'linux_commands.dart';
import 'linux_parsers.dart';

class LinuxNetworkGateway implements NetworkPlatformGateway {
  const LinuxNetworkGateway({required this.runner});

  final CommandRunner runner;

  @override
  Future<NetworkStatus> readStatus(SdwanProfile profile) async {
    final admin = await _isAdmin();
    final routeTable = await _run(LinuxCommands.routeTable());
    final defaultRoute = await _run(LinuxCommands.defaultRoute());
    final routeInfo = LinuxParsers.defaultRouteInfo(defaultRoute.stdout);
    var dnsMode = DnsMode.unknown;
    var dnsServers = <String>[];

    if (routeInfo.interfaceName != null) {
      final dnsResult = await _run(LinuxCommands.dnsStatus());
      if (dnsResult.succeeded) {
        final dns = LinuxParsers.dnsInfo(
          dnsResult.stdout,
          routeInfo.interfaceName!,
        );
        dnsMode = dns.mode;
        dnsServers = dns.servers;
      }
    }

    return NetworkStatus(
      platformName: 'Linux',
      capability: PlatformCapability.full,
      isAdmin: admin,
      accelerationEnabled: LinuxParsers.hasAccelerationRoutes(
        routeTable.stdout,
        profile.cpeIp,
      ),
      activeInterfaceName: routeInfo.interfaceName,
      activeInterfaceIp: routeInfo.sourceIp,
      dnsMode: dnsMode,
      dnsServers: dnsServers,
      message: 'Linux 桌面端通过 pkexec 请求授权；DNS 使用 systemd-resolved 的 resolvectl。',
    );
  }

  @override
  Future<GatewayOperationResult> ensureAdminOrRelaunch() async {
    return const GatewayOperationResult(
      success: true,
      message: 'Linux 会在执行系统路由或 DNS 操作时通过 pkexec 请求授权',
    );
  }

  @override
  Future<GatewayOperationResult> enableAcceleration(SdwanProfile profile) {
    return _runSequence('开启加速', LinuxCommands.enableAcceleration(profile));
  }

  @override
  Future<GatewayOperationResult> disableAcceleration(SdwanProfile profile) {
    return _runSequence('关闭加速', LinuxCommands.disableAcceleration());
  }

  @override
  Future<GatewayOperationResult> setDns(SdwanProfile profile) async {
    final routeInfo = LinuxParsers.defaultRouteInfo(
      (await _run(LinuxCommands.defaultRoute())).stdout,
    );
    final interfaceName = routeInfo.interfaceName;
    if (interfaceName == null) {
      return const GatewayOperationResult(
        success: false,
        message: '未找到 Linux 活动网卡，无法设置 DNS',
      );
    }
    return _runSequence('设置 DNS', LinuxCommands.setDns(interfaceName, profile));
  }

  @override
  Future<GatewayOperationResult> restoreDns() async {
    final routeInfo = LinuxParsers.defaultRouteInfo(
      (await _run(LinuxCommands.defaultRoute())).stdout,
    );
    final interfaceName = routeInfo.interfaceName;
    if (interfaceName == null) {
      return const GatewayOperationResult(
        success: false,
        message: '未找到 Linux 活动网卡，无法恢复 DNS',
      );
    }
    return _runSequence('恢复 DNS', LinuxCommands.restoreDns(interfaceName));
  }

  Future<bool> _isAdmin() async {
    final result = await _run(LinuxCommands.adminCheck());
    return result.stdout.trim() == '0';
  }

  Future<GatewayOperationResult> _runSequence(
    String action,
    List<LinuxCommand> commands,
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

  Future<CommandResult> _run(LinuxCommand command) {
    return runner.run(command.executable, command.arguments);
  }
}
