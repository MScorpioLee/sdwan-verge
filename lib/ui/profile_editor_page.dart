import 'package:flutter/material.dart';

import '../domain/acceleration_mode.dart';
import '../domain/openvpn_profile.dart';
import '../domain/sdwan_profile.dart';
import '../services/app_config_controller.dart';
import 'theme.dart';

class ProfileEditorPage extends StatefulWidget {
  const ProfileEditorPage({
    super.key,
    required this.controller,
    required this.profile,
  });

  final AppConfigController controller;
  final SdwanProfile profile;

  @override
  State<ProfileEditorPage> createState() => _ProfileEditorPageState();
}

class _ProfileEditorPageState extends State<ProfileEditorPage> {
  late final TextEditingController _name;
  late final TextEditingController _cpe;
  late final TextEditingController _remoteHost;
  late final TextEditingController _remotePort;
  late final TextEditingController _customDirectives;
  late OpenVpnProtocol _protocol;
  late bool _syncDns;
  late bool _ipv4Only;
  late bool _authUserPass;
  String? _message;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    final openVpn = profile.openVpn;
    _name = TextEditingController(text: profile.name);
    _cpe = TextEditingController(text: profile.cpeIp);
    _remoteHost = TextEditingController(text: openVpn.remoteHost);
    _remotePort = TextEditingController(text: openVpn.remotePort.toString());
    _customDirectives = TextEditingController(
      text: openVpn.customDirectives.join('\n'),
    );
    _protocol = openVpn.protocol;
    _syncDns = profile.syncDnsWithAcceleration;
    _ipv4Only = openVpn.ipv4Only;
    _authUserPass = openVpn.authUserPass;
  }

  @override
  void dispose() {
    _name.dispose();
    _cpe.dispose();
    _remoteHost.dispose();
    _remotePort.dispose();
    _customDirectives.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('编辑配置'),
        backgroundColor: AppColors.bg,
        surfaceTintColor: AppColors.bg,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _Section(
            title: '基本信息',
            children: [
              _Field(label: '配置名称', controller: _name),
              _Field(label: 'CPE 地址', controller: _cpe),
              SwitchListTile(
                key: const ValueKey('profile-sync-dns-switch'),
                value: _syncDns,
                onChanged: (value) => setState(() => _syncDns = value),
                title: const Text('DNS 跟随 CPE'),
                subtitle: const Text('开启当前配置时把 IPv4 DNS 临时指向 CPE'),
              ),
            ],
          ),
          if (profile.mode == AccelerationMode.openVpn) ...[
            const SizedBox(height: 16),
            _Section(
              title: 'OpenVPN',
              children: [
                SegmentedButton<OpenVpnProtocol>(
                  segments: const [
                    ButtonSegment(
                      value: OpenVpnProtocol.udp4,
                      label: Text('UDP IPv4'),
                    ),
                    ButtonSegment(
                      value: OpenVpnProtocol.tcpClient,
                      label: Text('TCP IPv4'),
                    ),
                  ],
                  selected: {_protocol},
                  onSelectionChanged: (value) {
                    setState(() => _protocol = value.single);
                  },
                ),
                const SizedBox(height: 12),
                _Field(label: '服务器地址', controller: _remoteHost),
                _Field(label: '端口', controller: _remotePort),
                SwitchListTile(
                  value: _ipv4Only,
                  onChanged: (value) => setState(() => _ipv4Only = value),
                  title: const Text('仅 IPv4'),
                  subtitle: const Text('忽略 OpenVPN 服务端推送的 IPv6 路由'),
                ),
                SwitchListTile(
                  value: _authUserPass,
                  onChanged: (value) {
                    setState(() => _authUserPass = value);
                  },
                  title: const Text('需要账号密码'),
                  subtitle: const Text('密码后续保存到系统安全存储，不进入导出配置'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _Section(
              title: 'OpenVPN 自定义配置',
              children: [
                TextField(
                  controller: _customDirectives,
                  minLines: 6,
                  maxLines: 12,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'verb 3\nnobind\nresolv-retry infinite',
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_rounded),
                label: const Text('保存配置'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded),
                label: const Text('取消'),
              ),
            ],
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, style: const TextStyle(color: AppColors.primary)),
          ],
        ],
      ),
    );
  }

  Future<void> _save() async {
    final current = widget.profile;
    final openVpn = current.openVpn.copyWith(
      remoteHost: _remoteHost.text.trim(),
      remotePort: int.tryParse(_remotePort.text.trim()) ?? 0,
      protocol: _protocol,
      authUserPass: _authUserPass,
      ipv4Only: _ipv4Only,
      pullFilterIpv6: _ipv4Only,
      customDirectives: _customDirectives.text
          .split('\n')
          .map((line) => line.trimRight())
          .where((line) => line.trim().isNotEmpty)
          .toList(),
    );
    final updated = current.copyWith(
      name: _name.text.trim().isEmpty ? current.name : _name.text.trim(),
      cpeIp: _cpe.text.trim().isEmpty ? current.cpeIp : _cpe.text.trim(),
      syncDnsWithAcceleration: _syncDns,
      openVpn: openVpn,
    );
    final result = await widget.controller.saveProfile(updated);
    if (!mounted) {
      return;
    }
    setState(() => _message = result.message);
    if (result.success) {
      Navigator.of(context).maybePop();
    }
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
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
