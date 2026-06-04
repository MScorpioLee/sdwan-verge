import 'dart:async';
import 'dart:io';

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
    final checkedAt = DateTime.now();
    final stopwatch = Stopwatch()..start();
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final uri = Uri.parse(target.url);
      final request = await client.getUrl(uri).timeout(timeout);
      request.followRedirects = true;
      request.headers.set(HttpHeaders.userAgentHeader, 'SD-WAN Verge');
      request.headers.set(HttpHeaders.connectionHeader, 'close');
      final response = await request.close().timeout(timeout);
      final latencyMs = stopwatch.elapsedMilliseconds;
      if (response.statusCode >= 200 && response.statusCode < 500) {
        return LatencyProbeResult.success(
          target: target,
          latencyMs: latencyMs,
          checkedAt: checkedAt,
        );
      }
      return LatencyProbeResult.failure(
        target: target,
        checkedAt: checkedAt,
        error: 'HTTP ${response.statusCode}',
      );
    } on TimeoutException {
      return LatencyProbeResult.timeout(target: target, checkedAt: checkedAt);
    } on Object catch (error) {
      return LatencyProbeResult.failure(
        target: target,
        checkedAt: checkedAt,
        error: error.toString(),
      );
    } finally {
      stopwatch.stop();
      client.close(force: true);
    }
  }
}
