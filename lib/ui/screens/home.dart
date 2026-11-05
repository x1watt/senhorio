import 'package:flutter/material.dart';

import '../widgets/common.dart';
import 'buildings.dart';
import 'dashboard.dart';
import 'expenses.dart';
import 'settings.dart';
import 'stats.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  static const _pages = [
    DashboardScreen(),
    BuildingsScreen(),
    ExpensesScreen(),
    StatsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final dests = [
      (Icons.dashboard_outlined, Icons.dashboard, l.dashboard),
      (Icons.apartment_outlined, Icons.apartment, l.buildings),
      (Icons.receipt_long_outlined, Icons.receipt_long, l.expenses),
      (Icons.bar_chart_outlined, Icons.bar_chart, l.statistics),
      (Icons.more_horiz, Icons.more_horiz, l.more),
    ];
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final body = IndexedStack(index: _tab, children: _pages);
    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: _tab,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [
              for (final d in dests)
                NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          for (final d in dests)
            NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
        ],
      ),
    );
  }
}
