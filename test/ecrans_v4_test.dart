import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mtandao/db.dart';
import 'package:mtandao/format.dart';
import 'package:mtandao/models.dart';
import 'package:mtandao/repo.dart';
import 'package:mtandao/screens/caisse_screen.dart';
import 'package:mtandao/screens/dettes_screen.dart';
import 'package:mtandao/screens/historique_screen.dart';
import 'package:mtandao/state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> attendre(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
  await t.pump();
}

void main() {
  late Repo repo;
  late Directory tmp;

  setUpAll(() async {
    sqfliteFfiInit();
    await initializeDateFormatting('fr');
    tmp = Directory.systemTemp.createTempSync('mtandao_ecrans4_');
    final db = await databaseFactoryFfi.openDatabase(
      '${tmp.path}/e.db',
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

  setUp(() async {
    for (final t in ['clotures', 'tickets', 'lots', 'clients']) {
      await repo.db.delete(t);
    }
    final lot = await repo.importerLot(
      nom: 'Lot',
      forfait: (await repo.forfaits()).first,
      source: 'texte',
      tickets: [for (var i = 1; i <= 5; i++) ParsedTicket(code: 'K$i')],
    );
    final ts = await repo.ticketsDuLot(lot.lotId!);
    final marie = await repo.ajouterClient('Marie', telephone: '0812');
    await repo.vendre(ts[0].id, clientId: marie);
    await repo.vendre(ts[1].id);
    await repo.vendre(ts[2].id, paiement: Paiement.credit, clientId: marie);
    await repo.db.update('tickets',
        {'vendu_le': DateTime.now().subtract(const Duration(days: 12)).millisecondsSinceEpoch},
        where: 'id = ?', whereArgs: [ts[2].id]);
  });

  Future<void> afficher(WidgetTester t, Widget ecran) async {
    t.view.physicalSize = const Size(800, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(locale: const Locale('fr'), home: ecran));
    await attendre(t);
  }

  testWidgets('recherche : dernières ventes puis filtre par client', (t) async {
    await afficher(t, const HistoriqueScreen());
    expect(find.text('Dernières ventes'), findsOneWidget);
    expect(find.text('K1'), findsOneWidget);
    expect(find.text('K2'), findsOneWidget);
    expect(find.text('K5'), findsNothing); // en stock : pas dans les dernières ventes

    await t.enterText(find.byType(TextField), 'maria');
    await t.pump();
    await attendre(t);
    expect(find.text('K1'), findsNothing);
    await t.enterText(find.byType(TextField), 'mar');
    await t.pump();
    await attendre(t);
    expect(find.text('K1'), findsOneWidget);
    expect(find.text('K3'), findsOneWidget);
    expect(find.text('K2'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('recherche : détails et annulation d\'une vente', (t) async {
    await afficher(t, const HistoriqueScreen());
    await t.tap(find.text('K2'));
    await t.pumpAndSettle();
    expect(find.text('Envoyer le code'), findsOneWidget);
    await t.tap(find.text('Annuler cette vente'));
    await t.pumpAndSettle();
    await t.tap(find.text('Oui, annuler'));
    await attendre(t);
    await t.pumpAndSettle();
    final k2 = (await t.runAsync(() => repo.rechercher('K2')))!.single.ticket;
    expect(k2.vendu, isFalse);
  });

  testWidgets('caisse : attendu, écart et enregistrement', (t) async {
    await afficher(t, const CaisseScreen());
    // K1 et K2 en espèces ; K3 est à crédit, donc pas en caisse.
    expect(find.text(cdf(2000)), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, 'Argent compté (CDF)'), '1500');
    await t.pump();
    expect(find.text('Manque : ${cdf(500)}'), findsOneWidget);
    await t.ensureVisible(find.text('Enregistrer la clôture'));
    await t.tap(find.text('Enregistrer la clôture'));
    await attendre(t);
    await t.pumpAndSettle();
    final c = (await t.runAsync(() => repo.clotures()))!.single;
    expect((c.attenduCdf, c.compteCdf), (2000, 1500));
    expect(find.text('Clôtures précédentes'), findsOneWidget);
  });

  testWidgets('dettes : le retard est signalé', (t) async {
    await afficher(t, const DettesScreen());
    expect(find.textContaining('En retard : 12 jours'), findsOneWidget);
  });
}
