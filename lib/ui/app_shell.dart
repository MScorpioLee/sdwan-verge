import 'package:flutter/material.dart';

import '../services/app_config_controller.dart';
import '../tun/tun_controller.dart';
import '../tun/tun_models.dart';
import 'connections_page.dart';
import 'dashboard_page.dart';
import 'help_page.dart';
import 'logs_page.dart';
import 'settings_page.dart';
import 'theme.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.configController,
    required this.tunController,
  });

  final AppConfigController configController;
  final TunController tunController;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  var _index = 0;

  static const _items = [
    _NavMeta('仪表盘', Icons.dashboard_rounded),
    _NavMeta('连接', Icons.hub_rounded),
    _NavMeta('日志', Icons.receipt_long_rounded),
    _NavMeta('设置', Icons.tune_rounded),
    _NavMeta('帮助', Icons.help_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(
        configController: widget.configController,
        tunController: widget.tunController,
      ),
      ConnectionsPage(tunController: widget.tunController),
      LogsPage(tunController: widget.tunController),
      SettingsPage(
        controller: widget.configController,
        tunController: widget.tunController,
      ),
      const HelpPage(),
    ];

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            _Sidebar(
              items: _items,
              selectedIndex: _index,
              onSelect: (i) => setState(() => _index = i),
              tunController: widget.tunController,
            ),
            Expanded(child: pages[_index]),
          ],
        ),
      ),
    );
  }
}

class _NavMeta {
  const _NavMeta(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
    required this.tunController,
  });

  final List<_NavMeta> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final TunController tunController;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 224,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Brand(),
          const SizedBox(height: 8),
          for (var i = 0; i < items.length; i++)
            _NavTile(
              meta: items[i],
              selected: i == selectedIndex,
              onTap: () => onSelect(i),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _StatusFooter(tunController: tunController),
          ),
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: kPrimaryGradient,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.rocket_launch_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'SD-WAN',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  height: 1.15,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                'Verge 加速器',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.meta,
    required this.selected,
    required this.onTap,
  });

  final _NavMeta meta;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: selected ? AppColors.primarySoft : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                Icon(
                  meta.icon,
                  size: 20,
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                ),
                const SizedBox(width: 12),
                Text(
                  meta.label,
                  style: TextStyle(
                    color: selected ? AppColors.primary : AppColors.textPrimary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusFooter extends StatelessWidget {
  const _StatusFooter({required this.tunController});

  final TunController tunController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: tunController,
      builder: (context, _) {
        final status = tunController.status;
        final running = status.state == TunState.running;
        final reachable = status.cpe.reachable;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: panelDecoration(color: AppColors.bg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row(
                'CPE',
                reachable ? '已连接' : '未连接',
                reachable ? AppColors.success : AppColors.danger,
              ),
              const SizedBox(height: 10),
              _row(
                '加速',
                running ? '运行中' : '已停止',
                running ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(height: 10),
              _row(
                '上行速率',
                _formatRate(status.traffic.txRate),
                AppColors.textPrimary,
              ),
              const SizedBox(height: 10),
              _row(
                '下行速率',
                _formatRate(status.traffic.rxRate),
                AppColors.textPrimary,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(String label, String value, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

String _formatRate(int bytesPerSecond) => '${_formatBytes(bytesPerSecond)}/s';

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final kb = bytes / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(kb >= 10 ? 0 : 1)} KB';
  }
  final mb = kb / 1024;
  if (mb < 1024) {
    return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
  }
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(gb >= 10 ? 0 : 1)} GB';
}
