import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:senhorio/app_state.dart';
import 'package:senhorio/domain/roles.dart';
import 'package:senhorio/identity/identity_service.dart';
import 'package:senhorio/platform/backup.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('senhorio-backup'));
  tearDown(() async => dir.delete(recursive: true));

  test('restore key round-trips through pasted text', () {
    final id = Identity.generate();
    final pw = 'ab' * 32;
    final key = Backups.restoreKey(id.nsec, pw);
    expect(Backups.parseRestoreKey('  $key \n'), (id.nsec, pw));
    expect(Backups.parseRestoreKey('${pw.toUpperCase()}, ${id.nsec}'), (id.nsec, pw));
    expect(Backups.parseRestoreKey(id.nsec), isNull);
    expect(Backups.parseRestoreKey(pw), isNull);
  });

  test('a backup restored on a fresh install brings the data and identity back', () async {
    final keysA = MemoryKeyStore();
    final a = await AppState.boot(dir: '${dir.path}/a', keys: keysA, network: false);
    final b = await a.ledger.createBuilding({'name': 'Rua A'});
    final nsec = a.identity.nsec;
    final pw = await a.identityService.dbPassword();
    await a.shutdown();
    final backup = '${dir.path}/backup.zx';
    await File('${dir.path}/a/$archiveFile').copy(backup);

    // the wrong password, or not an archive at all, is refused
    await expectLater(Backups.verify(backup, 'ff' * 32), throwsA(anything));
    await File('${dir.path}/junk.zx').writeAsString('hello');
    await expectLater(Backups.verify('${dir.path}/junk.zx', pw), throwsA(anything));
    expect(await File(backup).length(), greaterThan(0));

    // a fresh install with its own identity
    final keysB = MemoryKeyStore();
    final fresh = await AppState.boot(dir: '${dir.path}/b', keys: keysB, network: false);
    expect(fresh.identity.pubkey, isNot(a.identity.pubkey));
    await fresh.ledger.createBuilding({'name': 'Lost'});
    var restarted = false;
    fresh.onRestart = () async => restarted = true;
    final (n, p) = Backups.parseRestoreKey(Backups.restoreKey(nsec, pw))!;
    await fresh.restoreBackup(backup, nsec: n, password: p);
    expect(restarted, isTrue);

    final again = await AppState.boot(dir: '${dir.path}/b', keys: keysB, network: false);
    expect(again.identity.pubkey, a.identity.pubkey);
    expect((await again.q.buildings()).single['name'], 'Rua A');
    expect(await again.ledger.myRole(b), Role.owner);
    // a restored device writes on a new lane: the old one may be ahead at peers
    expect(await keysB.read('senhorio_device'), isNot(await keysA.read('senhorio_device')));
    expect(await File('${dir.path}/b/$archiveBeforeRestore').exists(), isTrue);
    await again.shutdown();
  });
}
