import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/ledger.dart';
import '../../app_state.dart';
import '../widgets/common.dart';
import 'buildings.dart';
import 'dashboard.dart';
import 'expenses.dart';
import 'settings.dart';
import 'stats.dart';
import 'update_dialog.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // Once a day, offer the latest GitHub release (no-op on the web).
    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final app = context.app;
        final last = int.tryParse(await app.store.getMeta('update_check') ?? '') ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - last < const Duration(hours: 20).inMilliseconds) return;
        await app.store.exec('INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)', ['update_check', '$now']);
        if (mounted) await checkForUpdates(context);
      });
    }
  }

  static const _pages = [
    DashboardScreen(),
    BuildingsScreen(),
    ExpensesScreen(),
    StatsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    context.select<Ledger, int>((l) => l.revision);
    return FutureBuilder<bool>(
      future: app.q.onlyTenant(app.identity.pubkey),
      builder: (context, snap) => _shell(context, snap.data ?? false),
    );
  }

  Widget _shell(BuildContext context, bool partial) {
    final l = context.l;
    // Tenants and workers hold nothing to total up: their buildings and More.
    final all = [
      (Icons.dashboard_outlined, Icons.dashboard, l.dashboard, 0),
      (Icons.apartment_outlined, Icons.apartment, l.buildings, 1),
      (Icons.receipt_long_outlined, Icons.receipt_long, l.expenses, 2),
      (Icons.bar_chart_outlined, Icons.bar_chart, l.statistics, 3),
      (Icons.more_horiz, Icons.more_horiz, l.more, 4),
    ];
    final dests = partial ? [all[1], all[4]] : all;
    if (_tab >= dests.length) _tab = 0;
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final body = IndexedStack(index: dests[_tab].$4, children: _pages);
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
