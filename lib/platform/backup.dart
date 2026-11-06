// Backups: the whole .zx archive (every generation) copied to a place an
// uninstall does not wipe (the public Downloads folder on Android, a
// chosen file on desktop), and restored with one pasted "restore key":
// the nsec and the archive's password.

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/dates.dart';
import '../data/sql_backend_native.dart' if (dart.library.js_interop) '../data/sql_backend_web.dart';

/// The live archive, inside the app's data directory.
const archiveFile = 'senhorio.zx';

/// Where the previous archive goes when a backup is restored over it.
const archiveBeforeRestore = 'senhorio-before-restore.zx';

const _channel = MethodChannel('com.x1watt.senhorio/bg');

class Backups {
  static String fileName() => 'senhorio-${isoDate(DateTime.now())}.zx';

  /// Copies the archive out; returns where it went (null: cancelled).
  static Future<String?> export(String archivePath) async {
    final name = fileName();
    if (Platform.isAndroid) {
      try {
        return await _channel.invokeMethod<String>('saveToDownloads', {'path': archivePath, 'name': name});
      } on PlatformException catch (e) {
        if (e.code != 'permission') rethrow;
        // Android 9 and older without the storage permission: the app's own
        // folder (lost on uninstall, but still a copy).
        final dir = await getExternalStorageDirectory();
        if (dir == null) rethrow;
        return (await File(archivePath).copy('${dir.path}/$name')).path;
      }
    }
    final loc = await getSaveLocation(suggestedName: name);
    if (loc == null) return null;
    await File(archivePath).copy(loc.path);
    return loc.path;
  }

  /// Lets the user pick a backup file: its path and display name (Android
  /// hands over a cached copy whose path does not keep the name); null when
  /// cancelled.
  static Future<({String path, String name})?> pick() async {
    const group = XTypeGroup(label: 'ZX', extensions: ['zx'], mimeTypes: ['*/*']);
    XFile? f;
    try {
      f = await openFile(acceptedTypeGroups: const [group]);
    } on ArgumentError {
      f = await openFile();
    }
    return f == null ? null : (path: f.path, name: f.name);
  }

  // ------------------------------------------------------------ restore key

  /// What the user keeps with the backup: the nsec and the archive password.
  static String restoreKey(String nsec, String password) => '$nsec\n$password';

  /// Finds the nsec and the password in pasted text (any order, any
  /// separators); null when one is missing.
  static (String nsec, String password)? parseRestoreKey(String text) {
    String? nsec, pw;
    for (final t in text.split(RegExp(r'[\s,;:]+'))) {
      if (t.startsWith('nsec1')) {
        nsec = t;
      } else if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(t)) {
        pw = t.toLowerCase();
      }
    }
    return nsec == null || pw == null ? null : (nsec, pw);
  }

  // ---------------------------------------------------------------- restore

  /// Opens [file] with [password] without touching it further; throws when
  /// it is not a Senhorio archive opened by that password.
  static Future<void> verify(String file, String password) async {
    final db = await openBackend(file, password: password);
    try {
      final n = (await db.execute('SELECT count(*) FROM events')).scalar;
      if (n == null) throw const FormatException('not a Senhorio archive');
    } finally {
      await db.close();
    }
  }

  /// Copies [file] next to the archive and checks it; returns the copy.
  static Future<String> stage(String dataDir, String file, String password) async {
    final tmp = '$dataDir/restore.zx';
    await File(file).copy(tmp);
    try {
      await verify(tmp, password);
    } catch (_) {
      try {
        await File(tmp).delete();
      } catch (_) {}
      rethrow;
    }
    return tmp;
  }

  /// Puts the staged copy in place of the archive (the app must be shut
  /// down); the previous archive is kept as [archiveBeforeRestore].
  static Future<void> commit(String dataDir, String staged) async {
    final live = File('$dataDir/$archiveFile');
    if (await live.exists()) await live.rename('$dataDir/$archiveBeforeRestore');
    await File(staged).rename(live.path);
  }
}
