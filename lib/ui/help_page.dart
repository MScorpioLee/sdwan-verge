import 'package:flutter/material.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    const items = [
      ('TUN 模式', '软件只使用虚拟网卡接管流量，不直接修改物理网卡 IP、默认网关或系统 DNS。'),
      ('CPE 入口', 'TUN 后端把需要接管的流量转发到配置的 CPE 地址，CPE 保持标准局域网入口即可。'),
      ('自动切回', '软件会持续检测虚拟网卡和 CPE 的连接，连续失败后自动停止 TUN，让系统恢复本机直连。'),
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
