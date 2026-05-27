import 'package:flutter/material.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    const items = [
      ('为什么需要管理员权限', 'Windows 修改持久路由和网卡 DNS 需要管理员权限。软件启动时会自动触发 UAC。'),
      ('开启加速做了什么', '软件会添加 0.0.0.0/1 和 128.0.0.0/1 两条路由到配置的 CPE 网关，并刷新 DNS 缓存。'),
      ('关闭加速做了什么', '软件会删除两条加速路由，并刷新 DNS 缓存。'),
      ('DNS 同步开关', '默认关闭。开启后，开启加速会设置主备 DNS，关闭加速会恢复 DNS 自动获取。'),
      ('其它平台', '第一版 Windows 完整支持。macOS、Web、iOS、Android 会显示能力说明，不直接修改系统路由。'),
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
