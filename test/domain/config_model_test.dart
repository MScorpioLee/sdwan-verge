import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/domain/app_config.dart';
import 'package:sdwan_client/domain/sdwan_profile.dart';

void main() {
  test('default config uses BAT defaults and one active profile', () {
    final config = AppConfig.defaults();
    final active = config.activeProfile;

    expect(config.activeProfileId, 'default');
    expect(config.profiles, hasLength(1));
    expect(active.companyName, '宁波市富金园艺灌溉设备有限公司');
    expect(active.cpeIp, '192.168.1.140');
    expect(active.primaryDns, '223.5.5.5');
    expect(active.secondaryDns, '114.114.114.114');
    expect(active.syncDnsWithAcceleration, isFalse);
  });

  test('serializes and deserializes app config', () {
    final config = AppConfig.defaults().copyWith(
      profiles: [
        SdwanProfile.defaults().copyWith(
          cpeIp: '10.0.0.1',
          syncDnsWithAcceleration: true,
        ),
      ],
    );

    final restored = AppConfig.fromJson(config.toJson());

    expect(restored.activeProfile.cpeIp, '10.0.0.1');
    expect(restored.activeProfile.syncDnsWithAcceleration, isTrue);
  });
}
