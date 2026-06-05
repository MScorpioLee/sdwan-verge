import 'package:flutter/material.dart';

import '../services/app_config_controller.dart';
import '../tun/tun_controller.dart';
import '../tun/tun_models.dart';
import 'theme.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({
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
        final profile = configController.config.activeProfile;
        final status = tunController.status;
        final cpe = status.cpe;
        final running = status.state == TunState.running;
        final halfRoute =
            status.adapterName.toLowerCase().contains('half route') ||
            status.adapterName.contains('半路由');
        final canStart =
            !tunController.busy &&
            status.permission != TunPermission.unsupported &&
            status.state != TunState.running;

        return ListView(
          padding: const EdgeInsets.all(28),
          children: [
            Row(
              children: [
                const Text(
                  '仪表盘',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: tunController.busy
                      ? null
                      : tunController.initialize,
                  icon: const Icon(Icons.refresh_rounded),
                  color: AppColors.textSecondary,
                  tooltip: '刷新状态',
                ),
              ],
            ),
            const SizedBox(height: 18),
            _PowerCard(
              running: running,
              busy: tunController.busy,
              stateText: _stateText(status.state),
              subtitle: _stateSubtitle(status.state),
              canStart: canStart,
              onStart: tunController.start,
              onStop: tunController.stop,
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, c) {
                final twoCol = c.maxWidth > 620;
                final cardW = twoCol ? (c.maxWidth - 16) / 2 : c.maxWidth;
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    SizedBox(
                      width: cardW,
                      child: _InfoCard(
                        icon: Icons.router_rounded,
                        title: 'CPE 网关',
                        value: cpe.reachable ? '已连接' : '未连接',
                        valueColor: cpe.reachable
                            ? AppColors.success
                            : AppColors.danger,
                        rows: [
                          _Kv('地址', cpe.host),
                          _Kv('服务', cpe.serviceReady ? '可用' : '待检测'),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: cardW,
                      child: _InfoCard(
                        icon: Icons.verified_user_rounded,
                        title: '运行信息',
                        value: _permissionText(status),
                        valueColor: status.helperInstalled
                            ? AppColors.primary
                            : AppColors.warning,
                        trailing: status.helperInstalled
                            ? IconButton(
                                onPressed: tunController.busy
                                    ? null
                                    : tunController.uninstallHelper,
                                icon: const Icon(Icons.delete_outline_rounded),
                                tooltip: '卸载助手',
                                color: AppColors.danger,
                              )
                            : null,
                        rows: [
                          _Kv('入口', status.adapterName),
                          _Kv('出口', 'CPE ${profile.cpeIp}'),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: c.maxWidth,
                      child: _TrafficCard(stats: status.traffic),
                    ),
                    SizedBox(
                      width: c.maxWidth,
                      child: _DiagnosticsCard(diagnostics: status.diagnostics),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            _NoteCard(
              text: halfRoute
                  ? 'IPv4 流量通过系统半路由交给 CPE ${profile.cpeIp}，源 IP 保持不变，由 CPE 负责分流。'
                        '若连续检测不到 CPE，将自动删除半路由并回切本机直连，本轮不改 DNS。'
                  : '当前入口为 ${status.adapterName}，需要本地 helper/service 数据面转发到 CPE ${profile.cpeIp}。'
                        '若连续检测不到 CPE，将自动停止并回切本机直连。',
            ),
            if (status.lastError != null && status.lastError!.isNotEmpty) ...[
              const SizedBox(height: 16),
              _ErrorCard(text: status.lastError!),
            ],
          ],
        );
      },
    );
  }

  String _stateText(TunState state) {
    return switch (state) {
      TunState.stopped => '未运行',
      TunState.starting => '启动中',
      TunState.running => '运行中',
      TunState.stopping => '停止中',
      TunState.failed => '启动失败',
      TunState.autoRecovered => '已自动切回',
    };
  }

  String _stateSubtitle(TunState state) {
    return switch (state) {
      TunState.autoRecovered => 'CPE 异常，已恢复本机直连',
      TunState.running => '正在通过半路由交给 CPE',
      TunState.starting => '正在配置半路由…',
      TunState.stopping => '正在恢复直连…',
      TunState.failed => '启动失败，请查看下方提示',
      TunState.stopped => '点击右侧按钮开启加速',
    };
  }

  String _permissionText(TunStatus status) {
    if (!status.helperInstalled) {
      return '待安装助手';
    }
    return switch (status.permission) {
      TunPermission.ready => '已授权',
      TunPermission.needsVpnConsent => '等待授权',
      TunPermission.needsHelperInstall => '待安装助手',
      TunPermission.denied => '授权被拒绝',
      TunPermission.unsupported => '暂未接入',
    };
  }
}

/// 顶部主开关大卡：运行时蓝色渐变，停止时白底。
class _PowerCard extends StatelessWidget {
  const _PowerCard({
    required this.running,
    required this.busy,
    required this.stateText,
    required this.subtitle,
    required this.canStart,
    required this.onStart,
    required this.onStop,
  });

  final bool running;
  final bool busy;
  final String stateText;
  final String subtitle;
  final bool canStart;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: running ? kPrimaryGradient : null,
        color: running ? null : AppColors.card,
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(
          color: running ? Colors.transparent : AppColors.border,
        ),
        boxShadow: kCardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: running ? AppColors.white18 : AppColors.primarySoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              running ? Icons.shield_rounded : Icons.shield_outlined,
              color: running ? Colors.white : AppColors.primary,
              size: 28,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '国际网络加速',
                  style: TextStyle(
                    fontSize: 13,
                    color: running
                        ? AppColors.white70
                        : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  stateText,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: running ? Colors.white : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: running
                        ? AppColors.white70
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _PowerButton(
            running: running,
            busy: busy,
            canStart: canStart,
            onStart: onStart,
            onStop: onStop,
          ),
        ],
      ),
    );
  }
}

class _TrafficCard extends StatelessWidget {
  const _TrafficCard({required this.stats});

  final TrafficStats stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.swap_vert_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                '流量统计',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _TrafficMetric(
                label: '累计上行',
                value: _formatBytes(stats.txBytes),
                icon: Icons.upload_rounded,
              ),
              _TrafficMetric(
                label: '累计下行',
                value: _formatBytes(stats.rxBytes),
                icon: Icons.download_rounded,
              ),
              _TrafficMetric(
                label: '上行速率',
                value: _formatRate(stats.txRate),
                icon: Icons.north_east_rounded,
              ),
              _TrafficMetric(
                label: '下行速率',
                value: _formatRate(stats.rxRate),
                icon: Icons.south_west_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrafficMetric extends StatelessWidget {
  const _TrafficMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 142,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: AppColors.primary),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticsCard extends StatelessWidget {
  const _DiagnosticsCard({required this.diagnostics});

  final TunDiagnostics diagnostics;

  @override
  Widget build(BuildContext context) {
    final warningColor = diagnostics.hasWarnings
        ? AppColors.warning
        : AppColors.success;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  diagnostics.hasWarnings
                      ? Icons.warning_amber_rounded
                      : Icons.health_and_safety_rounded,
                  size: 18,
                  color: warningColor,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                '链路诊断',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _TrafficMetric(
                label: '出站包',
                value: diagnostics.txPackets.toString(),
                icon: Icons.call_made_rounded,
              ),
              _TrafficMetric(
                label: '回程包',
                value: diagnostics.rxPackets.toString(),
                icon: Icons.call_received_rounded,
              ),
              _TrafficMetric(
                label: '出站丢弃',
                value: diagnostics.txDropped.toString(),
                icon: Icons.upload_file_rounded,
              ),
              _TrafficMetric(
                label: '回程丢弃',
                value: diagnostics.rxDropped.toString(),
                icon: Icons.download_for_offline_rounded,
              ),
              _TrafficMetric(
                label: 'NAT Miss',
                value: diagnostics.natMisses.toString(),
                icon: Icons.link_off_rounded,
              ),
              _TrafficMetric(
                label: '发送失败',
                value: diagnostics.sendFailures.toString(),
                icon: Icons.error_outline_rounded,
              ),
              _TrafficMetric(
                label: 'UDP 443',
                value: diagnostics.udp443Packets.toString(),
                icon: Icons.bolt_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PowerButton extends StatelessWidget {
  const _PowerButton({
    required this.running,
    required this.busy,
    required this.canStart,
    required this.onStart,
    required this.onStop,
  });

  final bool running;
  final bool busy;
  final bool canStart;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return Container(
        width: 116,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: running ? AppColors.white24 : AppColors.primarySoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: running ? Colors.white : AppColors.primary,
          ),
        ),
      );
    }

    final style = FilledButton.styleFrom(
      backgroundColor: running ? Colors.white : AppColors.primary,
      foregroundColor: running ? AppColors.primary : Colors.white,
      disabledBackgroundColor: AppColors.border,
      disabledForegroundColor: AppColors.textSecondary,
      minimumSize: const Size(116, 44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
    );

    return FilledButton(
      onPressed: running ? onStop : (canStart ? onStart : null),
      style: style,
      child: Text(running ? '关闭' : '开启加速'),
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

class _Kv {
  const _Kv(this.label, this.value);
  final String label;
  final String value;
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.valueColor,
    required this.rows,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color valueColor;
  final List<_Kv> rows;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: valueColor,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 4),
                SizedBox(width: 32, height: 32, child: trailing),
              ],
            ],
          ),
          const SizedBox(height: 14),
          for (final r in rows) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Text(
                    r.label,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    r.value,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: panelDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: AppColors.danger,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: Color(0xFF991B1B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
