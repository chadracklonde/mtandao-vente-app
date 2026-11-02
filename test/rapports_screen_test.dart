import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mtandao/db.dart';
import 'package:mtandao/format.dart';
import 'package:mtandao/models.dart';
import 'package:mtandao/repo.dart';
import 'package:mtandao/screens/rapports_screen.dart';
import 'package:mtandao/state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Laisse le temps aux accès réels à la base de se terminer.
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
    tmp = Directory.systemTemp.createTempSync('mtandao_ecran_');
    final db = await databaseFactoryFfi.openDatabase(
      '${tmp.path}/ecran.db',
      options: OpenDatabaseOptions(
        version: AppDb.version,
        onConfigure: AppDb.configurer,
        onCreate: AppDb.creer,
      ),
    );
    repo = Repo(db);
    appState.utiliserPourTest(repo);

    final forfait = (await repo.forfaits()).first;
    final lot = await repo.importerLot(
      nom: 'Lot',
      forfait: forfait,
      source: 'texte',
      tickets: [for (var i = 1; i <= 6; i++) ParsedTicket(code: 'T$i')],
    );
    final ts = await repo.ticketsDuLot(lot.lotId!);
    final marie = await repo.ajouterClient('Marie');
    final jean = await repo.ajouterVendeur('Jean');
    await repo.vendre(ts[0].id, vendeurId: jean); // espèces
    await repo.vendre(ts[1].id, paiement: Paiement.mobile);
    await repo.vendre(ts[2].id, paiement: Paiement.credit, clientId: marie);
    await repo.vendre(ts[3].id, paiement: Paiement.offert);
  });

  tearDownAll(() => tmp.deleteSync(recursive: true));

  Future<void> afficher(WidgetTester t) async {
    // Grand écran : la liste ne construit que ce qui est visible.
    t.view.physicalSize = const Size(800, 4000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(
      locale: Locale('fr'),
      home: RapportsScreen(),
    ));
    await attendre(t);
  }

  testWidgets('le jour : encaissé, à recevoir, offerts, vendeur et graphiques', (t) async {
    await afficher(t);

    // 2 000 CDF encaissés (espèces + mobile), 1 000 à recevoir, 1 offert.
    expect(find.text(cdf(2000)), findsWidgets);
    expect(find.text('4 tickets vendus  ·  1 offert'), findsOneWidget);
    expect(find.text('À recevoir : ${cdf(1000)}'), findsOneWidget);
    expect(find.text('Heures de pointe'), findsOneWidget);
    expect(find.textContaining('Heure la plus chargée'), findsOneWidget);
    // Par mode de paiement et par vendeur.
    expect(find.text('Par mode de paiement'), findsOneWidget);
    expect(find.text('Mobile money'), findsWidgets);
    expect(find.text('Par vendeur'), findsOneWidget);
    expect(find.text('Jean'), findsWidgets);
    expect(find.text('Sans vendeur'), findsOneWidget);
    // Détail de la journée : 4 lignes de vente.
    expect(find.text('Ventes de la journée'), findsOneWidget);
    expect(find.text('T1'), findsOneWidget);
    expect(find.text('T4'), findsOneWidget);
    expect(find.text('T5'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('la semaine : graphique d\'évolution et détail par jour', (t) async {
    await afficher(t);
    await t.tap(find.text('Semaine'));
    await attendre(t);

    expect(find.text('Évolution (argent encaissé par jour)'), findsOneWidget);
    expect(find.text('Par jour'), findsOneWidget);
    expect(find.text('Montant encaissé'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('le mois et le retour à une période passée sans vente', (t) async {
    await afficher(t);
    await t.tap(find.text('Mois'));
    await attendre(t);
    expect(find.text('Évolution (argent encaissé par jour)'), findsOneWidget);

    await t.tap(find.byTooltip('Précédent'));
    await attendre(t);
    expect(find.text('Aucune vente sur cette période.'), findsOneWidget);
    expect(find.text("Revenir à aujourd'hui"), findsOneWidget);
    // Pas de graphique ni de détail quand il n'y a rien.
    expect(find.text('Heures de pointe'), findsNothing);

    await t.tap(find.text("Revenir à aujourd'hui"));
    await attendre(t);
    expect(find.text('Aucune vente sur cette période.'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('le menu propose texte, CSV et PDF', (t) async {
    await afficher(t);
    await t.tap(find.byTooltip('Partager ou exporter le rapport'));
    await t.pumpAndSettle();
    expect(find.text('Partager en texte'), findsOneWidget);
    expect(find.text('Exporter en CSV (tableur)'), findsOneWidget);
    expect(find.text('Exporter en PDF'), findsOneWidget);
  });
}
