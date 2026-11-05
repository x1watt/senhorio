import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reticulum/reticulum.dart' show NostrEvent;
import 'package:senhorio/data/ledger.dart';
import 'package:senhorio/data/queries.dart';
import 'package:senhorio/data/zx_store.dart';
import 'package:senhorio/domain/checkpoints.dart';
import 'package:senhorio/identity/identity_service.dart';

Future<(ZxStore, Ledger)> openLedger(Directory dir, String name, Identity id) async {
  final store = await ZxStore.open('${dir.path}/$name.zx', password: 'pw');
  final l = Ledger(store, id);
  await l.init();
  return (store, l);
}

Future<List<NostrEvent>> allEvents(ZxStore s) async => [
      for (final r in await s.query('SELECT json FROM events ORDER BY hlc'))
        NostrEvent.fromJson(jsonDecode(r['json'] as String) as Map<String, dynamic>)
    ];

void main() {
  late Directory dir;
  final alice = Identity.generate();
  final bob = Identity.generate();
  final eve = Identity.generate();

  setUp(() async => dir = await Directory.systemTemp.createTemp('senhorio'));
  tearDown(() async => dir.delete(recursive: true));

  test('local writes project, default categories seeded', () async {
    final (s, l) = await openLedger(dir, 'a', alice);
    final b = await l.createBuilding({'name': 'Rua A', 'currency': 'EUR'});
    final apt = await l.upsert('apartments', b, {'name': '1º Esq'});
    await l.upsert('rooms', b, {'apartment_id': apt, 'name': 'Quarto 1', 'available': 1});
    final q = Queries(s);
    expect((await q.buildings()).single['name'], 'Rua A');
    expect((await q.rooms(b)).single['name'], 'Quarto 1');
    expect((await q.members(b)).single['role'], 'owner');
    expect((await q.categories()).length, defaultCategories.length);
    await s.close();
  });

  test('sync between two ledgers converges, LWW per field, deletes soft', () async {
    final (sa, la) = await openLedger(dir, 'a', alice);
    final (sb, lb) = await openLedger(dir, 'b', bob);
    final b = await la.createBuilding({'name': 'Rua A'});
    await la.upsert('members', b, {'pubkey': bob.pubkey, 'role': 'member'},
        id: '$b:${bob.pubkey}');
    final t = await la.upsert('tenants', b, {'name': 'Ana', 'phone': '1'});
    expect(await lb.ingest(await allEvents(sa)), greaterThan(0));
    // concurrent edits of different fields both survive
    await la.upsert('tenants', b, {'phone': '2'}, id: t);
    await lb.upsert('tenants', b, {'email': 'ana@x'}, id: t);
    await lb.ingest(await allEvents(sa));
    await la.ingest(await allEvents(sb));
    for (final s in [sa, sb]) {
      final r = (await Queries(s).byId('tenants', t))!;
      expect(r['phone'], '2');
      expect(r['email'], 'ana@x');
    }
    await lb.delete('tenants', b, t);
    await la.ingest(await allEvents(sb));
    expect(await Queries(sa).tenants(b), isEmpty);
    expect((await Queries(sa).byId('tenants', t))!['deleted'], 1);
    await sa.close();
    await sb.close();
  });

  test('non-members and non-owners are refused', () async {
    final (sa, la) = await openLedger(dir, 'a', alice);
    final (se, le) = await openLedger(dir, 'e', eve);
    final b = await la.createBuilding({'name': 'Rua A'});
    await le.ingest(await allEvents(sa));
    // eve is no member: her change stays pending at alice, not applied
    final t = await le.upsert('tenants', b, {'name': 'Fake'}).catchError((_) => '');
    expect(t, isNotEmpty); // eve's own copy has no rule against her...
    await la.ingest(await allEvents(se));
    expect(await Queries(sa).tenants(b), isEmpty);
    final st = await sa.scalar(
        "SELECT count(*) FROM events WHERE author = ? AND status = 'pending'", [eve.pubkey]);
    expect(st, 1);
    await sa.close();
    await se.close();
  });

  test('checkpoint diff shows a deletion made after it, restore brings it back', () async {
    final (s, l) = await openLedger(dir, 'a', alice);
    final b = await l.createBuilding({'name': 'Rua A'});
    final e = await l.upsert('expenses', b, {'amount_cents': 1234, 'vendor': 'EDP'});
    final cp = Checkpoints(s, l);
    await cp.create('before', alice.pubkey);
    final g = (await cp.list()).first['generation'] as int;
    await l.delete('expenses', b, e);
    await l.upsert('apartments', b, {'name': 'new'});
    final d = await cp.diff(g);
    final del = d.singleWhere((c) => c.kind == ChangeKind.deleted);
    expect(del.table, 'expenses');
    expect(del.before!['vendor'], 'EDP');
    expect(d.where((c) => c.kind == ChangeKind.added).single.table, 'apartments');
    await cp.restore(del);
    expect((await Queries(s).expenses()).single['amount_cents'], 1234);
    await s.close();
  });

  test('archive reopens with its data', () async {
    final (s, l) = await openLedger(dir, 'a', alice);
    await l.createBuilding({'name': 'Persist'});
    await s.close();
    final (s2, _) = await openLedger(dir, 'a', alice);
    expect((await Queries(s2).buildings()).single['name'], 'Persist');
    await s2.close();
  });
}
