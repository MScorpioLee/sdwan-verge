import 'acceleration_mode.dart';
import 'openvpn_profile.dart';

class SdwanProfile {
  const SdwanProfile({
    required this.id,
    required this.name,
    required this.companyName,
    required this.cpeIp,
    required this.primaryDns,
    required this.secondaryDns,
    required this.syncDnsWithAcceleration,
    required this.mode,
    required this.openVpn,
  });

  factory SdwanProfile.defaults() => SdwanProfile(
    id: 'default',
    name: 'OpenVPN UDP',
    companyName: '',
    cpeIp: '192.168.1.140',
    primaryDns: '223.5.5.5',
    secondaryDns: '114.114.114.114',
    syncDnsWithAcceleration: false,
    mode: AccelerationMode.openVpn,
    openVpn: OpenVpnProfile.defaults(),
  );

  factory SdwanProfile.openVpnDefaults() => SdwanProfile.defaults().copyWith(
    id: 'openvpn-default',
    name: 'OpenVPN UDP',
    mode: AccelerationMode.openVpn,
  );

  factory SdwanProfile.fromJson(Map<String, Object?> json) => SdwanProfile(
    id: json['id'] as String? ?? 'default',
    name: json['name'] as String? ?? '默认加速配置',
    companyName: json['companyName'] as String? ?? '',
    cpeIp: json['cpeIp'] as String? ?? '192.168.1.140',
    primaryDns: json['primaryDns'] as String? ?? '223.5.5.5',
    secondaryDns: json['secondaryDns'] as String? ?? '114.114.114.114',
    syncDnsWithAcceleration: json['syncDnsWithAcceleration'] as bool? ?? false,
    mode: AccelerationMode.fromJson(json['mode']),
    openVpn: _openVpnFromJson(json['openVpn']),
  );

  final String id;
  final String name;
  final String companyName;
  final String cpeIp;
  final String primaryDns;
  final String secondaryDns;
  final bool syncDnsWithAcceleration;
  final AccelerationMode mode;
  final OpenVpnProfile openVpn;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'companyName': companyName,
    'cpeIp': cpeIp,
    'primaryDns': primaryDns,
    'secondaryDns': secondaryDns,
    'syncDnsWithAcceleration': syncDnsWithAcceleration,
    'mode': mode.json,
    'openVpn': openVpn.toJson(),
  };

  SdwanProfile copyWith({
    String? id,
    String? name,
    String? companyName,
    String? cpeIp,
    String? primaryDns,
    String? secondaryDns,
    bool? syncDnsWithAcceleration,
    AccelerationMode? mode,
    OpenVpnProfile? openVpn,
  }) {
    return SdwanProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      companyName: companyName ?? this.companyName,
      cpeIp: cpeIp ?? this.cpeIp,
      primaryDns: primaryDns ?? this.primaryDns,
      secondaryDns: secondaryDns ?? this.secondaryDns,
      syncDnsWithAcceleration:
          syncDnsWithAcceleration ?? this.syncDnsWithAcceleration,
      mode: mode ?? this.mode,
      openVpn: openVpn ?? this.openVpn,
    );
  }
}

OpenVpnProfile _openVpnFromJson(Object? value) {
  if (value is Map<String, Object?>) {
    return OpenVpnProfile.fromJson(value);
  }
  if (value is Map) {
    return OpenVpnProfile.fromJson(Map<String, Object?>.from(value));
  }
  return OpenVpnProfile.defaults();
}
