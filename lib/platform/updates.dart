// Updates from GitHub releases (https://github.com/x1watt/senhorio/releases):
// compares the installed version with the latest release and, on Android,
// downloads its APK and opens the system installer. Desktop builds only
// show the link. The daily check and the silent download live in
// update_watcher.dart; this file is the stateless part.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

const kRepo = 'x1watt/senhorio';

class ReleaseInfo {
  final String version; // "0.2.0"
  final String tag;
  final String? apkUrl;
  final int? apkSize; // bytes, to tell a whole download from a cut one
  final String htmlUrl;
  final String notes;
  ReleaseInfo(this.version, this.tag, this.apkUrl, this.htmlUrl, this.notes, {this.apkSize});

  Map<String, Object?> toJson() =>
      {'version': version, 'tag': tag, 'apk': apkUrl, 'size': apkSize, 'url': htmlUrl, 'notes': notes};

  static ReleaseInfo fromJson(Map<String, Object?> j) => ReleaseInfo(
        j['version'] as String? ?? '',
        j['tag'] as String? ?? '',
        j['apk'] as String?,
        j['url'] as String? ?? 'https://github.com/$kRepo/releases',
        j['notes'] as String? ?? '',
        apkSize: j['size'] as int?,
      );
}

class UpdateService {
  static const _ch = MethodChannel('com.x1watt.senhorio/bg');

  static Future<String> installedVersion() async => (await PackageInfo.fromPlatform()).version;

  /// The latest release, or null when none is published or offline.
  static Future<ReleaseInfo?> latest() async {
    try {
      final r = await http.get(Uri.parse('https://api.github.com/repos/$kRepo/releases/latest'),
          headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'senhorio'})
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return null;
      final j = jsonDecodeMap(r.body);
      final tag = j['tag_name'] as String? ?? '';
      final assets = (j['assets'] as List?) ?? const [];
      String? apk;
      int? size;
      for (final a in assets) {
        final name = (a as Map)['name'] as String? ?? '';
        if (name.endsWith('.apk')) {
          apk = a['browser_download_url'] as String?;
          size = a['size'] as int?;
        }
      }
      return ReleaseInfo(tag.replaceFirst(RegExp('^v'), ''), tag, apk,
          j['html_url'] as String? ?? 'https://github.com/$kRepo/releases', j['body'] as String? ?? '',
          apkSize: size);
    } catch (_) {
      return null;
    }
  }

  /// True when [a] is newer than [b] ("1.2.10" > "1.2.9").
  static bool isNewer(String a, String b) {
    List<int> parts(String v) =>
        v.split('+').first.split('.').map((p) => int.tryParse(p.replaceAll(RegExp(r'\D.*$'), '')) ?? 0).toList();
    final x = parts(a), y = parts(b);
    for (var i = 0; i < 3; i++) {
      final xi = i < x.length ? x[i] : 0, yi = i < y.length ? y[i] : 0;
      if (xi != yi) return xi > yi;
    }
    return false;
  }

  /// An update newer than what is installed, or null.
  static Future<ReleaseInfo?> check() async {
    final r = await latest();
    if (r == null) return null;
    return isNewer(r.version, await installedVersion()) ? r : null;
  }

  static bool get canInstall => !kIsWeb && Platform.isAndroid;

  // ------------------------------------------------------------ the APK

  static Future<Directory> _dir() async {
    final d = Directory('${(await getTemporaryDirectory()).path}/updates');
    await d.create(recursive: true);
    return d;
  }

  static Future<File> _apkFile(ReleaseInfo r) async => File('${(await _dir()).path}/senhorio-${r.version}.apk');

  /// The APK of [r] when it is already downloaded whole, else null.
  static Future<File?> downloaded(ReleaseInfo r) async {
    if (!canInstall) return null;
    final f = await _apkFile(r);
    if (!await f.exists()) return null;
    final len = await f.length();
    if (len == 0 || (r.apkSize != null && len != r.apkSize)) return null;
    return f;
  }

  /// Downloads the APK of [r] (reporting 0..1) into the cache; a cut
  /// download never replaces a whole one (written to .part first).
  static Future<File> download(ReleaseInfo r, void Function(double) onProgress) async {
    final url = r.apkUrl;
    if (url == null) throw StateError('no APK in release ${r.tag}');
    final file = await _apkFile(r);
    final part = File('${file.path}.part');
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url))..headers['User-Agent'] = 'senhorio';
      final res = await client.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final total = res.contentLength ?? r.apkSize ?? 0;
      var got = 0;
      final sink = part.openWrite();
      try {
        await for (final chunk in res.stream.timeout(const Duration(minutes: 2))) {
          sink.add(chunk);
          got += chunk.length;
          if (total > 0) onProgress(got / total);
        }
      } finally {
        await sink.close();
      }
      if (total > 0 && got != total) throw const HttpException('download cut short');
    } catch (_) {
      if (await part.exists()) await part.delete();
      rethrow;
    } finally {
      client.close();
    }
    return part.rename(file.path);
  }

  /// Opens the system installer on a downloaded APK.
  static Future<void> install(File apk) => _ch.invokeMethod('installApk', {'path': apk.path});

  /// Downloads (unless already here) and opens the installer.
  static Future<void> downloadAndInstall(ReleaseInfo r, void Function(double) onProgress) async {
    final f = await downloaded(r) ?? await download(r, onProgress);
    await install(f);
  }

  /// Deletes cached APKs and partial downloads, except the one of [keep].
  static Future<void> cleanup({ReleaseInfo? keep}) async {
    if (!canInstall) return;
    try {
      final keepPath = keep == null ? null : (await _apkFile(keep)).path;
      await for (final e in (await _dir()).list()) {
        if (e is File && e.path != keepPath) await e.delete();
      }
    } catch (_) {
      // the cache is the system's to clean too
    }
  }
}

Map<String, Object?> jsonDecodeMap(String s) => (jsonDecode(s) as Map).cast<String, Object?>();
