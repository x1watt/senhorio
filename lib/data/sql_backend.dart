// What ZxStore needs from a database: SQL and the archive's generations.
// Native builds use a .zx archive file (sql_backend_native.dart); the web
// build runs the same ZX SQL engine in memory (sql_backend_web.dart).

// ignore: implementation_imports
import 'package:zx/src/db/sql/sql_result.dart' show ZxSqlResult;

export 'package:zx/src/db/sql/sql_result.dart' show ZxSqlResult;

abstract class SqlBackend {
  Future<ZxSqlResult> execute(String sql, [Object? params]);

  /// Latest committed generation (0 when none).
  Future<int> lastGeneration();

  Future<void> close();
}
