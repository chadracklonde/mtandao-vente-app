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
    await db.delete('forfaits', where: 'duree_minutes != 1440');
    appState.forfaitActifId = null;
    await db.delete('settings',
        where:
            "cle IN ('lot_actif','seuil_stock','vendeur_actif','derniere_sauvegarde','taux_dollar','forfait_actif') OR cle LIKE 'pin\\_v%' ESCAPE '\\'");
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
    expect(find.textContaining('Plus que 4 tickets'), findsOneWidget);
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

  // -------------------------------------------------- plusieurs forfaits
  /// Ajoute un forfait avec un lot de [n] tickets (codes préfixe1, préfixe2…).
  Future<int> ajouterForfaitAvecLot(WidgetTester t, String nom, int minutes,
      int prix, String prefixe, int n) async {
    late int id;
    await t.runAsync(() async {
      id = await repo.ajouterForfait(nom, minutes, prix);
      final f = (await repo.forfaits()).firstWhere((x) => x.id == id);
      await repo.importerLot(
        nom: 'Lot $nom',
        forfait: f,
        source: 'texte',
        tickets: [for (var i = 1; i <= n; i++) ParsedTicket(code: '$prefixe$i')],
      );
    });
    return id;
  }

  testWidgets('un seul forfait : pas de pastilles, l\'écran reste simple', (t) async {
    await afficher(t);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('Plus de tickets'), findsNothing);
  });

  testWidgets('plusieurs forfaits : pastilles classées par durée avec le stock', (t) async {
    await ajouterForfaitAvecLot(t, '1 semaine', 10080, 5000, 'S', 2);
    await ajouterForfaitAvecLot(t, '1 heure', 60, 500, 'H', 3);
    await afficher(t);

    expect(find.byType(ChoiceChip), findsNWidgets(3));
    final heure = t.getTopLeft(find.widgetWithText(ChoiceChip, '1 h  3'));
    final jour = t.getTopLeft(find.widgetWithText(ChoiceChip, '1 jour  4'));
    final semaine = t.getTopLeft(find.widgetWithText(ChoiceChip, '1 semaine  2'));
    // 1 h, puis 1 jour, puis 1 semaine (de gauche à droite).
    expect(heure.dx < jour.dx && jour.dx < semaine.dx, isTrue);
    // Le forfait choisi par défaut est le premier qui a du stock : 1 h.
    expect(find.text('1 HEURE  ·  ${cdf(500)}'), findsOneWidget);
    expect(find.text('H1'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('un appui sur une pastille change de forfait, et le choix est mémorisé', (t) async {
    final semaine = await ajouterForfaitAvecLot(t, '1 semaine', 10080, 5000, 'S', 2);
    await afficher(t);
    expect(find.text('T1'), findsWidgets); // 24 h (1 h n'existe pas ici)

    await t.tap(find.widgetWithText(ChoiceChip, '1 semaine  2'));
    await attendre(t);
    await t.pumpAndSettle();

    expect(find.text('1 SEMAINE  ·  ${cdf(5000)}'), findsOneWidget);
    expect(find.text('S1'), findsWidgets);
    expect(find.text('T1'), findsNothing);
    expect(await t.runAsync(() => repo.getSetting('forfait_actif')), '$semaine');
  });

  testWidgets('la vente touche seulement le forfait affiché, au bon prix', (t) async {
    await ajouterForfaitAvecLot(t, '1 heure', 60, 500, 'H', 3);
    await afficher(t);
    await vendreAuComptoir(t);

    final tout = (await t.runAsync(() => repo.profils()))!;
    final heure = tout.firstWhere((p) => p.forfait.nom == '1 heure');
    final jour = tout.firstWhere((p) => p.forfait.dureeMinutes == 1440);
    expect(heure.vendus, 1);
    expect(heure.montant, 500);
    expect(jour.vendus, 0); // le 24 h n'a pas bougé
    expect(find.textContaining('Ticket H1 vendu'), findsOneWidget);
    expect(find.text('H2'), findsWidgets);
    // Total du jour, tous forfaits.
    expect(find.textContaining('Aujourd\'hui, tous forfaits : 1 ticket'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('le total du jour réunit tous les forfaits', (t) async {
    await ajouterForfaitAvecLot(t, '1 heure', 60, 500, 'H', 3);
    await afficher(t);
    await vendreAuComptoir(t); // 1 h : 500
    await t.pump(const Duration(seconds: 5));
    await t.tap(find.widgetWithText(ChoiceChip, '1 jour  4'));
    await attendre(t);
    await t.pumpAndSettle();
    await vendreAuComptoir(t); // 24 h : 1 000
    expect(find.textContaining('Aujourd\'hui, tous forfaits : 2 tickets  ·  ${cdf(1500)}'),
        findsOneWidget);
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('stock bas : l\'alerte nomme le forfait affiché', (t) async {
    await ajouterForfaitAvecLot(t, '1 semaine', 10080, 5000, 'S', 2);
    await afficher(t);
    await t.tap(find.widgetWithText(ChoiceChip, '1 semaine  2'));
    await attendre(t);
    await t.pumpAndSettle();
    expect(find.textContaining('Plus que 2 tickets « 1 semaine »'), findsOneWidget);
  });

  testWidgets('forfait épuisé : message clair, on garde la pastille, l\'autre forfait reste vendable', (t) async {
    await ajouterForfaitAvecLot(t, '1 semaine', 10080, 5000, 'S', 1);
    await afficher(t);
    await t.tap(find.widgetWithText(ChoiceChip, '1 semaine  1'));
    await attendre(t);
    await t.pumpAndSettle();
    await vendreAuComptoir(t);
    await t.pump(const Duration(seconds: 5));
    await attendre(t);

    expect(find.text('Plus de tickets'), findsOneWidget);
    expect(find.textContaining('Tous les tickets « 1 semaine » sont vendus'), findsOneWidget);
    expect(find.text('Choisissez un autre forfait ci-dessus.'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '1 semaine  0'), findsOneWidget);

    await t.tap(find.widgetWithText(ChoiceChip, '1 jour  4'));
    await attendre(t);
    await t.pumpAndSettle();
    expect(find.text('T1'), findsWidgets);
    expect(find.text('Plus de tickets'), findsNothing);
  });

  testWidgets('à l\'ouverture : un forfait sans ticket est remplacé par le premier qui en a', (t) async {
    final heure = await ajouterForfaitAvecLot(t, '1 heure', 60, 500, 'H', 1);
    await t.runAsync(() async {
      final h = (await repo.prochainTicketForfait(heure))!;
      await repo.vendre(h.id);
      await appState.definirForfaitActif(heure);
    });
    await afficher(t);
    expect(find.text('T1'), findsWidgets); // on est tombé sur le 24 h
    expect(find.text('Plus de tickets'), findsNothing);
  });

  testWidgets('Annuler remet en vente la dernière vente, même d\'un autre forfait', (t) async {
    await ajouterForfaitAvecLot(t, '1 heure', 60, 500, 'H', 3);
    await afficher(t);
    await vendreAuComptoir(t); // vente de H1
    await t.pump(const Duration(seconds: 5));
    await t.tap(find.widgetWithText(ChoiceChip, '1 jour  4'));
    await attendre(t);
    await t.pumpAndSettle();

    await t.tap(find.widgetWithText(OutlinedButton, 'Annuler'));
    await attendre(t);
    await t.pumpAndSettle();
    expect(find.textContaining('Le ticket H1 (1 h) sera remis en vente'), findsOneWidget);
    await t.tap(find.text('Oui, annuler'));
    await attendre(t);
    await t.pumpAndSettle();

    final h = (await t.runAsync(() => repo.profils()))!.firstWhere((p) => p.forfait.nom == '1 heure');
    expect(h.vendus, 0);
    expect(find.textContaining('Ticket H1 (1 h) remis en vente'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('deux forfaits de même durée : les pastilles montrent leur nom', (t) async {
    await ajouterForfaitAvecLot(t, 'Jour promo', 1440, 800, 'P', 2);
    await afficher(t);
    expect(find.widgetWithText(ChoiceChip, 'Jour promo  2'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '1 jour (24 h)  4'), findsOneWidget);
  });

  testWidgets('Annuler : une fois seulement, impossible de remonter à la vente d\'avant', (t) async {
    await afficher(t);
    await vendreAuComptoir(t); // T1
    await t.pump(const Duration(seconds: 5));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await vendreAuComptoir(t); // T2
    await t.pump(const Duration(seconds: 5));

    await t.tap(find.widgetWithText(OutlinedButton, 'Annuler'));
    await attendre(t);
    await t.pumpAndSettle();
    expect(find.textContaining('Une vente ne peut être annulée qu\'une seule fois'), findsOneWidget);
    await t.tap(find.text('Oui, annuler'));
    await attendre(t);
    await t.pumpAndSettle();
    var ts = (await t.runAsync(() => repo.ticketsDuLot(lotId)))!;
    expect(ts.map((x) => x.vendu), [true, false, false, false]);
    await t.pump(const Duration(seconds: 5));

    // Deuxième appui : T1 est plus ancienne que l'annulation, elle reste vendue.
    await t.tap(find.widgetWithText(OutlinedButton, 'Annuler'));
    await attendre(t);
    await t.pumpAndSettle();
    expect(find.textContaining('Seule la vente qui vient d\'être faite peut être annulée'), findsOneWidget);
    expect(find.text('Oui, annuler'), findsNothing);
    ts = (await t.runAsync(() => repo.ticketsDuLot(lotId)))!;
    expect(ts.first.vendu, isTrue);
    await t.pump(const Duration(seconds: 8));
  });
}
