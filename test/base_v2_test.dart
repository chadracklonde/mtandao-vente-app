import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao/backup.dart';
import 'package:mtandao/db.dart';
import 'package:mtandao/models.dart';
import 'package:mtandao/repo.dart';
import 'package:mtandao/state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Schéma d'origine (version 1), recopié tel quel : sert à vérifier que la
/// migration conserve les données déjà présentes sur les téléphones.
const _v1 = [
  '''CREATE TABLE forfaits(id INTEGER PRIMARY KEY AUTOINCREMENT, nom TEXT NOT NULL,
     duree_minutes INTEGER NOT NULL, prix INTEGER NOT NULL, actif INTEGER NOT NULL DEFAULT 1)''',
  '''CREATE TABLE lots(id INTEGER PRIMARY KEY AUTOINCREMENT, nom TEXT NOT NULL,
     forfait_id INTEGER NOT NULL REFERENCES forfaits(id), source TEXT NOT NULL,
     fichier TEXT, login_url TEXT, cree_le INTEGER NOT NULL)''',
  '''CREATE TABLE tickets(id INTEGER PRIMARY KEY AUTOINCREMENT,
     lot_id INTEGER NOT NULL REFERENCES lots(id) ON DELETE CASCADE,
     position INTEGER NOT NULL, numero INTEGER, code TEXT NOT NULL UNIQUE,
     mot_de_passe TEXT, qr_texte TEXT, prix INTEGER NOT NULL,
     forfait_id INTEGER NOT NULL REFERENCES forfaits(id),
     vendu INTEGER NOT NULL DEFAULT 0, vendu_le INTEGER)''',
  '''CREATE TABLE ticket_images(ticket_id INTEGER PRIMARY KEY REFERENCES tickets(id) ON DELETE CASCADE,
     data BLOB NOT NULL)''',
  'CREATE TABLE settings(cle TEXT PRIMARY KEY, valeur TEXT)',
];

late Directory _tmp;
var _n = 0;

String _chemin() => '${_tmp.path}/base_${_n++}.db';

Future<Database> _neuve() => databaseFactoryFfi.openDatabase(
      _chemin(),
      options: OpenDatabaseOptions(
        version: AppDb.version,
        onConfigure: AppDb.configurer,
        onCreate: AppDb.creer,
        onUpgrade: AppDb.migrer,
      ),
    );

/// Un lot de 4 tickets de 1 000 CDF.
Future<(Repo, int)> _repoAvecLot() async {
  final repo = Repo(await _neuve());
  final forfaits = await repo.forfaits();
  final lot = await repo.importerLot(
    nom: 'Lot test',
    forfait: forfaits.first,
    source: 'texte',
    tickets: [for (var i = 1; i <= 4; i++) ParsedTicket(code: 'C$i', numero: i)],
  );
  return (repo, lot.lotId!);
}

Future<List<Ticket>> _tickets(Repo repo, int lotId) => repo.ticketsDuLot(lotId);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    _tmp = Directory.systemTemp.createTempSync('mtandao_test_');
  });
  tearDownAll(() => _tmp.deleteSync(recursive: true));

  group('Migration v1 vers v2', () {
    test('conserve toutes les données existantes', () async {
      final chemin = _chemin();
      final v1 = await databaseFactoryFfi.openDatabase(chemin,
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, _) async {
              for (final ddl in _v1) {
                await db.execute(ddl);
              }
            },
          ));
      await v1.insert('forfaits',
          {'nom': '1 jour', 'duree_minutes': 1440, 'prix': 1000, 'actif': 1});
      await v1.insert('lots', {
        'nom': 'Ancien lot', 'forfait_id': 1, 'source': 'texte', 'cree_le': 1000,
      });
      for (var i = 1; i <= 5; i++) {
        await v1.insert('tickets', {
          'lot_id': 1, 'position': i, 'code': 'A$i', 'prix': 1000,
          'forfait_id': 1,
          'vendu': i <= 3 ? 1 : 0,
          'vendu_le': i <= 3 ? 5000 + i : null,
        });
      }
      await v1.insert('settings', {'cle': 'login_url', 'valeur': 'http://x'});
      await v1.close();

      final v2 = await databaseFactoryFfi.openDatabase(chemin,
          options: OpenDatabaseOptions(
            version: 2,
            onConfigure: AppDb.configurer,
            onUpgrade: AppDb.migrer,
          ));
      final repo = Repo(v2);

      final tickets = await repo.ticketsDuLot(1);
      expect(tickets, hasLength(5));
      expect(tickets.where((t) => t.vendu), hasLength(3));
      // Les anciennes ventes sont des ventes en espèces, comme avant.
      for (final t in tickets) {
        expect(t.paiement, Paiement.especes);
        expect(t.defectueux, isFalse);
        expect(t.clientId, isNull);
        expect(t.vendeurId, isNull);
      }
      final lot = (await repo.lot(1))!;
      expect(lot.montant, 3000);
      expect(lot.restants, 2);
      expect(await repo.getSetting('login_url'), 'http://x');
      expect(await repo.clients(), isEmpty);
      expect(await repo.vendeurs(), isEmpty);
      await v2.close();
    });

    test('une base neuve a le même schéma qu\'une base migrée', () async {
      final neuve = await _neuve();

      final chemin = _chemin();
      final v1 = await databaseFactoryFfi.openDatabase(chemin,
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, _) async {
              for (final ddl in _v1) {
                await db.execute(ddl);
              }
            },
          ));
      await v1.close();
      final migree = await databaseFactoryFfi.openDatabase(chemin,
          options: OpenDatabaseOptions(
              version: 2,
              onConfigure: AppDb.configurer,
              onUpgrade: AppDb.migrer));

      Future<List<String>> colonnes(Database db, String table) async =>
          (await db.rawQuery('PRAGMA table_info($table)'))
              .map((r) => '${r['name']}:${r['type']}:${r['notnull']}:${r['dflt_value']}')
              .toList()
            ..sort();

      for (final t in ['forfaits', 'lots', 'tickets', 'clients', 'vendeurs']) {
        expect(await colonnes(migree, t), await colonnes(neuve, t), reason: t);
      }
      await neuve.close();
      await migree.close();
    });
  });

  group('Défectueux', () {
    test('un ticket défectueux n\'est plus proposé ni compté', () async {
      final (repo, lotId) = await _repoAvecLot();
      final t = (await _tickets(repo, lotId)).first;
      expect(await repo.signalerDefectueux(t.id), isTrue);

      expect((await repo.prochainTicket(lotId))!.code, 'C2');
      expect((await repo.lot(lotId))!.restants, 3);
      expect((await repo.stats(lotId)).restants, 3);

      await repo.reactiverTicket(t.id);
      expect((await repo.prochainTicket(lotId))!.code, 'C1');
      expect((await repo.lot(lotId))!.restants, 4);
    });

    test('un ticket déjà vendu ne peut pas être signalé défectueux', () async {
      final (repo, lotId) = await _repoAvecLot();
      final t = (await _tickets(repo, lotId)).first;
      await repo.vendre(t.id);
      expect(await repo.signalerDefectueux(t.id), isFalse);
    });

    test('un ticket défectueux ne peut pas être vendu', () async {
      final (repo, lotId) = await _repoAvecLot();
      final t = (await _tickets(repo, lotId)).first;
      await repo.signalerDefectueux(t.id);
      expect(await repo.vendre(t.id), isFalse);
    });
  });

  group('Paiements', () {
    test('espèces et mobile money sont encaissés', () async {
      final (repo, lotId) = await _repoAvecLot();
      final ts = await _tickets(repo, lotId);
      await repo.vendre(ts[0].id);
      await repo.vendre(ts[1].id, paiement: Paiement.mobile);
      expect((await repo.stats(lotId)).montant, 2000);
      expect((await repo.lot(lotId))!.montant, 2000);
      expect((await repo.stats(lotId)).vendus, 2);
    });

    test('un ticket offert est vendu mais rien n\'est encaissé', () async {
      final (repo, lotId) = await _repoAvecLot();
      final ts = await _tickets(repo, lotId);
      await repo.vendre(ts[0].id, paiement: Paiement.offert);
      final s = await repo.stats(lotId);
      expect(s.vendus, 1);
      expect(s.montant, 0);
      expect(s.restants, 3);
    });

    test('hors crédit, le client est facultatif et n\'est pas une dette', () async {
      final (repo, lotId) = await _repoAvecLot();
      final ts = await _tickets(repo, lotId);
      final marie = await repo.ajouterClient('Marie');
      await repo.vendre(ts[0].id, clientId: marie);
      await repo.vendre(ts[1].id);
      final v = await repo.ventes(
          DateTime.now().subtract(const Duration(days: 1)),
          DateTime.now().add(const Duration(days: 1)));
      expect(v.where((l) => l.clientNom == 'Marie').length, 1);
      expect(v.where((l) => l.clientNom == null).length, 1);
      expect(await repo.dettes(), isEmpty);
    });

    test('une vente à crédit exige un client', () async {
      final (repo, lotId) = await _repoAvecLot();
      final t = (await _tickets(repo, lotId)).first;
      expect(() => repo.vendre(t.id, paiement: Paiement.credit),
          throwsArgumentError);
      expect(() => repo.vendre(t.id, paiement: 'bitcoin'), throwsArgumentError);
    });

    test('un crédit n\'est encaissé qu\'une fois payé', () async {
      final (repo, lotId) = await _repoAvecLot();
      final ts = await _tickets(repo, lotId);
      final client = await repo.ajouterClient('Marie', telephone: ' 0812 ');
      await repo.vendre(ts[0].id, paiement: Paiement.credit, clientId: client);
      await repo.vendre(ts[1].id, paiement: Paiement.credit, clientId: client);

      expect((await repo.stats(lotId)).montant, 0);
      final dettes = await repo.dettes();
      expect(dettes, hasLength(2));
      expect(dettes.first.clientNom, 'Marie');
      expect(dettes.first.clientTelephone, '0812');
      expect(dettes.fold<int>(0, (a, d) => a + d.prix), 2000);

      await repo.marquerPaye(dettes.first.ticketId);
      expect((await repo.stats(lotId)).montant, 1000);
      expect(await repo.dettes(), hasLength(1));

      await repo.marquerClientPaye(client);
      expect((await repo.stats(lotId)).montant, 2000);
      expect(await repo.dettes(), isEmpty);
    });

    test('annuler une vente à crédit efface la dette', () async {
      final (repo, lotId) = await _repoAvecLot();
      final t = (await _tickets(repo, lotId)).first;
      final client = await repo.ajouterClient('Paul');
      await repo.vendre(t.id, paiement: Paiement.credit, clientId: client);
      expect(await repo.dettes(), hasLength(1));

      final annule = await repo.annulerDerniereVente(lotId);
      expect(annule!.code, 'C1');
      expect(await repo.dettes(), isEmpty);
      final apres = (await _tickets(repo, lotId)).first;
      expect(apres.vendu, isFalse);
      expect(apres.paiement, Paiement.especes);
      expect(apres.clientId, isNull);
    });

    test('les rapports donnent le mode de paiement, le client et le vendeur',
        () async {
      final (repo, lotId) = await _repoAvecLot();
      final ts = await _tickets(repo, lotId);
      final vendeur = await repo.ajouterVendeur('Jean');
      final client = await repo.ajouterClient('Anne');
      await repo.vendre(ts[0].id, vendeurId: vendeur);
      await repo.vendre(ts[1].id,
          paiement: Paiement.credit, clientId: client, vendeurId: vendeur);
      await repo.vendre(ts[2].id, paiement: Paiement.offert);

      final lignes = await repo.ventes(
          DateTime.now().subtract(const Duration(hours: 1)),
          DateTime.now().add(const Duration(hours: 1)));
      expect(lignes, hasLength(3));
      final parCode = {for (final l in lignes) l.code: l};
      expect(parCode['C1']!.vendeurNom, 'Jean');
      expect(parCode['C1']!.encaisse, isTrue);
      expect(parCode['C2']!.clientNom, 'Anne');
      expect(parCode['C2']!.aRecevoir, isTrue);
      expect(parCode['C2']!.encaisse, isFalse);
      expect(parCode['C3']!.encaisse, isFalse);
      expect(parCode['C3']!.aRecevoir, isFalse);
      expect(lignes.fold<int>(0, (a, l) => a + l.montantEncaisse), 1000);
    });
  });

  group('Ajout de tickets à un lot', () {
    test('place les nouveaux tickets à la suite, au prix du forfait', () async {
      final (repo, lotId) = await _repoAvecLot();
      final r = await repo.ajouterTickets(lotId, [
        ParsedTicket(code: 'N1'),
        ParsedTicket(code: 'N2', motDePasse: 'mdp'),
      ]);
      expect(r.inseres, 2);
      expect(r.doublons, 0);

      final ts = await _tickets(repo, lotId);
      expect(ts.map((t) => t.code), ['C1', 'C2', 'C3', 'C4', 'N1', 'N2']);
      expect(ts.map((t) => t.position), [0, 1, 2, 3, 4, 5]);
      expect(ts.last.motDePasse, 'mdp');
      expect(ts.last.prix, ts.first.prix);
      expect((await repo.lot(lotId))!.total, 6);
    });

    test('ignore les codes déjà présents, même dans un autre lot', () async {
      final (repo, lotId) = await _repoAvecLot();
      final autre = await repo.importerLot(
        nom: 'Autre',
        forfait: (await repo.forfaits()).first,
        source: 'manuel',
        tickets: [ParsedTicket(code: 'Z9')],
      );
      final r = await repo.ajouterTickets(lotId, [
        ParsedTicket(code: 'C1'),
        ParsedTicket(code: 'Z9'),
        ParsedTicket(code: 'NEUF'),
      ]);
      expect(r.inseres, 1);
      expect(r.doublons, 2);
      expect((await repo.lot(autre.lotId!))!.total, 1);
    });

    test('lot inexistant : erreur claire', () async {
      final (repo, _) = await _repoAvecLot();
      expect(() => repo.ajouterTickets(9999, [ParsedTicket(code: 'X')]),
          throwsStateError);
    });
  });

  group('À recevoir d\'un lot', () {
    test('somme des crédits non payés, avant suppression du lot', () async {
      final (repo, lotId) = await _repoAvecLot();
      final ts = await _tickets(repo, lotId);
      final client = await repo.ajouterClient('Léa');
      await repo.vendre(ts[0].id, paiement: Paiement.credit, clientId: client);
      await repo.vendre(ts[1].id, paiement: Paiement.credit, clientId: client);
      await repo.vendre(ts[2].id);
      expect(await repo.aRecevoirDuLot(lotId), 2000);
      await repo.marquerPaye((await repo.dettes()).first.ticketId);
      expect(await repo.aRecevoirDuLot(lotId), 1000);
      expect(await repo.aRecevoirDuLot(9999), 0);
    });
  });

  group('Vente par forfait', () {
    /// Deux forfaits : 24 h (déjà créé, 4 tickets) et 1 h (3 tickets, 2 lots).
    Future<(Repo, Forfait, Forfait)> deuxForfaits() async {
      final (repo, _) = await _repoAvecLot();
      final jour = (await repo.forfaits()).first;
      final idHeure = await repo.ajouterForfait('1 heure', 60, 500);
      final heure = (await repo.forfaits()).firstWhere((f) => f.id == idHeure);
      await repo.importerLot(
          nom: 'Heure A',
          forfait: heure,
          source: 'texte',
          tickets: [ParsedTicket(code: 'H1'), ParsedTicket(code: 'H2')]);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repo.importerLot(
          nom: 'Heure B',
          forfait: heure,
          source: 'texte',
          tickets: [ParsedTicket(code: 'H3')]);
      return (repo, jour, heure);
    }

    test('les profils : forfaits classés par durée, avec leur stock', () async {
      final (repo, jour, heure) = await deuxForfaits();
      final p = await repo.profils();
      expect(p.map((x) => x.forfait.id), [heure.id, jour.id]); // 1 h avant 24 h
      expect(p.first.total, 3);
      expect(p.first.restants, 3);
      expect(p.last.restants, 4);
    });

    test('le stock tient compte des ventes, des défectueux et de l\'argent encaissé', () async {
      final (repo, jour, heure) = await deuxForfaits();
      final h = await repo.prochainTicketForfait(heure.id);
      await repo.vendre(h!.id);
      final h2 = await repo.prochainTicketForfait(heure.id);
      await repo.signalerDefectueux(h2!.id);
      final p = (await repo.profils()).firstWhere((x) => x.forfait.id == heure.id);
      expect(p.total, 3);
      expect(p.vendus, 1);
      expect(p.defectueux, 1);
      expect(p.restants, 1);
      expect(p.montant, 500);
      expect((await repo.profils()).firstWhere((x) => x.forfait.id == jour.id).vendus, 0);
    });

    test('un forfait désactivé sans ticket disparaît, avec des tickets il reste', () async {
      final (repo, _, heure) = await deuxForfaits();
      await repo.modifierForfait(heure.id, actif: false);
      expect((await repo.profils()).any((x) => x.forfait.id == heure.id), isTrue);
      while (true) {
        final t = await repo.prochainTicketForfait(heure.id);
        if (t == null) break;
        await repo.vendre(t.id);
      }
      expect((await repo.profils()).any((x) => x.forfait.id == heure.id), isFalse);
    });

    test('le prochain ticket vient du lot le plus ancien du forfait', () async {
      final (repo, _, heure) = await deuxForfaits();
      final codes = <String>[];
      while (true) {
        final t = await repo.prochainTicketForfait(heure.id);
        if (t == null) break;
        codes.add(t.code);
        await repo.vendre(t.id);
      }
      expect(codes, ['H1', 'H2', 'H3']);
    });

    test('le lot préféré passe en premier, s\'il est du bon forfait', () async {
      final (repo, jour, heure) = await deuxForfaits();
      final lots = await repo.lots();
      final heureB = lots.firstWhere((l) => l.nom == 'Heure B');
      expect((await repo.prochainTicketForfait(heure.id, lotPrefereId: heureB.id))!.code, 'H3');
      // Lot préféré d'un autre forfait : ignoré.
      expect((await repo.prochainTicketForfait(jour.id, lotPrefereId: heureB.id))!.code, 'C1');
      // Lot préféré épuisé : on revient au plus ancien.
      await repo.vendre((await repo.prochainTicketForfait(heure.id, lotPrefereId: heureB.id))!.id);
      expect((await repo.prochainTicketForfait(heure.id, lotPrefereId: heureB.id))!.code, 'H1');
    });

    test('forfait sans ticket à vendre : aucun ticket', () async {
      final (repo, _) = await _repoAvecLot();
      final id = await repo.ajouterForfait('1 semaine', 10080, 5000);
      expect(await repo.prochainTicketForfait(id), isNull);
    });

    test('dernière vente et annulation, tous forfaits confondus', () async {
      final (repo, jour, heure) = await deuxForfaits();
      expect(await repo.dernierVenduGlobal(), isNull);
      await repo.vendre((await repo.prochainTicketForfait(jour.id))!.id);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repo.vendre((await repo.prochainTicketForfait(heure.id))!.id);

      expect((await repo.dernierVenduGlobal())!.code, 'H1');
      final annule = await repo.annulerDerniereVenteGlobale();
      expect(annule!.code, 'H1');
      expect((await repo.dernierVenduGlobal())!.code, 'C1');
    });

    test('total d\'une période : tickets vendus et argent encaissé, tous forfaits', () async {
      final (repo, jour, heure) = await deuxForfaits();
      await repo.vendre((await repo.prochainTicketForfait(jour.id))!.id);
      await repo.vendre((await repo.prochainTicketForfait(heure.id))!.id,
          paiement: Paiement.offert);
      final now = DateTime.now();
      final s = await repo.statsPeriode(
          now.subtract(const Duration(hours: 1)), now.add(const Duration(hours: 1)));
      expect(s.vendus, 2);
      expect(s.montant, 1000); // 24 h en espèces ; le ticket offert n'est pas encaissé
      final vide = await repo.statsPeriode(
          now.subtract(const Duration(days: 3)), now.subtract(const Duration(days: 2)));
      expect(vide.vendus, 0);
      expect(vide.montant, 0);
    });

    test('le forfait affiché est mémorisé, et suit le lot choisi', () async {
      final (repo, jour, heure) = await deuxForfaits();
      appState.utiliserPourTest(repo);
      await appState.definirForfaitActif(heure.id);
      expect(await repo.getSetting('forfait_actif'), '${heure.id}');
      final lotJour = (await repo.lots()).firstWhere((l) => l.forfaitId == jour.id);
      await appState.definirLotActif(lotJour.id);
      expect(appState.forfaitActifId, jour.id);
      expect(await repo.getSetting('forfait_actif'), '${jour.id}');
    });
  });

  group('Vendeurs', () {
    test('vendeur actif : seulement un vendeur actif existant', () async {
      final repo = Repo(await _neuve());
      expect(await repo.vendeurActifId(), isNull);
      final id = await repo.ajouterVendeur(' Luc ');
      expect((await repo.vendeurs()).single.nom, 'Luc');
      await repo.definirVendeurActif(id);
      expect(await repo.vendeurActifId(), id);

      await repo.modifierVendeur(id, actif: false);
      expect(await repo.vendeurActifId(), isNull);
      expect(await repo.vendeurs(seulementActifs: true), isEmpty);

      await repo.definirVendeurActif(null);
      expect(await repo.vendeurActifId(), isNull);
    });
  });

  group('Sauvegarde et restauration', () {
    test('aller-retour : tout est restauré, y compris crédits et vendeurs',
        () async {
      final (repo, lotId) = await _repoAvecLot();
      final ts = await _tickets(repo, lotId);
      final client = await repo.ajouterClient('Zoé');
      final vendeur = await repo.ajouterVendeur('Max');
      await repo.vendre(ts[0].id, vendeurId: vendeur);
      await repo.vendre(ts[1].id, paiement: Paiement.credit, clientId: client);
      await repo.signalerDefectueux(ts[3].id);
      await repo.definirVendeurActif(vendeur);

      final octets = await Sauvegarde.contenu(repo);

      final autre = Repo(await _neuve());
      await autre.setSetting('pin_hash', 'garde-moi');
      await autre.setSetting('drive_actif', '1');
      await Sauvegarde.restaurer(autre, octets);

      final lot = (await autre.lots()).single;
      expect(lot.total, 4);
      expect(lot.vendus, 2);
      expect(lot.defectueux, 1);
      expect(lot.montant, 1000);
      expect((await autre.dettes()).single.clientNom, 'Zoé');
      expect((await autre.vendeurs()).single.nom, 'Max');
      // Propres au téléphone : conservés ou non restaurés.
      expect(await autre.getSetting('pin_hash'), 'garde-moi');
      expect(await autre.getSetting('drive_actif'), '1');
      expect(await autre.getSetting('vendeur_actif'), isNull);
    });

    test('une sauvegarde de la version 1 se restaure encore', () async {
      final (repo, lotId) = await _repoAvecLot();
      final ts = await _tickets(repo, lotId);
      await repo.vendre(ts[0].id);
      final octets = await Sauvegarde.contenu(repo);

      // On fabrique un fichier « ancien » : version 1, sans clients ni vendeurs,
      // et sans les nouvelles colonnes des tickets.
      final ancien = await Sauvegarde.decoderPourTest(octets);
      ancien['version'] = 1;
      ancien.remove('clients');
      ancien.remove('vendeurs');
      for (final t in (ancien['tickets'] as List).cast<Map>()) {
        for (final c in [
          'defectueux', 'paiement', 'client_id', 'paye_le', 'vendeur_id'
        ]) {
          t.remove(c);
        }
      }
      final octetsV1 = await Sauvegarde.encoderPourTest(ancien);

      final autre = Repo(await _neuve());
      await Sauvegarde.restaurer(autre, octetsV1);
      final lot = (await autre.lots()).single;
      expect(lot.total, 4);
      expect(lot.vendus, 1);
      expect(lot.montant, 1000);
    });
  });
}
