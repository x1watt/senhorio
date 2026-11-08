// The daily update check that keeps running for as long as the app lives
// (on Android the process rarely restarts: the sync service holds it, so a
// check only at start-up would hardly ever run). Once a day it asks GitHub
// for the latest release; a newer one is downloaded quietly and kept ready,
// announced with a notification, and the UI (update_dialog.dart) offers to
// install it. What was found survives a restart (meta `update_found`), so
// the offer comes back without asking GitHub again.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/zx_store.dart';
import 'alerts.dart';
import 'updates.dart';

enum UpdatePoll { offline, upToDate, found }

class UpdateWatcher extends ChangeNotifier {
  final ZxStore store;
  final Future<ReleaseInfo?> Function() fetchLatest;
  final Future<String> Function() installed;
  final Future<File?> Function(ReleaseInfo) fetchApk; // null: nothing to install here
  final (String, String) Function(ReleaseInfo) notification; // title, text (localised)

  static const checkEvery = Duration(hours: 20);
  static const offerEvery = Duration(hours: 20); // how often the dialog comes back after "Later"

  UpdateWatcher(this.store,
      {required this.notification,
      Future<ReleaseInfo?> Function()? fetchLatest,
      Future<String> Function()? installed,
      Future<File?> Function(ReleaseInfo)? fetchApk})
      : fetchLatest = fetchLatest ?? UpdateService.latest,
        installed = installed ?? UpdateService.installedVersion,
        fetchApk = fetchApk ?? _download;

  static Future<File?> _download(ReleaseInfo r) async {
    if (!UpdateService.canInstall || r.apkUrl == null) return null;
    return await UpdateService.downloaded(r) ?? await UpdateService.download(r, (_) {});
  }

  /// A newer release than the installed one, downloaded when [apk] is set.
  ReleaseInfo? ready;
  File? apk;
  bool get hasUpdate => ready != null;

  Timer? _timer;
  Future<UpdatePoll>? _inFlight;
  String? _announced;

  /// Polls now and then every hour (the check itself runs once a day).
  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(hours: 1), (_) => unawaited(poll()));
    unawaited(poll());
  }

  /// Checks GitHub when the last check is older than [checkEvery] (or
  /// [force]); otherwise only makes sure a release found earlier is
  /// downloaded and announced. Cheap to call often.
  Future<UpdatePoll> poll({bool force = false}) {
    final f = _inFlight;
    if (f != null) return f;
    final run = _poll(force);
    _inFlight = run;
    return run.whenComplete(() => _inFlight = null);
  }

  Future<UpdatePoll> _poll(bool force) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = int.tryParse(await store.getMeta('update_check') ?? '') ?? 0;
      final due = force || now - last >= checkEvery.inMilliseconds;
      ReleaseInfo? r;
      if (due) {
        r = await fetchLatest();
        if (r == null) return UpdatePoll.offline; // try again next hour
        await store.exec('INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)', ['update_check', '$now']);
        await store.exec('INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)',
            ['update_found', jsonEncode(r.toJson())]);
      } else {
        final s = await store.getMeta('update_found');
        if (s == null || s.isEmpty) return UpdatePoll.upToDate;
        r = ReleaseInfo.fromJson(jsonDecodeMap(s));
      }
      if (!UpdateService.isNewer(r.version, await installed())) {
        // installed (or never newer): forget it and clean up
        if (ready != null || due) {
          ready = null;
          apk = null;
          await UpdateService.cleanup();
          await UpdateNotification.clear();
          notifyListeners();
        }
        return UpdatePoll.upToDate;
      }
      await _prepare(r);
      return UpdatePoll.found;
    } catch (_) {
      return UpdatePoll.offline;
    }
  }

  Future<void> _prepare(ReleaseInfo r) async {
    if (ready?.version != r.version) {
      ready = r;
      apk = null;
      notifyListeners();
      await UpdateService.cleanup(keep: r);
    }
    if (apk == null) {
      try {
        apk = await fetchApk(r);
      } catch (_) {
        apk = null; // offline or cut: the dialog can download by hand, next hour tries again
      }
      notifyListeners();
    }
    if (_announced != r.version && (apk != null || !UpdateService.canInstall)) {
      _announced = r.version;
      final (title, text) = notification(r);
      await UpdateNotification.show(title, text);
    }
  }

  /// True when the dialog should be offered now: an update is ready and the
  /// user did not say "Later" for it in the last [offerEvery].
  Future<bool> shouldOffer() async {
    final r = ready;
    if (r == null) return false;
    final s = await store.getMeta('update_offered') ?? '';
    final i = s.indexOf(':');
    if (i < 0) return true;
    if (s.substring(0, i) != r.version) return true;
    final at = int.tryParse(s.substring(i + 1)) ?? 0;
    return DateTime.now().millisecondsSinceEpoch - at >= offerEvery.inMilliseconds;
  }

  Future<void> offered() async {
    final r = ready;
    if (r == null) return;
    await store.exec('INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)',
        ['update_offered', '${r.version}:${DateTime.now().millisecondsSinceEpoch}']);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
