import 'package:flutter/material.dart';

import '../services/sdwan_controller.dart';
import 'dashboard_page.dart';
import 'help_page.dart';
import 'logs_page.dart';
import 'settings_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});

  final SdwanController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(controller: widget.controller),
      SettingsPage(controller: widget.controller),
      LogsPage(controller: widget.controller),
      const HelpPage(),
    ];

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (value) => setState(() => _index = value),
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: Text('仪表盘'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: Text('设置'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long),
                  label: Text('日志'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.help_outline),
                  selectedIcon: Icon(Icons.help),
                  label: Text('帮助'),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: pages[_index]),
          ],
        ),
      ),
    );
  }
}
