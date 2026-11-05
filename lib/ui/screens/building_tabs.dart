import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../data/zx_store.dart';
import '../../domain/recurrence.dart';
import '../../identity/identity_service.dart';
import '../forms.dart';
import '../widgets/common.dart';
import '../widgets/entity_form.dart';
import 'expenses.dart';

class TenantsTab extends StatelessWidget {
  final DbRow building;
  const TenantsTab({super.key, required this.building});

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final bid = building['id'] as String;
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        heroTag: 'tenant-$bid',
        tooltip: l.newTenant,
        onPressed: () => editEntity(context, table: 'tenants', building: bid,
            title: l.newTenant, fields: tenantFields(l)),
        child: const Icon(Icons.person_add),
      ),
      body: LiveFuture<List<DbRow>>(
        load: (a) => a.q.tenants(bid),
        builder: (context, rows) => rows.isEmpty
            ? EmptyState(Icons.people_outline, l.noTenants)
            : ListView(children: [
                for (final t in rows)
                  ListTile(
                    leading: CircleAvatar(child: Text(((t['name'] as String?) ?? '?').characters.first.toUpperCase())),
                    title: Text(t['name'] as String? ?? ''),
                    subtitle: Text([t['phone'], t['email']].whereType<String>().join(' · ')),
                    onTap: () => editEntity(context, table: 'tenants', building: bid,
                        title: l.edit, fields: tenantFields(l), row: t),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        if (await confirm(context, l.confirmDelete) && context.mounted) {
                          await guarded(context, () => context.app.ledger.delete('tenants', bid, t['id'] as String));
                        }
                      },
                    ),
                  ),
              ]),
      ),
    );
  }
}

class RecurringBillsTab extends StatelessWidget {
  final DbRow building;
  const RecurringBillsTab({super.key, required this.building});

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final bid = building['id'] as String;
    return LiveFuture<(List<DbRow>, List<DbRow>, List<DbRow>)>(
      load: (a) async => (await a.q.recurringBills(building: bid), await a.q.categories(),
          await a.q.apartments(bid)),
      builder: (context, d) {
        final (bills, cats, apts) = d;
        final catById = {for (final c in cats) c['id']: c};
        return Scaffold(
          floatingActionButton: FloatingActionButton(
            heroTag: 'bill-$bid',
            tooltip: l.newRecurringBill,
            onPressed: () => editEntity(context, table: 'recurring_bills', building: bid,
                title: l.newRecurringBill, fields: recurringBillFields(context, cats, apts),
                defaults: {'active': 1, 'frequency': 'monthly', 'due_day': 1, 'start_date': todayIso()}),
            child: const Icon(Icons.add),
          ),
          body: bills.isEmpty
              ? EmptyState(Icons.event_repeat, l.noRecurringBills)
              : ListView(children: [
                  for (final b in bills) _billTile(context, b, catById[b['category_id']], cats, apts),
                ]),
        );
      },
    );
  }

  Widget _billTile(BuildContext context, DbRow b, DbRow? cat, List<DbRow> cats, List<DbRow> apts) {
    final l = context.l;
    final bid = building['id'] as String;
    final rec = Recurrence(frequencyOf(b['frequency']), (b['due_day'] as int?) ?? 1,
        parseIsoDate(b['start_date']) ?? DateTime.now());
    final next = rec.nextDue(DateTime.now().subtract(const Duration(days: 1)));
    final active = b['active'] != 0;
    return ListTile(
      leading: CategoryAvatar(cat),
      title: Text(b['vendor'] as String? ?? ''),
      subtitle: Text(active
          ? '${l.frequency(b['frequency'] as String? ?? 'monthly')} · ${l.nextDue(isoDate(next))}'
          : l.inactive),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (b['expected_cents'] != null) Text(context.money(b['expected_cents'] as int)),
        PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'pay') {
              await openExpenseForm(context, prefill: {
                'building_id': bid,
                'apartment_id': (b['apartment_id'] as String?)?.isEmpty == true ? null : b['apartment_id'],
                'category_id': b['category_id'],
                'vendor': b['vendor'],
                'amount_cents': b['expected_cents'],
                'recurring_bill_id': b['id'],
                'date': todayIso(),
              });
            } else if (v == 'edit') {
              await editEntity(context, table: 'recurring_bills', building: bid, title: l.edit,
                  fields: recurringBillFields(context, cats, apts), row: b);
            } else if (v == 'delete' && await confirm(context, l.confirmDelete) && context.mounted) {
              await guarded(context, () => context.app.ledger.delete('recurring_bills', bid, b['id'] as String));
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'pay', child: Text(l.registerExpense)),
            PopupMenuItem(value: 'edit', child: Text(l.edit)),
            PopupMenuItem(value: 'delete', child: Text(l.delete)),
          ],
        ),
      ]),
    );
  }
}

class MembersTab extends StatelessWidget {
  final DbRow building;
  const MembersTab({super.key, required this.building});

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final bid = building['id'] as String;
    final me = context.app.identity.pubkey;
    final isOwner = building['owner'] == me;
    return Scaffold(
      floatingActionButton: !isOwner
          ? null
          : FloatingActionButton.extended(
              heroTag: 'member-$bid',
              icon: const Icon(Icons.group_add),
              label: Text(l.addMember),
              onPressed: () => _add(context, bid),
            ),
      body: LiveFuture<List<DbRow>>(
        load: (a) => a.q.members(bid),
        builder: (context, rows) => ListView(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(isOwner ? l.membersHelpOwner : l.membersHelpMember,
                style: Theme.of(context).textTheme.bodySmall),
          ),
          for (final m in rows)
            ListTile(
              leading: Icon(m['role'] == 'owner' ? Icons.verified_user : Icons.person),
              title: Text((m['name'] as String?) ??
                  (m['pubkey'] == me ? l.you : shortNpub(m['pubkey'] as String))),
              subtitle: Text('${m['role'] == 'owner' ? l.owner : l.member} · ${shortNpub(m['pubkey'] as String)}'),
              trailing: isOwner && m['role'] != 'owner'
                  ? IconButton(
                      icon: const Icon(Icons.person_remove),
                      tooltip: l.revoke,
                      onPressed: () async {
                        if (await confirm(context, l.confirmRevoke) && context.mounted) {
                          await guarded(context,
                              () => context.app.ledger.delete('members', bid, m['id'] as String));
                        }
                      },
                    )
                  : null,
            ),
        ]),
      ),
    );
  }

  Future<void> _add(BuildContext context, String bid) async {
    final l = context.l;
    final v = await showEntityForm(context, title: l.addMember, fields: [
      FieldSpec('npub', 'npub', required: true, hint: 'npub1…'),
      FieldSpec('name', l.name),
    ]);
    if (v == null || !context.mounted) return;
    String pk;
    try {
      pk = parsePubkey(v['npub'] as String);
    } catch (_) {
      context.toast(l.invalidNpub);
      return;
    }
    await guarded(context, () => context.app.ledger.upsert('members', bid,
        {'pubkey': pk, 'name': v['name'], 'role': 'member', 'deleted': 0}, id: '$bid:$pk'));
  }
}
