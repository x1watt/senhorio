import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:senhorio/data/ledger.dart';
import 'package:senhorio/data/queries.dart';
import 'package:senhorio/data/zx_store.dart';
import 'package:senhorio/identity/identity_service.dart';
import 'package:senhorio/sync/sync_engine.dart';

import 'wire.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('senhorio-sync'));
  tearDown(() async => dir.delete(recursive: true));

  test('owner shares a building with a member; edits, deletes and receipts converge; strangers get nothing', () async {
    final wire = Wire();
    Future<(ZxStore, Ledger, SyncEngine)> peer(String name, Identity id) async {
      final s = await ZxStore.open('${dir.path}/$name.zx');
      final l = Ledger(s, id, device: name);
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

  test('one npub on two devices: both keep every change, in both directions', () async {
    final wire = Wire();
    final alice = Identity.generate();
    Future<(ZxStore, Ledger, SyncEngine)> device(String name) async {
      final s = await ZxStore.open('${dir.path}/$name.zx');
      final l = Ledger(s, alice, device: name);
      await l.init();
      final e = SyncEngine(l, s, send: (to, m) => wire.sendAll(alice.pubkey, to, m));
      wire.devices.putIfAbsent(alice.pubkey, () => []).add(e);
      return (s, l, e);
    }

    final (s1, l1, e1) = await device('phone');
    final (s2, l2, e2) = await device('laptop');
    final b = await l1.createBuilding({'name': 'Casa'});
    await l1.upsert('tenants', b, {'name': 'Ana'});
    await wire.settle();
    expect((await Queries(s2).tenants(b)).single['name'], 'Ana');
    // both devices write at the same time (same author, separate sequences)
    await l1.upsert('tenants', b, {'name': 'Bruno'});
    await l2.upsert('tenants', b, {'name': 'Carla'});
    await wire.settle();
    for (final s in [s1, s2]) {
      expect((await Queries(s).tenants(b)).map((t) => t['name']).toSet(), {'Ana', 'Bruno', 'Carla'});
    }
    // a third device restored from the nsec gets everything by asking
    final (s3, _, e3) = await device('tablet');
    await e3.syncWith(alice.pubkey);
    await wire.settle();
    expect((await Queries(s3).tenants(b)).length, 3);
    expect(e1.stats.eventsOut + e2.stats.eventsOut, greaterThan(0));
    for (final s in [s1, s2, s3]) {
      await s.close();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
