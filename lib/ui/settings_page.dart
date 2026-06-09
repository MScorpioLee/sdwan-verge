import 'package:flutter/material.dart';

import '../services/app_config_controller.dart';
import '../tun/tun_controller.dart';
import 'theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    required this.tunController,
  });

  final AppConfigController controller;
  final TunController tunController;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.tunController.refreshLaunchAtLogin();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('设置', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 20),
        _SystemSettingsCard(tunController: widget.tunController),
        const SizedBox(height: 20),
        _TrafficHistorySwitch(
          value: widget.controller.config.retainTrafficHistory,
          onChanged: _setRetainTrafficHistory,
        ),
        const SizedBox(height: 12),
        _LaunchAtLoginSwitch(
          value: widget.tunController.launchAtLogin,
          busy: widget.tunController.busy,
          onChanged: _setLaunchAtLogin,
        ),
        if (_message != null) ...[const SizedBox(height: 12), Text(_message!)],
      ],
    );
  }

  Future<void> _setRetainTrafficHistory(bool value) async {
    final result = await widget.controller.setRetainTrafficHistory(value);
    await widget.tunController.setRetainTrafficHistory(value);
    if (!mounted) {
      return;
    }
    setState(() => _message = result.message);
  }

  Future<void> _setLaunchAtLogin(bool value) async {
    await widget.tunController.setLaunchAtLogin(value);
    if (!mounted) {
      return;
    }
    setState(() {
      _message = widget.tunController.launchAtLogin ? '已开启开机自动启动' : '已关闭开机自动启动';
    });
  }
}

class _LaunchAtLoginSwitch extends StatelessWidget {
  const _LaunchAtLoginSwitch({
    required this.value,
    required this.busy,
    required this.onChanged,
  });

  final bool value;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: panelDecoration(),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.power_settings_new_rounded,
              size: 18,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '开机自动启动',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '登录 macOS 后自动打开客户端，后台保持菜单栏入口。',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(value: value, onChanged: busy ? null : onChanged),
        ],
      ),
    );
  }
}

class _TrafficHistorySwitch extends StatelessWidget {
  const _TrafficHistorySwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: panelDecoration(),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.query_stats_rounded,
              size: 18,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '保留历史流量统计',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '关闭后每次启动 App 都重新统计；开启后保留最近的带宽趋势采样。',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _SystemSettingsCard extends StatelessWidget {
  const _SystemSettingsCard({required this.tunController});

  final TunController tunController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: tunController,
      builder: (context, _) {
        final status = tunController.status;
        final installed = status.helperInstalled;
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: panelDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '系统设置',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(
                    installed
                        ? Icons.check_circle_rounded
                        : Icons.pause_circle_outline_rounded,
                    color: installed
                        ? AppColors.success
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    '系统加速模式',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: installed ? '助手已安装，日常开关不再需要重复输入密码' : '首次安装需要管理员密码',
                    child: const Icon(
                      Icons.settings_rounded,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: tunController.busy || !installed
                        ? null
                        : tunController.uninstallHelper,
                    icon: const Icon(Icons.delete_outline_rounded),
                    tooltip: '卸载助手',
                    color: AppColors.danger,
                  ),
                  Switch(
                    value: installed,
                    onChanged: tunController.busy
                        ? null
                        : (value) {
                            if (value) {
                              tunController.installHelper();
                            } else {
                              tunController.uninstallHelper();
                            }
                          },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                installed ? '助手已注册，开启/关闭无需重复授权' : '未注册助手，开启/关闭会请求管理员授权',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
