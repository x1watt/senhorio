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
