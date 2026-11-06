// An in-memory network for sync tests.

import 'dart:convert';

import 'package:senhorio/sync/sync_engine.dart';

/// Peers wired by an in-memory network (messages are JSON round-tripped).
class Wire {
  final engines = <String, SyncEngine>{};
  var pending = <Future<void>>[];
  Future<bool> send(String from, String to, Map<String, Object?> msg) async {
    final e = engines[to];
    if (e == null) return false;
    final copy = jsonDecode(jsonEncode(msg)) as Map<String, Object?>;
    pending.add(Future(() => e.onMessage(from, copy)));
    return true;
  }

  /// Delivers to every engine registered for [to] (devices of one npub).
  final devices = <String, List<SyncEngine>>{};
  Future<bool> sendAll(String from, String to, Map<String, Object?> msg) async {
    final list = devices[to] ?? const [];
    for (final e in list) {
      final copy = jsonDecode(jsonEncode(msg)) as Map<String, Object?>;
      pending.add(Future(() => e.onMessage(from, copy)));
    }
    return list.isNotEmpty;
  }

  /// Runs until no message is in flight.
  Future<void> settle() async {
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (pending.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (pending.isEmpty) return;
      }
      final p = pending;
      pending = [];
      await Future.wait(p);
    }
  }
}
