import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'l10n/gen/app_localizations.dart';
import 'ui/screens/home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _Boot());
}

/// Opens the archive, then shows the app (or the error that stopped it).
class _Boot extends StatefulWidget {
  const _Boot();
  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  late final Future<AppState> _boot = AppState.boot();

  @override
  Widget build(BuildContext context) => FutureBuilder<AppState>(
        future: _boot,
        builder: (context, snap) {
          if (snap.hasData) return SenhorioApp(state: snap.data!);
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: senhorioTheme(Brightness.light),
            darkTheme: senhorioTheme(Brightness.dark),
            home: Scaffold(
              body: Center(
                child: snap.hasError
                    ? Padding(padding: const EdgeInsets.all(24), child: SelectableText('${snap.error}'))
                    : const CircularProgressIndicator(),
              ),
            ),
          );
        },
      );
}

ThemeData senhorioTheme(Brightness b) => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D6B), brightness: b),
      useMaterial3: true,
    );

class SenhorioApp extends StatelessWidget {
  final AppState state;
  const SenhorioApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: state),
          ChangeNotifierProvider.value(value: state.ledger),
        ],
        child: Consumer<AppState>(
          builder: (context, app, _) => MaterialApp(
            title: 'Senhorio',
            debugShowCheckedModeBanner: false,
            theme: senhorioTheme(Brightness.light),
            darkTheme: senhorioTheme(Brightness.dark),
            locale: app.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const HomeShell(),
          ),
        ),
      );
}
