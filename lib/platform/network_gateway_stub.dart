import '../domain/network_status.dart';
import '../domain/sdwan_profile.dart';
import 'network_platform_gateway.dart';

NetworkPlatformGateway createNetworkPlatformGateway() =>
    UnsupportedNetworkGateway('Web');

class UnsupportedNetworkGateway implements NetworkPlatformGateway {
  UnsupportedNetworkGateway(this.platformName);

  final String platformName;

  @override
  Future<NetworkStatus> readStatus(SdwanProfile profile) async {
    return NetworkStatus.unsupported(platformName);
  }

  @override
  Future<GatewayOperationResult> ensureAdminOrRelaunch() async {
    return GatewayOperationResult(
      success: false,
      message: '$platformName 暂不支持管理员提权',
    );
  }

  @override
  Future<GatewayOperationResult> enableAcceleration(
    SdwanProfile profile,
  ) async {
    return _unsupported('开启加速');
  }

  @override
  Future<GatewayOperationResult> disableAcceleration(
    SdwanProfile profile,
  ) async {
    return _unsupported('关闭加速');
  }

  @override
  Future<GatewayOperationResult> setDns(SdwanProfile profile) async {
    return _unsupported('设置 DNS');
  }

  @override
  Future<GatewayOperationResult> restoreDns() async {
    return _unsupported('恢复 DNS');
  }

  GatewayOperationResult _unsupported(String action) => GatewayOperationResult(
    success: false,
    message: '$platformName 暂不支持$action，请使用 Windows 客户端',
  );
}
