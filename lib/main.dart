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
  late Future<AppState> _boot = _start();

  Future<AppState> _start() async {
    final s = await AppState.boot();
    s.onRestart = () async {
      if (mounted) setState(() => _boot = _start());
    };
    return s;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AppState>(
        future: _boot,
        builder: (context, snap) {
          if (snap.hasData) return SenhorioApp(state: snap.data!);
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: senhorioTheme(Brightness.light),
            darkTheme: senhorioTheme(Brightness.dark),
            themeMode: ThemeMode.dark,
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

/// Dark, black theme (OLED friendly); the light one stays for readers who
/// force it in the system settings... the app itself always uses dark.
ThemeData senhorioTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D6B), brightness: b);
  if (b == Brightness.light) return ThemeData(colorScheme: scheme, useMaterial3: true);
  const black = Color(0xFF000000);
  const panel = Color(0xFF111413);
  const panel2 = Color(0xFF1A1F1D);
  final dark = scheme.copyWith(
    surface: black,
    surfaceContainerLowest: black,
    surfaceContainerLow: const Color(0xFF0B0D0C),
    surfaceContainer: panel,
    surfaceContainerHigh: panel2,
    surfaceContainerHighest: const Color(0xFF242A28),
    primary: const Color(0xFF5FD3B5),
    onPrimary: black,
    primaryContainer: const Color(0xFF1F4D40),
    onPrimaryContainer: const Color(0xFFBDF2E2),
    error: const Color(0xFFFF5252),
    outline: const Color(0xFF6F7A76),
  );
  return ThemeData(
    colorScheme: dark,
    useMaterial3: true,
    scaffoldBackgroundColor: black,
    canvasColor: black,
    appBarTheme: const AppBarTheme(backgroundColor: black, surfaceTintColor: Colors.transparent),
    cardTheme: const CardThemeData(color: panel, surfaceTintColor: Colors.transparent, elevation: 0),
    navigationBarTheme: const NavigationBarThemeData(backgroundColor: panel, surfaceTintColor: Colors.transparent),
    navigationRailTheme: const NavigationRailThemeData(backgroundColor: black),
    dialogTheme: const DialogThemeData(backgroundColor: panel2, surfaceTintColor: Colors.transparent),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: panel2, surfaceTintColor: Colors.transparent),
    popupMenuTheme: const PopupMenuThemeData(color: panel2, surfaceTintColor: Colors.transparent),
    inputDecorationTheme: const InputDecorationTheme(filled: true, fillColor: panel),
    chipTheme: const ChipThemeData(backgroundColor: panel2),
    dividerColor: panel2,
  );
}

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
            themeMode: ThemeMode.dark,
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
