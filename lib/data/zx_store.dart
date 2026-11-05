// The local database: one .zx archive (SQL + every past generation).
// All writes go through [transaction] so one user action = one generation,
// and transactions never interleave (a single async lock).

import 'dart:async';

import 'package:zx/zx.dart';
// ZxDbStoreOptions is not exported by package:zx/zx.dart.
// ignore: implementation_imports
import 'package:zx/src/db/engine/store.dart' show ZxDbStoreOptions;

import 'schema.dart';

typedef DbRow = Map<String, Object?>;

class ZxStore {
  final ZxDatabaseAsync db;
  final String path;
  Future<void> _tail = Future.value();

  ZxStore._(this.db, this.path);

  /// Opens (or creates) the archive at [path] and runs the migrations.
  static Future<ZxStore> open(String path, {String? password}) async {
    final options = ZxDbStoreOptions(
      // phone-sized caches; the data is small
      pageCacheBytes: 16 << 20,
      blockCacheBytes: 8 << 20,
      compression: 'balanced',
      threads: 2,
    );
    final db = await ZxDatabaseAsync.open(path,
        password: password, create: true, options: options);
    final s = ZxStore._(db, path);
    await s._migrate();
    return s;
  }

  Future<void> _migrate() async {
    final existing = (await db.select(
            "SELECT name FROM sqlite_schema WHERE type = 'table'"))
        .map((r) => r[0] as String)
        .toSet();
    final missing = [
      for (final t in entityFields.keys)
        if (!existing.contains(t)) createEntityTableSql(t),
      for (final e in localTables.entries)
        if (!existing.contains(e.key)) e.value,
    ];
    // Columns added to an entity after its table was created.
    final alters = <String>[];
    for (final t in entityFields.keys) {
      if (!existing.contains(t)) continue;
      final cols = (await db.select('PRAGMA table_info($t)'))
          .map((r) => r[1] as String)
          .toSet();
      final want = {...syncColumns, ...entityFields[t]!};
      for (final c in want.entries) {
        if (!cols.contains(c.key)) {
          alters.add('ALTER TABLE $t ADD COLUMN ${c.key} ${c.value}');
        }
      }
    }
    if (missing.isEmpty && alters.isEmpty) return;
    await transaction(() async {
      for (final sql in [...missing, ...alters]) {
        await db.execute(sql);
      }
      for (final sql in entityIndexes) {
        await db.execute(sql);
      }
    });
  }

  /// Runs [body] inside BEGIN/COMMIT, serialized with every other write.
  Future<T> transaction<T>(Future<T> Function() body) => _locked(() async {
        await db.execute('BEGIN');
        try {
          final r = await body();
          await db.execute('COMMIT');
          return r;
        } catch (_) {
          await db.execute('ROLLBACK');
          rethrow;
        }
      });

  Future<T> _locked<T>(Future<T> Function() body) {
    final done = Completer<void>();
    final prev = _tail;
    _tail = done.future;
    return prev.then((_) => body()).whenComplete(done.complete);
  }

  Future<List<DbRow>> query(String sql, [Object? params]) async =>
      (await db.execute(sql, params)).maps;

  Future<DbRow?> first(String sql, [Object? params]) async {
    final r = await query(sql, params);
    return r.isEmpty ? null : r.first;
  }

  Future<Object?> scalar(String sql, [Object? params]) async =>
      (await db.execute(sql, params)).scalar;

  /// Write outside of [transaction] (one statement = one generation).
  Future<void> exec(String sql, [Object? params]) =>
      _locked(() => db.execute(sql, params));

  Future<String?> getMeta(String key) async =>
      await scalar('SELECT value FROM meta WHERE key = ?', [key]) as String?;

  /// Must be called inside a transaction or via [exec].
  Future<void> putMetaRaw(String key, String value) => db.execute(
      'INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)', [key, value]);

  Future<int> lastGeneration() async {
    final g = await db.generations();
    return g.isEmpty ? 0 : g.last.generation;
  }

  Future<void> close() => db.close();
}
