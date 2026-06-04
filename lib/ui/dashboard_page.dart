import 'package:flutter/material.dart';

import '../services/app_config_controller.dart';
import '../tun/tun_controller.dart';
import '../tun/tun_models.dart';

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
        final canStart =
            !tunController.busy &&
            status.permission != TunPermission.unsupported &&
            status.state != TunState.running;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'SD-WAN Verge',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _StatusCard(
                  title: 'TUN 状态',
                  value: _stateText(status.state),
                  subtitle: _stateSubtitle(status.state),
                  icon: Icons.hub,
                ),
                _StatusCard(
                  title: 'CPE 状态',
                  value: cpe.reachable ? '已连接' : '未连接',
                  subtitle: '${cpe.host}${cpe.serviceReady ? ' · 服务可用' : ''}',
                  icon: Icons.router,
                ),
                _StatusCard(
                  title: '权限状态',
                  value: _permissionText(status.permission),
                  subtitle: '不修改物理网卡、默认网关或系统 DNS',
                  icon: Icons.verified_user,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: canStart ? tunController.start : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('开启 TUN'),
                ),
                OutlinedButton.icon(
                  onPressed: tunController.busy ? null : tunController.stop,
                  icon: const Icon(Icons.stop),
                  label: const Text('关闭 TUN'),
                ),
                IconButton.filledTonal(
                  onPressed: tunController.busy
                      ? null
                      : tunController.initialize,
                  icon: const Icon(Icons.refresh),
                  tooltip: '刷新状态',
                ),
              ],
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '当前配置：TUN 入口指向 CPE ${profile.cpeIp}。'
                  '如果连续检测不到 CPE，软件会自动停止 TUN，系统流量回到本机直连。',
                ),
              ),
            ),
            if (status.lastError != null) ...[
              const SizedBox(height: 12),
              Text(
                status.permission == TunPermission.unsupported
                    ? '当前平台暂未接入 TUN 原生服务：${status.lastError}'
                    : status.lastError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
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
      TunState.running => '正在通过虚拟网卡接管流量',
      _ => '等待启动',
    };
  }

  String _permissionText(TunPermission permission) {
    return switch (permission) {
      TunPermission.ready => '已授权',
      TunPermission.needsVpnConsent => '等待 VPN/TUN 授权',
      TunPermission.needsHelperInstall => '需要安装本机助手',
      TunPermission.denied => '授权被拒绝',
      TunPermission.unsupported => '暂未接入',
    };
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.title,
    required this.value,
    required this.icon,
    this.subtitle,
  });

  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(value, style: Theme.of(context).textTheme.titleLarge),
              if (subtitle != null && subtitle!.isNotEmpty) Text(subtitle!),
            ],
          ),
        ),
      ),
    );
  }
}
