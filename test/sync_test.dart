import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:senhorio/data/ledger.dart';
import 'package:senhorio/data/queries.dart';
import 'package:senhorio/data/zx_store.dart';
import 'package:senhorio/identity/identity_service.dart';
import 'package:senhorio/sync/sync_engine.dart';

/// Peers wired by an in-memory network (messages are JSON round-tripped).
class Wire {
  final engines = <String, SyncEngine>{};
  var pending = <Future<void>>[];
  Future<bool> send(String from, String to, Map<String, Object?> msg) async {
    final e = engines[to];
    if (e == null) return false;
    final copy = jsonDecode(jsonEncode(msg)) as Map<String, Object?>;
    pending.add(Future(() => e.onMessage(from, copy)));
    return true;
  }

  /// Runs until no message is in flight.
  Future<void> settle() async {
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (pending.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (pending.isEmpty) return;
      }
      final p = pending;
      pending = [];
      await Future.wait(p);
    }
  }
}

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('senhorio-sync'));
  tearDown(() async => dir.delete(recursive: true));

  test('owner shares a building with a member; edits, deletes and receipts converge; strangers get nothing', () async {
    final wire = Wire();
    Future<(ZxStore, Ledger, SyncEngine)> peer(String name, Identity id) async {
      final s = await ZxStore.open('${dir.path}/$name.zx');
      final l = Ledger(s, id);
      await l.init();
      final e = SyncEngine(l, s, send: (to, m) => wire.send(id.pubkey, to, m));
      wire.engines[id.pubkey] = e;
      return (s, l, e);
    }

    final alice = Identity.generate(), bob = Identity.generate(), eve = Identity.generate();
    final (sa, la, ea) = await peer('a', alice);
    final (sb, lb, eb) = await peer('b', bob);
    final (se, _, ee) = await peer('e', eve);

    final b = await la.createBuilding({'name': 'Rua A'});
    final sha = await Queries(sa).putAttachment(Uint8List.fromList(List.generate(5000, (i) => i % 251)), 'image/jpeg');
    final exp = await la.upsert('expenses', b, {'amount_cents': 4200, 'vendor': 'EDP', 'attachments': [sha]});
    await la.upsert('members', b, {'pubkey': bob.pubkey, 'role': 'member'}, id: '$b:${bob.pubkey}');
    await wire.settle();

    expect((await Queries(sb).buildings()).single['name'], 'Rua A');
    expect((await Queries(sb).expenses()).single['vendor'], 'EDP');
    expect(await Queries(sb).hasAttachment(sha), isTrue);

    // bob edits and deletes; alice receives both (pushed live)
    await lb.upsert('expenses', b, {'amount_cents': 4300}, id: exp);
    final t = await lb.upsert('tenants', b, {'name': 'Ana'});
    await lb.delete('tenants', b, t);
    await wire.settle();
    expect((await Queries(sa).expenses()).single['amount_cents'], 4300);
    expect((await Queries(sa).byId('tenants', t))!['deleted'], 1);

    // eve asks for a sync: she is no member, receives nothing of the building
    await ee.syncWith(alice.pubkey);
    await wire.settle();
    expect(await Queries(se).buildings(), isEmpty);

    // offline catch-up: bob misses changes, then a hello brings them
    wire.engines.remove(bob.pubkey);
    await la.upsert('apartments', b, {'name': '2º Dto'});
    await wire.settle();
    wire.engines[bob.pubkey] = eb;
    await eb.syncWith(alice.pubkey);
    await wire.settle();
    expect((await Queries(sb).apartments(b)).single['name'], '2º Dto');

    // revoked: bob no longer receives new data
    await la.delete('members', b, '$b:${bob.pubkey}');
    await wire.settle();
    await la.upsert('apartments', b, {'name': '3º Esq'});
    await eb.syncWith(alice.pubkey);
    await wire.settle();
    expect((await Queries(sb).apartments(b)).length, 1);

    for (final s in [sa, sb, se]) {
      await s.close();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
