import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/ledger.dart';
import '../../app_state.dart';
import '../../platform/update_watcher.dart';
import '../../platform/updates.dart';
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
  AppLifecycleListener? _lifecycle;
  UpdateWatcher? _updates;
  bool _offering = false;

  @override
  void initState() {
    super.initState();
    // The daily check runs in AppState.updates for as long as the process
    // lives; here we offer what it found: when it arrives, and each time
    // the app comes back to the front (at most once a day after "Later").
    if (!kIsWeb) {
      _updates = context.app.updates..addListener(_maybeOffer);
      _lifecycle = AppLifecycleListener(onResume: () {
        unawaited(_updates?.poll());
        _maybeOffer();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOffer());
    }
  }

  @override
  void dispose() {
    _updates?.removeListener(_maybeOffer);
    _lifecycle?.dispose();
    super.dispose();
  }

  Future<void> _maybeOffer() async {
    final w = _updates;
    if (w == null || _offering || !mounted) return;
    if (w.ready == null || (w.apk == null && UpdateService.canInstall)) return; // not downloaded yet
    if (!await w.shouldOffer()) return;
    if (!mounted) return;
    _offering = true;
    try {
      await w.offered(); // not again for a day unless they install
      if (mounted) await offerUpdate(context);
    } finally {
      _offering = false;
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
