import 'acceleration_mode.dart';
import 'sdwan_profile.dart';
import '../tun/tun_models.dart';

class AppConfig {
  const AppConfig({
    required this.activeProfileId,
    required this.profiles,
    required this.latencyTargets,
    this.retainTrafficHistory = false,
  });

  factory AppConfig.defaults() => AppConfig(
    activeProfileId: 'default',
    profiles: [SdwanProfile.defaults()],
    latencyTargets: LatencyTarget.defaults,
    retainTrafficHistory: false,
  );

  factory AppConfig.fromJson(Map<String, Object?> json) {
    final profilesJson = json['profiles'];
    final profiles = profilesJson is List
        ? profilesJson
              .whereType<Map>()
              .map(
                (item) =>
                    SdwanProfile.fromJson(Map<String, Object?>.from(item)),
              )
              .toList()
        : <SdwanProfile>[];

    final resolvedProfiles = profiles.isEmpty
        ? [SdwanProfile.defaults()]
        : profiles.map(_normalizeOpenVpnProfile).toList();
    final requestedActive = json['activeProfileId'] as String? ?? 'default';
    final hasActive = resolvedProfiles.any(
      (profile) => profile.id == requestedActive,
    );
    final latencyTargets = _latencyTargetsFromJson(json['latencyTargets']);

    return AppConfig(
      activeProfileId: hasActive ? requestedActive : resolvedProfiles.first.id,
      profiles: resolvedProfiles,
      latencyTargets: latencyTargets.isEmpty
          ? LatencyTarget.defaults
          : latencyTargets,
      retainTrafficHistory: json['retainTrafficHistory'] as bool? ?? false,
    );
  }

  final String activeProfileId;
  final List<SdwanProfile> profiles;
  final List<LatencyTarget> latencyTargets;
  final bool retainTrafficHistory;

  SdwanProfile get activeProfile => profiles.firstWhere(
    (profile) => profile.id == activeProfileId,
    orElse: () => profiles.first,
  );

  Map<String, Object?> toJson() => {
    'activeProfileId': activeProfileId,
    'profiles': profiles.map((profile) => profile.toJson()).toList(),
    'latencyTargets': latencyTargets.map((target) => target.toJson()).toList(),
    'retainTrafficHistory': retainTrafficHistory,
  };

  AppConfig copyWith({
    String? activeProfileId,
    List<SdwanProfile>? profiles,
    List<LatencyTarget>? latencyTargets,
    bool? retainTrafficHistory,
  }) {
    return AppConfig(
      activeProfileId: activeProfileId ?? this.activeProfileId,
      profiles: profiles ?? this.profiles,
      latencyTargets: latencyTargets ?? this.latencyTargets,
      retainTrafficHistory: retainTrafficHistory ?? this.retainTrafficHistory,
    );
  }
}

SdwanProfile _normalizeOpenVpnProfile(SdwanProfile profile) {
  if (profile.mode == AccelerationMode.openVpn) {
    return profile.copyWith(syncDnsWithAcceleration: false);
  }
  return profile.copyWith(
    mode: AccelerationMode.openVpn,
    syncDnsWithAcceleration: false,
    openVpn: profile.openVpn.copyWith(remoteHost: profile.cpeIp),
  );
}

List<LatencyTarget> _latencyTargetsFromJson(Object? value) {
  if (value is! List) {
    return LatencyTarget.defaults;
  }
  final targets = <LatencyTarget>[];
  final seen = <String>{};
  for (final item in value) {
    if (item is! Map) {
      continue;
    }
    final target = LatencyTarget.fromJson(Map<String, Object?>.from(item));
    if (!target.isValid || seen.contains(target.id)) {
      continue;
    }
    targets.add(target);
    seen.add(target.id);
  }
  return targets;
}
