import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../identity/identity_service.dart';
import '../../platform/background.dart';
import '../../sync/sync_service.dart';
import '../widgets/common.dart';
import '../widgets/entity_form.dart';

/// Reticulum sync status: hubs, peers, counters and the node's log.
class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return ChangeNotifierProvider<SyncService>.value(
      value: context.app.sync,
      child: Consumer<SyncService>(builder: (context, sync, _) {
        final node = sync.node;
        final st = sync.engine.stats;
        return Scaffold(
          appBar: AppBar(
            title: Text(l.sync),
            actions: [
              IconButton(
                icon: const Icon(Icons.sync),
                tooltip: l.syncNow,
                onPressed: sync.running ? () => sync.syncAll() : null,
              ),
            ],
          ),
          body: ListView(children: [
            FutureBuilder<bool>(
              future: sync.enabled(),
              builder: (context, snap) => SwitchListTile(
                secondary: const Icon(Icons.hub),
                title: Text(l.syncOverReticulum),
                subtitle: Text(l.syncHelp),
                value: sync.running,
                onChanged: (v) => sync.setEnabled(v),
              ),
            ),
            if (BackgroundSync.supported)
              FutureBuilder<bool>(
                future: sync.backgroundEnabled(),
                builder: (context, snap) => SwitchListTile(
                  secondary: const Icon(Icons.notifications_active_outlined),
                  title: Text(l.syncInBackground),
                  subtitle: Text(l.syncInBackgroundHelp),
                  value: snap.data ?? true,
                  onChanged: (v) => sync.setBackground(v),
                ),
              ),
            if (node != null) ...[
              ListTile(
                leading: const Icon(Icons.fingerprint),
                title: Text(l.reticulumAddress),
                subtitle: SelectableText(node.rnsHash ?? '-', style: const TextStyle(fontFamily: 'monospace')),
              ),
              ListTile(
                leading: Icon(Icons.cloud, color: node.connectedHubs.isEmpty ? Theme.of(context).colorScheme.error : Colors.green),
                title: Text(l.hubs),
                subtitle: Text(node.connectedHubs.isEmpty ? l.noHubConnected : node.connectedHubs.join('\n')),
                trailing: IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () async {
                    final current = (await sync.hubs()).join('\n');
                    if (!context.mounted) return;
                    final v = await showEntityForm(context, title: l.hubs,
                        fields: [FieldSpec('hubs', l.hubsHelp, type: FieldType.multiline, required: true)],
                        initial: {'hubs': current});
                    if (v != null) await sync.setHubs(v['hubs'] as String);
                  },
                ),
              ),
              ListTile(
                leading: Icon(Icons.lan, color: node.lanUp ? Colors.green : null),
                title: Text(l.localNetwork),
                subtitle: Text(node.lanUp ? l.on : l.off),
              ),
              SectionHeader(l.peers),
              if (node.peers.isEmpty) ListTile(title: Text(l.noPeersYet)),
              for (final p in node.peers.values)
                ListTile(
                  leading: Icon(sync.partners.contains(p.pubkey) ? Icons.handshake : Icons.person_outline),
                  title: Text(p.pubkey == context.app.identity.pubkey ? l.myOtherDevice : shortNpub(p.pubkey)),
                  subtitle: Text('${p.identity.hexHash.substring(0, 12)} · ${p.via} · ${p.lastSeen.toString().substring(11, 19)}'),
                  trailing: sync.partners.contains(p.pubkey)
                      ? IconButton(icon: const Icon(Icons.sync), onPressed: () => sync.engine.syncWith(p.pubkey))
                      : null,
                ),
              SectionHeader(l.activity),
              ListTile(
                dense: true,
                title: Text(l.syncCounters(st.sent, st.received, st.eventsIn, st.eventsOut, st.blobsIn)),
                subtitle: st.lastSync == null ? null : Text('${l.lastSync}: ${st.lastSync.toString().substring(0, 19)}'),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(node.logLines.reversed.take(80).join('\n'),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
              ),
            ],
          ]),
        );
      }),
    );
  }
}
