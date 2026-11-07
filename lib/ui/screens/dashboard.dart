import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../data/zx_store.dart';
import '../../domain/recurrence.dart';
import '../../domain/rent_schedule.dart';
import '../widgets/common.dart';
import 'expenses.dart';
import 'room.dart';
import 'tasks.dart';

class _Late {
  final LeaseStatus status;
  final DbRow? tenant, room, building;
  _Late(this.status, this.tenant, this.room, this.building);
}

class _Upcoming {
  final DbRow bill;
  final DateTime due;
  final bool registered;
  _Upcoming(this.bill, this.due, this.registered);
}

class _DashData {
  final List<_Late> late;
  final List<_Upcoming> upcoming;
  final int income, expenses, buildings;
  final List<DbRow> review; // tasks marked done, waiting for approval
  _DashData(this.late, this.upcoming, this.income, this.expenses, this.buildings, this.review);
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(title: Text(l.appTitle)),
      floatingActionButton: StaffOnly(child: FloatingActionButton.extended(
        icon: const Icon(Icons.receipt_long),
        label: Text(l.newExpense),
        onPressed: () => openExpenseForm(context),
      )),
      body: LiveFuture<_DashData>(
        load: (a) async {
          final now = DateTime.now();
          final buildings = {for (final b in await a.q.buildings()) b['id']: b};
          final rooms = {for (final r in await a.q.allRooms()) r['id']: r};
          final tenants = {for (final t in await a.q.allTenants()) t['id']: t};
          final pays = await a.q.payments();
          final late = <_Late>[];
          for (final le in await a.q.leases()) {
            if (!buildings.containsKey(le['building_id']) || !rooms.containsKey(le['room_id'])) continue;
            final st = leaseStatus(le, pays.where((p) => p['lease_id'] == le['id']).toList(), now);
            if (st.isLate) {
              late.add(_Late(st, tenants[le['tenant_id']], rooms[le['room_id']], buildings[le['building_id']]));
            }
          }
          late.sort((x, y) => y.status.owedLate.compareTo(x.status.owedLate));
          // Recurring bills due in the next 2 weeks (or overdue this period).
          final upcoming = <_Upcoming>[];
          final exps = await a.q.expenses(from: isoDate(now.subtract(const Duration(days: 62))));
          for (final b in await a.q.recurringBills()) {
            if (b['active'] == 0 || !buildings.containsKey(b['building_id'])) continue;
            final rec = Recurrence(frequencyOf(b['frequency']), (b['due_day'] as int?) ?? 1,
                parseIsoDate(b['start_date']) ?? now);
            final dues = rec.dueDates(now.add(const Duration(days: 14)));
            if (dues.isEmpty) continue;
            final due = dues.last;
            final windowStart = isoDate(due.subtract(const Duration(days: 20)));
            final registered = exps.any((e) =>
                e['recurring_bill_id'] == b['id'] && (e['date'] as String? ?? '').compareTo(windowStart) >= 0);
            if (!registered) upcoming.add(_Upcoming(b, due, registered));
          }
          upcoming.sort((x, y) => x.due.compareTo(y.due));
          final month = monthKey(now);
          final income = pays
              .where((p) => (p['paid_on'] as String? ?? '').startsWith(month))
              .fold<int>(0, (s, p) => s + ((p['amount_cents'] as int?) ?? 0));
          final spent = exps
              .where((e) => (e['date'] as String? ?? '').startsWith(month))
              .fold<int>(0, (s, e) => s + ((e['amount_cents'] as int?) ?? 0));
          final review = (await a.q.tasks()).where((t) => t['status'] == 'done' && buildings.containsKey(t['building_id'])).toList();
          return _DashData(late, upcoming, income, spent, buildings.length, review);
        },
        builder: (context, d) {
          final scheme = Theme.of(context).colorScheme;
          if (d.buildings == 0) return EmptyState(Icons.apartment, l.welcome);
          return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), children: [
            Row(children: [
              Expanded(child: _Stat(l.incomeThisMonth, context.money(d.income), Colors.green)),
              const SizedBox(width: 8),
              Expanded(child: _Stat(l.expensesThisMonth, context.money(d.expenses), scheme.error)),
              const SizedBox(width: 8),
              Expanded(child: _Stat(l.net, context.money(d.income - d.expenses), scheme.primary)),
            ]),
            const SizedBox(height: 12),
            Card(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SectionHeader(l.lateRent),
                if (d.late.isEmpty)
                  ListTile(leading: const Icon(Icons.check_circle, color: Colors.green), title: Text(l.everyonePaid)),
                for (final x in d.late)
                  ListTile(
                    leading: Icon(Icons.warning_amber, color: scheme.error),
                    title: Text(x.tenant?['name'] as String? ?? '?'),
                    subtitle: Text('${x.building?['name']} · ${x.room?['name']} · ${l.periodsLate(x.status.late.length)}'),
                    trailing: Text(context.money(x.status.owedLate),
                        style: TextStyle(color: scheme.error, fontWeight: FontWeight.bold)),
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => RoomScreen(roomId: x.room!['id'] as String))),
                  ),
              ]),
            ),
            if (d.review.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SectionHeader(l.tasksToReview),
                  for (final t in d.review)
                    ListTile(
                      leading: const Icon(Icons.hourglass_top, color: Colors.orange),
                      title: Text(t['title'] as String? ?? ''),
                      subtitle: Text(t['place'] as String? ?? ''),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => TaskScreen(taskId: t['id'] as String))),
                    ),
                ]),
              ),
            ],
            const SizedBox(height: 12),
            Card(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SectionHeader(l.upcomingBills),
                if (d.upcoming.isEmpty) ListTile(title: Text(l.nothingDue)),
                for (final u in d.upcoming)
                  ListTile(
                    leading: Icon(Icons.event,
                        color: u.due.isBefore(DateTime.now()) ? scheme.error : null),
                    title: Text(u.bill['vendor'] as String? ?? ''),
                    subtitle: Text(isoDate(u.due)),
                    trailing: TextButton(
                      child: Text(l.registerExpense),
                      onPressed: () => openExpenseForm(context, prefill: {
                        'building_id': u.bill['building_id'],
                        'apartment_id': (u.bill['apartment_id'] as String?)?.isEmpty == true ? null : u.bill['apartment_id'],
                        'category_id': u.bill['category_id'],
                        'vendor': u.bill['vendor'],
                        'amount_cents': u.bill['expected_cents'],
                        'recurring_bill_id': u.bill['id'],
                        'date': isoDate(DateTime.now()),
                      }),
                    ),
                  ),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _Stat(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall, maxLines: 2),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.bold)),
            ),
          ]),
        ),
      );
}
