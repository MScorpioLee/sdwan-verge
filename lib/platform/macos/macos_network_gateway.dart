import '../../domain/network_status.dart';
import '../../domain/sdwan_profile.dart';
import '../command_runner.dart';
import '../network_platform_gateway.dart';
import 'macos_commands.dart';
import 'macos_parsers.dart';

class MacosNetworkGateway implements NetworkPlatformGateway {
  const MacosNetworkGateway({required this.runner});

  final CommandRunner runner;

  @override
  Future<NetworkStatus> readStatus(SdwanProfile profile) async {
    final admin = await _isAdmin();
    final routeTable = await _run(MacosCommands.routeTable());
    final defaultRoute = await _run(MacosCommands.defaultRoute());
    final device = MacosParsers.defaultInterface(defaultRoute.stdout);
    String? serviceName;
    var dnsMode = DnsMode.unknown;
    var dnsServers = <String>[];

    if (device != null) {
      final ports = await _run(MacosCommands.hardwarePorts());
      serviceName = MacosParsers.serviceNameForDevice(ports.stdout, device);
      if (serviceName != null) {
        final dns = MacosParsers.dnsInfo(
          (await _run(MacosCommands.dnsServers(serviceName))).stdout,
        );
        dnsMode = dns.mode;
        dnsServers = dns.servers;
      }
    }

    return NetworkStatus(
      platformName: 'macOS',
      capability: PlatformCapability.full,
      isAdmin: admin,
      accelerationEnabled: MacosParsers.hasAccelerationRoutes(
        routeTable.stdout,
        profile.cpeIp,
      ),
      activeInterfaceName: serviceName ?? device,
      dnsMode: dnsMode,
      dnsServers: dnsServers,
      message: 'macOS 操作会在需要时弹出管理员授权；路由重启后可能需要重新开启。',
    );
  }

  @override
  Future<GatewayOperationResult> ensureAdminOrRelaunch() async {
    return const GatewayOperationResult(
      success: true,
      message: 'macOS 会在执行系统路由或 DNS 操作时请求管理员授权',
    );
  }

  @override
  Future<GatewayOperationResult> enableAcceleration(SdwanProfile profile) {
    return _runSequence('开启加速', MacosCommands.enableAcceleration(profile));
  }

  @override
  Future<GatewayOperationResult> disableAcceleration(SdwanProfile profile) {
    return _runSequence('关闭加速', MacosCommands.disableAcceleration());
  }

  @override
  Future<GatewayOperationResult> setDns(SdwanProfile profile) async {
    final serviceName = await _activeServiceName();
    if (serviceName == null) {
      return const GatewayOperationResult(
        success: false,
        message: '未找到 macOS 活动网络服务，无法设置 DNS',
      );
    }
    return _runSequence('设置 DNS', MacosCommands.setDns(serviceName, profile));
  }

  @override
  Future<GatewayOperationResult> restoreDns() async {
    final serviceName = await _activeServiceName();
    if (serviceName == null) {
      return const GatewayOperationResult(
        success: false,
        message: '未找到 macOS 活动网络服务，无法恢复 DNS',
      );
    }
    return _runSequence('恢复 DNS', MacosCommands.restoreDns(serviceName));
  }

  Future<String?> _activeServiceName() async {
    final defaultRoute = await _run(MacosCommands.defaultRoute());
    final device = MacosParsers.defaultInterface(defaultRoute.stdout);
    if (device == null) {
      return null;
    }
    final ports = await _run(MacosCommands.hardwarePorts());
    return MacosParsers.serviceNameForDevice(ports.stdout, device);
  }

  Future<bool> _isAdmin() async {
    final result = await _run(MacosCommands.adminCheck());
    return result.stdout.trim() == '0';
  }

  Future<GatewayOperationResult> _runSequence(
    String action,
    List<MacosCommand> commands,
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

  Future<CommandResult> _run(MacosCommand command) {
    return runner.run(command.executable, command.arguments);
  }
}
