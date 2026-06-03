import 'dart:io';

import 'command_runner.dart';
import 'linux/linux_network_gateway.dart';
import 'macos/macos_network_gateway.dart';
import 'network_gateway_stub.dart';
import 'network_platform_gateway.dart';
import 'windows/windows_network_gateway.dart';

NetworkPlatformGateway createNetworkPlatformGateway() {
  if (Platform.isWindows) {
    return WindowsNetworkGateway(
      runner: ProcessCommandRunner(),
      executablePath: Platform.resolvedExecutable,
    );
  }
  if (Platform.isMacOS) {
    return MacosNetworkGateway(runner: ProcessCommandRunner());
  }
  if (Platform.isIOS) {
    return RemoteManagementGateway('iOS');
  }
  if (Platform.isAndroid) {
    return RemoteManagementGateway('Android');
  }
  if (Platform.isLinux) {
    return LinuxNetworkGateway(runner: ProcessCommandRunner());
  }
  return UnsupportedNetworkGateway('当前平台');
}
