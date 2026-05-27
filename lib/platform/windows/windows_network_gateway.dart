import 'dart:io' show exit;

import '../../domain/network_status.dart';
import '../../domain/sdwan_profile.dart';
import '../command_runner.dart';
import '../network_platform_gateway.dart';
import 'windows_commands.dart';
import 'windows_parsers.dart';

class WindowsNetworkGateway implements NetworkPlatformGateway {
  WindowsNetworkGateway({
    required this.runner,
    this.executablePath,
    this.exitProcess = exit,
  });

  final CommandRunner runner;
  final String? executablePath;
  final void Function(int code) exitProcess;

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
    final path = executablePath;
    if (path == null || path.isEmpty) {
      return const GatewayOperationResult(
        success: false,
        message: '当前不是管理员权限，请右键以管理员身份运行',
      );
    }
    final command = WindowsCommands.relaunchAsAdmin(path);
    final result = await _run(command);
    if (result.succeeded) {
      exitProcess(0);
    }
    return GatewayOperationResult(
      success: result.succeeded,
      message: result.succeeded ? '已请求管理员权限重新启动' : '请求管理员权限失败',
      command: command.display,
      exitCode: result.exitCode,
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
