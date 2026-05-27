import 'sdwan_profile.dart';

class AppConfig {
  const AppConfig({
    required this.activeProfileId,
    required this.profiles,
  });

  factory AppConfig.defaults() => AppConfig(
        activeProfileId: 'default',
        profiles: [SdwanProfile.defaults()],
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

    final resolvedProfiles =
        profiles.isEmpty ? [SdwanProfile.defaults()] : profiles;
    final requestedActive = json['activeProfileId'] as String? ?? 'default';
    final hasActive =
        resolvedProfiles.any((profile) => profile.id == requestedActive);

    return AppConfig(
      activeProfileId: hasActive ? requestedActive : resolvedProfiles.first.id,
      profiles: resolvedProfiles,
    );
  }

  final String activeProfileId;
  final List<SdwanProfile> profiles;

  SdwanProfile get activeProfile => profiles.firstWhere(
        (profile) => profile.id == activeProfileId,
        orElse: () => profiles.first,
      );

  Map<String, Object?> toJson() => {
        'activeProfileId': activeProfileId,
        'profiles': profiles.map((profile) => profile.toJson()).toList(),
      };

  AppConfig copyWith({
    String? activeProfileId,
    List<SdwanProfile>? profiles,
  }) {
    return AppConfig(
      activeProfileId: activeProfileId ?? this.activeProfileId,
      profiles: profiles ?? this.profiles,
    );
  }
}
