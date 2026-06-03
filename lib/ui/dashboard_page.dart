import 'package:flutter/material.dart';

import '../domain/network_status.dart';
import '../services/sdwan_controller.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.controller});

  final SdwanController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final status = controller.status;
        final profile = controller.config.activeProfile;
        final canOperateLocally = status.capability == PlatformCapability.full;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('SD-WAN Verge', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _StatusCard(
                  title: '加速状态',
                  value: status.accelerationEnabled ? '已开启' : '未开启',
                  icon: Icons.speed,
                ),
                _StatusCard(
                  title: '活动网卡',
                  value: status.activeInterfaceName ?? '未检测到',
                  subtitle: status.activeInterfaceIp,
                  icon: Icons.lan,
                ),
                _StatusCard(
                  title: '当前 DNS',
                  value: _dnsModeText(status.dnsMode),
                  subtitle: status.dnsServers.join(' / '),
                  icon: Icons.dns,
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
                  onPressed: controller.busy || !canOperateLocally
                      ? null
                      : () => controller.enableAcceleration(),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('开启加速'),
                ),
                OutlinedButton.icon(
                  onPressed: controller.busy || !canOperateLocally
                      ? null
                      : () => controller.disableAcceleration(),
                  icon: const Icon(Icons.stop),
                  label: const Text('关闭加速'),
                ),
                IconButton.filledTonal(
                  onPressed: controller.busy ? null : controller.refreshStatus,
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
                  '当前配置：CPE ${profile.cpeIp}，DNS ${profile.primaryDns} / ${profile.secondaryDns}，'
                  '同步 DNS：${profile.syncDnsWithAcceleration ? '开启' : '关闭'}',
                ),
              ),
            ),
            if (status.message != null) ...[
              const SizedBox(height: 12),
              Text(
                status.message!,
                style: TextStyle(
                  color: canOperateLocally
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  String _dnsModeText(DnsMode mode) {
    return switch (mode) {
      DnsMode.dhcp => '自动获取',
      DnsMode.static => '静态 DNS',
      DnsMode.unknown => '未知',
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
