import 'package:flutter/material.dart';

import '../tun/tun_controller.dart';
import 'theme.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key, required this.tunController});

  final TunController tunController;

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.tunController.refreshLogs();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.tunController,
      builder: (context, _) {
        final logs = widget.tunController.logs;
        return ListView(
          padding: const EdgeInsets.all(28),
          children: [
            Row(
              children: [
                const Text(
                  '事件日志',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: widget.tunController.refreshLogs,
                  icon: const Icon(Icons.refresh_rounded),
                  color: AppColors.textSecondary,
                  tooltip: '刷新日志',
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: panelDecoration(),
              child: logs.isEmpty
                  ? const _EmptyLog()
                  : Column(
                      children: [
                        for (var i = 0; i < logs.length; i++)
                          _LogTile(
                            time: logs[i].time,
                            message: logs[i].message,
                            isLast: i == logs.length - 1,
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

class _EmptyLog extends StatelessWidget {
  const _EmptyLog();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Text(
          '暂无事件',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({
    required this.time,
    required this.message,
    required this.isLast,
  });

  final String time;
  final String message;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(top: 5),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
            if (!isLast)
              Container(width: 1, height: 24, color: AppColors.border),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  time,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
