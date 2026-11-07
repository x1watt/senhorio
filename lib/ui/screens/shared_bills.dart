// Bills shared by a group of tenants: a manager enters the bill and the
// group (an apartment's tenants, or the building's), it is split evenly,
// each tenant marks their share paid, and a manager confirms it.

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/ids.dart';
import '../../data/zx_store.dart';
import '../../domain/roles.dart';
import '../../domain/shared_bills.dart';
import '../widgets/alerts.dart';
import '../widgets/attachments.dart';
import '../widgets/common.dart';
import '../widgets/entity_form.dart';
import '../forms.dart';

List<String> billAttachments(DbRow b) {
  final s = b['attachments'] as String?;
  if (s == null || s.isEmpty) return const [];
  return (jsonDecode(s) as List).cast<String>();
}

Color shareColor(BuildContext context, String? status, {bool overdue = false}) => switch (status) {
      'confirmed' => const Color(0xFF2ECC71),
      'paid' => Colors.orange,
      _ => overdue ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.outline,
    };

IconData shareIcon(String? status) => switch (status) {
      'confirmed' => Icons.verified,
      'paid' => Icons.hourglass_top,
      _ => Icons.radio_button_unchecked,
    };

class ShareStatusChip extends StatelessWidget {
  final String? status;
  final bool overdue;
  const ShareStatusChip(this.status, {super.key, this.overdue = false});
  @override
  Widget build(BuildContext context) {
    final c = shareColor(context, status, overdue: overdue);
    return Chip(
      avatar: Icon(shareIcon(status), size: 16, color: c),
      label: Text(overdue && status != 'confirmed' && status != 'paid' ? context.l.overdue : context.l.shareStatus(status ?? 'open'),
          style: TextStyle(color: c)),
      side: BorderSide(color: c),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Tenants with a lease running today in [apartment] (null: the building).
Future<List<DbRow>> currentTenants(BuildContext context, String building, String? apartment) async {
  final app = context.app;
  final today = todayIso();
  final rooms = await app.q.rooms(building, apartment: apartment);
  final roomIds = {for (final r in rooms) r['id']};
  final tenants = {for (final t in await app.q.tenants(building)) t['id']: t};
  final out = <String, DbRow>{};
  for (final le in await app.q.leases(building: building)) {
    final end = le['end_date'] as String?;
    if (end != null && end.compareTo(today) < 0) continue;
    if (apartment != null && !roomIds.contains(le['room_id'])) continue;
    final t = tenants[le['tenant_id']];
    if (t != null) out[t['id'] as String] = t;
  }
  return out.values.toList()..sort((a, b) => (a['name'] as String? ?? '').compareTo(b['name'] as String? ?? ''));
}

/// The form of a new shared bill, the group preview, and the split.
Future<void> newSharedBill(BuildContext context, String building) async {
  final l = context.l;
  final app = context.app;
  final apts = await app.q.apartments(building);
  if (!context.mounted) return;
  final values = await showEntityForm(context, title: l.newSharedBill, fields: [
    FieldSpec('title', l.title, required: true, hint: l.sharedBillTitleHint),
    FieldSpec('amount_cents', l.totalAmount, type: FieldType.money, required: true),
    FieldSpec('due_date', l.dueDate, type: FieldType.date, required: true),
    FieldSpec('apartment_id', l.whoShares, type: FieldType.choice, required: true,
        options: {'': l.allTenantsOfBuilding, ...optionsOf(apts, (r) => l.tenantsOfApartment(r['name'] as String? ?? ''))}),
    FieldSpec('description', l.description, type: FieldType.multiline),
  ], initial: {'due_date': isoDate(DateTime.now().add(const Duration(days: 14))), 'apartment_id': ''});
  if (values == null || !context.mounted) return;
  final apt = (values['apartment_id'] as String?)?.isEmpty ?? true ? null : values['apartment_id'] as String;
  final group = await currentTenants(context, building, apt);
  if (!context.mounted) return;
  if (group.isEmpty) {
    context.toast(l.noTenantsInGroup);
    return;
  }
  final chosen = await showDialog<List<DbRow>>(
    context: context,
    builder: (c) => _GroupDialog(tenants: group, total: (values['amount_cents'] as int?) ?? 0),
  );
  if (chosen == null || chosen.isEmpty || !context.mounted) return;
  final parts = splitEvenly((values['amount_cents'] as int?) ?? 0, chosen.length);
  final billId = newId();
  await guarded(context, () => app.ledger.batch([
        (entity: 'shared_bills', building: building, id: billId, op: 'upsert', fields: {
          ...values,
          'apartment_id': apt,
        }),
        for (var i = 0; i < chosen.length; i++)
          (entity: 'bill_shares', building: building, id: newId(), op: 'upsert', fields: {
            'bill_id': billId,
            'tenant_id': chosen[i]['id'],
            'amount_cents': parts[i],
            'status': 'open',
          }),
      ]));
}

class _GroupDialog extends StatefulWidget {
  final List<DbRow> tenants;
  final int total;
  const _GroupDialog({required this.tenants, required this.total});
  @override
  State<_GroupDialog> createState() => _GroupDialogState();
}

class _GroupDialogState extends State<_GroupDialog> {
  late final Set<String> on = {for (final t in widget.tenants) t['id'] as String};

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final chosen = widget.tenants.where((t) => on.contains(t['id'])).toList();
    final parts = splitEvenly(widget.total, chosen.length);
    return AlertDialog(
      title: Text(l.whoShares),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(l.splitHelp(context.money(widget.total), chosen.length), style: Theme.of(context).textTheme.bodySmall),
          for (final t in widget.tenants)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: on.contains(t['id']),
              title: Text(t['name'] as String? ?? '?'),
              secondary: on.contains(t['id'])
                  ? Text(context.money(parts[chosen.indexOf(t)]), style: const TextStyle(fontWeight: FontWeight.bold))
                  : null,
              onChanged: (v) => setState(() => v == true ? on.add(t['id'] as String) : on.remove(t['id'])),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(onPressed: chosen.isEmpty ? null : () => Navigator.pop(context, chosen), child: Text(l.save)),
      ],
    );
  }
}

class _BillsData {
  final List<DbRow> bills, shares, tenants;
  final String? myTenantId;
  _BillsData(this.bills, this.shares, this.tenants, this.myTenantId);
}

/// Staff: every shared bill of the building; a tenant: their shares.
class SharedBillsTab extends StatelessWidget {
  final DbRow building;
  final Role? role; // mine
  const SharedBillsTab({super.key, required this.building, required this.role});

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final bid = building['id'] as String;
    final staff = role?.isStaff ?? false;
    return LiveFuture<_BillsData>(
      load: (a) async => _BillsData(await a.q.sharedBills(building: bid), await a.q.billShares(building: bid),
          await a.q.tenants(bid), staff ? null : await a.q.myTenantId(bid, a.identity.pubkey)),
      builder: (context, d) {
        final today = todayIso();
        return Scaffold(
          floatingActionButton: !staff
              ? null
              : FloatingActionButton.extended(
                  heroTag: 'bill-$bid',
                  icon: const Icon(Icons.call_split),
                  label: Text(l.newSharedBill),
                  onPressed: () => newSharedBill(context, bid),
                ),
          body: ListView(padding: const EdgeInsets.only(bottom: 88), children: [
            if (!staff) TenantAlertsBanner(building: bid),
            if (d.bills.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 48),
                child: EmptyState(Icons.call_split, staff ? l.noSharedBillsStaff : l.noSharedBillsTenant),
              ),
            for (final b in d.bills) _tile(context, b, d, staff, today),
          ]),
        );
      },
    );
  }

  Widget _tile(BuildContext context, DbRow b, _BillsData d, bool staff, String today) {
    final l = context.l;
    final shares = d.shares.where((s) => s['bill_id'] == b['id']).toList();
    final mine = d.myTenantId == null ? null : shares.where((s) => s['tenant_id'] == d.myTenantId).firstOrNull;
    final confirmed = shares.where((s) => s['status'] == 'confirmed').length;
    final paid = shares.where((s) => s['status'] == 'paid').length;
    final overdue = mine != null && shareOverdue(mine, b, today);
    return ListTile(
      leading: Icon(
        mine != null ? shareIcon(mine['status'] as String?) : (confirmed == shares.length ? Icons.verified : Icons.call_split),
        color: mine != null ? shareColor(context, mine['status'] as String?, overdue: overdue)
            : (confirmed == shares.length ? const Color(0xFF2ECC71) : null),
      ),
      title: Text(b['title'] as String? ?? ''),
      subtitle: Text(staff
          ? '${context.money(b['amount_cents'] as int?)} · ${l.dueOn(b['due_date'] as String? ?? '')} · ${l.sharesProgress(confirmed, shares.length)}${paid > 0 ? ' · ${l.sharesPaidToConfirm(paid)}' : ''}'
          : '${l.yourShare}: ${context.money(mine?['amount_cents'] as int?)} ${l.ofTotal(context.money(b['amount_cents'] as int?))} · ${l.dueOn(b['due_date'] as String? ?? '')}'),
      trailing: mine != null ? ShareStatusChip(mine['status'] as String?, overdue: overdue) : const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SharedBillScreen(billId: b['id'] as String))),
    );
  }
}

class SharedBillScreen extends StatelessWidget {
  final String billId;
  const SharedBillScreen({super.key, required this.billId});

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return LiveFuture<(DbRow?, _BillsData?, Role?)>(
      load: (a) async {
        final b = await a.q.byId('shared_bills', billId);
        if (b == null) return (null, null, null);
        final bid = b['building_id'] as String;
        final role = await a.ledger.myRole(bid);
        return (
          b,
          _BillsData(const [], await a.q.billShares(bill: billId), await a.q.tenants(bid),
              (role?.isStaff ?? false) ? null : await a.q.myTenantId(bid, a.identity.pubkey)),
          role,
        );
      },
      builder: (context, d) {
        final (b, data, role) = d;
        if (b == null || b['deleted'] == 1 || data == null) {
          return Scaffold(appBar: AppBar(), body: EmptyState(Icons.delete, l.deleted));
        }
        final bid = b['building_id'] as String;
        final staff = role?.isStaff ?? false;
        final tenants = {for (final t in data.tenants) t['id']: t};
        final today = todayIso();
        final shares = data.myTenantId == null
            ? data.shares
            : data.shares.where((s) => s['tenant_id'] == data.myTenantId).toList();
        final toConfirm = data.shares.where((s) => s['status'] == 'paid').toList();
        return Scaffold(
          appBar: AppBar(
            title: Text(b['title'] as String? ?? ''),
            actions: [
              if (staff)
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'confirmAll') {
                      await guarded(context, () => context.app.ledger.batch([
                            for (final s in toConfirm)
                              (entity: 'bill_shares', building: bid, id: s['id'] as String, op: 'upsert', fields: _confirmFields(context)),
                          ]));
                    } else if (v == 'delete' && await confirm(context, l.confirmDelete) && context.mounted) {
                      await guarded(context, () => context.app.ledger.delete('shared_bills', bid, billId));
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                  itemBuilder: (_) => [
                    if (toConfirm.isNotEmpty) PopupMenuItem(value: 'confirmAll', child: Text(l.confirmAllPaid(toConfirm.length))),
                    PopupMenuItem(value: 'delete', child: Text(l.delete)),
                  ],
                ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            Text('${context.money(b['amount_cents'] as int?)} · ${l.dueOn(b['due_date'] as String? ?? '')}',
                style: Theme.of(context).textTheme.titleMedium),
            if ((b['description'] as String?)?.isNotEmpty ?? false) Text(b['description'] as String),
            const SizedBox(height: 8),
            AttachmentList(
              shas: billAttachments(b),
              onChanged: !staff ? null : (list) => guarded(context, () => context.app.ledger.upsert('shared_bills', bid, {'attachments': list}, id: billId)),
            ),
            const Divider(height: 32),
            Text(data.myTenantId == null ? l.shares : l.yourShare, style: Theme.of(context).textTheme.titleSmall),
            for (final s in shares) _shareTile(context, b, s, tenants[s['tenant_id']], staff, data.myTenantId != null, today),
          ]),
        );
      },
    );
  }

  Map<String, Object?> _confirmFields(BuildContext context) => {
        'status': 'confirmed',
        'confirmed_by': context.app.identity.pubkey,
        'confirmed_at': isoDateTime(DateTime.now()),
      };

  Widget _shareTile(BuildContext context, DbRow b, DbRow s, DbRow? tenant, bool staff, bool mine, String today) {
    final l = context.l;
    final bid = b['building_id'] as String;
    final status = s['status'] as String? ?? 'open';
    final overdue = shareOverdue(s, b, today);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(mine ? context.money(s['amount_cents'] as int?) : '${tenant?['name'] ?? '?'} · ${context.money(s['amount_cents'] as int?)}',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            ShareStatusChip(status, overdue: overdue),
          ]),
          if (s['paid_at'] != null)
            Text(l.paidOnLine(s['paid_at'] as String), style: Theme.of(context).textTheme.bodySmall),
          if ((s['note'] as String?)?.isNotEmpty ?? false) Text(s['note'] as String),
          if (status == 'confirmed' && s['confirmed_at'] != null)
            Text(l.confirmedOnLine(s['confirmed_at'] as String), style: TextStyle(color: const Color(0xFF2ECC71), fontSize: 12)),
          if (overdue && status != 'paid')
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(l.overdueSince(b['due_date'] as String? ?? ''), style: TextStyle(color: scheme.error, fontWeight: FontWeight.bold)),
            ),
          const SizedBox(height: 8),
          if (mine && status == 'open')
            FilledButton.icon(
              icon: const Icon(Icons.check),
              label: Text(l.markPaid),
              onPressed: () => _markPaid(context, bid, s),
            ),
          if (mine && status == 'paid')
            Text(l.waitingConfirmation, style: Theme.of(context).textTheme.bodySmall),
          if (staff && status != 'confirmed')
            Row(children: [
              FilledButton.icon(
                icon: const Icon(Icons.verified),
                label: Text(l.confirmPaid),
                onPressed: () => guarded(context, () => context.app.ledger.upsert('bill_shares', bid, _confirmFields(context), id: s['id'] as String)),
              ),
            ]),
          if (staff && status == 'confirmed')
            TextButton(
              onPressed: () => guarded(context, () => context.app.ledger.upsert('bill_shares', bid,
                  {'status': 'open', 'confirmed_by': null, 'confirmed_at': null, 'paid_at': null}, id: s['id'] as String)),
              child: Text(l.reopen),
            ),
        ]),
      ),
    );
  }

  Future<void> _markPaid(BuildContext context, String bid, DbRow s) async {
    final l = context.l;
    final ctrl = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.markPaid),
        content: TextField(controller: ctrl, autofocus: true, decoration: InputDecoration(labelText: l.noteOptional, hintText: l.markPaidHint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: Text(l.ok)),
        ],
      ),
    );
    ctrl.dispose();
    if (note == null || !context.mounted) return;
    await guarded(context, () => context.app.ledger.upsert('bill_shares', bid, {
          'status': 'paid',
          'paid_at': isoDateTime(DateTime.now()),
          'note': note.isEmpty ? null : note,
        }, id: s['id'] as String));
  }
}
