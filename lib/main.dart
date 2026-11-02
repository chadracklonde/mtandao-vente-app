import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pdfrx/pdfrx.dart';

import 'sauvegarde_auto.dart';
import 'screens/home_shell.dart';
import 'screens/lock_gate.dart';
import 'state.dart';
import 'widgets/ticket_card.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await initializeDateFormatting('fr');
  await pdfrxFlutterInitialize();
  await appState.init();
  try {
    await SauvegardeAuto.initialiser();
  } catch (_) {
    // La sauvegarde automatique est facultative : l'application doit
    // démarrer et vendre même si elle est indisponible.
  }
  runApp(const MtandaoApp());
}

class MtandaoApp extends StatelessWidget {
  const MtandaoApp({super.key});

  ThemeData _theme(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: bleuMtandao, brightness: b);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      appBarTheme: const AppBarTheme(centerTitle: false),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (context, mode, _) => MaterialApp(
        title: 'Mtandao',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: mode,
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) =>
            LockGate(child: child ?? const SizedBox.shrink()),
        home: const HomeShell(),
      ),
    );
  }
}
