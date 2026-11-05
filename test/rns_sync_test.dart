// Two real Reticulum nodes syncing a building through a public hub:
// announces, the npub binding, LXMF delivery. Needs the internet, so it runs
// only when a hub is given:  SENHORIO_HUB=rns.wisco.network:4242 flutter test test/rns_sync_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:senhorio/data/ledger.dart';
import 'package:senhorio/data/queries.dart';
import 'package:senhorio/data/zx_store.dart';
import 'package:senhorio/identity/identity_service.dart';
import 'package:senhorio/sync/sync_service.dart';

Future<bool> waitFor(Future<bool> Function() cond, {int seconds = 90}) async {
  for (var i = 0; i < seconds * 2; i++) {
    if (await cond()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

void main() {
  final hub = Platform.environment['SENHORIO_HUB'];
  test('two nodes sync a building over a Reticulum hub', () async {
    final dir = await Directory.systemTemp.createTemp('senhorio-rns');
    Future<(ZxStore, Ledger, SyncService)> peer(String name, Identity id) async {
      final s = await ZxStore.open('${dir.path}/$name.zx');
      final l = Ledger(s, id);
      await l.init();
      await s.exec("INSERT OR REPLACE INTO meta (key, value) VALUES ('hubs', ?)", [hub]);
      final sync = SyncService(s, l, MemoryKeyStore());
      await sync.start();
      return (s, l, sync);
    }

    final alice = Identity.generate(), bob = Identity.generate();
    final (sa, la, ya) = await peer('a', alice);
    final (sb, lb, yb) = await peer('b', bob);

    expect(await waitFor(() async =>
        ya.node!.peers.containsKey(bob.pubkey) && yb.node!.peers.containsKey(alice.pubkey)), isTrue,
        reason: 'nodes did not hear each other');

    final b = await la.createBuilding({'name': 'Rua RNS'});
    await la.upsert('members', b, {'pubkey': bob.pubkey, 'role': 'member'}, id: '$b:${bob.pubkey}');
    expect(await waitFor(() async => (await Queries(sb).buildings()).isNotEmpty), isTrue);
    expect((await Queries(sb).buildings()).single['name'], 'Rua RNS');

    // and back: bob's change reaches alice
    await lb.upsert('apartments', b, {'name': 'R/C'});
    expect(await waitFor(() async => (await Queries(sa).apartments(b)).isNotEmpty), isTrue);

    await ya.stop();
    await yb.stop();
    await sa.close();
    await sb.close();
    await dir.delete(recursive: true);
  }, skip: hub == null ? 'set SENHORIO_HUB=host:port to run' : null,
      timeout: const Timeout(Duration(minutes: 5)));
}
