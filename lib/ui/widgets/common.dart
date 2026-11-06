// Small widgets shared by every screen.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/money.dart';
import '../../data/ledger.dart';
import '../../data/zx_store.dart';
import '../../l10n/gen/app_localizations.dart';

extension Ctx on BuildContext {
  AppLocalizations get l => AppLocalizations.of(this);
  AppState get app => read<AppState>();
  String get localeName => Localizations.localeOf(this).toString();
  String money(int? cents, {String currency = 'EUR'}) =>
      formatMoney(cents ?? 0, currency: currency, locale: localeName);
  void toast(String msg) =>
      ScaffoldMessenger.of(this).showSnackBar(SnackBar(content: Text(msg)));
}

/// Loads [load] again whenever the ledger changes (watches its revision).
/// While it reloads it keeps showing the previous data, and the widgets
/// below keep their state (selected tab, scroll position, open tiles).
class LiveFuture<T> extends StatelessWidget {
  final Future<T> Function(AppState app) load;
  final Widget Function(BuildContext context, T data) builder;
  const LiveFuture({super.key, required this.load, required this.builder});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    // Rebuilding on a new revision starts a new load.
    context.select<Ledger, int>((l) => l.revision);
    return FutureBuilder<T>(
      future: load(app),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('${snap.error}', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ));
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        return builder(context, snap.data as T);
      },
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const EmptyState(this.icon, this.text, {super.key});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          ]),
        ),
      );
}

Future<bool> confirm(BuildContext context, String message) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(c.l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(c.l.ok)),
        ],
      ),
    ) ??
    false;

/// Runs a write and reports a failure (e.g. not allowed) as a snackbar.
Future<void> guarded(BuildContext context, Future<void> Function() body) async {
  try {
    await body();
  } catch (e) {
    if (context.mounted) context.toast('$e');
  }
}

/// Section title inside lists.
class SectionHeader extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionHeader(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
        child: Row(children: [
          Expanded(
            child: Text(text,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary)),
          ),
          ?trailing,
        ]),
      );
}

const categoryIcons = <String, IconData>{
  'water_drop': Icons.water_drop,
  'bolt': Icons.bolt,
  'local_fire_department': Icons.local_fire_department,
  'wifi': Icons.wifi,
  'apartment': Icons.apartment,
  'construction': Icons.construction,
  'handyman': Icons.handyman,
  'cleaning_services': Icons.cleaning_services,
  'restaurant': Icons.restaurant,
  'chair': Icons.chair,
  'shield': Icons.shield,
  'account_balance': Icons.account_balance,
  'category': Icons.category,
  'receipt': Icons.receipt_long,
  'home': Icons.home,
  'car': Icons.directions_car,
};

/// Display name of a category row (default categories are translated).
String categoryName(BuildContext context, DbRow? c) {
  if (c == null) return context.l.uncategorised;
  final n = c['name'] as String?;
  if (n != null && n.isNotEmpty) return n;
  return context.l.defaultCategory(c['key'] as String? ?? 'other');
}

class CategoryAvatar extends StatelessWidget {
  final DbRow? category;
  final double radius;
  const CategoryAvatar(this.category, {super.key, this.radius = 18});
  @override
  Widget build(BuildContext context) {
    final color = Color((category?['color'] as int?) ?? 0xFF9E9E9E);
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.18),
      child: Icon(categoryIcons[category?['icon']] ?? Icons.category,
          color: color, size: radius * 1.1),
    );
  }
}

/// Shows [child] unless this person only holds buildings as a tenant
/// (who changes nothing); nothing while it is being checked.
class StaffOnly extends StatelessWidget {
  final Widget child;
  const StaffOnly({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    context.select<Ledger, int>((l) => l.revision);
    return FutureBuilder<bool>(
      future: app.q.onlyTenant(app.identity.pubkey),
      builder: (context, snap) => snap.data == false ? child : const SizedBox.shrink(),
    );
  }
}
