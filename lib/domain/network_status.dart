enum PlatformCapability { full, unsupported }

enum DnsMode { dhcp, static, unknown }

class NetworkStatus {
  const NetworkStatus({
    required this.platformName,
    required this.capability,
    required this.isAdmin,
    required this.accelerationEnabled,
    this.activeInterfaceName,
    this.activeInterfaceIp,
    this.dnsMode = DnsMode.unknown,
    this.dnsServers = const [],
    this.message,
  });

  factory NetworkStatus.unsupported(String platformName) => NetworkStatus(
    platformName: platformName,
    capability: PlatformCapability.unsupported,
    isAdmin: false,
    accelerationEnabled: false,
    message: '$platformName 暂不支持直接修改系统路由和 DNS',
  );

  final String platformName;
  final PlatformCapability capability;
  final bool isAdmin;
  final bool accelerationEnabled;
  final String? activeInterfaceName;
  final String? activeInterfaceIp;
  final DnsMode dnsMode;
  final List<String> dnsServers;
  final String? message;

  NetworkStatus copyWith({
    String? platformName,
    PlatformCapability? capability,
    bool? isAdmin,
    bool? accelerationEnabled,
    String? activeInterfaceName,
    String? activeInterfaceIp,
    DnsMode? dnsMode,
    List<String>? dnsServers,
    String? message,
  }) {
    return NetworkStatus(
      platformName: platformName ?? this.platformName,
      capability: capability ?? this.capability,
      isAdmin: isAdmin ?? this.isAdmin,
      accelerationEnabled: accelerationEnabled ?? this.accelerationEnabled,
      activeInterfaceName: activeInterfaceName ?? this.activeInterfaceName,
      activeInterfaceIp: activeInterfaceIp ?? this.activeInterfaceIp,
      dnsMode: dnsMode ?? this.dnsMode,
      dnsServers: dnsServers ?? this.dnsServers,
      message: message ?? this.message,
    );
  }
}
