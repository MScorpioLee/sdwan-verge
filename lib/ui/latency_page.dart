import 'package:flutter/material.dart';

import '../services/app_config_controller.dart';
import '../tun/tun_controller.dart';
import '../tun/tun_models.dart';
import 'theme.dart';

class LatencyPage extends StatelessWidget {
  const LatencyPage({
    super.key,
    required this.configController,
    required this.tunController,
  });

  final AppConfigController configController;
  final TunController tunController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([configController, tunController]),
      builder: (context, _) {
        final results = tunController.latencyResults;
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
                OutlinedButton.icon(
                  onPressed: () => _restoreDefaults(context),
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  label: const Text('恢复默认'),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () => _showEditor(context),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('添加网站'),
                ),
                const SizedBox(width: 10),
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
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: panelDecoration(),
              child: results.isEmpty
                  ? const _EmptyLatencyTargets()
                  : Column(
                      children: [
                        for (var i = 0; i < results.length; i++)
                          _LatencyRow(
                            result: results[i],
                            isLast: i == results.length - 1,
                            canDelete: results.length > 1,
                            onTest: () => tunController.testLatencyTarget(
                              results[i].target,
                            ),
                            onEdit: () =>
                                _showEditor(context, target: results[i].target),
                            onDelete: () =>
                                _deleteTarget(context, results[i].target),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showEditor(
    BuildContext context, {
    LatencyTarget? target,
  }) async {
    final value = await showDialog<_LatencyFormValue>(
      context: context,
      builder: (_) => _LatencyTargetDialog(target: target),
    );
    if (value == null || !context.mounted) {
      return;
    }

    final result = target == null
        ? await configController.addLatencyTarget(
            name: value.name,
            url: value.url,
          )
        : await configController.updateLatencyTarget(
            target.copyWith(name: value.name, url: value.url),
          );
    _syncTargets();
    if (context.mounted) {
      _showSnack(context, result.message);
    }
  }

  Future<void> _deleteTarget(BuildContext context, LatencyTarget target) async {
    final result = await configController.deleteLatencyTarget(target.id);
    _syncTargets();
    if (context.mounted) {
      _showSnack(context, result.message);
    }
  }

  Future<void> _restoreDefaults(BuildContext context) async {
    final result = await configController.restoreDefaultLatencyTargets();
    _syncTargets();
    if (context.mounted) {
      _showSnack(context, result.message);
    }
  }

  void _syncTargets() {
    tunController.setLatencyTargets(configController.config.latencyTargets);
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}

class _LatencyRow extends StatelessWidget {
  const _LatencyRow({
    required this.result,
    required this.isLast,
    required this.canDelete,
    required this.onTest,
    required this.onEdit,
    required this.onDelete,
  });

  final LatencyProbeResult result;
  final bool isLast;
  final bool canDelete;
  final VoidCallback onTest;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(result.status);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: AppColors.border)),
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
            width: 92,
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
          const SizedBox(width: 8),
          IconButton(
            onPressed: result.status == LatencyProbeStatus.testing
                ? null
                : onTest,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '测试',
          ),
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_rounded),
            tooltip: '编辑网站',
          ),
          IconButton(
            onPressed: canDelete ? onDelete : null,
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: '删除网站',
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

class _LatencyTargetDialog extends StatefulWidget {
  const _LatencyTargetDialog({this.target});

  final LatencyTarget? target;

  @override
  State<_LatencyTargetDialog> createState() => _LatencyTargetDialogState();
}

class _LatencyTargetDialogState extends State<_LatencyTargetDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _url;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.target?.name ?? '');
    _url = TextEditingController(text: widget.target?.url ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.target == null ? '添加测速网站' : '编辑测速网站'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: '名称'),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请输入名称' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _url,
                decoration: const InputDecoration(labelText: 'URL'),
                validator: (value) {
                  final uri = Uri.tryParse(value?.trim() ?? '');
                  if (uri == null ||
                      !uri.hasAuthority ||
                      (uri.scheme != 'http' && uri.scheme != 'https')) {
                    return '请输入 http 或 https 地址';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) {
              return;
            }
            Navigator.of(context).pop(
              _LatencyFormValue(name: _name.text.trim(), url: _url.text.trim()),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _LatencyFormValue {
  const _LatencyFormValue({required this.name, required this.url});

  final String name;
  final String url;
}

class _EmptyLatencyTargets extends StatelessWidget {
  const _EmptyLatencyTargets();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Text(
          '暂无测速网站',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
