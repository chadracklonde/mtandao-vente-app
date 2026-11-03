import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mtandao/db.dart';
import 'package:mtandao/format.dart';
import 'package:mtandao/models.dart';
import 'package:mtandao/repo.dart';
import 'package:mtandao/screens/vente_screen.dart';
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
  late int lotId;

  setUpAll(() async {
    sqfliteFfiInit();
    await initializeDateFormatting('fr');
    tmp = Directory.systemTemp.createTempSync('mtandao_vente_');
    final db = await databaseFactoryFfi.openDatabase(
      '${tmp.path}/vente.db',
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

  /// Base neuve à chaque test : un lot de 4 tickets de 1 000 CDF.
  setUp(() async {
    final db = repo.db;
    await db.delete('ticket_images');
    await db.delete('tickets');
    await db.delete('lots');
    await db.delete('clients');
    await db.delete('vendeurs');
    await db.delete('settings',
        where:
            "cle IN ('lot_actif','seuil_stock','vendeur_actif','derniere_sauvegarde','taux_dollar') OR cle LIKE 'pin\\_v%' ESCAPE '\\'");
    final forfait = (await repo.forfaits()).first;
    final lot = await repo.importerLot(
      nom: 'Lot du jour',
      forfait: forfait,
      source: 'texte',
      tickets: [for (var i = 1; i <= 4; i++) ParsedTicket(code: 'T$i', numero: i)],
    );
    lotId = lot.lotId!;
    appState.lotActifId = null;
  });

  Future<void> afficher(WidgetTester t, {VoidCallback? surReglages}) async {
    t.view.physicalSize = const Size(800, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      home: VenteScreen(surReglages: surReglages),
    ));
    await attendre(t);
  }

  Future<void> vendreAuComptoir(WidgetTester t) async {
    await t.tap(find.text('VENDU'));
    await attendre(t);
    await t.pumpAndSettle();
    await t.tap(find.text('Oui, vendu'));
    await attendre(t);
    await t.pumpAndSettle();
  }

  testWidgets('affiche le premier ticket et les compteurs', (t) async {
    await afficher(t);
    expect(find.text('T1'), findsWidgets);
    expect(find.text('VENDU'), findsOneWidget);
    expect(find.text('déjà vendus'), findsOneWidget);
    expect(find.text('restants'), findsOneWidget);
    expect(find.text('4'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('vente en espèces : le ticket suivant apparaît, la bannière ne masque pas VENDU', (t) async {
    await afficher(t);
    await vendreAuComptoir(t);

    // T1 est vendu en espèces, T2 est maintenant proposé.
    final t1 = (await t.runAsync(() => repo.ticketsDuLot(lotId)))!.first;
    expect(t1.vendu, isTrue);
    expect(t1.paiement, Paiement.especes);
    expect(find.text('T2'), findsWidgets);
    expect(find.textContaining('Ticket T1 vendu'), findsOneWidget);
    // Le bouton VENDU reste visible et utilisable pour enchaîner.
    expect(find.text('VENDU'), findsOneWidget);
    expect(find.text('ANNULER'), findsOneWidget);
    expect(find.textContaining(cdf(1000)), findsWidgets);
    await t.pump(const Duration(seconds: 5)); // laisse la bannière disparaître
    expect(t.takeException(), isNull);
  });

  testWidgets('ANNULER dans la bannière remet le ticket en vente', (t) async {
    await afficher(t);
    await vendreAuComptoir(t);
    await t.tap(find.text('ANNULER'));
    await attendre(t);
    await t.pumpAndSettle();

    final t1 = (await t.runAsync(() => repo.ticketsDuLot(lotId)))!.first;
    expect(t1.vendu, isFalse);
    expect(find.textContaining('remis en vente'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('« Non » ne vend rien', (t) async {
    await afficher(t);
    await t.tap(find.text('VENDU'));
    await attendre(t);
    await t.pumpAndSettle();
    await t.tap(find.text('Non'));
    await attendre(t);
    final ts = (await t.runAsync(() => repo.ticketsDuLot(lotId)))!;
    expect(ts.where((x) => x.vendu), isEmpty);
  });

  testWidgets('vente à crédit avec un nouveau client : une dette est créée', (t) async {
    await afficher(t);
    await t.tap(find.text('VENDU'));
    await attendre(t);
    await t.pumpAndSettle();
    await t.tap(find.text('À crédit'));
    await t.pumpAndSettle();
    await t.tap(find.text('Nouveau client'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Nom'), 'Marie');
    await t.tap(find.text('Ajouter'));
    await attendre(t);
    await t.pumpAndSettle();
    await t.tap(find.text('Oui, vendu'));
    await attendre(t);
    await t.pumpAndSettle();

    final dettes = (await t.runAsync(() => repo.dettes()))!;
    expect(dettes, hasLength(1));
    expect(dettes.single.clientNom, 'Marie');
    expect(dettes.single.code, 'T1');
    expect(find.textContaining('à crédit (Marie)'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('alerte de stock bas, avec le seuil par défaut (20)', (t) async {
    await afficher(t);
    expect(find.textContaining('Plus que 4 tickets en stock'), findsOneWidget);
    expect(find.text('Importer'), findsOneWidget);
  });

  testWidgets('seuil à 0 : pas d\'alerte de stock', (t) async {
    await t.runAsync(() => repo.setSetting(cleSeuilStock, '0'));
    await afficher(t);
    expect(find.textContaining('en stock'), findsNothing);
  });

  testWidgets('alerte de sauvegarde seulement s\'il y a des ventes sans sauvegarde récente', (t) async {
    await afficher(t);
    expect(find.textContaining('ne sont pas sauvegardées'), findsNothing); // aucune vente

    await t.runAsync(() async {
      final t1 = (await repo.ticketsDuLot(lotId)).first;
      await repo.vendre(t1.id);
    });
    appState.changed();
    await attendre(t);
    expect(find.textContaining('Vos ventes ne sont pas sauvegardées'), findsOneWidget);

    // Une sauvegarde récente fait disparaître l'alerte.
    await t.runAsync(() => repo.setSetting(
        'derniere_sauvegarde', '${DateTime.now().millisecondsSinceEpoch}'));
    appState.changed();
    await attendre(t);
    expect(find.textContaining('sauvegardées'), findsNothing);
  });

  testWidgets('ticket défectueux : il est sauté, et le lot affiche les bons restants', (t) async {
    await t.runAsync(() async {
      final ts = await repo.ticketsDuLot(lotId);
      await repo.signalerDefectueux(ts[0].id);
    });
    await afficher(t);
    // T1 est défectueux : on propose T2.
    expect(find.text('T2'), findsWidgets);
    expect(find.text('T1'), findsNothing);
    expect(find.text('3'), findsWidgets); // 3 restants
  });

  testWidgets('sans aucun lot : état vide avec import et saisie manuelle', (t) async {
    await t.runAsync(() => repo.supprimerLot(lotId));
    await afficher(t);
    expect(find.text('Aucun ticket à vendre'), findsOneWidget);
    expect(find.text('Importer un PDF'), findsOneWidget);
    expect(find.text('Saisir des codes à la main'), findsOneWidget);
  });

  Future<void> saisir(WidgetTester t, String code) async {
    for (final c in code.split('')) {
      await t.tap(find.widgetWithText(TextButton, c));
      await t.pump();
    }
    await attendre(t);
    await t.pumpAndSettle();
  }

  testWidgets('vendeur protégé : son code est demandé, un mauvais code est refusé', (t) async {
    late int anne;
    await t.runAsync(() async {
      anne = await repo.ajouterVendeur('Anne');
      await repo.definirPinVendeur(anne, '1234');
      await repo.ajouterVendeur('Luc');
    });
    await afficher(t);
    expect(find.text('Choisir le vendeur'), findsOneWidget);

    await t.tap(find.text('Choisir le vendeur'));
    await t.pumpAndSettle();
    await t.tap(find.text('Anne'));
    await t.pumpAndSettle();
    expect(find.text('Code de Anne'), findsOneWidget);

    await saisir(t, '0000');
    expect(find.textContaining('Code incorrect'), findsOneWidget);
    expect(await t.runAsync(() => repo.vendeurActifId()), isNull);

    await saisir(t, '1234');
    expect(find.text('Code de Anne'), findsNothing);
    expect(await t.runAsync(() => repo.vendeurActifId()), anne);
    await attendre(t);
    expect(find.text('Anne'), findsOneWidget); // la pastille affiche le vendeur
  });

  testWidgets('vendeur sans code : choisi directement', (t) async {
    late int luc;
    await t.runAsync(() async {
      luc = await repo.ajouterVendeur('Luc');
    });
    await afficher(t);
    await t.tap(find.text('Choisir le vendeur'));
    await t.pumpAndSettle();
    await t.tap(find.text('Luc'));
    await attendre(t);
    await t.pumpAndSettle();
    expect(find.textContaining('Code de'), findsNothing);
    expect(await t.runAsync(() => repo.vendeurActifId()), luc);
  });

  testWidgets('vente en dollars : le message donne le montant reçu', (t) async {
    await t.runAsync(() => repo.setSetting(cleTauxDollar, '2800'));
    await afficher(t);
    await t.tap(find.text('VENDU'));
    await attendre(t);
    await t.pumpAndSettle();
    await t.tap(find.text('Dollars (USD)'));
    await t.pumpAndSettle();
    await t.tap(find.text('Oui, vendu'));
    await attendre(t);
    await t.pumpAndSettle();

    final t1 = (await t.runAsync(() => repo.ticketsDuLot(lotId)))!.first;
    expect(t1.devise, Devise.usd);
    expect(t1.montantDevise, 36);
    expect(find.textContaining('reçu 0,36 USD'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
  });
}
