// The sync protocol, independent of the transport (Reticulum in the app,
// an in-memory wire in tests). Peers are NOSTR pubkeys; messages are JSON.
//
//   hello  {t, first, v: {building: {author: contiguousSeq}}}
//          sent on discovery and periodically; the receiver answers with the
//          events the sender lacks (only for buildings the sender is a member
//          of) and, when `first`, with its own hello.
//   events {t, e: [nostr event json...]}   batches of signed ledger events
//   need   {t, sha: [...]}                  receipts we reference but lack
//   blob   {t, sha, mime, data(base64)}     one receipt
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

  /// Everyone we share at least one building with (sync partners).
  Future<Set<String>> partners() async {
    final all = await q.allMemberPubkeys();
    final owners = (await store.query('SELECT DISTINCT owner FROM buildings WHERE deleted = 0'))
        .map((r) => r['owner'] as String?)
        .whereType<String>();
    return {...all, ...owners}..remove(me);
  }

  // ---------------------------------------------------------------- vectors

  /// author -> highest seq such that every seq 1..n is held.
  Future<Map<String, int>> vector(String building) async {
    final rows = await store.query(
        'SELECT author, seq FROM events WHERE building_id = ? ORDER BY author, seq',
        [building]);
    final out = <String, int>{};
    for (final r in rows) {
      final a = r['author'] as String;
      final s = r['seq'] as int;
      final have = out[a] ?? 0;
      if (s == have + 1) out[a] = s;
      out.putIfAbsent(a, () => 0);
    }
    out.removeWhere((_, v) => v == 0);
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

  /// Starts a sync round with [peer].
  Future<void> syncWith(String peer) async {
    if (peer == me) return;
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
    final rows = await store.query(
        "SELECT author, seq, json FROM events WHERE building_id = ? AND status = 'applied' ORDER BY hlc",
        [building]);
    final out = <String>[];
    for (final r in rows) {
      if ((r['seq'] as int) > (theirs[r['author']] ?? 0)) out.add(r['json'] as String);
    }
    await _sendEvents(to, out);
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
  }

  Future<void> _requestMissingBlobs(String from) async {
    final rows = await store.query(
        "SELECT attachments FROM expenses WHERE deleted = 0 AND attachments IS NOT NULL AND attachments != '[]'");
    final need = <String>{};
    for (final r in rows) {
      for (final sha in (jsonDecode(r['attachments'] as String) as List).cast<String>()) {
        if (!await q.hasAttachment(sha)) need.add(sha);
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
      final byBuilding = <String, List<String>>{};
      for (final e in events) {
        byBuilding.putIfAbsent(e.building, () => []).add(jsonEncode(e.raw.toJson()));
      }
      for (final peer in await partners()) {
        final shared = await buildingsSharedWith(peer);
        final out = [
          for (final b in byBuilding.entries)
            if (b.key == globalBuilding || shared.contains(b.key)) ...b.value,
        ];
        // A member added just now also needs the history it lacks.
        if (events.any((e) => e.entity == 'members' && e.fields['pubkey'] == peer)) {
          await syncWith(peer);
          continue;
        }
        if (out.isNotEmpty) await _sendEvents(peer, out);
      }
    }());
  }

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
