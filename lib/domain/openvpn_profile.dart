enum OpenVpnProtocol {
  udp4('udp4', 'UDP IPv4'),
  tcpClient('tcp-client', 'TCP IPv4');

  const OpenVpnProtocol(this.ovpnValue, this.label);

  final String ovpnValue;
  final String label;

  static OpenVpnProtocol fromJson(Object? value) {
    final text = value?.toString().trim().toLowerCase();
    return switch (text) {
      'tcp' || 'tcp4' || 'tcp-client' => OpenVpnProtocol.tcpClient,
      _ => OpenVpnProtocol.udp4,
    };
  }
}

class OpenVpnProfile {
  const OpenVpnProfile({
    required this.remoteHost,
    required this.remotePort,
    required this.protocol,
    required this.authUserPass,
    required this.credentialRef,
    required this.configRef,
    required this.redirectGateway,
    required this.tunName,
    required this.mtu,
    required this.mssfix,
    required this.ipv4Only,
    required this.pullFilterIpv6,
    required this.customDirectives,
    required this.inlineBlocks,
  });

  factory OpenVpnProfile.defaults() => const OpenVpnProfile(
    remoteHost: '192.168.1.140',
    remotePort: 10189,
    protocol: OpenVpnProtocol.udp4,
    authUserPass: true,
    credentialRef: null,
    configRef: null,
    redirectGateway: 'def1',
    tunName: 'auto',
    mtu: 'auto',
    mssfix: 'auto',
    ipv4Only: true,
    pullFilterIpv6: true,
    customDirectives: ['verb 3', 'resolv-retry infinite', 'nobind'],
    inlineBlocks: {},
  );

  factory OpenVpnProfile.fromJson(Map<String, Object?> json) {
    final directives = json['customDirectives'];
    final blocks = json['inlineBlocks'];
    return OpenVpnProfile(
      remoteHost: json['remoteHost'] as String? ?? '192.168.1.140',
      remotePort: (json['remotePort'] as num?)?.toInt() ?? 10189,
      protocol: OpenVpnProtocol.fromJson(json['protocol']),
      authUserPass: json['authUserPass'] as bool? ?? true,
      credentialRef: json['credentialRef'] as String?,
      configRef: json['configRef'] as String?,
      redirectGateway: json['redirectGateway'] as String? ?? 'def1',
      tunName: json['tunName'] as String? ?? 'auto',
      mtu: json['mtu'] as String? ?? 'auto',
      mssfix: json['mssfix'] as String? ?? 'auto',
      ipv4Only: json['ipv4Only'] as bool? ?? true,
      pullFilterIpv6: json['pullFilterIpv6'] as bool? ?? true,
      customDirectives: directives is List
          ? directives.map((item) => item.toString()).toList()
          : OpenVpnProfile.defaults().customDirectives,
      inlineBlocks: blocks is Map
          ? blocks.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const {},
    );
  }

  final String remoteHost;
  final int remotePort;
  final OpenVpnProtocol protocol;
  final bool authUserPass;
  final String? credentialRef;
  final String? configRef;
  final String redirectGateway;
  final String tunName;
  final String mtu;
  final String mssfix;
  final bool ipv4Only;
  final bool pullFilterIpv6;
  final List<String> customDirectives;
  final Map<String, String> inlineBlocks;

  Map<String, Object?> toJson() => {
    'remoteHost': remoteHost,
    'remotePort': remotePort,
    'protocol': protocol.ovpnValue,
    'authUserPass': authUserPass,
    'credentialRef': credentialRef,
    'configRef': configRef,
    'redirectGateway': redirectGateway,
    'tunName': tunName,
    'mtu': mtu,
    'mssfix': mssfix,
    'ipv4Only': ipv4Only,
    'pullFilterIpv6': pullFilterIpv6,
    'customDirectives': customDirectives,
    'inlineBlocks': inlineBlocks,
  };

  OpenVpnProfile copyWith({
    String? remoteHost,
    int? remotePort,
    OpenVpnProtocol? protocol,
    bool? authUserPass,
    Object? credentialRef = _unset,
    Object? configRef = _unset,
    String? redirectGateway,
    String? tunName,
    String? mtu,
    String? mssfix,
    bool? ipv4Only,
    bool? pullFilterIpv6,
    List<String>? customDirectives,
    Map<String, String>? inlineBlocks,
  }) {
    return OpenVpnProfile(
      remoteHost: remoteHost ?? this.remoteHost,
      remotePort: remotePort ?? this.remotePort,
      protocol: protocol ?? this.protocol,
      authUserPass: authUserPass ?? this.authUserPass,
      credentialRef: credentialRef == _unset
          ? this.credentialRef
          : credentialRef as String?,
      configRef: configRef == _unset ? this.configRef : configRef as String?,
      redirectGateway: redirectGateway ?? this.redirectGateway,
      tunName: tunName ?? this.tunName,
      mtu: mtu ?? this.mtu,
      mssfix: mssfix ?? this.mssfix,
      ipv4Only: ipv4Only ?? this.ipv4Only,
      pullFilterIpv6: pullFilterIpv6 ?? this.pullFilterIpv6,
      customDirectives: customDirectives ?? this.customDirectives,
      inlineBlocks: inlineBlocks ?? this.inlineBlocks,
    );
  }
}

const _unset = Object();
