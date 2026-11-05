import 'package:flutter/material.dart';

import '../../data/schema.dart';
import '../../data/zx_store.dart';
import '../../domain/checkpoints.dart';
import '../../identity/identity_service.dart';
import '../widgets/common.dart';
import '../widgets/entity_form.dart';

class CheckpointsScreen extends StatelessWidget {
  const CheckpointsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(title: Text(l.checkpoints)),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.flag),
        label: Text(l.newCheckpoint),
        onPressed: () async {
          final v = await showEntityForm(context, title: l.newCheckpoint,
              fields: [FieldSpec('label', l.name, required: true)]);
          if (v == null || !context.mounted) return;
          final app = context.app;
          await app.checkpoints.create(v['label'] as String, app.identity.pubkey);
          app.ledger.touch();
        },
      ),
      body: LiveFuture<List<DbRow>>(
        load: (a) => a.checkpoints.list(),
        builder: (context, rows) => rows.isEmpty
            ? EmptyState(Icons.flag_outlined, l.noCheckpoints)
            : ListView(children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(l.checkpointsHelp, style: Theme.of(context).textTheme.bodySmall),
                ),
                for (final c in rows)
                  ListTile(
                    leading: Icon(c['auto'] == 1 ? Icons.schedule : Icons.flag),
                    title: Text(c['label'] as String? ?? ''),
                    subtitle: Text('${DateTime.fromMillisecondsSinceEpoch(c['time'] as int).toString().substring(0, 16)} · #${c['generation']}'),
                    trailing: const Icon(Icons.compare_arrows),
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => CheckpointDiffScreen(checkpoint: c))),
                  ),
              ]),
      ),
    );
  }
}

class CheckpointDiffScreen extends StatelessWidget {
  final DbRow checkpoint;
  const CheckpointDiffScreen({super.key, required this.checkpoint});

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(title: Text(l.changesSince(checkpoint['label'] as String? ?? ''))),
      body: LiveFuture<(List<ChangeEntry>, Map<String, String>)>(
        load: (a) async {
          final names = <String, String>{};
          for (final b in await a.store.query('SELECT id, name FROM buildings')) {
            names[b['id'] as String] = b['name'] as String? ?? '';
          }
          return (await a.checkpoints.diff(checkpoint['generation'] as int), names);
        },
        builder: (context, d) {
          final (changes, buildings) = d;
          if (changes.isEmpty) return EmptyState(Icons.check, l.noChanges);
          final order = [ChangeKind.vanished, ChangeKind.deleted, ChangeKind.changed, ChangeKind.added];
          changes.sort((a, b) => order.indexOf(a.kind).compareTo(order.indexOf(b.kind)));
          return ListView(children: [
            for (final c in changes) _tile(context, c, buildings),
          ]);
        },
      ),
    );
  }

  Widget _tile(BuildContext context, ChangeEntry c, Map<String, String> buildings) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, label) = switch (c.kind) {
      ChangeKind.added => (Icons.add_circle_outline, Colors.green, l.added),
      ChangeKind.changed => (Icons.edit, scheme.primary, l.changed),
      ChangeKind.deleted => (Icons.delete, scheme.error, l.deleted),
      ChangeKind.vanished => (Icons.report, scheme.error, l.vanished),
    };
    final row = c.after ?? c.before!;
    final title = (row['name'] ?? row['vendor'] ?? row['description'] ?? row['period'] ?? row['id']).toString();
    final by = c.by == null || c.by!.isEmpty ? '' : shortNpub(c.by!);
    return ExpansionTile(
      leading: Icon(icon, color: color),
      title: Text('$label · ${l.entityName(c.table)}'),
      subtitle: Text('$title${buildings[c.building] == null ? '' : ' · ${buildings[c.building]}'}${by.isEmpty ? '' : ' · $by'}'),
      children: [
        for (final f in entityFields[c.table]!.keys)
          if (c.before?[f] != null || c.after?[f] != null)
            ListTile(
              dense: true,
              title: Text(f),
              subtitle: Text(
                c.kind == ChangeKind.changed && c.changedFields.contains(f)
                    ? '${c.before?[f]}  →  ${c.after?[f]}'
                    : '${c.before?[f] ?? c.after?[f]}',
                style: c.changedFields.contains(f) ? TextStyle(color: scheme.primary) : null,
              ),
            ),
        OverflowBar(children: [
          TextButton.icon(
            icon: const Icon(Icons.restore),
            label: Text(c.kind == ChangeKind.added ? l.undoAdd : l.restore),
            onPressed: () async {
              if (await confirm(context, l.confirmRestore) && context.mounted) {
                await guarded(context, () => context.app.checkpoints.restore(c));
              }
            },
          ),
        ]),
      ],
    );
  }
}
