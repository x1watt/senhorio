import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:senhorio/data/ledger.dart';
import 'package:senhorio/data/queries.dart';
import 'package:senhorio/data/zx_store.dart';
import 'package:senhorio/domain/roles.dart';
import 'package:senhorio/identity/identity_service.dart';
import 'package:senhorio/sync/invites.dart';
import 'package:senhorio/sync/sync_engine.dart';

import 'wire.dart';

class Peer {
  final Identity id;
  final ZxStore s;
  final Ledger l;
  final SyncEngine e;
  final Invites inv;
  Peer(this.id, this.s, this.l, this.e, this.inv);
  Queries get q => Queries(s);
}

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('senhorio-invite'));
  tearDown(() async => dir.delete(recursive: true));

  test('roles', () {
    expect(roleOf('member'), Role.mod);
    expect(Role.admin.canManage(Role.mod, Role.admin), isTrue);
    expect(Role.admin.canManage(Role.owner, null), isFalse);
    expect(Role.mod.canManage(Role.user, null), isTrue);
    expect(Role.mod.canManage(null, Role.mod), isFalse);
    expect(Role.user.canManage(null, Role.user), isFalse);
    expect(normalizeInviteCode(' ab-49 '), 'AB49');
    expect(normalizeInviteCode('ab49'), 'AB49');
    expect(normalizeInviteCode('A0B1'), isNull);
  });

  test('invite codes: roles, single use, expiry, tenants see only their own lease', () async {
    final wire = Wire();
    final tags = <String, Set<int>>{};
    Future<Peer> peer(String name) async {
      final id = Identity.generate();
      final s = await ZxStore.open('${dir.path}/$name.zx');
      final l = Ledger(s, id, device: name);
      await l.init();
      final e = SyncEngine(l, s, send: (to, m) => wire.send(id.pubkey, to, m));
      wire.engines[id.pubkey] = e;
      final inv = Invites(s, l, e,
          peersWithTag: (t) => [for (final x in tags.entries) if (x.value.contains(t)) x.key])
        ..onTags = (t) => tags[id.pubkey] = t;
      return Peer(id, s, l, e, inv);
    }

    final alice = await peer('alice'), bob = await peer('bob'), carol = await peer('carol'),
        dave = await peer('dave');

    // alice's building: two rooms, two tenants with leases, an expense
    final b = await alice.l.createBuilding({'name': 'Rua A'});
    final apt = await alice.l.upsert('apartments', b, {'name': '1º'});
    final r1 = await alice.l.upsert('rooms', b, {'apartment_id': apt, 'name': 'Q1'});
    final r2 = await alice.l.upsert('rooms', b, {'apartment_id': apt, 'name': 'Q2'});
    final ana = await alice.l.upsert('tenants', b, {'name': 'Ana', 'phone': '911'});
    final rui = await alice.l.upsert('tenants', b, {'name': 'Rui', 'phone': '922'});
    final la = await alice.l.upsert('leases', b,
        {'room_id': r1, 'tenant_id': ana, 'rent_cents': 30000, 'start_date': '2026-01-01'});
    final lr = await alice.l.upsert('leases', b,
        {'room_id': r2, 'tenant_id': rui, 'rent_cents': 32000, 'start_date': '2026-01-01'});
    await alice.l.upsert('payments', b, {'lease_id': la, 'amount_cents': 30000, 'paid_on': '2026-01-08'});
    await alice.l.upsert('payments', b, {'lease_id': lr, 'amount_cents': 32000, 'paid_on': '2026-01-08'});
    await alice.l.upsert('expenses', b, {'amount_cents': 4200, 'vendor': 'EDP'});

    // alice invites bob as a mod
    final code = await alice.inv.create(b, Role.mod, name: 'Bob');
    expect(code.code, matches(RegExp('^[$inviteAlphabet]{4}\$')));
    expect(tags[alice.id.pubkey], {inviteTag(code.code)});
    final res = await bob.inv.join(code.code.toLowerCase(), failAfter: Duration.zero);
    expect(res.building, b);
    expect(res.role, 'mod');
    await wire.settle();
    expect((await bob.q.expenses()).single['vendor'], 'EDP');
    expect(await bob.l.myRole(b), Role.mod);
    expect(tags[alice.id.pubkey], isEmpty); // used: no longer announced

    // single use: no longer announced, and refused if asked anyway
    await expectLater(dave.inv.join(code.code, timeout: const Duration(seconds: 3)),
        throwsA(isA<JoinError>().having((e) => e.reason, 'reason', 'notFound')));
    tags[alice.id.pubkey] = {inviteTag(code.code)};
    await expectLater(dave.inv.join(code.code, failAfter: Duration.zero),
        throwsA(isA<JoinError>().having((e) => e.reason, 'reason', 'used')));
    tags[alice.id.pubkey] = {};

    // a mod cannot make admins or mods, but invites tenants
    await expectLater(bob.inv.create(b, Role.admin), throwsStateError);
    await expectLater(() => bob.l.upsert('members', b, {'pubkey': dave.id.pubkey, 'role': 'admin'},
        id: '$b:${dave.id.pubkey}'), throwsStateError);
    final forAna = await bob.inv.create(b, Role.user, tenantId: ana, name: 'Ana');
    await carol.inv.join(forAna.code, failAfter: Duration.zero);
    await wire.settle();

    // carol (Ana) sees her lease, room, payments and the managers; nothing else
    expect((await carol.q.buildings()).single['name'], 'Rua A');
    expect((await carol.q.tenants(b)).map((t) => t['name']), ['Ana']);
    expect((await carol.q.leases(building: b)).single['id'], la);
    expect((await carol.q.rooms(b)).single['id'], r1);
    expect((await carol.q.apartments(b)).single['id'], apt);
    expect((await carol.q.payments(building: b)).single['lease_id'], la);
    expect(await carol.q.expenses(), isEmpty);
    expect((await carol.q.members(b)).map((m) => m['role']).toSet(), {'owner', 'mod', 'user'});
    expect(await carol.l.myRole(b), Role.user);
    // and changes nothing
    await expectLater(() => carol.l.upsert('payments', b, {'lease_id': la, 'amount_cents': 1}), throwsStateError);

    // live pushes are filtered too, and leave her no gaps to re-ask
    await bob.l.upsert('payments', b, {'lease_id': la, 'amount_cents': 30000, 'paid_on': '2026-02-08'});
    await bob.l.upsert('expenses', b, {'amount_cents': 999, 'vendor': 'Água'});
    await bob.l.upsert('tenants', b, {'phone': '933'}, id: rui);
    await wire.settle();
    expect((await carol.q.payments(building: b)).length, 2);
    expect(await carol.q.expenses(), isEmpty);
    final before = alice.e.stats.eventsOut + bob.e.stats.eventsOut;
    await carol.e.syncWith(alice.id.pubkey);
    await carol.e.syncWith(bob.id.pubkey);
    await wire.settle();
    expect(alice.e.stats.eventsOut + bob.e.stats.eventsOut, before);

    // a new lease for Ana in another room: that room's history arrives
    await alice.l.upsert('leases', b, {'room_id': r2, 'tenant_id': ana, 'rent_cents': 1, 'start_date': '2027-01-01'});
    await wire.settle();
    expect((await carol.q.rooms(b)).map((r) => r['id']).toSet(), {r1, r2});
    expect((await carol.q.tenants(b)).map((t) => t['name']), ['Ana']);

    // expired codes are refused
    final late = await alice.inv.create(b, Role.admin);
    alice.inv.now = () => DateTime.now().add(const Duration(hours: 25));
    await expectLater(dave.inv.join(late.code, failAfter: Duration.zero),
        throwsA(isA<JoinError>().having((e) => e.reason, 'reason', 'expired')));
    alice.inv.now = DateTime.now;

    // an admin manages members; a mod revokes tenants but not admins
    final adm = await alice.inv.create(b, Role.admin);
    await dave.inv.join(adm.code, failAfter: Duration.zero);
    await wire.settle();
    expect(await dave.l.myRole(b), Role.admin);
    await expectLater(() => bob.l.delete('members', b, '$b:${dave.id.pubkey}'), throwsStateError);
    await expectLater(() => dave.l.delete('members', b, '$b:${alice.id.pubkey}'), throwsStateError);
    await bob.l.delete('members', b, '$b:${carol.id.pubkey}');
    await dave.l.upsert('members', b, {'role': 'user'}, id: '$b:${bob.id.pubkey}');
    await wire.settle();
    // bob's earlier changes (as a mod) stay valid everywhere
    for (final p in [alice, dave]) {
      expect((await p.q.expenses()).length, 2);
      expect((await p.q.members(b)).firstWhere((m) => m['pubkey'] == bob.id.pubkey)['role'], 'user');
    }
    await expectLater(() => bob.l.upsert('expenses', b, {'amount_cents': 1}), throwsStateError);

    for (final p in [alice, bob, carol, dave]) {
      await p.s.close();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
