import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/sdwan_controller.dart';

class LogsPage extends StatelessWidget {
  const LogsPage({super.key, required this.controller});

  final SdwanController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final logs = controller.logs;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Text('日志', style: Theme.of(context).textTheme.headlineMedium),
                const Spacer(),
                IconButton.filledTonal(
                  tooltip: '复制日志',
                  onPressed: logs.isEmpty
                      ? null
                      : () => Clipboard.setData(
                          ClipboardData(
                            text: logs
                                .map(
                                  (log) =>
                                      '${log.displayTime} ${log.action} ${log.success ? '成功' : '失败'} ${log.message}',
                                )
                                .join('\n'),
                          ),
                        ),
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (logs.isEmpty) const Text('暂无操作日志'),
            for (final log in logs)
              ListTile(
                leading: Icon(log.success ? Icons.check_circle : Icons.error),
                title: Text('${log.displayTime} ${log.action}'),
                subtitle: Text(
                  [
                    log.message,
                    if (log.command != null) '命令：${log.command}',
                    if (log.exitCode != null) '退出码：${log.exitCode}',
                  ].join('\n'),
                ),
              ),
          ],
        );
      },
    );
  }
}
