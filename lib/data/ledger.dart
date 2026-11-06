// The ledger: every change is a signed NOSTR event (kind 30777), stored in
// `events` and projected into the entity tables with field-level
// last-writer-wins on hybrid logical clocks. Local writes and events
// received from peers go through the same projector, so all devices that
// hold the same events hold the same state.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:reticulum/reticulum.dart' show NostrEvent;

import '../core/hlc.dart';
import '../core/ids.dart';
import '../domain/roles.dart';
import '../identity/identity_service.dart';
import 'schema.dart';
import 'zx_store.dart';

const ledgerEventKind = 30777;

enum EventStatus { applied, pending, rejected, duplicate }

/// A parsed, signature-checked ledger event.
class LedgerEvent {
  final NostrEvent raw;
  final String building;
  final int seq;
  final String hlc;
  final String device; // the author's device ('' for events before devices)
  final String entity;
  final String entityId;
  final String op; // upsert | delete
  final Map<String, Object?> fields;

  LedgerEvent._(this.raw, this.building, this.seq, this.hlc, this.device,
      this.entity, this.entityId, this.op, this.fields);

  /// Key of the (author, device) sequence in sync vectors.
  String get lane => '$author/$device';

  String get id => raw.id!;
  String get author => raw.pubkey;

  static String? _tag(NostrEvent e, String name) {
    for (final t in e.tags) {
      if (t.length >= 2 && t[0] == name) return t[1];
    }
    return null;
  }

  /// Parses [e]; returns null when it is not a well-formed ledger event.
  static LedgerEvent? parse(NostrEvent e) {
    if (e.kind != ledgerEventKind || e.id == null) return null;
    try {
      final c = jsonDecode(e.content) as Map<String, dynamic>;
      final entity = c['entity'] as String;
      if (!entityFields.containsKey(entity)) return null;
      final op = c['op'] as String;
      if (op != 'upsert' && op != 'delete') return null;
      return LedgerEvent._(
        e,
        _tag(e, 'b') ?? globalBuilding,
        int.parse(_tag(e, 'seq') ?? '0'),
        _tag(e, 'hlc') ?? '',
        _tag(e, 'd') ?? '',
        entity,
        c['id'] as String,
        op,
        Map<String, Object?>.from((c['fields'] as Map?) ?? const {}),
      );
    } catch (_) {
      return null;
    }
  }
}

/// The write side of the app, plus the projector used for remote events.
class Ledger extends ChangeNotifier {
  final ZxStore store;
  Identity identity;

  /// This device, so several devices can share one npub: each keeps its own
  /// sequence of events (tag `d`) and its own HLC node id.
  final String device;
  final HlcClock clock;

  /// Bumped after every committed change; screens rebuild on it.
  int revision = 0;

  /// Sign local events (always, except in the browser preview: it never
  /// syncs, and secp256k1 in JavaScript takes seconds per signature).
  bool signLocal = true;

  /// Called with the events created locally (the sync engine pushes them).
  void Function(List<LedgerEvent>)? onLocalEvents;

  Ledger(this.store, this.identity, {String? device})
      : device = device ?? newId().substring(0, 16),
        clock = HlcClock(_nodeId(device ?? identity.pubkey));

  static String _nodeId(String s) => s.length > 8 ? s.substring(0, 8) : s;

  String get me => identity.pubkey;

  Future<void> init() async {
    final last = await store.scalar(
        'SELECT max(hlc) FROM events WHERE author = ?', [me]) as String?;
    if (last != null) clock.observe(last);
    await _seedDefaultCategories();
  }

  // ---------------------------------------------------------------- writes

  /// Creates or updates [entity] [id] with [fields]; returns the id.
  Future<String> upsert(String entity, String building, Map<String, Object?> fields,
      {String? id}) async {
    final eid = id ?? newId();
    await _write([_Change(entity, building, eid, 'upsert', fields)]);
    return eid;
  }

  Future<void> delete(String entity, String building, String id) =>
      _write([_Change(entity, building, id, 'delete', const {'deleted': 1})]);

  /// Several changes in one generation (e.g. a building and its owner member).
  Future<void> batch(List<({String entity, String building, String id, String op, Map<String, Object?> fields})> changes) =>
      _write([for (final c in changes) _Change(c.entity, c.building, c.id, c.op, c.fields)]);

  /// Creates a building owned by this identity.
  Future<String> createBuilding(Map<String, Object?> fields) async {
    final bid = newId();
    await _write([
      _Change('buildings', bid, bid, 'upsert', {...fields, 'owner': me}),
      _Change('members', bid, '$bid:$me', 'upsert',
          {'pubkey': me, 'role': 'owner'}),
    ]);
    return bid;
  }

  Future<void> _write(List<_Change> changes) async {
    final created = <LedgerEvent>[];
    await store.transaction(() async {
      for (final c in changes) {
        final seq = ((await store.scalar(
                    'SELECT max(seq) FROM events WHERE author = ? AND device = ? AND building_id = ?',
                    [me, device, c.building]) as int?) ??
                0) +
            1;
        final hlc = clock.now().toString();
        final e = NostrEvent(
          pubkey: me,
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          kind: ledgerEventKind,
          tags: [
            ['b', c.building],
            ['seq', '$seq'],
            ['hlc', hlc],
            ['d', device],
            ['e', c.entity],
          ],
          content: jsonEncode(
              {'entity': c.entity, 'id': c.id, 'op': c.op, 'fields': c.fields}),
        );
        if (signLocal) {
          identity.sign(e);
        } else {
          e.calculateId();
        }
        final le = LedgerEvent.parse(e)!;
        final st = await _apply(le);
        if (st == EventStatus.rejected) {
          throw StateError('not allowed to change ${c.entity} here');
        }
        created.add(le);
      }
    });
    _changed();
    onLocalEvents?.call(created);
  }

  // ---------------------------------------------------------------- remote

  /// (building, entity) of the events the last [ingest] applied.
  final lastApplied = <(String, String)>{};

  /// Verifies and applies events from a peer (one generation per batch).
  /// Returns how many were new.
  Future<int> ingest(List<NostrEvent> events) async {
    lastApplied.clear();
    final parsed = <LedgerEvent>[];
    for (final e in events) {
      if (e.kind != ledgerEventKind || !e.verify()) continue;
      final le = LedgerEvent.parse(e);
      if (le != null) parsed.add(le);
    }
    if (parsed.isEmpty) return 0;
    parsed.sort((a, b) => a.hlc.compareTo(b.hlc));
    var fresh = 0;
    await store.transaction(() async {
      final touched = <String>{};
      for (final e in parsed) {
        clock.observe(e.hlc);
        final st = await _apply(e);
        if (st != EventStatus.duplicate) fresh++;
        if (st == EventStatus.applied) {
          touched.add(e.building);
          lastApplied.add((e.building, e.entity));
        }
      }
      for (final b in touched) {
        await _retryPending(b);
      }
    });
    if (fresh > 0) _changed();
    return fresh;
  }

  /// Tells screens to reload after a change outside the ledger.
  void touch() => _changed();

  void _changed() {
    revision++;
    notifyListeners();
  }

  // ------------------------------------------------------------- projector

  Future<EventStatus> _apply(LedgerEvent e, {bool retry = false}) async {
    if (!retry) {
      final seen = await store.scalar('SELECT status FROM events WHERE id = ?', [e.id]);
      if (seen != null) return EventStatus.duplicate;
    }
    final verdict = await _authorize(e);
    final status = verdict ?? EventStatus.applied;
    if (retry) {
      await store.db.execute(
          'UPDATE events SET status = ? WHERE id = ?', [status.name, e.id]);
    } else {
      await store.db.execute(
          'INSERT INTO events (id, author, device, building_id, seq, hlc, entity, entity_id, json, status, received_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            e.id, e.author, e.device, e.building, e.seq, e.hlc, e.entity, e.entityId,
            jsonEncode(e.raw.toJson()), status.name,
            DateTime.now().millisecondsSinceEpoch,
          ]);
    }
    if (status == EventStatus.applied) await _project(e);
    return status;
  }

  /// null = allowed; pending = author not (yet) known as a member.
  Future<EventStatus?> _authorize(LedgerEvent e) async {
    if (e.building == globalBuilding) {
      if (e.entity != 'categories') return EventStatus.rejected;
      if (e.author == me) return null;
      // Shared categories come from the people who manage some building.
      final n = await store.scalar(
          "SELECT count(*) FROM members WHERE pubkey = ? AND deleted = 0 AND (role IS NULL OR role != 'user')",
          [e.author]);
      return (n as int) > 0 ? null : EventStatus.pending;
    }
    final b = await store.first(
        'SELECT owner, deleted FROM buildings WHERE id = ?', [e.building]);
    if (b == null) {
      // Only the creation of a building by its owner opens a building.
      final ok = e.entity == 'buildings' &&
          e.entityId == e.building &&
          e.op == 'upsert' &&
          e.fields['owner'] == e.author;
      return ok ? null : EventStatus.pending;
    }
    final owner = b['owner'] as String?;
    if (e.entity == 'buildings' && e.entityId != e.building) {
      return EventStatus.rejected;
    }
    if (e.entity == 'members') {
      final shape = await _memberShape(e, owner);
      if (shape != null) return shape;
    }
    if (e.author == owner) return null;
    final role = await roleAt(e.building, e.author, e.hlc);
    if (role == null) return EventStatus.pending;
    if (role == _revoked) return EventStatus.rejected;
    final r = roleOf(role) ?? Role.mod;
    if (e.entity == 'members') {
      final target = await store.first(
          'SELECT role, deleted FROM members WHERE id = ?', [e.entityId]);
      final targetRole =
          target == null || target['deleted'] == 1 ? null : roleOf(target['role']);
      final to = e.op == 'delete' ? null : roleOf(e.fields['role']);
      if (target == null && to == null) return EventStatus.rejected;
      if (target != null && target['deleted'] == 1 && e.fields['deleted'] == 0 &&
          to == null) {
        return EventStatus.rejected; // re-adding needs an explicit role
      }
      return r.canManage(targetRole, to) ? null : EventStatus.rejected;
    }
    if (e.entity == 'buildings' && e.op == 'delete') {
      return r.canDeleteBuilding ? null : EventStatus.rejected;
    }
    return r.canWrite(e.entity) ? null : EventStatus.rejected;
  }

  static const _revoked = '-';

  /// Checks that a `members` event targets row `building:pubkey` and does
  /// not change its pubkey; rejected otherwise.
  Future<EventStatus?> _memberShape(LedgerEvent e, String? owner) async {
    final pk = e.fields['pubkey'];
    if (pk != null && e.entityId != '${e.building}:$pk') return EventStatus.rejected;
    if (!e.entityId.startsWith('${e.building}:')) return EventStatus.rejected;
    final target = e.entityId.substring(e.building.length + 1);
    if (target == owner && e.author != owner) return EventStatus.rejected;
    if (e.fields['role'] == 'owner' && target != owner) return EventStatus.rejected;
    return null;
  }

  /// The role [pubkey] had in [building] at [hlc]: folds the membership's
  /// applied events up to [hlc], so changes made before a revocation or a
  /// demotion stay valid. Returns null when not a member (yet), or
  /// [_revoked]. The owner's role is 'owner'.
  Future<String?> roleAt(String building, String pubkey, String hlc) async {
    final rows = await store.query(
        "SELECT hlc, json FROM events WHERE entity = 'members' AND entity_id = ? AND status = 'applied' ORDER BY hlc",
        ['$building:$pubkey']);
    if (rows.isEmpty) return null;
    String? role;
    var deleted = false;
    var any = false;
    for (final r in rows) {
      if ((r['hlc'] as String).compareTo(hlc) > 0) break;
      any = true;
      final c = jsonDecode((jsonDecode(r['json'] as String) as Map)['content'] as String) as Map;
      final f = (c['fields'] as Map?) ?? const {};
      if (c['op'] == 'delete') {
        deleted = true;
      } else {
        if (f.containsKey('role')) role = f['role'] as String?;
        if (f.containsKey('deleted')) deleted = f['deleted'] == 1 || f['deleted'] == true;
      }
    }
    if (!any) {
      // Written before its author was added (a skewed clock): judge by the
      // membership as it is now.
      final m = await store.first(
          'SELECT role, deleted FROM members WHERE id = ?', ['$building:$pubkey']);
      if (m == null) return null;
      return m['deleted'] == 1 ? _revoked : (m['role'] as String? ?? 'mod');
    }
    return deleted ? _revoked : (role ?? 'mod');
  }

  /// The role this identity has now in [building] (null: none).
  Future<Role?> myRole(String building) async {
    final b = await store.first('SELECT owner FROM buildings WHERE id = ?', [building]);
    if (b != null && b['owner'] == me) return Role.owner;
    final m = await store.first(
        'SELECT role, deleted FROM members WHERE id = ?', ['$building:$me']);
    if (m == null || m['deleted'] == 1) return null;
    return roleOf(m['role']) ?? Role.mod;
  }

  Future<void> _retryPending(String building) async {
    for (var round = 0; round < 8; round++) {
      final rows = await store.query(
          "SELECT json FROM events WHERE status = 'pending' AND (building_id = ? OR building_id = ?) ORDER BY hlc",
          [building, globalBuilding]);
      var progress = false;
      for (final r in rows) {
        final le = LedgerEvent.parse(
            NostrEvent.fromJson(jsonDecode(r['json'] as String) as Map<String, dynamic>));
        if (le == null) continue;
        if (await _apply(le, retry: true) == EventStatus.applied) progress = true;
      }
      if (!progress) return;
    }
  }

  Future<void> _project(LedgerEvent e) async {
    final table = e.entity;
    final allowed = {...entityFields[table]!.keys, 'deleted'};
    final row = await store.first('SELECT * FROM $table WHERE id = ?', [e.entityId]);
    final fieldHlc = row == null
        ? <String, dynamic>{}
        : (jsonDecode((row['field_hlc'] as String?) ?? '{}') as Map<String, dynamic>);
    final sets = <String, Object?>{};
    final fields = e.op == 'delete' ? const {'deleted': 1} : e.fields;
    for (final f in fields.entries) {
      if (!allowed.contains(f.key)) continue;
      if (f.key == 'owner' && row != null) continue; // immutable
      final prev = fieldHlc[f.key] as String? ?? '';
      if (e.hlc.compareTo(prev) > 0) {
        sets[f.key] = _sqlValue(f.value);
        fieldHlc[f.key] = e.hlc;
      }
    }
    final newest = row == null ||
        e.hlc.compareTo(row['updated_hlc'] as String? ?? '') > 0;
    if (row == null) {
      final cols = {
        'id': e.entityId,
        'building_id': e.building,
        'deleted': 0,
        'updated_hlc': e.hlc,
        'updated_by': e.author,
        'field_hlc': jsonEncode(fieldHlc),
        ...sets,
      };
      await store.db.execute(
          'INSERT INTO $table (${cols.keys.join(', ')}) VALUES (${List.filled(cols.length, '?').join(', ')})',
          cols.values.toList());
    } else {
      if (sets.isEmpty && !newest) return;
      final cols = {
        ...sets,
        'field_hlc': jsonEncode(fieldHlc),
        if (newest) 'updated_hlc': e.hlc,
        if (newest) 'updated_by': e.author,
      };
      await store.db.execute(
          'UPDATE $table SET ${cols.keys.map((k) => '$k = ?').join(', ')} WHERE id = ?',
          [...cols.values, e.entityId]);
    }
  }

  static Object? _sqlValue(Object? v) {
    if (v is bool) return v ? 1 : 0;
    if (v is List || v is Map) return jsonEncode(v);
    return v;
  }

  // ------------------------------------------------------------- defaults

  Future<void> _seedDefaultCategories() async {
    final have = (await store.query(
            "SELECT key FROM categories WHERE building_id = '' AND key IS NOT NULL"))
        .map((r) => r['key'])
        .toSet();
    final missing = defaultCategories.where((c) => !have.contains(c.key)).toList();
    if (missing.isEmpty) return;
    await store.transaction(() async {
      for (final c in missing) {
        // Same id on every device, no event: renames by users are events.
        await store.db.execute(
            'INSERT INTO categories (id, building_id, deleted, updated_hlc, updated_by, field_hlc, key, icon, color, unit) '
            "VALUES (?, '', 0, '', '', '{}', ?, ?, ?, ?)",
            ['cat_${c.key}', c.key, c.icon, c.color, c.unit]);
      }
    });
  }
}

class _Change {
  final String entity, building, id, op;
  final Map<String, Object?> fields;
  _Change(this.entity, this.building, this.id, this.op, this.fields);
}

class DefaultCategory {
  final String key, icon;
  final int color;
  final String? unit;
  const DefaultCategory(this.key, this.icon, this.color, [this.unit]);
}

/// Default categories (names come from the translations, key `cat_<key>`).
const defaultCategories = [
  DefaultCategory('water', 'water_drop', 0xFF2196F3, 'm³'),
  DefaultCategory('energy', 'bolt', 0xFFFFB300, 'kWh'),
  DefaultCategory('gas', 'local_fire_department', 0xFFFF7043, 'm³'),
  DefaultCategory('internet', 'wifi', 0xFF7E57C2),
  DefaultCategory('condo', 'apartment', 0xFF8D6E63),
  DefaultCategory('material', 'construction', 0xFF78909C),
  DefaultCategory('repairs', 'handyman', 0xFF546E7A),
  DefaultCategory('cleaning', 'cleaning_services', 0xFF26A69A),
  DefaultCategory('food', 'restaurant', 0xFF66BB6A),
  DefaultCategory('furniture', 'chair', 0xFFA1887F),
  DefaultCategory('insurance', 'shield', 0xFF5C6BC0),
  DefaultCategory('taxes', 'account_balance', 0xFFEF5350),
  DefaultCategory('other', 'category', 0xFF9E9E9E),
];
