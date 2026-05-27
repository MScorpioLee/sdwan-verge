import 'dart:io';

import 'command_runner.dart';
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
    return UnsupportedNetworkGateway('macOS');
  }
  if (Platform.isIOS) {
    return UnsupportedNetworkGateway('iOS');
  }
  if (Platform.isAndroid) {
    return UnsupportedNetworkGateway('Android');
  }
  if (Platform.isLinux) {
    return UnsupportedNetworkGateway('Linux');
  }
  return UnsupportedNetworkGateway('当前平台');
}
