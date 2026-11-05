import 'package:zx/zx.dart';
// ZxDbStoreOptions is not exported by package:zx/zx.dart.
// ignore: implementation_imports
import 'package:zx/src/db/engine/store.dart' show ZxDbStoreOptions;

import 'sql_backend.dart';

/// The database inside a .zx archive, in a worker isolate.
class ZxFileBackend implements SqlBackend {
  final ZxDatabaseAsync db;
  ZxFileBackend(this.db);

  @override
  Future<ZxSqlResult> execute(String sql, [Object? params]) => db.execute(sql, params);

  @override
  Future<int> lastGeneration() async {
    final g = await db.generations();
    return g.isEmpty ? 0 : g.last.generation;
  }

  @override
  Future<void> close() => db.close();
}

Future<SqlBackend> openBackend(String path, {String? password}) async {
  final options = ZxDbStoreOptions(
    // phone-sized caches; the data is small
    pageCacheBytes: 16 << 20,
    blockCacheBytes: 8 << 20,
    compression: 'balanced',
    threads: 2,
  );
  final db = await ZxDatabaseAsync.open(path, password: password, create: true, options: options);
  return ZxFileBackend(db);
}
