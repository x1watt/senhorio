// Updates from GitHub releases (https://github.com/x1watt/senhorio/releases):
// compares the installed version with the latest release and, on Android,
// downloads its APK and opens the system installer. Desktop builds only
// show the link.

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
  final String htmlUrl;
  final String notes;
  ReleaseInfo(this.version, this.tag, this.apkUrl, this.htmlUrl, this.notes);
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
      for (final a in assets) {
        final name = (a as Map)['name'] as String? ?? '';
        if (name.endsWith('.apk')) apk = a['browser_download_url'] as String?;
      }
      return ReleaseInfo(tag.replaceFirst(RegExp('^v'), ''), tag, apk,
          j['html_url'] as String? ?? 'https://github.com/$kRepo/releases', j['body'] as String? ?? '');
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

  /// Downloads the APK (reporting 0..1) and opens the installer.
  static Future<void> downloadAndInstall(ReleaseInfo r, void Function(double) onProgress) async {
    final url = r.apkUrl;
    if (url == null) throw StateError('no APK in release ${r.tag}');
    final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
    await dir.create(recursive: true);
    final file = File('${dir.path}/senhorio-${r.version}.apk');
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url))..headers['User-Agent'] = 'senhorio';
      final res = await client.send(req);
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final total = res.contentLength ?? 0;
      var got = 0;
      final sink = file.openWrite();
      await for (final chunk in res.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress(got / total);
      }
      await sink.close();
    } finally {
      client.close();
    }
    await _ch.invokeMethod('installApk', {'path': file.path});
  }
}

Map<String, Object?> jsonDecodeMap(String s) => (jsonDecode(s) as Map).cast<String, Object?>();
