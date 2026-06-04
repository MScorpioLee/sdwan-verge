import 'package:flutter/material.dart';

import '../services/app_config_controller.dart';
import '../tun/tun_controller.dart';
import 'dashboard_page.dart';
import 'help_page.dart';
import 'settings_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.configController,
    required this.tunController,
  });

  final AppConfigController configController;
  final TunController tunController;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(
        configController: widget.configController,
        tunController: widget.tunController,
      ),
      SettingsPage(controller: widget.configController),
      const HelpPage(),
    ];

    final destinations = const [
      _Destination(
        label: '仪表盘',
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard,
      ),
      _Destination(
        label: '设置',
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
      ),
      _Destination(
        label: '帮助',
        icon: Icons.help_outline,
        selectedIcon: Icons.help,
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 720) {
              return Column(
                children: [
                  Expanded(child: pages[_index]),
                  NavigationBar(
                    selectedIndex: _index,
                    onDestinationSelected: (value) {
                      setState(() => _index = value);
                    },
                    destinations: [
                      for (final destination in destinations)
                        NavigationDestination(
                          icon: Icon(destination.icon),
                          selectedIcon: Icon(destination.selectedIcon),
                          label: destination.label,
                        ),
                    ],
                  ),
                ],
              );
            }

            return Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: (value) {
                    setState(() => _index = value);
                  },
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final destination in destinations)
                      NavigationRailDestination(
                        icon: Icon(destination.icon),
                        selectedIcon: Icon(destination.selectedIcon),
                        label: Text(destination.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: pages[_index]),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Destination {
  const _Destination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
