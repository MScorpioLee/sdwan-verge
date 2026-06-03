import 'package:flutter/material.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    const items = [
      ('为什么需要管理员权限', 'Windows、macOS、Linux 修改系统路由和网卡 DNS 都需要管理员权限。Windows 使用 UAC，macOS 使用管理员授权，Linux 使用 pkexec。'),
      ('开启加速做了什么', '软件会添加 0.0.0.0/1 和 128.0.0.0/1 两条路由到配置的 CPE 网关，并刷新 DNS 缓存。'),
      ('关闭加速做了什么', '软件会删除两条加速路由，并刷新 DNS 缓存。'),
      ('DNS 同步开关', '默认关闭。开启后，开启加速会设置主备 DNS，关闭加速会恢复 DNS 自动获取。'),
      ('OpenWrt/iStoreOS 插件', '路由器插件可以让整网统一生效。Web、iOS、Android 先作为插件管理端，不直接修改本机系统路由。'),
      ('移动端限制', 'iOS 和 Android 不能像桌面端一样随意改全局路由和 DNS。若要本机接管流量，需要后续单独做 VPN/TUN 原生方案。'),
    ];

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('帮助', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        for (final item in items)
          Card(
            child: ListTile(title: Text(item.$1), subtitle: Text(item.$2)),
          ),
      ],
    );
  }
}
