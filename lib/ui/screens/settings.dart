
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app_state.dart';
import '../../data/zx_store.dart';
import '../forms.dart';
import '../widgets/common.dart';
import '../widgets/entity_form.dart';
import '../../platform/backup.dart';
import '../../platform/updates.dart';
import 'checkpoints.dart';
import 'profile.dart';
import 'update_dialog.dart';
import 'sync_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text(l.more)),
      body: ListView(children: [
        ListTile(
          leading: const Icon(Icons.key),
          title: Text(l.myIdentity),
          subtitle: Text(app.identity.npub, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IdentityScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.account_circle),
          title: Text(l.myProfile),
          subtitle: Text(l.myProfileSubtitle),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.sync),
          title: Text(l.sync),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SyncScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.flag),
          title: Text(l.checkpoints),
          subtitle: Text(l.checkpointsSubtitle),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CheckpointsScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.category),
          title: Text(l.categories),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoriesScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.mail_outline),
          title: Text(l.documents),
          subtitle: Text(l.comingSoon),
          enabled: false,
        ),
        if (!kIsWeb) ListenableBuilder(
          listenable: app.updates,
          builder: (context, _) {
            final r = app.updates.ready;
            if (r != null) {
              return ListTile(
                leading: Icon(Icons.system_update, color: Theme.of(context).colorScheme.primary),
                title: Text(l.updateReady(r.version)),
                subtitle: Text(app.updates.apk == null && UpdateService.canInstall ? l.updateDownloading : l.updateReadyHelp),
                trailing: FilledButton(onPressed: () => offerUpdate(context), child: Text(l.installNow)),
                onTap: () => offerUpdate(context),
              );
            }
            return ListTile(
              leading: const Icon(Icons.system_update),
              title: Text(l.checkForUpdates),
              subtitle: FutureBuilder<String>(
                future: UpdateService.installedVersion(),
                builder: (c, s) => Text('${l.installedVersion} ${s.data ?? ''} · ${l.updatesAutomatic}'),
              ),
              onTap: () => checkForUpdates(context, manual: true),
            );
          },
        ),
        if (!kIsWeb) ListTile(
          leading: const Icon(Icons.save_alt),
          title: Text(l.exportBackup),
          subtitle: Text(l.exportBackupHelp),
          onTap: () => _exportBackup(context),
        ),
        if (!kIsWeb) ListTile(
          leading: const Icon(Icons.settings_backup_restore),
          title: Text(l.restoreBackup),
          subtitle: Text(l.restoreBackupHelp),
          onTap: () => _restoreBackup(context),
        ),
        ListTile(
          leading: const Icon(Icons.language),
          title: Text(l.language),
          trailing: DropdownButton<String>(
            value: app.locale?.languageCode ?? '',
            items: [
              DropdownMenuItem(value: '', child: Text(l.systemLanguage)),
              const DropdownMenuItem(value: 'pt', child: Text('Português')),
              const DropdownMenuItem(value: 'en', child: Text('English')),
            ],
            onChanged: (v) => app.setLocale(v == null || v.isEmpty ? null : Locale(v)),
          ),
        ),
        const AboutListTile(
          icon: Icon(Icons.info_outline),
          applicationName: 'Senhorio',
        ),
      ]),
    );
  }

  Future<void> _exportBackup(BuildContext context) async {
    final app = context.app;
    final l = context.l;
    String? target;
    try {
      target = await Backups.export(app.store.path);
    } catch (e) {
      if (context.mounted) context.toast('$e');
      return;
    }
    if (target == null || !context.mounted) return;
    final key = Backups.restoreKey(app.identity.nsec, await app.identityService.dbPassword());
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.backupSaved),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText(target!),
            const SizedBox(height: 12),
            Text(l.backupPassword),
            const SizedBox(height: 4),
            SelectableText(key, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ]),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy),
            label: Text(l.copyRestoreKey),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: key));
              c.toast(l.copied);
            },
          ),
          FilledButton(onPressed: () => Navigator.pop(c), child: Text(l.ok)),
        ],
      ),
    );
  }

  Future<void> _restoreBackup(BuildContext context) async {
    final app = context.app;
    final l = context.l;
    final picked = await Backups.pick();
    if (picked == null || !context.mounted) return;
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.restoreBackup),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.restoreKeyHelp),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: InputDecoration(labelText: l.restoreKey),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: Text(l.ok)),
        ],
      ),
    );
    ctrl.dispose();
    if (text == null || !context.mounted) return;
    final key = Backups.parseRestoreKey(text);
    if (key == null) {
      context.toast(l.restoreKeyInvalid);
      return;
    }
    if (!await confirm(context, l.restoreConfirm(picked.name)) || !context.mounted) return;
    final (nsec, password) = key;
    try {
      await app.restoreBackup(picked.path, nsec: nsec, password: password);
    } catch (e) {
      if (context.mounted) context.toast(l.restoreFailed);
      return;
    }
  }
}

class IdentityScreen extends StatefulWidget {
  const IdentityScreen({super.key});
  @override
  State<IdentityScreen> createState() => _IdentityScreenState();
}

class _IdentityScreenState extends State<IdentityScreen> {
  bool _showNsec = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final id = context.watch<AppState>().identity;
    return Scaffold(
      appBar: AppBar(title: Text(l.myIdentity)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(l.identityHelp, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        Center(
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(8),
            child: QrImageView(data: id.npub, size: 220),
          ),
        ),
        const SizedBox(height: 12),
        SelectableText(id.npub, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'monospace')),
        TextButton.icon(
          icon: const Icon(Icons.copy),
          label: Text(l.copyNpub),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: id.npub));
            context.toast(l.copied);
          },
        ),
        const Divider(height: 32),
        ListTile(
          leading: const Icon(Icons.vpn_key),
          title: Text(l.secretKey),
          subtitle: Text(_showNsec ? id.nsec : '••••••••••••', style: const TextStyle(fontFamily: 'monospace')),
          trailing: IconButton(
            icon: Icon(_showNsec ? Icons.visibility_off : Icons.visibility),
            onPressed: () async {
              if (!_showNsec && !await confirm(context, l.nsecWarning)) return;
              setState(() => _showNsec = !_showNsec);
            },
          ),
          onLongPress: _showNsec
              ? () {
                  Clipboard.setData(ClipboardData(text: id.nsec));
                  context.toast(l.copied);
                }
              : null,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.download),
          label: Text(l.importNsec),
          onPressed: () async {
            final v = await showEntityForm(context, title: l.importNsec,
                fields: [FieldSpec('nsec', 'nsec', required: true, hint: 'nsec1…')]);
            if (v == null || !context.mounted) return;
            if (!await confirm(context, l.importNsecWarning) || !context.mounted) return;
            try {
              await context.app.importIdentity(v['nsec'] as String);
              if (context.mounted) context.toast(l.identityImported);
            } catch (_) {
              if (context.mounted) context.toast(l.invalidNsec);
            }
          },
        ),
      ]),
    );
  }
}

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(title: Text(l.categories)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => editEntity(context, table: 'categories', building: '', title: l.newCategory,
            fields: categoryFields(l), defaults: {'icon': 'category', 'color': 0xFF607D8B}),
        child: const Icon(Icons.add),
      ),
      body: LiveFuture<List<DbRow>>(
        load: (a) => a.q.categories(),
        builder: (context, rows) => ListView(children: [
          for (final c in rows)
            ListTile(
              leading: CategoryAvatar(c),
              title: Text(categoryName(context, c)),
              subtitle: c['unit'] == null ? null : Text(c['unit'] as String),
              onTap: () => editEntity(context, table: 'categories', building: '', title: l.edit,
                  fields: categoryFields(l), row: {...c, 'name': categoryName(context, c)}),
              trailing: c['key'] != null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        if (await confirm(context, l.confirmDelete) && context.mounted) {
                          await guarded(context, () => context.app.ledger.delete('categories', '', c['id'] as String));
                        }
                      },
                    ),
            ),
        ]),
      ),
    );
  }
}
