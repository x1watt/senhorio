import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app_state.dart';
import '../../core/dates.dart';
import '../../data/zx_store.dart';
import '../forms.dart';
import '../widgets/common.dart';
import '../widgets/entity_form.dart';
import 'checkpoints.dart';
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
        if (!kIsWeb) ListTile(
          leading: const Icon(Icons.save_alt),
          title: Text(l.exportBackup),
          subtitle: Text(l.exportBackupHelp),
          onTap: () => _exportBackup(context),
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
          applicationVersion: '0.1.0',
        ),
      ]),
    );
  }

  Future<void> _exportBackup(BuildContext context) async {
    final app = context.app;
    final l = context.l;
    final name = 'senhorio-${isoDate(DateTime.now())}.zx';
    String? target;
    if (Platform.isAndroid || Platform.isIOS) {
      final dir = await getDownloadsDirectory() ?? await getExternalStorageDirectory();
      if (dir != null) target = '${dir.path}/$name';
    } else {
      target = (await getSaveLocation(suggestedName: name))?.path;
    }
    if (target == null) return;
    await File(app.store.path).copy(target);
    final pw = await app.identityService.dbPassword();
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.backupSaved),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          SelectableText(target!),
          const SizedBox(height: 12),
          Text(l.backupPassword),
          SelectableText(pw, style: const TextStyle(fontFamily: 'monospace')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(l.ok))],
      ),
    );
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
