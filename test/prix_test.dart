import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mtandao/db.dart';
import 'package:mtandao/format.dart';
import 'package:mtandao/models.dart';
import 'package:mtandao/repo.dart';
import 'package:mtandao/screens/import_flow.dart';
import 'package:mtandao/screens/lots_screen.dart';
import 'package:mtandao/screens/saisie_manuelle.dart';
import 'package:mtandao/screens/settings_screen.dart';
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
    tmp = Directory.systemTemp.createTempSync('mtandao_prix_');
    final db = await databaseFactoryFfi.openDatabase(
      '${tmp.path}/prix.db',
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

  /// Base neuve : forfait 24 h à 1 000 CDF, forfait 1 h à 500 CDF.
  late Forfait jour;
  late Forfait heure;
  setUp(() async {
    final db = repo.db;
    await db.delete('ticket_images');
    await db.delete('tickets');
    await db.delete('lots');
    await db.delete('forfaits', where: 'duree_minutes != 1440');
    await db.update('forfaits', {'prix': 1000});
    final id = await repo.ajouterForfait('1 heure', 60, 500);
    final tous = await repo.forfaits();
    jour = tous.firstWhere((f) => f.dureeMinutes == 1440);
    heure = tous.firstWhere((f) => f.id == id);
    appState.forfaitActifId = null;
  });

  Future<int> lot(Forfait f, String prefixe, int n, {int? prix}) async {
    final r = await repo.importerLot(
      nom: 'Lot $prefixe',
      forfait: f,
      source: 'texte',
      tickets: [for (var i = 1; i <= n; i++) ParsedTicket(code: '$prefixe$i')],
      prix: prix,
    );
    return r.lotId!;
  }

  group('Prix dans la base', () {
    test('un lot importé prend le prix du forfait, ou le prix donné', () async {
      final a = await lot(jour, 'A', 2);
      final b = await lot(jour, 'B', 2, prix: 800);
      expect((await repo.ticketsDuLot(a)).map((t) => t.prix), [1000, 1000]);
      expect((await repo.ticketsDuLot(b)).map((t) => t.prix), [800, 800]);
      // Le forfait n'a pas changé.
      expect((await repo.forfaits()).firstWhere((f) => f.id == jour.id).prix, 1000);
    });

    test('modifier le prix d\'un lot : seulement les tickets non vendus', () async {
      final id = await lot(jour, 'A', 4);
      final ts = await repo.ticketsDuLot(id);
      await repo.vendre(ts[0].id);
      await repo.vendre(ts[1].id);

      final n = await repo.modifierPrixLot(id, 1200);
      expect(n, 2);
      final apres = await repo.ticketsDuLot(id);
      expect(apres.map((t) => t.prix), [1000, 1000, 1200, 1200]);
      // Les ventes passées gardent leur prix : les rapports ne bougent pas.
      final ventes = await repo.ventes(DateTime.now().subtract(const Duration(hours: 1)),
          DateTime.now().add(const Duration(hours: 1)));
      expect(ventes.map((v) => v.prix), [1000, 1000]);
      expect((await repo.stats(id)).montant, 2000);
      // Les prochaines ventes se font au nouveau prix.
      await repo.vendre(apres[2].id);
      expect((await repo.stats(id)).montant, 3200);
    });

    test('modifier le prix du stock d\'un forfait : tous les lots, sans les vendus', () async {
      final a = await lot(jour, 'A', 2);
      final b = await lot(jour, 'B', 2);
      final autre = await lot(heure, 'H', 2);
      await repo.vendre((await repo.ticketsDuLot(a)).first.id);

      expect(await repo.stockForfait(jour.id), 3);
      final n = await repo.modifierPrixStockForfait(jour.id, 1500);
      expect(n, 3);
      expect((await repo.ticketsDuLot(a)).map((t) => t.prix), [1000, 1500]);
      expect((await repo.ticketsDuLot(b)).map((t) => t.prix), [1500, 1500]);
      expect((await repo.ticketsDuLot(autre)).map((t) => t.prix), [500, 500]); // autre forfait
    });

    test('prix du lot : commun, ou inconnu s\'il diffère ou s\'il ne reste rien', () async {
      final id = await lot(jour, 'A', 3, prix: 900);
      expect(await repo.prixDuLot(id), 900);
      final ts = await repo.ticketsDuLot(id);
      await repo.db.update('tickets', {'prix': 1100}, where: 'id = ?', whereArgs: [ts[0].id]);
      expect(await repo.prixDuLot(id), isNull); // prix différents
      for (final t in ts) {
        await repo.vendre(t.id);
      }
      expect(await repo.prixDuLot(id), isNull); // plus rien à vendre
    });

    test('un prix négatif est refusé, zéro est permis', () async {
      final id = await lot(jour, 'A', 1);
      expect(() => repo.modifierPrixLot(id, -1), throwsArgumentError);
      expect(() => repo.modifierPrixStockForfait(jour.id, -5), throwsArgumentError);
      expect(await repo.modifierPrixLot(id, 0), 1);
      expect((await repo.ticketsDuLot(id)).single.prix, 0);
    });

    test('ajouter des tickets à un lot : le prix du lot, ou celui qu\'on donne', () async {
      final id = await lot(jour, 'A', 2, prix: 800);
      await repo.ajouterTickets(id, [ParsedTicket(code: 'N1')]);
      await repo.ajouterTickets(id, [ParsedTicket(code: 'N2')], prix: 1300);
      expect((await repo.ticketsDuLot(id)).map((t) => t.prix), [800, 800, 800, 1300]);
    });
  });

  group('Fenêtre d\'import : prix', () {
    Future<Future<ConfirmationImport?> Function()> ouvrir(
      WidgetTester t, {
      int? prixDetecte,
      int? duree,
    }) async {
      ConfirmationImport? resultat;
      var fini = false;
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              resultat = await showDialog<ConfirmationImport>(
                context: context,
                builder: (_) => DialogueConfirmationImport(
                  nomParDefaut: 'Mon PDF',
                  forfaits: [heure, jour],
                  nombre: 10,
                  doublons: 0,
                  ignorees: 0,
                  dureeMinutes: duree,
                  source: 'texte',
                  prixDetecte: prixDetecte,
                ),
              );
              fini = true;
            },
            child: const Text('ouvrir'),
          ),
        ),
      ));
      return () async {
        expect(fini, isTrue);
        return resultat;
      };
    }

    Future<Future<ConfirmationImport?> Function()> demarrer(WidgetTester t,
        {int? prixDetecte, int? duree}) async {
      final f = await ouvrir(t, prixDetecte: prixDetecte, duree: duree);
      await t.pumpAndSettle();
      await t.tap(find.text('ouvrir'));
      await t.pumpAndSettle();
      return f;
    }

    String champPrix(WidgetTester t) => t
        .widget<TextField>(find.widgetWithText(TextField, 'Prix de chaque ticket (CDF)'))
        .controller!
        .text;

    testWidgets('sans prix dans le PDF : le prix du forfait est proposé', (t) async {
      final resultat = await demarrer(t, duree: 1440);
      expect(champPrix(t), '1000');
      expect(find.textContaining('Prix du forfait'), findsOneWidget);
      await t.tap(find.text('Importer'));
      await t.pumpAndSettle();
      final c = (await resultat())!;
      expect(c.prix, 1000);
      expect(c.retenirPrix, isFalse);
    });

    testWidgets('avec un prix lu dans le PDF : il est proposé, et il ne bouge pas si on change de forfait', (t) async {
      await demarrer(t, prixDetecte: 750, duree: 1440);
      expect(champPrix(t), '750');
      expect(find.textContaining('Prix lu dans le PDF'), findsOneWidget);

      await t.tap(find.byType(DropdownButton<int>));
      await t.pumpAndSettle();
      await t.tap(find.textContaining('1 heure').last);
      await t.pumpAndSettle();
      expect(champPrix(t), '750');
    });

    testWidgets('sans prix lu : le prix suit le forfait choisi, tant qu\'on ne l\'a pas modifié', (t) async {
      await demarrer(t, duree: 1440);
      expect(champPrix(t), '1000');
      await t.tap(find.byType(DropdownButton<int>));
      await t.pumpAndSettle();
      await t.tap(find.textContaining('1 heure').last);
      await t.pumpAndSettle();
      expect(champPrix(t), '500');

      // Une fois modifié à la main, il ne suit plus.
      await t.enterText(find.widgetWithText(TextField, 'Prix de chaque ticket (CDF)'), '650');
      await t.pumpAndSettle();
      await t.tap(find.byType(DropdownButton<int>));
      await t.pumpAndSettle();
      await t.tap(find.textContaining('1 jour').last);
      await t.pumpAndSettle();
      expect(champPrix(t), '650');
    });

    testWidgets('prix modifié : retourné, avec la case « Retenir ce prix »', (t) async {
      final resultat = await demarrer(t, duree: 1440);
      expect(find.textContaining('Retenir ce prix'), findsNothing); // identique : pas de case
      await t.enterText(find.widgetWithText(TextField, 'Prix de chaque ticket (CDF)'), '1200');
      await t.pumpAndSettle();
      expect(find.textContaining('Retenir ce prix'), findsOneWidget);
      await t.tap(find.byType(CheckboxListTile));
      await t.pumpAndSettle();
      await t.tap(find.text('Importer'));
      await t.pumpAndSettle();
      final c = (await resultat())!;
      expect(c.prix, 1200);
      expect(c.retenirPrix, isTrue);
      expect(c.forfait.id, jour.id);
    });

    testWidgets('prix vide : impossible d\'importer', (t) async {
      await demarrer(t, duree: 1440);
      await t.enterText(find.widgetWithText(TextField, 'Prix de chaque ticket (CDF)'), '');
      await t.pumpAndSettle();
      final bouton = t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Importer'));
      expect(bouton.onPressed, isNull);
    });
  });

  group('Écrans : modifier un prix', () {
    Future<void> grand(WidgetTester t) async {
      t.view.physicalSize = const Size(800, 2200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
    }

    testWidgets('détail d\'un lot : le prix des tickets non vendus change, pas celui des vendus', (t) async {
      await grand(t);
      late int id;
      await t.runAsync(() async {
        id = await lot(jour, 'A', 3);
        await repo.vendre((await repo.ticketsDuLot(id)).first.id);
      });
      await t.pumpWidget(MaterialApp(locale: const Locale('fr'), home: LotDetailScreen(lotId: id)));
      await attendre(t);

      await t.tap(find.byTooltip('Modifier le prix des tickets non vendus'));
      await attendre(t);
      await t.pumpAndSettle();
      expect(find.textContaining('2 tickets non vendus dans ce lot, actuellement à ${cdf(1000)}'), findsOneWidget);
      expect(find.textContaining('Les 1 déjà vendus gardent leur prix'), findsOneWidget);

      await t.enterText(find.widgetWithText(TextField, 'Nouveau prix (CDF)'), '1300');
      await t.tap(find.text('Enregistrer'));
      await attendre(t);
      await t.pumpAndSettle();

      final ts = (await t.runAsync(() => repo.ticketsDuLot(id)))!;
      expect(ts.map((x) => x.prix), [1000, 1300, 1300]);
      expect(find.textContaining('Prix de 2 tickets : ${cdf(1300)}'), findsOneWidget);
    });

    testWidgets('détail d\'un lot entièrement vendu : rien à modifier', (t) async {
      await grand(t);
      late int id;
      await t.runAsync(() async {
        id = await lot(jour, 'A', 1);
        await repo.vendre((await repo.ticketsDuLot(id)).first.id);
      });
      await t.pumpWidget(MaterialApp(locale: const Locale('fr'), home: LotDetailScreen(lotId: id)));
      await attendre(t);
      await t.tap(find.byTooltip('Modifier le prix des tickets non vendus'));
      await attendre(t);
      await t.pumpAndSettle();
      expect(find.textContaining('rien à modifier'), findsOneWidget);
    });

    testWidgets('forfait : « Appliquer aussi » aux tickets non vendus', (t) async {
      await grand(t);
      late int id;
      await t.runAsync(() async {
        id = await lot(jour, 'A', 3);
        await repo.vendre((await repo.ticketsDuLot(id)).first.id);
      });
      await t.pumpWidget(const MaterialApp(locale: Locale('fr'), home: ForfaitsScreen()));
      await attendre(t);

      await t.tap(find.textContaining('1 jour').first);
      await attendre(t);
      await t.pumpAndSettle();
      expect(find.textContaining('Appliquer aussi aux'), findsNothing); // prix inchangé
      await t.enterText(find.widgetWithText(TextField, 'Prix (CDF)'), '1400');
      await t.pumpAndSettle();
      expect(find.textContaining('Appliquer aussi aux 2 tickets non vendus'), findsOneWidget);
      await t.tap(find.byType(CheckboxListTile));
      await t.pumpAndSettle();
      await t.tap(find.text('Enregistrer'));
      await attendre(t);
      await t.pumpAndSettle();

      final f = (await t.runAsync(() => repo.forfaits()))!.firstWhere((x) => x.id == jour.id);
      expect(f.prix, 1400);
      expect((await t.runAsync(() => repo.ticketsDuLot(id)))!.map((x) => x.prix), [1000, 1400, 1400]);
    });

    testWidgets('forfait : prix changé sans « Appliquer aussi » : le stock garde son prix', (t) async {
      await grand(t);
      late int id;
      await t.runAsync(() async {
        id = await lot(jour, 'A', 2);
      });
      await t.pumpWidget(const MaterialApp(locale: Locale('fr'), home: ForfaitsScreen()));
      await attendre(t);
      await t.tap(find.textContaining('1 jour').first);
      await attendre(t);
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextField, 'Prix (CDF)'), '1400');
      await t.pumpAndSettle();
      await t.tap(find.text('Enregistrer'));
      await attendre(t);
      await t.pumpAndSettle();
      expect((await t.runAsync(() => repo.ticketsDuLot(id)))!.map((x) => x.prix), [1000, 1000]);
      expect((await t.runAsync(() => repo.forfaits()))!.firstWhere((x) => x.id == jour.id).prix, 1400);
    });

    testWidgets('saisie manuelle : prix du forfait proposé, modifiable', (t) async {
      await grand(t);
      await t.pumpWidget(const MaterialApp(locale: Locale('fr'), home: SaisieManuelleScreen()));
      await attendre(t);

      final champ = find.widgetWithText(TextField, 'Prix de chaque ticket (CDF)');
      expect(t.widget<TextField>(champ).controller!.text, '500'); // 1 h : premier par durée
      await t.enterText(champ, '650');
      await t.enterText(find.widgetWithText(TextField, 'Codes (un par ligne)'), 'X1\nX2');
      await t.pumpAndSettle();
      await t.tap(find.text('Créer le lot'));
      await attendre(t);
      await t.pumpAndSettle();

      final lots = (await t.runAsync(() => repo.lots()))!;
      final ts = (await t.runAsync(() => repo.ticketsDuLot(lots.single.id)))!;
      expect(ts.map((x) => x.prix), [650, 650]);
    });
  });
}
