import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao/backup.dart';
import 'package:mtandao/db.dart';
import 'package:mtandao/repo.dart';
import 'package:mtandao/screens/aide_screen.dart';
import 'package:mtandao/state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tmp;
  late Repo repo;

  setUpAll(() async {
    sqfliteFfiInit();
    tmp = Directory.systemTemp.createTempSync('mtandao_theme_');
    final db = await databaseFactoryFfi.openDatabase(
      '${tmp.path}/t.db',
      options: OpenDatabaseOptions(
        version: AppDb.version,
        onConfigure: AppDb.configurer,
        onCreate: AppDb.creer,
      ),
    );
    repo = Repo(db);
    appState.utiliserPourTest(repo);
  });
  tearDownAll(() => tmp.deleteSync(recursive: true));

  group('Thème', () {
    test('conversion de la valeur enregistrée', () {
      expect(themeDepuis('clair'), ThemeMode.light);
      expect(themeDepuis('sombre'), ThemeMode.dark);
      expect(themeDepuis('auto'), ThemeMode.system);
      expect(themeDepuis(null), ThemeMode.system);
      expect(themeDepuis('n importe quoi'), ThemeMode.system);
    });

    test('aller-retour texte', () {
      for (final m in ThemeMode.values) {
        expect(themeDepuis(themeVersTexte(m)), m);
      }
    });

    test('le choix est enregistré, et le notificateur mis à jour', () async {
      await appState.definirTheme(ThemeMode.dark);
      expect(themeMode.value, ThemeMode.dark);
      expect(await repo.getSetting(cleTheme), 'sombre');
      await appState.definirTheme(ThemeMode.system);
      expect(themeMode.value, ThemeMode.system);
      expect(await repo.getSetting(cleTheme), 'auto');
    });

    test('l\'apparence et le guide restent propres au téléphone (hors sauvegardes)', () {
      expect(Sauvegarde.estExclu(cleTheme), isTrue);
      expect(Sauvegarde.estExclu(cleGuideVu), isTrue);
    });
  });

  group('Guide', () {
    Future<void> ouvrir(WidgetTester t, {required bool premiere}) async {
      t.view.physicalSize = const Size(800, 3000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => AideScreen(premiereFois: premiere))),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('ouvrir'));
      await t.pumpAndSettle();
    }

    testWidgets('consultation depuis les réglages : pas de bouton Commencer', (t) async {
      await ouvrir(t, premiere: false);
      expect(find.text('Comment ça marche'), findsOneWidget);
      expect(find.text('Commencer'), findsNothing);
      expect(find.textContaining('1. Ajouter des tickets'), findsOneWidget);
      expect(find.textContaining('Protéger vos données'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('première fois : « Commencer » ferme le guide et le marque comme vu', (t) async {
      await t.runAsync(() => repo.removeSetting(cleGuideVu));
      await ouvrir(t, premiere: true);
      expect(find.text('Bienvenue dans Mtandao'), findsOneWidget);
      await t.tap(find.text('Commencer'));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await t.pumpAndSettle();
      expect(find.text('Bienvenue dans Mtandao'), findsNothing);
      final vu = await t.runAsync(() => repo.getSetting(cleGuideVu));
      expect(vu, '1');
    });
  });
}
