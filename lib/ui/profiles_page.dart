import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../domain/acceleration_mode.dart';
import '../domain/sdwan_profile.dart';
import '../services/app_config_controller.dart';
import '../services/profile_import_export_service.dart';
import 'profile_editor_page.dart';
import 'theme.dart';

class ProfilesPage extends StatelessWidget {
  ProfilesPage({
    super.key,
    required this.controller,
    ProfileImportExportService? importExportService,
  }) : importExportService =
           importExportService ?? ProfileImportExportService();

  final AppConfigController controller;
  final ProfileImportExportService importExportService;

  static const _ovpnTypeGroup = XTypeGroup(
    label: 'OpenVPN',
    extensions: ['ovpn'],
  );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final config = controller.config;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Text('配置', style: Theme.of(context).textTheme.headlineMedium),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () => _importOvpn(context),
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('导入 .ovpn'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: () async {
                    final profile = SdwanProfile.openVpnDefaults().copyWith(
                      id: DateTime.now().microsecondsSinceEpoch.toString(),
                      name: 'OpenVPN UDP',
                    );
                    final result = await controller.addProfile(profile);
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(result.message)));
                    }
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('添加配置'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            for (final profile in config.profiles) ...[
              _ProfileCard(
                profile: profile,
                active: profile.id == config.activeProfileId,
                onUse: () => controller.setActiveProfile(profile.id),
                onEdit: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProfileEditorPage(
                        controller: controller,
                        profile: profile,
                      ),
                    ),
                  );
                },
                onExport: profile.mode == AccelerationMode.openVpn
                    ? () => _exportOvpn(context, profile)
                    : null,
                onDelete: config.profiles.length == 1
                    ? null
                    : () => controller.deleteProfile(profile.id),
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }

  Future<void> _importOvpn(BuildContext context) async {
    final file = await openFile(acceptedTypeGroups: [_ovpnTypeGroup]);
    if (file == null) {
      return;
    }
    final content = await file.readAsString();
    final profile = importExportService.importOvpnContent(
      content,
      fileName: file.name,
    );
    final result = await controller.addProfile(profile);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  Future<void> _exportOvpn(BuildContext context, SdwanProfile profile) async {
    final location = await getSaveLocation(
      acceptedTypeGroups: [_ovpnTypeGroup],
      suggestedName: '${profile.name}.ovpn',
    );
    if (location == null) {
      return;
    }
    final content = importExportService.exportOvpnContent(profile);
    await File(location.path).writeAsString(content);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('配置已导出，未包含密码')));
    }
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.active,
    required this.onUse,
    required this.onEdit,
    required this.onExport,
    required this.onDelete,
  });

  final SdwanProfile profile;
  final bool active;
  final VoidCallback onUse;
  final VoidCallback onEdit;
  final VoidCallback? onExport;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: panelDecoration(),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_modeIcon(profile.mode), color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        profile.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (active) ...[
                      const SizedBox(width: 8),
                      const _Badge(text: '当前'),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${_modeLabel(profile.mode)} · ${_endpointText(profile)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: active ? null : onUse,
            child: const Text('使用'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: onEdit, child: const Text('编辑')),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: onExport, child: const Text('导出')),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: '删除',
            color: AppColors.danger,
          ),
        ],
      ),
    );
  }

  IconData _modeIcon(AccelerationMode mode) {
    return switch (mode) {
      AccelerationMode.openVpn => Icons.vpn_lock_rounded,
      AccelerationMode.halfRoute => Icons.alt_route_rounded,
      AccelerationMode.legacyTun => Icons.hub_rounded,
    };
  }

  String _modeLabel(AccelerationMode mode) {
    return switch (mode) {
      AccelerationMode.openVpn => 'OpenVPN',
      AccelerationMode.halfRoute => 'Half Route',
      AccelerationMode.legacyTun => 'Legacy TUN',
    };
  }

  String _endpointText(SdwanProfile profile) {
    return switch (profile.mode) {
      AccelerationMode.openVpn =>
        '${profile.openVpn.remoteHost}:${profile.openVpn.remotePort}/${profile.openVpn.protocol.ovpnValue}',
      AccelerationMode.halfRoute => 'CPE ${profile.cpeIp}',
      AccelerationMode.legacyTun => 'CPE ${profile.cpeIp}',
    };
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
