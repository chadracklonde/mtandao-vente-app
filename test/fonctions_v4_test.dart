import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao/backup.dart';
import 'package:mtandao/db.dart';
import 'package:mtandao/message_ticket.dart';
import 'package:mtandao/models.dart';
import 'package:mtandao/repo.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

late Directory _tmp;
var _n = 0;

Future<Repo> _neuf({int tickets = 6}) async {
  final db = await databaseFactoryFfi.openDatabase(
    '${_tmp.path}/v4_${_n++}.db',
    options: OpenDatabaseOptions(
      version: AppDb.version,
      onConfigure: AppDb.configurer,
      onCreate: AppDb.creer,
    ),
  );
  final repo = Repo(db);
  await repo.importerLot(
    nom: 'Lot',
    forfait: (await repo.forfaits()).first,
    source: 'texte',
    tickets: [for (var i = 1; i <= tickets; i++) ParsedTicket(code: 'T$i', numero: i)],
  );
  return repo;
}

Future<Ticket> _t(Repo r, String code) async =>
    (await r.db.query('tickets', where: 'code = ?', whereArgs: [code]))
        .map(Ticket.fromMap)
        .single;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    _tmp = Directory.systemTemp.createTempSync('mtandao_v4_');
  });
  tearDownAll(() => _tmp.deleteSync(recursive: true));

  group('Vente de plusieurs tickets', () {
    test('vend les N prochains d\'un coup, annulation groupée', () async {
      final repo = await _neuf();
      final f = (await repo.forfaits()).first;
      final marie = await repo.ajouterClient('Marie');
      final vendus = await repo.vendreQuantite(f.id, 3, clientId: marie);
      expect(vendus.map((t) => t.code), ['T1', 'T2', 'T3']);
      expect(vendus.every((t) => t.vendu && t.clientId == marie), isTrue);
      expect(vendus.map((t) => t.venduLe).toSet().length, 1);
      expect((await repo.statsPeriode(DateTime(2000), DateTime(2100))).vendus, 3);

      expect((await repo.derniereVente()).length, 3);
      await repo.annulerDerniereVenteGlobale();
      expect((await repo.statsPeriode(DateTime(2000), DateTime(2100))).vendus, 0);
    });

    test('tout ou rien quand il n\'y en a pas assez', () async {
      final repo = await _neuf(tickets: 2);
      final f = (await repo.forfaits()).first;
      expect(await repo.vendreQuantite(f.id, 3), isEmpty);
      expect((await repo.statsPeriode(DateTime(2000), DateTime(2100))).vendus, 0);
    });

    test('dollars : montant calculé par ticket ; crédit sans client refusé', () async {
      final repo = await _neuf();
      final f = (await repo.forfaits()).first;
      final v = await repo.vendreQuantite(f.id, 2, devise: Devise.usd, taux: 2000);
      expect(v.every((t) => t.devise == Devise.usd && t.montantDevise == 50), isTrue);
      expect(() => repo.vendreQuantite(f.id, 2, paiement: Paiement.credit),
          throwsArgumentError);
    });

    test('une vente simple reste annulée seule', () async {
      final repo = await _neuf();
      final f = (await repo.forfaits()).first;
      await repo.vendreQuantite(f.id, 2);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final t = (await repo.prochainsTicketsForfait(f.id, 1)).single;
      await repo.vendre(t.id);
      expect((await repo.derniereVente()).map((x) => x.code), ['T3']);
      await repo.annulerDerniereVenteGlobale();
      expect((await _t(repo, 'T1')).vendu, isTrue);
      expect((await _t(repo, 'T3')).vendu, isFalse);
    });
  });

  group('Message au client', () {
    final t1 = Ticket(
        id: 1, lotId: 1, position: 0, numero: 1, code: '111', motDePasse: '111',
        qrTexte: null, prix: 1000, forfaitId: 1, vendu: true, venduLe: null);
    final t2 = Ticket(
        id: 2, lotId: 1, position: 1, numero: 2, code: 'u2', motDePasse: 'pw',
        qrTexte: null, prix: 1000, forfaitId: 1, vendu: true, venduLe: null);

    test('un ticket, avec le nom du client', () {
      final m = messageTickets(
          tickets: [t1], forfaitNom: '1 jour', url: 'http://x.wifi', clientNom: 'Marie');
      expect(m, contains('Bonjour Marie,'));
      expect(m, contains('Code : 111'));
      expect(m, contains('Connexion : http://x.wifi'));
    });

    test('plusieurs tickets, sans nom', () {
      final m = messageTickets(tickets: [t1, t2], forfaitNom: '1 h', url: 'u');
      expect(m, isNot(contains('Bonjour')));
      expect(m, contains('1) 111'));
      expect(m, contains('2) u2 (mot de passe : pw)'));
    });
  });

  group('Recherche', () {
    test('par code, client, téléphone ; sans texte : les ventes récentes', () async {
      final repo = await _neuf();
      final marie = await repo.ajouterClient('Marie', telephone: '0812345');
      final ts = await repo.ticketsDuLot(1);
      await repo.vendre(ts[0].id, clientId: marie);
      await repo.vendre(ts[1].id);

      expect((await repo.rechercher('T2')).single.ticket.code, 'T2');
      final m = await repo.rechercher('mari');
      expect(m.single.ticket.code, 'T1');
      expect(m.single.clientNom, 'Marie');
      expect((await repo.rechercher('0812')).single.ticket.code, 'T1');
      // Un ticket en stock se trouve aussi par son code.
      expect((await repo.rechercher('T5')).single.ticket.vendu, isFalse);
      expect((await repo.rechercher('')).length, 2);
      expect(await repo.rechercher('zzz'), isEmpty);
      // Caractères spéciaux de LIKE sans effet.
      expect(await repo.rechercher('%'), hasLength(6));
    });
  });

  group('Suivi d\'utilisation', () {
    test('marque les utilisés et repère les écarts', () async {
      final repo = await _neuf();
      final ts = await repo.ticketsDuLot(1);
      await repo.vendre(ts[0].id); // T1 vendu, jamais utilisé
      await repo.vendre(ts[1].id); // T2 vendu et utilisé
      // T3 : en stock mais utilisé (fuite)
      final r = await repo.appliquerUtilisation(
        utilises: {'T2', 'T3', 'ZZZ'},
        disponibles: {'T1', 'T4'},
      );
      expect(r.marques, 2);
      expect(r.vendusNonUtilises.map((t) => t.code), ['T1']);
      expect(r.utilisesNonVendus.map((t) => t.code), ['T3']);
      expect(r.inconnus, 1);
      expect((await _t(repo, 'T2')).utiliseLe, isNotNull);
      expect((await _t(repo, 'T4')).utiliseLe, isNull);

      // Second passage : rien de nouveau à marquer.
      final r2 = await repo.appliquerUtilisation(
          utilises: {'T2', 'T3'}, disponibles: {});
      expect(r2.marques, 0);
    });
  });

  group('Clôture de caisse', () {
    test('attendu : espèces, dollars, dettes payées ; hors mobile et offert', () async {
      final repo = await _neuf();
      final v = await repo.ajouterClient('Paul');
      final ts = await repo.ticketsDuLot(1);
      await repo.vendre(ts[0].id); // 1000 espèces
      await repo.vendre(ts[1].id, paiement: Paiement.mobile); // hors caisse
      await repo.vendre(ts[2].id, paiement: Paiement.offert); // hors caisse
      await repo.vendre(ts[3].id, devise: Devise.usd, taux: 2000); // 0,50 $
      await repo.vendre(ts[4].id, paiement: Paiement.credit, clientId: v);
      var a = await repo.attenduCaisse(DateTime.now());
      expect((a.especesCdf, a.dettesCdf, a.usd), (1000, 0, 50));
      await repo.marquerPaye(ts[4].id);
      a = await repo.attenduCaisse(DateTime.now());
      expect(a.dettesCdf, 1000);
      // Un autre jour : rien.
      a = await repo.attenduCaisse(DateTime.now().subtract(const Duration(days: 3)));
      expect((a.especesCdf, a.dettesCdf, a.usd), (0, 0, 0));
    });

    test('filtre par vendeur, enregistrement et écart', () async {
      final repo = await _neuf();
      final anne = await repo.ajouterVendeur('Anne');
      final ts = await repo.ticketsDuLot(1);
      await repo.vendre(ts[0].id, vendeurId: anne);
      await repo.vendre(ts[1].id);
      expect((await repo.attenduCaisse(DateTime.now(), vendeurId: anne)).especesCdf, 1000);
      expect((await repo.attenduCaisse(DateTime.now())).especesCdf, 2000);

      await repo.enregistrerCloture(
          jour: DateTime.now(), vendeurId: anne, attenduCdf: 1000, compteCdf: 800, note: ' pièce fausse ');
      final c = (await repo.clotures()).single;
      expect(c.ecartCdf, -200);
      expect(c.vendeurNom, 'Anne');
      expect(c.note, 'pièce fausse');
      await repo.supprimerCloture(c.id);
      expect(await repo.clotures(), isEmpty);
    });

    test('les clôtures font partie de la sauvegarde', () async {
      final repo = await _neuf();
      await repo.enregistrerCloture(
          jour: DateTime(2026, 11, 3), attenduCdf: 5000, compteCdf: 5000);
      final octets = await Sauvegarde.contenu(repo);
      await repo.supprimerCloture((await repo.clotures()).single.id);
      await Sauvegarde.restaurer(repo, octets);
      final c = (await repo.clotures()).single;
      expect(c.jour, '2026-11-03');
      expect(c.attenduCdf, 5000);
    });
  });

  group('Dettes en retard', () {
    test('délai réglable ; 0 = jamais', () async {
      final repo = await _neuf();
      final p = await repo.ajouterClient('Paul');
      final ts = await repo.ticketsDuLot(1);
      await repo.vendre(ts[0].id, paiement: Paiement.credit, clientId: p);
      // Vieillit la dette de 10 jours.
      await repo.db.update(
          'tickets',
          {'vendu_le': DateTime.now().subtract(const Duration(days: 10)).millisecondsSinceEpoch},
          where: 'id = ?',
          whereArgs: [ts[0].id]);
      await repo.vendre(ts[1].id, paiement: Paiement.credit, clientId: p); // récente

      expect(await repo.delaiDetteJours(), 7);
      expect((await repo.dettesEnRetard()).map((d) => d.code), ['T1']);
      await repo.setSetting(cleDelaiDette, '30');
      expect(await repo.dettesEnRetard(), isEmpty);
      await repo.setSetting(cleDelaiDette, '0');
      expect(await repo.dettesEnRetard(), isEmpty);
    });
  });

  test('migration v3 vers v4 : données conservées', () async {
    final chemin = '${_tmp.path}/mig.db';
    final repo3 = await databaseFactoryFfi.openDatabase(chemin,
        options: OpenDatabaseOptions(
          version: 3,
          onConfigure: AppDb.configurer,
          onCreate: (db, v) async {
            await AppDb.creer(db, v);
            await db.execute('DROP TABLE clotures');
            await db.execute('DROP TABLE annulations');
            await db.execute('ALTER TABLE tickets DROP COLUMN annulations');
            // SQLite récent : retire la colonne ajoutée par la v4.
            await db.execute('ALTER TABLE tickets DROP COLUMN utilise_le');
          },
        ));
    await repo3.close();
    final v4 = await databaseFactoryFfi.openDatabase(chemin,
        options: OpenDatabaseOptions(
          version: AppDb.version,
          onConfigure: AppDb.configurer,
          onUpgrade: AppDb.migrer,
        ));
    final repo = Repo(v4);
    expect(await repo.clotures(), isEmpty);
    expect((await v4.rawQuery('PRAGMA table_info(tickets)'))
        .any((c) => c['name'] == 'utilise_le'), isTrue);
  });
}
