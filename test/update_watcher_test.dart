import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:senhorio/data/zx_store.dart';
import 'package:senhorio/platform/update_watcher.dart';
import 'package:senhorio/platform/updates.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('senhorio-updates'));
  tearDown(() async => dir.delete(recursive: true));

  ReleaseInfo release(String v) => ReleaseInfo(v, 'v$v', 'https://x/senhorio-$v.apk', 'https://x/$v', 'notes $v', apkSize: 3);

  test('isNewer compares versions numerically', () {
    expect(UpdateService.isNewer('0.6.0', '0.5.1'), isTrue);
    expect(UpdateService.isNewer('0.5.10', '0.5.9'), isTrue);
    expect(UpdateService.isNewer('0.5.1+9', '0.5.1'), isFalse);
    expect(UpdateService.isNewer('0.5.1', '0.6.0'), isFalse);
  });

  test('a new release is checked once a day, downloaded, remembered and forgotten once installed', () async {
    final store = await ZxStore.open('${dir.path}/a.zx');
    var fetches = 0, downloads = 0;
    var latest = release('0.6.0');
    var installedVersion = '0.5.1';
    UpdateWatcher watcher() => UpdateWatcher(store,
        notification: (r) => ('ready', r.version),
        fetchLatest: () async {
          fetches++;
          return latest;
        },
        installed: () async => installedVersion,
        fetchApk: (r) async {
          downloads++;
          return File('${dir.path}/${r.version}.apk')..writeAsStringSync('apk');
        });

    final w = watcher();
    var notified = 0;
    w.addListener(() => notified++);
    expect(await w.poll(), UpdatePoll.found);
    expect(w.ready?.version, '0.6.0');
    expect(w.apk, isNotNull);
    expect(await w.shouldOffer(), isTrue);
    expect(notified, greaterThan(0));
    expect((fetches, downloads), (1, 1));

    // an hour later: nothing asked again, nothing downloaded again
    expect(await w.poll(), UpdatePoll.found);
    expect((fetches, downloads), (1, 1));

    // "Later" holds the dialog back for a day
    await w.offered();
    expect(await w.shouldOffer(), isFalse);

    // the process restarts: the offer comes back from the archive without GitHub
    final w2 = watcher();
    expect(await w2.poll(), UpdatePoll.found);
    expect(w2.ready?.version, '0.6.0');
    expect(w2.apk?.existsSync(), isTrue);
    expect(fetches, 1);
    expect(await w2.shouldOffer(), isFalse); // still within the day of "Later"

    // installed: forgotten
    installedVersion = '0.6.0';
    expect(await w2.poll(), UpdatePoll.upToDate);
    expect(w2.ready, isNull);
    expect(await w2.shouldOffer(), isFalse);

    // a forced check reaches GitHub; offline leaves the last check untouched
    latest = release('0.6.0');
    expect(await w2.poll(force: true), UpdatePoll.upToDate);
    expect(fetches, 2);
    final w3 = UpdateWatcher(store,
        notification: (r) => ('', ''), fetchLatest: () async => null, installed: () async => '0.6.0');
    expect(await w3.poll(force: true), UpdatePoll.offline);
    await store.close();
  });

  test('a newer release found by a forced check replaces the stored one and a new version is offered again', () async {
    final store = await ZxStore.open('${dir.path}/b.zx');
    var latest = release('0.6.0');
    final w = UpdateWatcher(store,
        notification: (r) => ('', ''),
        fetchLatest: () async => latest,
        installed: () async => '0.5.0',
        fetchApk: (r) async => null);
    expect(await w.poll(), UpdatePoll.found);
    await w.offered();
    expect(await w.shouldOffer(), isFalse);
    latest = release('0.7.0');
    expect(await w.poll(force: true), UpdatePoll.found);
    expect(w.ready?.version, '0.7.0');
    expect(await w.shouldOffer(), isTrue); // "Later" was for 0.6.0
    await store.close();
  });
}
