// Wires the services together; one instance for the app's lifetime.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'data/ledger.dart';
import 'data/queries.dart';
import 'data/zx_store.dart';
import 'domain/category_learner.dart';
import 'demo/demo_data.dart';
import 'domain/checkpoints.dart';
import 'identity/identity_service.dart';
import 'platform/background.dart';
import 'platform/backup.dart';
import 'sync/sync_service.dart';

class AppState extends ChangeNotifier {
  final String dataDir;
  final IdentityService identityService;
  final ZxStore store;
  final Ledger ledger;
  final Queries q;
  final Checkpoints checkpoints;
  final SyncService sync;
  Locale? locale;

  AppState._(this.dataDir, this.identityService, this.store, this.ledger)
      : q = Queries(store),
        checkpoints = Checkpoints(store, ledger),
        sync = SyncService(store, ledger, identityService.store);

  Identity get identity => identityService.identity;

  static Future<AppState> boot({String? dir, KeyStore? keys, bool network = true}) async {
    // The browser preview: data in memory, no Reticulum (no sockets there).
    if (kIsWeb) {
      dir = 'web';
      keys ??= MemoryKeyStore();
      network = false;
    }
    final base = dir ?? (await getApplicationSupportDirectory()).path;
    if (!kIsWeb) await Directory(base).create(recursive: true);
    final ids = IdentityService(keys ?? SecureKeyStore(base));
    final id = await ids.load();
    final store =
        await ZxStore.open('$base/$archiveFile', password: await ids.dbPassword());
    final ledger = Ledger(store, id, device: await ids.deviceId())..signLocal = !kIsWeb;
    await ledger.init();
    final s = AppState._(base, ids, store, ledger);
    final lang = await store.getMeta('locale');
    if (lang != null && lang.isNotEmpty) s.locale = Locale(lang);
    if (kIsWeb && (await s.q.buildings()).isEmpty) await seedDemoData(s.ledger, s.checkpoints);
    await s.checkpoints.autoDaily(id.pubkey);
    if (network) {
      BackgroundSync.init(s.sync.nativeTick);
      s.sync.notificationText = s._notificationText();
      if (await s.sync.enabled()) unawaited(s.sync.start());
    }
    return s;
  }

  (String, String) _notificationText() {
    final lang = locale?.languageCode ?? PlatformDispatcher.instance.locale.languageCode;
    return lang == 'pt'
        ? ('Senhorio', 'Sincronização ativa em segundo plano')
        : ('Senhorio', 'Syncing in the background');
  }

  Future<void> setLocale(Locale? l) async {
    locale = l;
    await store.exec('INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)',
        ['locale', l?.languageCode ?? '']);
    sync.notificationText = _notificationText();
    notifyListeners();
  }

  /// Set by the root widget: boots a new state in place of this one.
  Future<void> Function()? onRestart;

  /// Stops syncing and closes the archive.
  Future<void> shutdown() async {
    await sync.stop();
    await store.close();
  }

  /// Replaces the archive and the keys with a backup (checked first), then
  /// restarts the app on it.
  Future<void> restoreBackup(String file, {required String nsec, required String password}) async {
    Identity.parse(nsec);
    final staged = await Backups.stage(dataDir, file, password);
    await shutdown();
    await Backups.commit(dataDir, staged);
    await identityService.installRestored(nsec: nsec, dbPassword: password);
    await onRestart?.call();
  }

  Future<void> importIdentity(String nsec) async {
    final id = await identityService.import(nsec);
    ledger.identity = id;
    if (sync.running) {
      await sync.stop();
      await sync.start();
    }
    notifyListeners();
  }

  // ---------------------------------------------------- category learner

  CategoryLearner? _learner;
  int _learnerRev = -1;

  /// The learner, rebuilt from all categorised expenses when data changed.
  Future<CategoryLearner> learner() async {
    if (_learner != null && _learnerRev == ledger.revision) return _learner!;
    final cats = await q.categories();
    final learner = CategoryLearner({
      for (final c in cats)
        if (c['key'] != null) c['key'] as String: c['id'] as String,
    });
    final rows = await store.query(
        'SELECT vendor, description, amount_cents, building_id, apartment_id, unit, category_id '
        'FROM expenses WHERE deleted = 0 AND category_id IS NOT NULL ORDER BY date');
    for (final r in rows) {
      learner.learn(featuresOf(r), r['category_id'] as String);
    }
    _learner = learner;
    _learnerRev = ledger.revision;
    return learner;
  }

  static ExpenseFeatures featuresOf(Map<String, Object?> r) => ExpenseFeatures(
        vendor: (r['vendor'] as String?) ?? '',
        description: (r['description'] as String?) ?? '',
        amountCents: (r['amount_cents'] as int?) ?? 0,
        building: r['building_id'] as String?,
        apartment: r['apartment_id'] as String?,
        unit: r['unit'] as String?,
      );
}
