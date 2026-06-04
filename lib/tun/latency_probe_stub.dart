import 'tun_models.dart';

abstract interface class LatencyProbeClient {
  Future<LatencyProbeResult> probe(
    LatencyTarget target, {
    Duration timeout = const Duration(seconds: 5),
  });
}

class DefaultLatencyProbeClient implements LatencyProbeClient {
  const DefaultLatencyProbeClient();

  @override
  Future<LatencyProbeResult> probe(
    LatencyTarget target, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    return LatencyProbeResult.failure(
      target: target,
      checkedAt: DateTime.now(),
      error: '当前平台不支持直接测速',
    );
  }
}
