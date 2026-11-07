import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../data/queries.dart';
import '../../data/zx_store.dart';
import '../../domain/recurrence.dart';
import '../../domain/roles.dart';
import '../../identity/identity_service.dart';
import '../forms.dart';
import '../widgets/common.dart';
import '../widgets/entity_form.dart';
import '../widgets/people.dart';
import 'expenses.dart';
import 'invites.dart';

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
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: const Icon(Icons.vpn_key_outlined),
                        tooltip: l.invite,
                        onPressed: () => inviteToBuilding(context, bid, tenantId: t['id'] as String),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          if (await confirm(context, l.confirmDelete) && context.mounted) {
                            await guarded(context, () => context.app.ledger.delete('tenants', bid, t['id'] as String));
                          }
                        },
                      ),
                    ]),
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
  final Role? role; // mine
  const MembersTab({super.key, required this.building, required this.role});

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final bid = building['id'] as String;
    final me = context.app.identity.pubkey;
    final mine = role;
    final canInvite = mine != null && mine.canGrant.isNotEmpty;
    final manages = mine == Role.owner || mine == Role.admin;
    return Scaffold(
      floatingActionButton: !canInvite
          ? null
          : FloatingActionButton.extended(
              heroTag: 'member-$bid',
              icon: const Icon(Icons.group_add),
              label: Text(l.invite),
              onPressed: () => inviteToBuilding(context, bid),
            ),
      body: LiveFuture<(List<DbRow>, Map<String, Person>)>(
        load: (a) async => (await a.q.members(bid), await a.q.people()),
        builder: (context, d) => ListView(padding: const EdgeInsets.only(bottom: 88), children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(manages ? l.membersHelpOwner : l.membersHelpMember,
                style: Theme.of(context).textTheme.bodySmall),
          ),
          if (canInvite) OpenInvites(building: bid),
          for (final m in d.$1) _memberTile(context, bid, me, mine, m, d.$2),
          if (manages)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: TextButton.icon(
                  icon: const Icon(Icons.key),
                  label: Text(l.addMember),
                  onPressed: () => _add(context, bid, mine!),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _memberTile(BuildContext context, String bid, String me, Role? mine, DbRow m, Map<String, Person> people) {
    final l = context.l;
    final pk = m['pubkey'] as String;
    final r = pk == building['owner'] ? Role.owner : (roleOf(m['role']) ?? Role.mod);
    final canEdit = mine != null && pk != me && mine.canManage(r, null);
    final canNickname = (mine?.isStaff ?? false) && pk != me;
    final p = people[pk];
    final roleIcon = switch (r) {
      Role.owner => Icons.verified_user,
      Role.admin => Icons.admin_panel_settings,
      Role.mod => Icons.manage_accounts,
      Role.user => Icons.person,
      Role.worker => Icons.cleaning_services,
    };
    // The nickname first; the name they gave themselves when it differs.
    final self = p?.profileName;
    final subtitle = [
      l.roleName(r.name),
      if (self != null && p?.nickname != null && self != p?.nickname) self,
      shortNpub(pk),
    ].join(' · ');
    return ListTile(
      leading: Stack(clipBehavior: Clip.none, children: [
        PersonAvatar(pubkey: pk, people: people),
        Positioned(
          right: -4,
          bottom: -4,
          child: CircleAvatar(
            radius: 9,
            backgroundColor: Theme.of(context).colorScheme.surface,
            child: Icon(roleIcon, size: 13),
          ),
        ),
      ]),
      title: Text(personName(context, pk, people)),
      subtitle: Text(subtitle),
      trailing: !canEdit && !canNickname
          ? null
          : PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'nickname') {
                  await editNickname(context, pk);
                } else if (v == 'revoke') {
                  if (await confirm(context, l.confirmRevoke) && context.mounted) {
                    await guarded(context, () => context.app.ledger.delete('members', bid, m['id'] as String));
                  }
                } else {
                  await guarded(context, () => context.app.ledger.upsert('members', bid,
                      {'role': v}, id: m['id'] as String));
                }
              },
              itemBuilder: (_) => [
                if (canNickname) PopupMenuItem(value: 'nickname', child: Text(l.nickname)),
                if (canEdit) ...[
                  for (final g in mine.canGrant)
                    if (g != r && g != Role.user && r != Role.user)
                      PopupMenuItem(value: g.name, child: Text('${l.changeRole}: ${l.roleName(g.name)}')),
                  PopupMenuItem(value: 'revoke', child: Text(l.revoke)),
                ],
              ],
            ),
    );
  }

  Future<void> _add(BuildContext context, String bid, Role mine) async {
    final l = context.l;
    final grant = mine.canGrant.where((r) => r != Role.user).toList();
    final v = await showEntityForm(context, title: l.addMember, fields: [
      FieldSpec('npub', 'npub', required: true, hint: 'npub1…'),
      FieldSpec('name', l.name),
      FieldSpec('role', l.role, type: FieldType.choice, required: true,
          options: {for (final r in grant) r.name: l.roleName(r.name)}),
    ], initial: {'role': Role.mod.name});
    if (v == null || !context.mounted) return;
    String pk;
    try {
      pk = parsePubkey(v['npub'] as String);
    } catch (_) {
      context.toast(l.invalidNpub);
      return;
    }
    await guarded(context, () => context.app.ledger.upsert('members', bid,
        {'pubkey': pk, 'name': v['name'], 'role': v['role'], 'deleted': 0}, id: '$bid:$pk'));
  }
}
