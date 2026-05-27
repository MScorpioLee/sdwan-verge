import '../domain/network_status.dart';
import '../domain/sdwan_profile.dart';

class GatewayOperationResult {
  const GatewayOperationResult({
    required this.success,
    required this.message,
    this.command,
    this.exitCode,
  });

  final bool success;
  final String message;
  final String? command;
  final int? exitCode;
}

abstract class NetworkPlatformGateway {
  Future<NetworkStatus> readStatus(SdwanProfile profile);

  Future<GatewayOperationResult> ensureAdminOrRelaunch();

  Future<GatewayOperationResult> enableAcceleration(SdwanProfile profile);

  Future<GatewayOperationResult> disableAcceleration(SdwanProfile profile);

  Future<GatewayOperationResult> setDns(SdwanProfile profile);

  Future<GatewayOperationResult> restoreDns();
}
