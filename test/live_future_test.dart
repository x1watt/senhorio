import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:senhorio/app_state.dart';
import 'package:senhorio/identity/identity_service.dart';
import 'package:senhorio/ui/widgets/common.dart';

void main() {
  testWidgets('a ledger change reloads LiveFuture without resetting the tab below it', (tester) async {
    final dir = await tester.runAsync(() => Directory.systemTemp.createTemp('senhorio-live'));
    final app = (await tester.runAsync(() => AppState.boot(dir: dir!.path, keys: MemoryKeyStore(), network: false)))!;
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: app),
        ChangeNotifierProvider.value(value: app.ledger),
      ],
      child: MaterialApp(
        home: LiveFuture<int>(
          load: (a) async => (await a.q.buildings()).length,
          builder: (context, n) => DefaultTabController(
            length: 2,
            child: Scaffold(
              appBar: AppBar(bottom: const TabBar(tabs: [Tab(text: 'one'), Tab(text: 'two')])),
              body: TabBarView(children: [Text('first $n'), Text('second $n')]),
            ),
          ),
        ),
      ),
    ));
    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();
      }
    }

    await settle();
    expect(find.text('first 0'), findsOneWidget);
    await tester.tap(find.text('two'));
    await tester.pumpAndSettle();
    expect(find.text('second 0'), findsOneWidget);

    await tester.runAsync(() => app.ledger.createBuilding({'name': 'Rua A'}));
    await tester.pump();
    // still on the second tab while reloading (no spinner), then with new data
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await settle();
    expect(find.text('second 1'), findsOneWidget);
    expect(DefaultTabController.of(tester.element(find.text('second 1'))).index, 1);

    await tester.runAsync(() async {
      await app.shutdown();
      await dir!.delete(recursive: true);
    });
  });
}
