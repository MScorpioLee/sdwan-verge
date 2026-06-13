import 'package:flutter/material.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    const items = [
      ('OpenVPN 加速', '客户端按当前 Profile 启动 OpenVPN，流量由 OpenVPN 虚拟网卡接管。'),
      (
        'macOS 安装',
        'macOS 首次使用时可在首页点击“安装 OpenVPN”。软件会优先通过 Homebrew 安装 openvpn；没有 Homebrew 时会提示先安装 Homebrew，或设置 SDWAN_OPENVPN_PATH 指向已有 openvpn。',
      ),
      ('配置管理', '可以导入 .ovpn，也可以手动编辑服务器、协议、端口、账号密码和自定义指令。'),
      ('退出保护', '从托盘退出时会先关闭 OpenVPN，避免后台残留加速进程。'),
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
