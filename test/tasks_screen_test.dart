import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:senhorio/app_state.dart';
import 'package:senhorio/domain/roles.dart';
import 'package:senhorio/identity/identity_service.dart';
import 'package:senhorio/l10n/gen/app_localizations.dart';
import 'package:senhorio/ui/screens/building_tabs.dart';
import 'package:senhorio/ui/screens/tasks.dart';

void main() {
  testWidgets('tasks and members screens show the work, its status and people by name', (tester) async {
    final dir = await tester.runAsync(() => Directory.systemTemp.createTemp('senhorio-tasks'));
    final app = (await tester.runAsync(() => AppState.boot(dir: dir!.path, keys: MemoryKeyStore(), network: false)))!;
    final worker = Identity.generate();
    final b = (await tester.runAsync(() async {
      final b = await app.ledger.createBuilding({'name': 'Rua A'});
      await app.ledger.upsert('members', b, {'pubkey': worker.pubkey, 'role': 'worker', 'name': 'Cleaner'},
          id: '$b:${worker.pubkey}');
      await app.q.setNickname(worker.pubkey, 'Zé');
      await app.ledger.upsert('tasks', b, {
        'title': 'Stairs', 'place': 'Stairs', 'assignee': worker.pubkey, 'status': 'done',
        'starts_at': '2026-11-10T09:00', 'ends_at': '2026-11-10T11:00',
      });
      return b;
    }))!;
    final building = (await tester.runAsync(() => app.q.byId('buildings', b)))!;
    Widget wrap(Widget child) => MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: app),
            ChangeNotifierProvider.value(value: app.ledger),
          ],
          child: MaterialApp(
            key: UniqueKey(), // a fresh navigator each time
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: child,
          ),
        );
    // Lets the real database work finish, then settles the animations.
    Future<void> settle() async {
      // (each pump moves the screen's load on by one await, so many short ones)
      for (var i = 0; i < 600; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
        if (i > 5 && find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      }
      // Transitions, not pumpAndSettle: the screens below reload on real I/O.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(TasksTab(building: building, role: Role.owner)));
    await settle();
    expect(find.text('Stairs'), findsOneWidget);
    expect(find.text('Waiting for approval'), findsNWidgets(2)); // the section and the chip
    expect(find.textContaining('Zé'), findsOneWidget); // the nickname, not the member name
    await tester.tap(find.text('Stairs'));
    await settle();
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);

    await tester.pumpWidget(wrap(MembersTab(building: building, role: Role.owner)));
    await settle();
    expect(find.text('Zé'), findsOneWidget);
    expect(find.textContaining('Worker'), findsOneWidget);

    await tester.runAsync(() async {
      await app.shutdown();
      await dir!.delete(recursive: true);
    });
  });
}
