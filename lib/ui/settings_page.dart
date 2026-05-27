import 'package:flutter/material.dart';

import '../domain/sdwan_profile.dart';
import '../services/sdwan_controller.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});

  final SdwanController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _company;
  late final TextEditingController _cpe;
  late final TextEditingController _primaryDns;
  late final TextEditingController _secondaryDns;
  late bool _syncDns;
  String? _message;

  @override
  void initState() {
    super.initState();
    final profile = widget.controller.config.activeProfile;
    _company = TextEditingController(text: profile.companyName);
    _cpe = TextEditingController(text: profile.cpeIp);
    _primaryDns = TextEditingController(text: profile.primaryDns);
    _secondaryDns = TextEditingController(text: profile.secondaryDns);
    _syncDns = profile.syncDnsWithAcceleration;
  }

  @override
  void dispose() {
    _company.dispose();
    _cpe.dispose();
    _primaryDns.dispose();
    _secondaryDns.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('设置', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 20),
        _Field(label: '公司名称', controller: _company),
        _Field(label: 'CPE 网关', controller: _cpe),
        _Field(label: '主 DNS', controller: _primaryDns),
        _Field(label: '备用 DNS', controller: _secondaryDns),
        SwitchListTile(
          title: const Text('路由操作同步 DNS'),
          subtitle: const Text('开启加速时设置 DNS，关闭加速时恢复自动获取'),
          value: _syncDns,
          onChanged: (value) => setState(() => _syncDns = value),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('保存配置'),
            ),
            OutlinedButton.icon(
              onPressed: _restoreDefaults,
              icon: const Icon(Icons.restore),
              label: const Text('恢复默认'),
            ),
          ],
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(_message!),
        ],
      ],
    );
  }

  Future<void> _save() async {
    final current = widget.controller.config.activeProfile;
    final result = await widget.controller.saveProfile(
      current.copyWith(
        companyName: _company.text.trim(),
        cpeIp: _cpe.text.trim(),
        primaryDns: _primaryDns.text.trim(),
        secondaryDns: _secondaryDns.text.trim(),
        syncDnsWithAcceleration: _syncDns,
      ),
    );
    setState(() => _message = result.message);
  }

  void _restoreDefaults() {
    final defaults = SdwanProfile.defaults();
    _company.text = defaults.companyName;
    _cpe.text = defaults.cpeIp;
    _primaryDns.text = defaults.primaryDns;
    _secondaryDns.text = defaults.secondaryDns;
    setState(() {
      _syncDns = defaults.syncDnsWithAcceleration;
      _message = '已恢复默认值，请点击保存配置';
    });
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
