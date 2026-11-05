// The database of the browser preview, in a Web Worker compiled with
// dart2wasm: the ZX SQL engine needs 64-bit integers, which dart2js (the
// UI) does not have. Same SQL dialect, generations and AS OF / HISTORY OF
// as the .zx archive of the native apps; kept in memory (no persistence).
// Messages are JSON strings: {id, op: 'sql'|'gen', sql, params} ->
// {id, result} | {id, error}. Client: lib/data/sql_backend_web.dart.

import 'dart:convert';
import 'dart:js_interop';

// ignore_for_file: implementation_imports
import 'package:zx/src/db/memory_store.dart';
import 'package:zx/src/db/sql/zx_sql.dart';
import 'package:zx/src/web/wire.dart' show sqlParamsFromWire, sqlResultToWire;

extension type _Scope._(JSObject _) implements JSObject {
  external void postMessage(JSAny? message);
  external set onmessage(JSFunction handler);
}

extension type _Message._(JSObject _) implements JSObject {
  external JSAny? get data;
}

@JS('self')
external _Scope get _self;

void main() {
  final store = ZxMemoryStore();
  final sql = ZxSql(store);
  _self.onmessage = ((_Message e) {
    final m = jsonDecode((e.data as JSString).toDart) as Map<String, Object?>;
    Map<String, Object?> reply;
    try {
      final Object result = switch (m['op']) {
        'sql' => sqlResultToWire(sql.execute(m['sql'] as String, sqlParamsFromWire(m['params']))),
        'gen' => store.generations.isEmpty ? 0 : store.generations.last.generation,
        _ => throw ArgumentError('unknown op ${m['op']}'),
      };
      reply = {'id': m['id'], 'result': result};
    } catch (e) {
      reply = {'id': m['id'], 'error': '$e'};
    }
    _self.postMessage(jsonEncode(reply).toJS);
  }).toJS;
  _self.postMessage(jsonEncode({'ready': true}).toJS);
}
