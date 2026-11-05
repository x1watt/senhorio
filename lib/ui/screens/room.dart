import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../data/zx_store.dart';
import '../../domain/rent_schedule.dart';
import '../forms.dart';
import '../widgets/common.dart';

class _RoomData {
  final DbRow room;
  final List<DbRow> apartments, tenants, leases;
  final Map<String, List<DbRow>> payments; // lease id -> payments
  _RoomData(this.room, this.apartments, this.tenants, this.leases, this.payments);
}

class RoomScreen extends StatelessWidget {
  final String roomId;
  const RoomScreen({super.key, required this.roomId});

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return LiveFuture<_RoomData?>(
      load: (a) async {
        final room = await a.q.byId('rooms', roomId);
        if (room == null) return null;
        final b = room['building_id'] as String;
        final leases = await a.q.leases(room: roomId);
        return _RoomData(room, await a.q.apartments(b), await a.q.tenants(b), leases, {
          for (final le in leases) le['id'] as String: await a.q.payments(lease: le['id'] as String),
        });
      },
      builder: (context, d) {
        if (d == null || d.room['deleted'] == 1) {
          return Scaffold(appBar: AppBar(), body: EmptyState(Icons.delete, l.deleted));
        }
        final bid = d.room['building_id'] as String;
        final tenants = {for (final t in d.tenants) t['id']: t};
        final now = DateTime.now();
        final current = d.leases.where((le) {
          final end = le['end_date'] as String?;
          return end == null || end.compareTo(todayIso()) >= 0;
        }).toList();
        final past = d.leases.where((le) => !current.contains(le)).toList();
        return Scaffold(
          appBar: AppBar(
            title: Text(d.room['name'] as String? ?? ''),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => editEntity(context, table: 'rooms', building: bid, title: l.edit,
                    fields: roomFields(l, d.apartments), row: d.room),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (await confirm(context, l.confirmDelete) && context.mounted) {
                    await guarded(context, () => context.app.ledger.delete('rooms', bid, roomId));
                    if (context.mounted) Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(Icons.assignment_add),
            label: Text(l.newLease),
            onPressed: () async {
              if (d.tenants.isEmpty) {
                final t = await editEntity(context, table: 'tenants', building: bid,
                    title: l.newTenant, fields: tenantFields(l));
                if (t == null || !context.mounted) return;
                final tenantsNow = await context.app.q.tenants(bid);
                if (!context.mounted) return;
                await _newLease(context, bid, tenantsNow, t);
              } else {
                await _newLease(context, bid, d.tenants, null);
              }
            },
          ),
          body: ListView(padding: const EdgeInsets.only(bottom: 88), children: [
            if (current.isEmpty)
              EmptyState(Icons.bed_outlined,
                  d.room['available'] == 0 ? l.keptEmpty : l.vacant),
            for (final le in current)
              _LeaseCard(
                lease: le,
                tenant: tenants[le['tenant_id']],
                status: leaseStatus(le, d.payments[le['id']] ?? const [], now),
                payments: d.payments[le['id']] ?? const [],
                tenants: d.tenants,
              ),
            if (past.isNotEmpty) SectionHeader(l.pastLeases),
            for (final le in past)
              ListTile(
                leading: const Icon(Icons.history),
                title: Text(tenants[le['tenant_id']]?['name'] as String? ?? '?'),
                subtitle: Text('${le['start_date']} → ${le['end_date']}'),
                trailing: Text(context.money(le['rent_cents'] as int?)),
              ),
          ]),
        );
      },
    );
  }

  Future<void> _newLease(BuildContext context, String bid, List<DbRow> tenants, String? tenant) =>
      editEntity(context, table: 'leases', building: bid, title: context.l.newLease,
          fields: leaseFields(context.l, tenants), defaults: {
        'room_id': roomId,
        'tenant_id': ?tenant,
        'frequency': 'monthly',
        'due_day': 8,
        'grace_days': 0,
        'start_date': todayIso(),
      });
}

class _LeaseCard extends StatelessWidget {
  final DbRow lease;
  final DbRow? tenant;
  final LeaseStatus status;
  final List<DbRow> payments;
  final List<DbRow> tenants;
  const _LeaseCard({required this.lease, required this.tenant, required this.status,
      required this.payments, required this.tenants});

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final bid = lease['building_id'] as String;
    final scheme = Theme.of(context).colorScheme;
    final dues = status.dues.reversed.take(12).toList();
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.person),
            const SizedBox(width: 8),
            Expanded(child: Text(tenant?['name'] as String? ?? '?',
                style: Theme.of(context).textTheme.titleMedium)),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'edit') {
                  await editEntity(context, table: 'leases', building: bid, title: l.edit,
                      fields: leaseFields(l, tenants), row: lease);
                } else if (v == 'end') {
                  await guarded(context, () => context.app.ledger.upsert('leases', bid,
                      {'end_date': todayIso()}, id: lease['id'] as String));
                } else if (v == 'delete' && await confirm(context, l.confirmDelete) && context.mounted) {
                  await guarded(context, () => context.app.ledger.delete('leases', bid, lease['id'] as String));
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit', child: Text(l.edit)),
                PopupMenuItem(value: 'end', child: Text(l.endLeaseToday)),
                PopupMenuItem(value: 'delete', child: Text(l.delete)),
              ],
            ),
          ]),
          Text('${context.money(lease['rent_cents'] as int?)} · ${l.frequency(lease['frequency'] as String? ?? 'monthly')} · ${l.dueDayN(lease['due_day'] as int? ?? 1)}'),
          Text('${l.since} ${lease['start_date']}${lease['end_date'] == null ? '' : ' → ${lease['end_date']}'}',
              style: Theme.of(context).textTheme.bodySmall),
          if (status.isLate)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(l.lateAmount(context.money(status.owedLate), status.late.length),
                  style: TextStyle(color: scheme.error, fontWeight: FontWeight.bold)),
            ),
          const Divider(),
          for (final due in dues)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                switch (due.state) {
                  DueState.paid => Icons.check_circle,
                  DueState.partial => Icons.timelapse,
                  DueState.open => Icons.radio_button_unchecked,
                  DueState.late => Icons.error,
                },
                color: switch (due.state) {
                  DueState.paid => Colors.green,
                  DueState.late => scheme.error,
                  _ => scheme.outline,
                },
              ),
              title: Text(isoDate(due.due)),
              subtitle: due.paid > 0 && due.paid < due.expected
                  ? Text(l.paidOf(context.money(due.paid), context.money(due.expected)))
                  : null,
              trailing: due.state == DueState.paid
                  ? null
                  : TextButton(
                      onPressed: () => _pay(context, due),
                      child: Text(l.registerPayment),
                    ),
            ),
          if (payments.isNotEmpty) ...[
            const Divider(),
            Text(l.payments, style: Theme.of(context).textTheme.titleSmall),
            for (final p in payments.take(24))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${p['paid_on']} · ${context.money(p['amount_cents'] as int?)}'),
                subtitle: Text('${l.period}: ${p['period'] ?? '-'}${p['method'] == null ? '' : ' · ${p['method']}'}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () async {
                    if (await confirm(context, l.confirmDelete) && context.mounted) {
                      await guarded(context, () => context.app.ledger.delete('payments', bid, p['id'] as String));
                    }
                  },
                ),
              ),
          ],
        ]),
      ),
    );
  }

  Future<void> _pay(BuildContext context, RentDue due) {
    final l = context.l;
    final periods = {
      for (final d in status.dues.reversed)
        d.period: '${d.period}${d.state == DueState.paid ? ' ✓' : ''}',
    };
    return editEntity(context,
        table: 'payments',
        building: lease['building_id'] as String,
        title: l.registerPayment,
        fields: paymentFields(l, periods),
        defaults: {
          'lease_id': lease['id'],
          'period': due.period,
          'amount_cents': due.owed,
          'paid_on': todayIso(),
        });
  }
}
