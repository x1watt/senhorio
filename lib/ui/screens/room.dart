import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/dates.dart';
import '../../data/zx_store.dart';
import '../../domain/rent_schedule.dart';
import '../forms.dart';
import '../widgets/attachments.dart';
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
            if (d.leases.isNotEmpty) SectionHeader(l.occupancyHistory),
            if (d.leases.isNotEmpty) _OccupancyTimeline(leases: d.leases, tenants: tenants, payments: d.payments),
            if (past.isNotEmpty) SectionHeader(l.pastLeases),
            for (final le in past)
              ListTile(
                leading: const Icon(Icons.history),
                title: Text(tenants[le['tenant_id']]?['name'] as String? ?? '?'),
                subtitle: Text('${le['start_date']} → ${le['end_date']}'
                    '${depositHeld(d.payments[le['id']] ?? const []) != 0 ? ' · ${l.depositHeld}: ${context.money(depositHeld(d.payments[le['id']] ?? const []))}' : ''}'),
                trailing: Text(context.money(le['rent_cents'] as int?)),
                onTap: () => _showPastLease(context, le, tenants[le['tenant_id']], d.payments[le['id']] ?? const [], d.tenants),
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

  void _showPastLease(BuildContext context, DbRow le, DbRow? tenant, List<DbRow> payments, List<DbRow> tenants) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (c, ctrl) => ListView(controller: ctrl, padding: const EdgeInsets.all(8), children: [
          _LeaseCard(lease: le, tenant: tenant, status: leaseStatus(le, payments, DateTime.now()),
              payments: payments, tenants: tenants),
        ]),
      ),
    );
  }
}

/// Who lived in the room and when, oldest first; late periods marked.
class _OccupancyTimeline extends StatelessWidget {
  final List<DbRow> leases;
  final Map<Object?, DbRow> tenants;
  final Map<String, List<DbRow>> payments;
  const _OccupancyTimeline({required this.leases, required this.tenants, required this.payments});

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    final sorted = [...leases]..sort((a, b) => (a['start_date'] as String? ?? '').compareTo(b['start_date'] as String? ?? ''));
    final rows = <Widget>[];
    String? prevEnd;
    for (final le in sorted) {
      final start = le['start_date'] as String? ?? '';
      if (prevEnd != null && start.compareTo(prevEnd) > 0) {
        rows.add(_row(context, Icons.bed_outlined, scheme.outline, l.vacant, '$prevEnd → $start', null));
      }
      final st = leaseStatus(le, payments[le['id']] ?? const [], DateTime.now());
      final late = st.dues.where((d) => d.state == DueState.late).length;
      final end = le['end_date'] as String?;
      final open = end == null || end.compareTo(todayIso()) >= 0;
      rows.add(_row(
        context,
        open ? Icons.person : Icons.person_outline,
        late > 0 ? scheme.error : (open ? const Color(0xFF2ECC71) : scheme.outline),
        tenants[le['tenant_id']]?['name'] as String? ?? '?',
        '$start → ${end ?? l.today} · ${context.money(le['rent_cents'] as int?)}',
        late > 0 ? l.periodsLate(late) : null,
      ));
      prevEnd = end;
    }
    return Column(children: rows);
  }

  Widget _row(BuildContext context, IconData icon, Color color, String title, String sub, String? note) => ListTile(
        dense: true,
        leading: Icon(icon, color: color),
        title: Text(title),
        subtitle: Text(sub),
        trailing: note == null ? null : Text(note, style: TextStyle(color: color)),
      );
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
    final held = depositHeld(payments);
    final docs = _docs(tenant);
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
                } else if (v == 'tenant' && tenant != null) {
                  await editEntity(context, table: 'tenants', building: bid, title: l.edit,
                      fields: tenantFields(l), row: tenant);
                } else if (v == 'end') {
                  await guarded(context, () => context.app.ledger.upsert('leases', bid,
                      {'end_date': todayIso()}, id: lease['id'] as String));
                } else if (v == 'delete' && await confirm(context, l.confirmDelete) && context.mounted) {
                  await guarded(context, () => context.app.ledger.delete('leases', bid, lease['id'] as String));
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit', child: Text(l.edit)),
                PopupMenuItem(value: 'tenant', child: Text(l.editTenant)),
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
          // ---- contacts
          if (tenant != null) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final phone in [tenant!['phone'], tenant!['phone2']].whereType<String>().where((p) => p.trim().isNotEmpty))
                ActionChip(avatar: const Icon(Icons.call, size: 16), label: Text(phone),
                    onPressed: () => _open(context, 'tel:${phone.replaceAll(' ', '')}')),
              if ((tenant!['email'] as String?)?.isNotEmpty ?? false)
                ActionChip(avatar: const Icon(Icons.mail, size: 16), label: Text(tenant!['email'] as String),
                    onPressed: () => _open(context, 'mailto:${tenant!['email']}')),
              if ((tenant!['emergency_contact'] as String?)?.isNotEmpty ?? false)
                Chip(avatar: const Icon(Icons.emergency, size: 16), label: Text(tenant!['emergency_contact'] as String)),
              if ((tenant!['tax_id'] as String?)?.isNotEmpty ?? false)
                Chip(avatar: const Icon(Icons.badge, size: 16), label: Text('NIF ${tenant!['tax_id']}')),
            ]),
            // ---- identification documents
            const SizedBox(height: 8),
            Text(l.idDocuments, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            AttachmentList(
              shas: docs,
              onChanged: (list) => guarded(context, () => context.app.ledger.upsert(
                  'tenants', bid, {'id_documents': list}, id: tenant!['id'] as String)),
            ),
          ],
          // ---- deposit
          const Divider(),
          Row(children: [
            const Icon(Icons.savings_outlined, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text('${l.depositHeld}: ${context.money(held)}'
                '${lease['deposit_cents'] != null ? ' / ${context.money(lease['deposit_cents'] as int)}' : ''}')),
            TextButton(onPressed: () => _pay(context, null, kind: held > 0 ? 'deposit_return' : 'deposit'),
                child: Text(held > 0 ? l.settleDeposit : l.registerDeposit)),
          ]),
          const Divider(),
          // ---- rent periods
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
                  DueState.paid => const Color(0xFF2ECC71),
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
                leading: Icon(isRentPayment(p) ? Icons.payments_outlined : Icons.savings_outlined, size: 18),
                title: Text('${p['paid_on']} · ${context.money(p['amount_cents'] as int?)}'
                    '${isRentPayment(p) ? '' : ' · ${l.paymentKind(p['kind'] as String)}'}'),
                subtitle: Text('${isRentPayment(p) ? '${l.period}: ${p['period'] ?? '-'}' : ''}'
                    '${p['method'] == null ? '' : ' · ${p['method']}'}${p['notes'] == null ? '' : ' · ${p['notes']}'}'),
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

  static List<String> _docs(DbRow? t) {
    final s = t?['id_documents'] as String?;
    if (s == null || s.isEmpty) return [];
    return (jsonDecode(s) as List).cast<String>();
  }

  Future<void> _open(BuildContext context, String url) async {
    if (!await launchUrl(Uri.parse(url)) && context.mounted) context.toast(url);
  }

  Future<void> _pay(BuildContext context, RentDue? due, {String kind = 'rent'}) {
    final l = context.l;
    final periods = {
      for (final d in status.dues.reversed)
        d.period: '${d.period}${d.state == DueState.paid ? ' ✓' : ''}',
    };
    final held = depositHeld(payments);
    return editEntity(context,
        table: 'payments',
        building: lease['building_id'] as String,
        title: kind == 'rent' ? l.registerPayment : l.registerDeposit,
        fields: paymentFields(l, periods),
        defaults: {
          'lease_id': lease['id'],
          'kind': kind,
          'period': ?due?.period,
          'amount_cents': switch (kind) {
            'rent' => due?.owed,
            'deposit' => lease['deposit_cents'] ?? lease['rent_cents'],
            'deposit_return' => held,
            _ => null,
          },
          'paid_on': todayIso(),
        });
  }
}
