// Checkpoints: named points in the archive's history. Because ZX keeps
// every generation, the state at a checkpoint can always be compared with
// now: what was added, changed, deleted (soft) or removed from the table
// (which only tampering with the file could do), and by whom.

import 'dart:convert';

import '../core/ids.dart';
import '../data/ledger.dart';
import '../data/schema.dart';
import '../data/zx_store.dart';

enum ChangeKind { added, changed, deleted, vanished }

class ChangeEntry {
  final String table;
  final String id;
  final ChangeKind kind;
  final DbRow? before;
  final DbRow? after;
  final List<String> changedFields;
  ChangeEntry(this.table, this.id, this.kind, this.before, this.after,
      [this.changedFields = const []]);

  String? get by => (after ?? before)?['updated_by'] as String?;
  String get building => ((after ?? before)?['building_id'] as String?) ?? '';
}

class Checkpoints {
  final ZxStore store;
  final Ledger ledger;
  Checkpoints(this.store, this.ledger);

  Future<List<DbRow>> list() =>
      store.query('SELECT * FROM checkpoints ORDER BY time DESC');

  /// Records the current generation under [label].
  Future<void> create(String label, String by, {bool auto = false}) async {
    final g = await store.lastGeneration();
    await store.exec(
        'INSERT INTO checkpoints (id, generation, label, created_by, time, auto) VALUES (?, ?, ?, ?, ?, ?)',
        [newId(), g, label, by, DateTime.now().millisecondsSinceEpoch, auto ? 1 : 0]);
  }

  /// One automatic checkpoint per day (taken at start-up).
  Future<void> autoDaily(String by) async {
    final last = await store.scalar(
        "SELECT max(time) FROM checkpoints WHERE auto = 1 AND label LIKE 'auto 2%'") as int?;
    final now = DateTime.now();
    if (last != null) {
      final t = DateTime.fromMillisecondsSinceEpoch(last);
      if (t.year == now.year && t.month == now.month && t.day == now.day) return;
    }
    await create('auto ${now.toIso8601String().substring(0, 10)}', by, auto: true);
  }

  /// Everything that differs between generation [g] and now.
  Future<List<ChangeEntry>> diff(int g) async {
    final out = <ChangeEntry>[];
    for (final table in entityFields.keys) {
      List<DbRow> then;
      try {
        then = await store.query('SELECT * FROM $table AS OF GENERATION $g');
      } catch (_) {
        then = const [];
      }
      final now = await store.query('SELECT * FROM $table');
      final before = {for (final r in then) r['id'] as String: r};
      final fields = entityFields[table]!.keys.toList();
      for (final r in now) {
        final id = r['id'] as String;
        final b = before.remove(id);
        final deletedNow = r['deleted'] == 1;
        if (b == null) {
          if (!deletedNow) out.add(ChangeEntry(table, id, ChangeKind.added, null, r));
          continue;
        }
        final deletedThen = b['deleted'] == 1;
        if (deletedNow && !deletedThen) {
          out.add(ChangeEntry(table, id, ChangeKind.deleted, b, r));
        } else if (!deletedNow) {
          final changed = [
            for (final f in fields)
              if (!_same(b[f], r[f])) f,
            if (deletedThen) 'deleted',
          ];
          if (changed.isNotEmpty) {
            out.add(ChangeEntry(table, id, ChangeKind.changed, b, r, changed));
          }
        }
      }
      for (final b in before.values) {
        out.add(ChangeEntry(table, b['id'] as String, ChangeKind.vanished, b, null));
      }
    }
    return out;
  }

  static bool _same(Object? a, Object? b) {
    if (a is List<int> && b is List<int>) return base64.encode(a) == base64.encode(b);
    return a == b;
  }

  /// Puts back the values a row had at the checkpoint (as a new, signed
  /// change that syncs to everyone).
  Future<void> restore(ChangeEntry c) async {
    final b = c.before;
    if (b == null) {
      // Added since: restoring means deleting it.
      await ledger.delete(c.table, c.building, c.id);
      return;
    }
    final fields = <String, Object?>{
      for (final f in entityFields[c.table]!.keys)
        if (f != 'owner') f: b[f],
      'deleted': 0,
    };
    await ledger.upsert(c.table, b['building_id'] as String? ?? '', fields, id: c.id);
  }
}
