// Read side: the queries screens and domain code share.

import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'zx_store.dart';

class Queries {
  final ZxStore s;
  Queries(this.s);

  static const _live = 'deleted = 0';

  Future<List<DbRow>> buildings() =>
      s.query('SELECT * FROM buildings WHERE $_live ORDER BY name');

  Future<DbRow?> byId(String table, String id) =>
      s.first('SELECT * FROM $table WHERE id = ?', [id]);

  Future<List<DbRow>> apartments(String building) => s.query(
      'SELECT * FROM apartments WHERE building_id = ? AND $_live ORDER BY name',
      [building]);

  Future<List<DbRow>> rooms(String building, {String? apartment}) => apartment == null
      ? s.query('SELECT * FROM rooms WHERE building_id = ? AND $_live ORDER BY name',
          [building])
      : s.query(
          'SELECT * FROM rooms WHERE building_id = ? AND apartment_id = ? AND $_live ORDER BY name',
          [building, apartment]);

  Future<List<DbRow>> allRooms() =>
      s.query('SELECT * FROM rooms WHERE $_live ORDER BY name');

  Future<List<DbRow>> tenants(String building) => s.query(
      'SELECT * FROM tenants WHERE building_id = ? AND $_live ORDER BY name',
      [building]);

  Future<List<DbRow>> allTenants() =>
      s.query('SELECT * FROM tenants WHERE $_live ORDER BY name');

  Future<List<DbRow>> leases({String? building, String? room}) {
    if (room != null) {
      return s.query(
          'SELECT * FROM leases WHERE room_id = ? AND $_live ORDER BY start_date DESC',
          [room]);
    }
    if (building != null) {
      return s.query(
          'SELECT * FROM leases WHERE building_id = ? AND $_live ORDER BY start_date DESC',
          [building]);
    }
    return s.query('SELECT * FROM leases WHERE $_live ORDER BY start_date DESC');
  }

  Future<List<DbRow>> payments({String? lease, String? building}) {
    if (lease != null) {
      return s.query(
          'SELECT * FROM payments WHERE lease_id = ? AND $_live ORDER BY paid_on DESC',
          [lease]);
    }
    if (building != null) {
      return s.query(
          'SELECT * FROM payments WHERE building_id = ? AND $_live ORDER BY paid_on DESC',
          [building]);
    }
    return s.query('SELECT * FROM payments WHERE $_live ORDER BY paid_on DESC');
  }

  Future<List<DbRow>> categories() => s.query(
      'SELECT * FROM categories WHERE $_live ORDER BY key IS NULL, key, name');

  Future<List<DbRow>> expenses({String? building, String? from, String? to}) {
    final where = [_live];
    final args = <Object?>[];
    if (building != null) {
      where.add('building_id = ?');
      args.add(building);
    }
    if (from != null) {
      where.add('date >= ?');
      args.add(from);
    }
    if (to != null) {
      where.add('date <= ?');
      args.add(to);
    }
    return s.query(
        'SELECT * FROM expenses WHERE ${where.join(' AND ')} ORDER BY date DESC',
        args);
  }

  Future<List<DbRow>> recurringBills({String? building}) => building == null
      ? s.query('SELECT * FROM recurring_bills WHERE $_live ORDER BY vendor')
      : s.query(
          'SELECT * FROM recurring_bills WHERE building_id = ? AND $_live ORDER BY vendor',
          [building]);

  Future<List<DbRow>> members(String building) => s.query(
      'SELECT * FROM members WHERE building_id = ? AND $_live ORDER BY role DESC, name',
      [building]);

  /// Hex pubkeys of every live member of every building (sync targets).
  Future<Set<String>> allMemberPubkeys() async =>
      (await s.query('SELECT DISTINCT pubkey FROM members WHERE $_live'))
          .map((r) => r['pubkey'] as String)
          .toSet();

  /// Buildings where [pubkey] is staff (owner, admin or mod).
  Future<int> staffBuildings(String pubkey) async => await s.scalar(
      "SELECT count(*) FROM buildings b WHERE b.deleted = 0 AND (b.owner = ? OR EXISTS ("
      "SELECT 1 FROM members m WHERE m.id = b.id || ':' || ? AND m.deleted = 0 "
      "AND (m.role IS NULL OR m.role NOT IN ('user', 'worker'))))",
      [pubkey, pubkey]) as int;

  /// True when [me] holds buildings only as a tenant or a worker.
  Future<bool> onlyTenant(String me) async {
    final total = await s.scalar('SELECT count(*) FROM buildings WHERE $_live') as int;
    if (total == 0) return false;
    return await staffBuildings(me) == 0;
  }

  // ---------------------------------------------------------------- tasks

  Future<List<DbRow>> tasks({String? building, String? assignee}) {
    final where = [_live, if (building != null) 'building_id = ?', if (assignee != null) 'assignee = ?'];
    return s.query('SELECT * FROM tasks WHERE ${where.join(' AND ')} ORDER BY starts_at DESC',
        [?building, ?assignee]);
  }

  // --------------------------------------------------------------- people

  Future<DbRow?> profile(String pubkey) => s.first('SELECT * FROM profiles WHERE id = ?', [pubkey]);

  Future<Map<String, String>> nicknames() async => {
        for (final r in await s.query('SELECT pubkey, nickname FROM nicknames'))
          r['pubkey'] as String: r['nickname'] as String,
      };

  Future<void> setNickname(String pubkey, String? nickname) => nickname == null || nickname.trim().isEmpty
      ? s.exec('DELETE FROM nicknames WHERE pubkey = ?', [pubkey])
      : s.exec('INSERT OR REPLACE INTO nicknames (pubkey, nickname) VALUES (?, ?)', [pubkey, nickname.trim()]);

  /// How to show people: the nickname this device gave them, else the name
  /// they gave themselves, else the name on their member rows; with their
  /// profile photo. Covers everyone in `members`, profiles and [extra].
  Future<Map<String, Person>> people({Iterable<String> extra = const []}) async {
    final out = <String, Person>{};
    for (final r in await s.query('SELECT pubkey, name FROM members WHERE $_live AND name IS NOT NULL')) {
      out[r['pubkey'] as String] = Person(memberName: r['name'] as String?);
    }
    for (final r in await s.query('SELECT id, name, photo FROM profiles WHERE $_live')) {
      final p = out[r['id'] as String] ?? Person();
      out[r['id'] as String] = Person(memberName: p.memberName, profileName: r['name'] as String?, photo: r['photo'] as String?);
    }
    for (final e in (await nicknames()).entries) {
      final p = out[e.key] ?? Person();
      out[e.key] = Person(memberName: p.memberName, profileName: p.profileName, photo: p.photo, nickname: e.value);
    }
    for (final pk in extra) {
      out.putIfAbsent(pk, Person.new);
    }
    return out;
  }

  // ------------------------------------------------------------ attachments

  /// Stores a file (deduplicated by SHA-256) and returns its hash.
  Future<String> putAttachment(Uint8List bytes, String mime) async {
    final sha = sha256.convert(bytes).toString();
    final have = await s.scalar('SELECT 1 FROM attachments WHERE sha256 = ?', [sha]);
    if (have == null) {
      await s.exec(
          'INSERT INTO attachments (sha256, mime, size, bytes, created_at) VALUES (?, ?, ?, ?, ?)',
          [sha, mime, bytes.length, bytes, DateTime.now().millisecondsSinceEpoch]);
    }
    return sha;
  }

  Future<Uint8List?> attachment(String sha) async =>
      await s.scalar('SELECT bytes FROM attachments WHERE sha256 = ?', [sha])
          as Uint8List?;

  Future<bool> hasAttachment(String sha) async =>
      await s.scalar('SELECT 1 FROM attachments WHERE sha256 = ?', [sha]) != null;
}

/// What is known about a person, by precedence: see [Queries.people].
class Person {
  final String? nickname, profileName, memberName, photo;
  const Person({this.nickname, this.profileName, this.memberName, this.photo});

  /// The best name, or null when only the npub is known.
  String? get name => nickname ?? profileName ?? memberName;
}
