import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/tun/tun_models.dart';

void main() {
  test('default status is stopped and points at OpenVPN server', () {
    final status = TunStatus.defaults();

    expect(status.mode, TunMode.tun);
    expect(status.adapterName, 'OpenVPN');
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

  test('copyWith preserves traffic statistics unless replaced', () {
    final status = TunStatus.defaults().copyWith(
      traffic: const TrafficStats(
        txBytes: 1200,
        rxBytes: 3400,
        txRate: 56,
        rxRate: 78,
      ),
    );

    final updated = status.copyWith(state: TunState.running);

    expect(updated.traffic.txBytes, 1200);
    expect(updated.traffic.rxBytes, 3400);
    expect(updated.traffic.txRate, 56);
    expect(updated.traffic.rxRate, 78);
  });

  test('copyWith preserves data plane diagnostics unless replaced', () {
    final status = TunStatus.defaults().copyWith(
      diagnostics: const TunDiagnostics(
        txPackets: 10,
        rxPackets: 8,
        txDropped: 2,
        rxDropped: 3,
        natMisses: 4,
        sendFailures: 5,
        udp443Packets: 6,
      ),
    );

    final updated = status.copyWith(state: TunState.running);

    expect(updated.diagnostics.txPackets, 10);
    expect(updated.diagnostics.rxPackets, 8);
    expect(updated.diagnostics.txDropped, 2);
    expect(updated.diagnostics.rxDropped, 3);
    expect(updated.diagnostics.natMisses, 4);
    expect(updated.diagnostics.sendFailures, 5);
    expect(updated.diagnostics.udp443Packets, 6);
  });

  test('copyWith can override adapter label', () {
    final status = TunStatus.defaults();

    final updated = status.copyWith(adapterName: 'Windows Half Route');

    expect(updated.adapterName, 'Windows Half Route');
    expect(status.adapterName, 'OpenVPN');
  });

  test('latency results expose success timeout and failure state', () {
    const target = LatencyTarget(
      id: 'github',
      name: 'GitHub',
      url: 'https://github.com/favicon.ico',
    );
    final at = DateTime(2026, 6, 4, 12);

    final success = LatencyProbeResult.success(
      target: target,
      latencyMs: 188,
      checkedAt: at,
    );
    final timeout = LatencyProbeResult.timeout(target: target, checkedAt: at);
    final failure = LatencyProbeResult.failure(
      target: target,
      checkedAt: at,
      error: 'network unreachable',
    );

    expect(success.status, LatencyProbeStatus.success);
    expect(success.latencyMs, 188);
    expect(timeout.status, LatencyProbeStatus.timeout);
    expect(failure.status, LatencyProbeStatus.failed);
    expect(failure.error, 'network unreachable');
  });

  test('traffic samples can carry measured RTT', () {
    final sample = TrafficSample(
      at: DateTime(2026, 6, 4, 12),
      txRate: 12,
      rxRate: 34,
      rttMs: 188,
    );

    expect(sample.rttMs, 188);
  });
}
