// The browser preview's database: a Web Worker running the ZX SQL engine
// (web_engine/db_worker.dart, dart2wasm). Nothing is persisted.

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

// ignore: implementation_imports
import 'package:zx/src/web/wire.dart' show sqlParamsToWire, sqlResultFromWire;

import 'sql_backend.dart';

@JS('Worker')
extension type _Worker._(JSObject _) implements JSObject {
  external factory _Worker(JSString url, JSAny options);
  external void postMessage(JSAny? message);
  external set onmessage(JSFunction handler);
}

extension type _Message._(JSObject _) implements JSObject {
  external JSAny? get data;
}

class WorkerBackend implements SqlBackend {
  final _Worker _w;
  final _pending = <int, Completer<Object?>>{};
  final _ready = Completer<void>();
  var _next = 0;

  WorkerBackend._(this._w) {
    _w.onmessage = ((_Message e) {
      final m = jsonDecode((e.data as JSString).toDart) as Map<String, Object?>;
      if (m['ready'] == true) {
        _ready.complete();
        return;
      }
      if (m['unsupported'] != null) {
        _ready.completeError(UnsupportedError(
            'This browser cannot run the database (needs WebAssembly GC): ${m['unsupported']}'));
        return;
      }
      final c = _pending.remove(m['id']);
      if (c == null) return;
      if (m['error'] != null) {
        c.completeError(Exception(m['error']));
      } else {
        c.complete(m['result']);
      }
    }).toJS;
  }

  static Future<WorkerBackend> start() async {
    final b = WorkerBackend._(_Worker('db/db_worker.js'.toJS, {'type': 'module'}.jsify()!));
    await b._ready.future;
    return b;
  }

  Future<Object?> _call(Map<String, Object?> m) {
    final id = ++_next;
    final c = Completer<Object?>();
    _pending[id] = c;
    _w.postMessage(jsonEncode({...m, 'id': id}).toJS);
    return c.future;
  }

  @override
  Future<ZxSqlResult> execute(String sql, [Object? params]) async {
    final r = await _call({'op': 'sql', 'sql': sql, 'params': sqlParamsToWire(params)});
    return sqlResultFromWire((r as Map).cast<String, Object?>());
  }

  @override
  Future<int> lastGeneration() async => (await _call({'op': 'gen'})) as int;

  @override
  Future<void> close() async {}
}

Future<SqlBackend> openBackend(String path, {String? password}) => WorkerBackend.start();
