import 'package:flutter/material.dart';

import '../tun/tun_controller.dart';
import '../tun/tun_models.dart';
import 'theme.dart';

class LatencyPage extends StatelessWidget {
  const LatencyPage({super.key, required this.tunController});

  final TunController tunController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: tunController,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.all(28),
          children: [
            Row(
              children: [
                const Text(
                  '网站测速',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: tunController.latencyTesting
                      ? null
                      : tunController.testAllLatencyTargets,
                  icon: tunController.latencyTesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.speed_rounded, size: 18),
                  label: const Text('全部测速'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: panelDecoration(),
              child: Column(
                children: [
                  for (final result in tunController.latencyResults)
                    _LatencyRow(
                      result: result,
                      onTest: () =>
                          tunController.testLatencyTarget(result.target),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LatencyRow extends StatelessWidget {
  const _LatencyRow({required this.result, required this.onTest});

  final LatencyProbeResult result;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(result.status);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(Icons.public_rounded, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.target.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  result.target.url,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 110,
            child: Text(
              _latencyText(result),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            onPressed: result.status == LatencyProbeStatus.testing
                ? null
                : onTest,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '测试',
          ),
        ],
      ),
    );
  }

  Color _statusColor(LatencyProbeStatus status) {
    return switch (status) {
      LatencyProbeStatus.success => _successLatencyColor(result.latencyMs ?? 0),
      LatencyProbeStatus.testing => AppColors.primary,
      LatencyProbeStatus.timeout ||
      LatencyProbeStatus.failed => AppColors.danger,
      LatencyProbeStatus.idle => AppColors.textSecondary,
    };
  }

  Color _successLatencyColor(int latencyMs) {
    if (latencyMs < 250) {
      return AppColors.success;
    }
    if (latencyMs < 600) {
      return AppColors.warning;
    }
    return AppColors.danger;
  }

  String _latencyText(LatencyProbeResult result) {
    return switch (result.status) {
      LatencyProbeStatus.success => '${result.latencyMs} ms',
      LatencyProbeStatus.testing => '测试中',
      LatencyProbeStatus.timeout => '超时',
      LatencyProbeStatus.failed => '失败',
      LatencyProbeStatus.idle => '未测试',
    };
  }
}
