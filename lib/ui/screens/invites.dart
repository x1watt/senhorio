// Invite codes in the UI: making one (role, and for a tenant which tenant),
// showing it, listing the open ones, and joining with one.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/zx_store.dart';
import '../../domain/roles.dart';
import '../../sync/invites.dart';
import '../widgets/common.dart';
import 'buildings.dart';

String _time(BuildContext context, DateTime t) =>
    MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(t)) +
    (DateUtils.isSameDay(t, DateTime.now())
        ? ''
        : ' (${MaterialLocalizations.of(context).formatShortMonthDay(t)})');

/// Asks for the role (and tenant) and shows the new code.
Future<void> inviteToBuilding(BuildContext context, String building, {String? tenantId}) async {
  final l = context.l;
  final app = context.app;
  if (!app.sync.running) {
    context.toast(l.syncNeededForInvites);
    return;
  }
  final mine = await app.ledger.myRole(building);
  final grant = mine?.canGrant ?? const <Role>[];
  if (grant.isEmpty || !context.mounted) return;
  final tenants = await app.q.tenants(building);
  if (!context.mounted) return;
  final choice = await showDialog<(Role, String?, String?)>(
    context: context,
    builder: (_) => _InviteDialog(
        grant: grant, tenants: tenants, tenantId: tenantId,
        initialRole: tenantId != null ? Role.user : (grant.contains(Role.mod) ? Role.mod : grant.first)),
  );
  if (choice == null || !context.mounted) return;
  final (role, tenant, name) = choice;
  Invite inv;
  try {
    inv = await app.sync.invites.create(building, role, tenantId: tenant, name: name);
  } catch (e) {
    if (context.mounted) context.toast('$e');
    return;
  }
  if (context.mounted) await showInviteCode(context, inv);
}

class _InviteDialog extends StatefulWidget {
  final List<Role> grant;
  final List<DbRow> tenants;
  final String? tenantId;
  final Role initialRole;
  const _InviteDialog({required this.grant, required this.tenants, required this.tenantId,
      required this.initialRole});
  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  late Role role = widget.initialRole;
  late String? tenant = widget.tenantId;
  final name = TextEditingController();

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  String? get _tenantName =>
      widget.tenants.where((t) => t['id'] == tenant).firstOrNull?['name'] as String?;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final needTenant = role == Role.user;
    final ok = !needTenant || tenant != null;
    return AlertDialog(
      title: Text(l.invite),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.role, style: Theme.of(context).textTheme.titleSmall),
          RadioGroup<Role>(
            groupValue: role,
            onChanged: (r) => setState(() => role = r!),
            child: Column(children: [
              for (final r in widget.grant)
                RadioListTile<Role>(
                  value: r,
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.roleName(r.name)),
                  subtitle: Text(l.roleHelp(r.name)),
                ),
            ]),
          ),
          if (needTenant) ...[
            const SizedBox(height: 8),
            if (widget.tenants.isEmpty)
              Text(l.noTenantsToInvite, style: TextStyle(color: Theme.of(context).colorScheme.error))
            else
              DropdownButtonFormField<String>(
                initialValue: tenant,
                isExpanded: true,
                decoration: InputDecoration(labelText: l.whichTenant),
                items: [
                  for (final t in widget.tenants)
                    DropdownMenuItem(value: t['id'] as String, child: Text(t['name'] as String? ?? '?')),
                ],
                onChanged: (v) => setState(() => tenant = v),
              ),
          ] else
            TextField(controller: name, decoration: InputDecoration(labelText: l.nameOptional)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(
          onPressed: ok
              ? () => Navigator.pop(context, (
                    role,
                    needTenant ? tenant : null,
                    needTenant ? _tenantName : (name.text.trim().isEmpty ? null : name.text.trim()),
                  ))
              : null,
          child: Text(l.invite),
        ),
      ],
    );
  }
}

/// The code, big, with who it is for and until when it works.
Future<void> showInviteCode(BuildContext context, Invite inv) {
  final l = context.l;
  return showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(l.inviteCode),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        SelectableText(inv.code,
            style: Theme.of(c).textTheme.displayMedium?.copyWith(
                fontFamily: 'monospace', fontWeight: FontWeight.bold, letterSpacing: 8)),
        const SizedBox(height: 8),
        Text([l.roleName(inv.role), ?inv.name].join(' · '),
            style: Theme.of(c).textTheme.titleMedium),
        const SizedBox(height: 12),
        Text(l.inviteCodeHelp(_time(c, inv.expiresAt)), textAlign: TextAlign.center),
      ]),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy),
          label: Text(l.copy),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: inv.code));
            c.toast(l.copied);
          },
        ),
        FilledButton(onPressed: () => Navigator.pop(c), child: Text(l.ok)),
      ],
    ),
  );
}

/// Open invites of [building] (made on this device), with cancel.
class OpenInvites extends StatelessWidget {
  final String building;
  const OpenInvites({super.key, required this.building});

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final invites = context.app.sync.invites;
    return ListenableBuilder(
      listenable: invites,
      builder: (context, _) => FutureBuilder<List<Invite>>(
        future: invites.active(building: building),
        builder: (context, snap) {
          final list = snap.data ?? const <Invite>[];
          if (list.isEmpty) return const SizedBox.shrink();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionHeader(l.openInvites),
            for (final i in list)
              ListTile(
                leading: const Icon(Icons.vpn_key_outlined),
                title: Text(i.code, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, letterSpacing: 3)),
                subtitle: Text([l.roleName(i.role), ?i.name, l.until(_time(context, i.expiresAt))].join(' · ')),
                onTap: () => showInviteCode(context, i),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: l.cancelInvite,
                  onPressed: () => invites.cancel(i.code),
                ),
              ),
            const Divider(),
          ]);
        },
      ),
    );
  }
}

/// Asks for a code, finds the inviter and joins; opens the building.
Future<void> joinWithCode(BuildContext context) async {
  final l = context.l;
  final app = context.app;
  if (!app.sync.running) {
    context.toast(l.syncNeededForInvites);
    return;
  }
  final ctrl = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(l.joinWithCode),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(l.enterInviteCode),
        const SizedBox(height: 12),
        TextField(
          controller: ctrl,
          autofocus: true,
          textAlign: TextAlign.center,
          textCapitalization: TextCapitalization.characters,
          maxLength: inviteLength,
          style: Theme.of(c).textTheme.headlineMedium?.copyWith(fontFamily: 'monospace', letterSpacing: 8),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[${inviteAlphabet}a-z]', caseSensitive: false)),
            TextInputFormatter.withFunction((_, v) => v.copyWith(text: v.text.toUpperCase())),
          ],
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(l.cancel)),
        FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: Text(l.ok)),
      ],
    ),
  );
  ctrl.dispose();
  if (code == null || code.trim().isEmpty || !context.mounted) return;
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 20),
          Expanded(child: Text(l.joining)),
        ]),
      ),
    ),
  ));
  try {
    final r = await app.sync.invites.join(code);
    nav.pop();
    messenger.showSnackBar(SnackBar(content: Text(l.joined(r.buildingName))));
    await nav.push(MaterialPageRoute(builder: (_) => BuildingScreen(buildingId: r.building)));
  } on JoinError catch (e) {
    nav.pop();
    messenger.showSnackBar(SnackBar(content: Text(l.joinError(e.reason))));
  }
}
