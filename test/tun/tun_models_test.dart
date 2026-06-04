import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/tun/tun_models.dart';

void main() {
  test('default TUN status is stopped and points at CPE', () {
    final status = TunStatus.defaults();

    expect(status.mode, TunMode.tun);
    expect(status.state, TunState.stopped);
    expect(status.permission, TunPermission.needsVpnConsent);
    expect(status.cpe.host, '192.168.1.140');
    expect(status.cpe.reachable, isFalse);
    expect(status.cpe.serviceReady, isFalse);
  });

  test('copyWith preserves CPE health unless replaced', () {
    final status = TunStatus.defaults();

    final updated = status.copyWith(state: TunState.running);

    expect(updated.state, TunState.running);
    expect(updated.cpe, status.cpe);
  });
}
