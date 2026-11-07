// The sync protocol, independent of the transport (Reticulum in the app,
// an in-memory wire in tests). Peers are NOSTR pubkeys; messages are JSON.
//
//   hello  {t, first, v: {building: {author: contiguousSeq}}}
//          sent on discovery and periodically; the receiver answers with the
//          events the sender lacks (only for buildings the sender is a member
//          of) and, when `first`, with its own hello.
//   events {t, e: [nostr event json...]}   batches of signed ledger events
//   need   {t, sha: [...]}                  receipts / ID documents we lack
//   blob   {t, sha, mime, data(base64)}     one receipt
//   skip   {t, b, r: [[lane, from, to]...]} sequences a tenant may not see
//   join / join-ok / join-fail              invite codes (sync/invites.dart)
//
// A tenant (role user) only receives the building, their own tenant row,
// leases, payments, rooms and apartments, and the managers' memberships;
// a worker only the building, the tasks given to them and the managers'
// memberships; both get the profiles of those people and nothing else of
// the global scope. `skip` tells them which sequences were left out so
// their vectors have no gaps.
//
// Events are self-authenticating (signed); the projector decides what to
// accept. This layer only decides who may *receive* a building's data.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:reticulum/reticulum.dart' show NostrEvent;

import '../data/ledger.dart';
import '../data/queries.dart';
import '../data/schema.dart';
import '../data/zx_store.dart';
import '../domain/roles.dart';

/// Sends one message to a peer; resolves false when it could not be delivered.
typedef SendToPeer = Future<bool> Function(String pubkey, Map<String, Object?> msg);

class SyncStats {
  int sent = 0, received = 0, eventsIn = 0, eventsOut = 0, blobsIn = 0;
  DateTime? lastSync;
}

class SyncEngine {
  final Ledger ledger;
  final ZxStore store;
  final Queries q;
  SendToPeer send;
  final stats = SyncStats();
  final void Function(String)? log;

  /// Called before applying a batch from [from] that deletes something.
  Future<void> Function(String from)? onRemoteDeletes;

  /// Handles the invite messages (`join`, `join-ok`, `join-fail`).
  Future<void> Function(String from, Map<String, Object?> msg)? onInvite;

  /// Max bytes of event JSON per message.
  static const batchBytes = 48 * 1024;

  SyncEngine(this.ledger, this.store, {required this.send, this.log}) : q = Queries(store) {
    ledger.onLocalEvents = _pushLocal;
  }

  String get me => ledger.me;

  // ---------------------------------------------------------------- access

  /// Buildings [peer] may receive: it is a live member, or the owner.
  Future<Set<String>> buildingsSharedWith(String peer) async {
    final rows = await store.query(
        'SELECT m.building_id FROM members m JOIN buildings b ON b.id = m.building_id '
        'WHERE m.pubkey = ? AND m.deleted = 0 AND b.deleted = 0',
        [peer]);
    final owned = await store.query(
        'SELECT id FROM buildings WHERE owner = ? AND deleted = 0', [peer]);
    return {
      for (final r in rows) r['building_id'] as String,
      for (final r in owned) r['id'] as String,
    };
  }

  /// Everyone we share at least one building with (sync partners),
  /// ourselves included: our other devices sync the same way.
  Future<Set<String>> partners() async {
    final all = await q.allMemberPubkeys();
    final owners = (await store.query('SELECT DISTINCT owner FROM buildings WHERE deleted = 0'))
        .map((r) => r['owner'] as String?)
        .whereType<String>();
    return {...all, ...owners, me};
  }

  /// What [peer] may receive of [building]: null = everything (managers,
  /// the owner, our own devices); otherwise a tenant's or a worker's rows.
  Future<PartialScope?> scopeFor(String peer, String building) async {
    if (peer == me) return null;
    if (building == globalBuilding) return _globalScopeFor(peer);
    final role = await _roleOfPeer(peer, building);
    if (role == null || !role.isPartial) return null;
    final ids = <String>{'buildings/$building'};
    Future<List<String>> idsOf(String sql, List<Object?> args) async =>
        [for (final r in await store.query(sql, args)) r['id'] as String];
    String inList(int n) => List.filled(n, '?').join(', ');
    for (final id in await _visibleMembers(peer, building)) {
      ids.add('members/$id');
    }
    if (role == Role.worker) {
      for (final id in await idsOf(
          'SELECT id FROM tasks WHERE building_id = ? AND assignee = ?', [building, peer])) {
        ids.add('tasks/$id');
      }
      return PartialScope(ids);
    }
    final m = await store.first('SELECT tenant_id FROM members WHERE id = ?', ['$building:$peer']);
    final tid = m?['tenant_id'] as String?;
    if (tid != null) {
      ids.add('tenants/$tid');
      final leases = await store.query(
          'SELECT id, room_id FROM leases WHERE building_id = ? AND tenant_id = ?', [building, tid]);
      final leaseIds = [for (final r in leases) r['id'] as String];
      final roomIds = {for (final r in leases) ?r['room_id'] as String?}.toList();
      ids.addAll(leaseIds.map((i) => 'leases/$i'));
      ids.addAll(roomIds.map((i) => 'rooms/$i'));
      if (leaseIds.isNotEmpty) {
        ids.addAll((await idsOf(
                'SELECT id FROM payments WHERE lease_id IN (${inList(leaseIds.length)})', leaseIds))
            .map((i) => 'payments/$i'));
      }
      if (roomIds.isNotEmpty) {
        final apts = await store.query(
            'SELECT apartment_id FROM rooms WHERE id IN (${inList(roomIds.length)})', roomIds);
        for (final a in apts) {
          if (a['apartment_id'] != null) ids.add('apartments/${a['apartment_id']}');
        }
      }
    }
    return PartialScope(ids);
  }

  /// [peer]'s role in [building] as the members table has it now (the
  /// owner: owner; null: not a member).
  Future<Role?> _roleOfPeer(String peer, String building) async {
    final b = await store.first('SELECT owner FROM buildings WHERE id = ?', [building]);
    if (b?['owner'] == peer) return Role.owner;
    final m = await store.first(
        'SELECT role, deleted FROM members WHERE id = ?', ['$building:$peer']);
    if (m == null || m['deleted'] == 1) return null;
    return roleOf(m['role']) ?? Role.mod;
  }

  /// Member row ids a tenant or worker may see: the managers' and their own.
  Future<List<String>> _visibleMembers(String peer, String building) async => [
        for (final r in await store.query(
            "SELECT id FROM members WHERE building_id = ? AND (id = ? OR role IS NULL OR role NOT IN ('user', 'worker'))",
            [building, '$building:$peer']))
          r['id'] as String
      ];

  /// Global rows for [peer]: everything when they manage some building we
  /// share; otherwise only the profiles of the people they may see (no
  /// categories: those name what the managers spend on).
  Future<PartialScope?> _globalScopeFor(String peer) async {
    final ids = <String>{'profiles/$peer'};
    for (final b in await buildingsSharedWith(peer)) {
      final role = await _roleOfPeer(peer, b);
      if (role == null || !role.isPartial) return null;
      for (final id in await _visibleMembers(peer, b)) {
        ids.add('profiles/${id.substring(b.length + 1)}');
      }
    }
    return PartialScope(ids);
  }

  /// Whether this device takes `skip` ranges for [building]: only a tenant
  /// or worker there (for the global scope: one who manages nothing).
  Future<bool> _acceptsSkips(String building) async {
    if (building == globalBuilding) return await q.staffBuildings(me) == 0;
    return (await ledger.myRole(building))?.isPartial ?? false;
  }

  // ---------------------------------------------------------------- vectors

  /// author/device -> highest seq such that every seq 1..n is held (or,
  /// on a tenant's device, was declared hidden by a manager).
  Future<Map<String, int>> vector(String building) async {
    final rows = await store.query(
        'SELECT author, device, seq FROM events WHERE building_id = ?', [building]);
    final held = <String, Set<int>>{};
    for (final r in rows) {
      held.putIfAbsent('${r['author']}/${r['device'] ?? ''}', () => {}).add(r['seq'] as int);
    }
    final ranges = <String, List<(int, int)>>{};
    for (final r in await store.query(
        'SELECT lane, from_seq, to_seq FROM hidden_ranges WHERE building_id = ?', [building])) {
      ranges.putIfAbsent(r['lane'] as String, () => []).add((r['from_seq'] as int, r['to_seq'] as int));
    }
    final out = <String, int>{};
    for (final lane in {...held.keys, ...ranges.keys}) {
      final h = held[lane] ?? const <int>{};
      final rs = ranges[lane] ?? const <(int, int)>[];
      var n = 0;
      while (true) {
        if (h.contains(n + 1)) {
          n++;
          continue;
        }
        var to = n;
        for (final (a, b) in rs) {
          if (a <= n + 1 && b > to) to = b;
        }
        if (to == n) break;
        n = to;
      }
      if (n > 0) out[lane] = n;
    }
    return out;
  }

  Future<Map<String, Object?>> _hello(String peer, {required bool first}) async {
    final shared = await buildingsSharedWith(peer);
    // Buildings where peer owns or shares with us, plus the global scope.
    return {
      't': 'hello',
      'first': first,
      'v': {
        for (final b in {...shared, globalBuilding}) b: await vector(b),
      },
    };
  }

  /// Starts a sync round with [peer] (our own npub: our other devices).
  Future<void> syncWith(String peer) async {
    await _send(peer, await _hello(peer, first: true));
  }

  // ---------------------------------------------------------------- inbound

  Future<void> onMessage(String from, Map<String, Object?> msg) async {
    stats.received++;
    try {
      switch (msg['t']) {
        case 'hello':
          await _onHello(from, msg);
        case 'events':
          await _onEvents(from, msg);
        case 'need':
          await _onNeed(from, msg);
        case 'blob':
          await _onBlob(msg);
        case 'skip':
          await _onSkip(from, msg);
        case 'join' || 'join-ok' || 'join-fail':
          await onInvite?.call(from, msg);
      }
    } catch (e) {
      log?.call('sync: bad ${msg['t']} from ${from.substring(0, 8)}: $e');
    }
  }

  Future<void> _onHello(String from, Map<String, Object?> msg) async {
    final v = (msg['v'] as Map?)?.cast<String, Object?>() ?? const {};
    final shared = await buildingsSharedWith(from);
    if (shared.isEmpty) {
      // Not a partner of ours (yet); still answer so an owner can reach us.
      if (msg['first'] == true) await _send(from, await _hello(from, first: false));
      return;
    }
    for (final e in v.entries) {
      final b = e.key;
      if (b != globalBuilding && !shared.contains(b)) continue;
      final theirs = (e.value as Map?)?.cast<String, Object?>() ?? const {};
      await _sendMissing(from, b, theirs.map((k, v) => MapEntry(k, (v as num).toInt())));
    }
    // A new member does not know the building yet: send it unasked.
    for (final b in shared) {
      if (!v.containsKey(b)) await _sendMissing(from, b, const {});
    }
    if (msg['first'] == true) await _send(from, await _hello(from, first: false));
    stats.lastSync = DateTime.now();
  }

  Future<void> _sendMissing(String to, String building, Map<String, int> theirs) async {
    final scope = await scopeFor(to, building);
    final rows = await store.query(
        "SELECT author, device, seq, entity, entity_id, status, json FROM events WHERE building_id = ? "
        "AND status ${scope == null ? "= 'applied'" : "!= 'pending'"} ORDER BY hlc",
        [building]);
    final out = <String>[];
    final hidden = <String, List<int>>{};
    for (final r in rows) {
      final lane = '${r['author']}/${r['device'] ?? ''}';
      final seq = r['seq'] as int;
      if (seq <= (theirs[lane] ?? 0)) continue;
      if (scope == null ||
          (r['status'] == 'applied' &&
              scope.visible(r['entity'] as String, r['entity_id'] as String))) {
        out.add(r['json'] as String);
      } else {
        hidden.putIfAbsent(lane, () => []).add(seq);
      }
    }
    await _sendEvents(to, out);
    await _sendSkip(to, building, hidden);
  }

  /// Tells a tenant which sequences of [building] were left out.
  Future<void> _sendSkip(String to, String building, Map<String, List<int>> hidden) async {
    if (hidden.isEmpty) return;
    final r = <List<Object>>[];
    for (final e in hidden.entries) {
      final seqs = e.value..sort();
      var from = seqs.first, prev = seqs.first;
      for (final s in seqs.skip(1)) {
        if (s == prev + 1) {
          prev = s;
          continue;
        }
        r.add([e.key, from, prev]);
        from = prev = s;
      }
      r.add([e.key, from, prev]);
    }
    await _send(to, {'t': 'skip', 'b': building, 'r': r});
  }

  Future<void> _onSkip(String from, Map<String, Object?> msg) async {
    final b = msg['b'] as String;
    // Only a tenant or worker accepts gaps, and only from someone sharing
    // the building (for the global scope: any building).
    if (!await _acceptsSkips(b)) return;
    final shared = await buildingsSharedWith(from);
    if (b == globalBuilding ? shared.isEmpty : !shared.contains(b)) return;
    final ranges = (msg['r'] as List?) ?? const [];
    if (ranges.isEmpty) return;
    await store.transaction(() async {
      for (final x in ranges) {
        final l = x as List;
        final args = [b, l[0] as String, (l[1] as num).toInt(), (l[2] as num).toInt()];
        final have = await store.scalar(
            'SELECT 1 FROM hidden_ranges WHERE building_id = ? AND lane = ? AND from_seq = ? AND to_seq = ?', args);
        if (have == null) {
          await store.db.execute(
              'INSERT INTO hidden_ranges (building_id, lane, from_seq, to_seq) VALUES (?, ?, ?, ?)', args);
        }
      }
    });
  }

  Future<void> _sendEvents(String to, List<String> jsons) async {
    var batch = <Object?>[];
    var size = 0;
    for (final j in jsons) {
      if (size + j.length > batchBytes && batch.isNotEmpty) {
        await _send(to, {'t': 'events', 'e': batch});
        stats.eventsOut += batch.length;
        batch = [];
        size = 0;
      }
      batch.add(jsonDecode(j));
      size += j.length;
    }
    if (batch.isNotEmpty) {
      await _send(to, {'t': 'events', 'e': batch});
      stats.eventsOut += batch.length;
    }
  }

  Future<void> _onEvents(String from, Map<String, Object?> msg) async {
    final list = (msg['e'] as List?) ?? const [];
    final events = [
      for (final e in list) NostrEvent.fromJson((e as Map).cast<String, dynamic>()),
    ];
    // Deletes from someone else: mark the state just before them.
    if (onRemoteDeletes != null &&
        events.any((e) => e.content.contains('"op":"delete"'))) {
      await onRemoteDeletes!(from);
    }
    final n = await ledger.ingest(events);
    stats.eventsIn += n;
    stats.lastSync = DateTime.now();
    if (n > 0) await _requestMissingBlobs(from);
    // A tenant whose lease or membership changed may now see rows it was
    // told to skip (and the profiles of new managers): forget the gaps and
    // ask again.
    final widened = {
      for (final (b, entity) in ledger.lastApplied)
        if (entity == 'leases' || entity == 'members') b,
    };
    var again = false;
    for (final b in widened) {
      if (!await _acceptsSkips(b)) continue;
      await store.exec('DELETE FROM hidden_ranges WHERE building_id = ? OR building_id = ?', [b, globalBuilding]);
      again = true;
    }
    if (again) await syncWith(from);
  }

  Future<void> _requestMissingBlobs(String from) async {
    final need = <String>{};
    for (final e in blobFields.entries) {
      for (final col in e.value) {
        final rows = await store.query(
            "SELECT $col AS a FROM ${e.key} WHERE deleted = 0 AND $col IS NOT NULL AND $col != '' AND $col != '[]'");
        for (final r in rows) {
          for (final sha in attachmentHashes(r['a'])) {
            if (!await q.hasAttachment(sha)) need.add(sha);
          }
        }
      }
    }
    if (need.isNotEmpty) await _send(from, {'t': 'need', 'sha': need.toList()});
  }

  Future<void> _onNeed(String from, Map<String, Object?> msg) async {
    if ((await buildingsSharedWith(from)).isEmpty) return;
    for (final sha in ((msg['sha'] as List?) ?? const []).cast<String>()) {
      final row = await store.first('SELECT mime, bytes FROM attachments WHERE sha256 = ?', [sha]);
      if (row == null) continue;
      await _send(from, {
        't': 'blob',
        'sha': sha,
        'mime': row['mime'],
        'data': base64.encode(row['bytes'] as Uint8List),
      });
    }
  }

  Future<void> _onBlob(Map<String, Object?> msg) async {
    final bytes = base64.decode(msg['data'] as String);
    if (sha256.convert(bytes).toString() != msg['sha']) return;
    await q.putAttachment(bytes, (msg['mime'] as String?) ?? 'application/octet-stream');
    stats.blobsIn++;
    ledger.touch();
  }

  // ---------------------------------------------------------------- outbound

  void _pushLocal(List<LedgerEvent> events) {
    unawaited(() async {
      final byBuilding = <String, List<LedgerEvent>>{};
      for (final e in events) {
        byBuilding.putIfAbsent(e.building, () => []).add(e);
      }
      for (final peer in await partners()) {
        // A member added just now also needs the history it lacks.
        if (events.any((e) => e.entity == 'members' && e.fields['pubkey'] == peer)) {
          await syncWith(peer);
          continue;
        }
        final shared = await buildingsSharedWith(peer);
        final out = <String>[];
        for (final b in byBuilding.entries) {
          if (b.key != globalBuilding && !shared.contains(b.key)) continue;
          final scope = await scopeFor(peer, b.key);
          final hidden = <String, List<int>>{};
          for (final e in b.value) {
            if (scope == null || scope.visible(e.entity, e.entityId)) {
              out.add(jsonEncode(e.raw.toJson()));
            } else {
              hidden.putIfAbsent(e.lane, () => []).add(e.seq);
            }
          }
          await _sendSkip(peer, b.key, hidden);
        }
        if (out.isNotEmpty) await _sendEvents(peer, out);
      }
    }());
  }

  /// Sends one message to [to] (used by the invites).
  Future<bool> post(String to, Map<String, Object?> msg) => _send(to, msg);

  Future<bool> _send(String to, Map<String, Object?> msg) async {
    stats.sent++;
    try {
      return await send(to, msg);
    } catch (e) {
      log?.call('sync: send to ${to.substring(0, 8)} failed: $e');
      return false;
    }
  }
}

/// The rows a tenant or a worker may receive, as "entity/id".
class PartialScope {
  final Set<String> ids;
  PartialScope(this.ids);
  bool visible(String entity, String id) => ids.contains('$entity/$id');
}

/// The hashes in an attachment column: a JSON list, or one sha256.
List<String> attachmentHashes(Object? v) {
  if (v is! String || v.isEmpty) return const [];
  if (v.startsWith('[')) return (jsonDecode(v) as List).cast<String>();
  return [v];
}
