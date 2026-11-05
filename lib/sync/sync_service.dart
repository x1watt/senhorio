// Runs the Reticulum node and the sync engine together.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/ledger.dart';
import '../domain/checkpoints.dart';
import '../data/zx_store.dart';
import '../identity/identity_service.dart';
import '../platform/background.dart';
import 'rns_node.dart';
import 'sync_engine.dart';

class SyncService extends ChangeNotifier {
  final ZxStore store;
  final Ledger ledger;
  final KeyStore keys;
  late final SyncEngine engine;
  RnsNode? node;
  Timer? _timer;
  final _lastHello = <String, DateTime>{};
  Set<String> partners = {};

  SyncService(this.store, this.ledger, this.keys) {
    engine = SyncEngine(ledger, store, send: _send, log: (m) => node?.log(m))
      ..onRemoteDeletes = (from) => Checkpoints(store, ledger)
          .create('auto: before deletes by ${shortNpub(from)}', ledger.me, auto: true);
  }

  bool get running => node?.running ?? false;
  DateTime _lastSyncAll = DateTime.fromMillisecondsSinceEpoch(0);

  /// Text of the Android background notification (title, body).
  (String, String) notificationText = ('Senhorio', 'Sync active');

  Future<bool> backgroundEnabled() async => (await store.getMeta('bg_sync')) != '0';

  Future<void> setBackground(bool on) async {
    await store.exec('INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)', ['bg_sync', on ? '1' : '0']);
    if (on && running) {
      await BackgroundSync.start(title: notificationText.$1, text: notificationText.$2);
    } else {
      await BackgroundSync.stop();
    }
    notifyListeners();
  }

  /// Heartbeat from the Android foreground service.
  Future<void> nativeTick() async {
    final n = node;
    if (n == null) return;
    await n.tick();
    if (DateTime.now().difference(_lastSyncAll) >= const Duration(minutes: 3)) await syncAll();
  }

  Future<List<String>> hubs() async {
    final s = await store.getMeta('hubs');
    if (s == null || s.trim().isEmpty) return defaultHubs;
    return s.split(RegExp(r'[\s,]+')).where((h) => h.isNotEmpty).toList();
  }

  Future<void> setHubs(String text) async {
    await store.exec('INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)', ['hubs', text]);
    if (running) {
      await stop();
      await start();
    }
  }

  Future<bool> enabled() async => (await store.getMeta('sync_enabled')) != '0';

  Future<void> setEnabled(bool on) async {
    await store.exec('INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)', ['sync_enabled', on ? '1' : '0']);
    on ? await start() : await stop();
  }

  Future<void> start() async {
    if (running) return;
    final n = RnsNode(
      nostr: ledger.identity,
      keys: keys,
      hubs: await hubs(),
      onMessage: (pk, msg) => unawaited(engine.onMessage(pk, msg).then((_) => notifyListeners())),
      onPeer: _onPeer,
    );
    n.addListener(notifyListeners);
    node = n;
    notifyListeners();
    try {
      await n.start();
    } catch (e) {
      n.log('start failed: $e');
    }
    partners = await engine.partners();
    _timer = Timer.periodic(const Duration(minutes: 3), (_) => syncAll());
    if (await backgroundEnabled()) {
      try {
        await BackgroundSync.start(title: notificationText.$1, text: notificationText.$2);
      } catch (e) {
        n.log('background service: $e');
      }
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    try {
      await BackgroundSync.stop();
    } catch (_) {}
    await node?.stop();
    node?.removeListener(notifyListeners);
    node = null;
    notifyListeners();
  }

  void _onPeer(String pk) {
    unawaited(() async {
      partners = await engine.partners();
      if (!partners.contains(pk)) {
        // Someone who just added us may already know us as a member while
        // we do not know the building yet: say hello once in a while.
        final last = _lastHello[pk];
        if (last != null && DateTime.now().difference(last) < const Duration(minutes: 10)) return;
      }
      final last = _lastHello[pk];
      if (last != null && DateTime.now().difference(last) < const Duration(seconds: 60)) return;
      _lastHello[pk] = DateTime.now();
      await engine.syncWith(pk);
      notifyListeners();
    }());
  }

  /// Says hello to every reachable partner.
  Future<void> syncAll() async {
    final n = node;
    if (n == null) return;
    _lastSyncAll = DateTime.now();
    await n.announce();
    partners = await engine.partners();
    for (final pk in partners) {
      if (!n.knows(pk)) continue;
      _lastHello[pk] = DateTime.now();
      await engine.syncWith(pk);
    }
    notifyListeners();
  }

  Future<bool> _send(String pk, Map<String, Object?> msg) async {
    final n = node;
    if (n == null) return false;
    return n.send(pk, msg);
  }
}
