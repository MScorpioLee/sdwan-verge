import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/domain/acceleration_mode.dart';
import 'package:sdwan_client/domain/app_config.dart';
import 'package:sdwan_client/domain/sdwan_profile.dart';
import 'package:sdwan_client/tun/tun_models.dart';

void main() {
  test('default config uses OpenVPN defaults and one active profile', () {
    final config = AppConfig.defaults();
    final active = config.activeProfile;

    expect(config.activeProfileId, 'default');
    expect(config.profiles, hasLength(1));
    expect(active.companyName, isEmpty);
    expect(active.cpeIp, '192.168.1.140');
    expect(active.primaryDns, '223.5.5.5');
    expect(active.secondaryDns, '114.114.114.114');
    expect(active.syncDnsWithAcceleration, isFalse);
    expect(active.mode, AccelerationMode.openVpn);
    expect(config.retainTrafficHistory, isFalse);
    expect(config.latencyTargets, contains(LatencyTarget.defaults.first));
    expect(
      config.latencyTargets.map((target) => target.id),
      containsAll(['claude', 'amazon']),
    );
  });

  test('legacy profile without DNS sync field migrates without DNS sync', () {
    final restored = AppConfig.fromJson({
      'activeProfileId': 'default',
      'profiles': [
        {
          'id': 'default',
          'name': '默认加速配置',
          'companyName': '',
          'cpeIp': '192.168.1.140',
          'primaryDns': '223.5.5.5',
          'secondaryDns': '114.114.114.114',
        },
      ],
    });

    expect(restored.activeProfile.syncDnsWithAcceleration, isFalse);
  });

  test('legacy profile migrates to OpenVPN mode', () {
    final restored = AppConfig.fromJson({
      'activeProfileId': 'default',
      'profiles': [
        {
          'id': 'default',
          'name': '默认加速配置',
          'companyName': '',
          'cpeIp': '192.168.1.140',
          'primaryDns': '223.5.5.5',
          'secondaryDns': '114.114.114.114',
        },
      ],
    });

    expect(restored.activeProfile.mode, AccelerationMode.openVpn);
    expect(restored.activeProfile.openVpn, isNotNull);
    expect(restored.activeProfile.cpeIp, '192.168.1.140');
    expect(restored.activeProfile.openVpn.remoteHost, '192.168.1.140');
  });

  test('serializes and deserializes app config', () {
    final config = AppConfig.defaults().copyWith(
      profiles: [
        SdwanProfile.defaults().copyWith(
          cpeIp: '10.0.0.1',
          syncDnsWithAcceleration: true,
        ),
      ],
      retainTrafficHistory: true,
      latencyTargets: const [
        LatencyTarget(
          id: 'custom-docs',
          name: 'Docs',
          url: 'https://docs.example.com/health',
        ),
      ],
    );

    final restored = AppConfig.fromJson(config.toJson());

    expect(restored.activeProfile.cpeIp, '10.0.0.1');
    expect(restored.activeProfile.syncDnsWithAcceleration, isTrue);
    expect(restored.retainTrafficHistory, isTrue);
    expect(restored.latencyTargets, hasLength(1));
    expect(restored.latencyTargets.single.name, 'Docs');
    expect(
      restored.latencyTargets.single.url,
      'https://docs.example.com/health',
    );
  });

  test('invalid stored latency targets fall back to defaults', () {
    final restored = AppConfig.fromJson({
      'activeProfileId': 'default',
      'profiles': [SdwanProfile.defaults().toJson()],
      'latencyTargets': [
        {'id': '', 'name': '', 'url': 'ftp://bad'},
      ],
    });

    expect(restored.latencyTargets, LatencyTarget.defaults);
  });
}
