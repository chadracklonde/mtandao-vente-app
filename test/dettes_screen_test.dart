import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mtandao/db.dart';
import 'package:mtandao/format.dart';
import 'package:mtandao/models.dart';
import 'package:mtandao/repo.dart';
import 'package:mtandao/screens/dettes_screen.dart';
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
    tmp = Directory.systemTemp.createTempSync('mtandao_dettes_');
    final db = await databaseFactoryFfi.openDatabase(
      '${tmp.path}/dettes.db',
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
    final db = repo.db;
    await db.delete('tickets');
    await db.delete('lots');
    await db.delete('clients');
    final forfait = (await repo.forfaits()).first;
    final lot = await repo.importerLot(
      nom: 'Lot',
      forfait: forfait,
      source: 'texte',
      tickets: [for (var i = 1; i <= 5; i++) ParsedTicket(code: 'D$i')],
    );
    final ts = await repo.ticketsDuLot(lot.lotId!);
    final marie = await repo.ajouterClient('Marie', telephone: '0812');
    final paul = await repo.ajouterClient('Paul');
    await repo.vendre(ts[0].id, paiement: Paiement.credit, clientId: marie);
    await repo.vendre(ts[1].id, paiement: Paiement.credit, clientId: marie);
    await repo.vendre(ts[2].id, paiement: Paiement.credit, clientId: paul);
  });

  Future<void> afficher(WidgetTester t) async {
    t.view.physicalSize = const Size(800, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(
      locale: Locale('fr'),
      home: DettesScreen(),
    ));
    await attendre(t);
  }

  testWidgets('total à recevoir et dettes regroupées par client', (t) async {
    await afficher(t);
    expect(find.text(cdf(3000)), findsOneWidget);
    expect(find.text('3 tickets  ·  2 clients'), findsOneWidget);
    expect(find.text('Marie  ·  ${cdf(2000)}'), findsOneWidget);
    expect(find.text('Paul  ·  ${cdf(1000)}'), findsOneWidget);
    expect(find.text('0812'), findsOneWidget);
    expect(find.text('D1'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('payer un ticket demande confirmation puis le retire', (t) async {
    await afficher(t);
    await t.tap(find.text('Payé').first);
    await t.pumpAndSettle();
    expect(find.text('Ticket payé ?'), findsOneWidget);
    await t.tap(find.text('Oui, payé'));
    await attendre(t);
    await t.pumpAndSettle();
    final restantes = (await t.runAsync(() => repo.dettes()))!;
    expect(restantes, hasLength(2));
    expect(find.text(cdf(2000)), findsOneWidget);
  });

  testWidgets('« Non » ne change rien', (t) async {
    await afficher(t);
    await t.tap(find.text('Payé').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Non'));
    await attendre(t);
    expect((await t.runAsync(() => repo.dettes()))!, hasLength(3));
  });

  testWidgets('« Tout payé » solde toutes les dettes du client', (t) async {
    await afficher(t);
    await t.tap(find.text('Tout payé').first); // Marie (ordre alphabétique)
    await t.pumpAndSettle();
    expect(find.text('Tout est payé ?'), findsOneWidget);
    await t.tap(find.text('Oui, tout payé'));
    await attendre(t);
    await t.pumpAndSettle();
    final restantes = (await t.runAsync(() => repo.dettes()))!;
    expect(restantes, hasLength(1));
    expect(restantes.single.clientNom, 'Paul');
  });

  testWidgets('plus aucune dette : message clair', (t) async {
    await t.runAsync(() async {
      for (final c in await repo.clients()) {
        await repo.marquerClientPaye(c.id);
      }
    });
    await afficher(t);
    expect(find.textContaining('Aucune dette en cours'), findsOneWidget);
  });
}
