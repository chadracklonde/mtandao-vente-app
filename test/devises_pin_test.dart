import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao/backup.dart';
import 'package:mtandao/db.dart';
import 'package:mtandao/models.dart';
import 'package:mtandao/rapport.dart';
import 'package:mtandao/rapport_export.dart';
import 'package:mtandao/repo.dart';
import 'package:mtandao/security.dart';
import 'package:mtandao/state.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Schéma de la version 2, tel qu'il existe sur les téléphones déjà à jour.
const _v2 = [
  '''CREATE TABLE forfaits(id INTEGER PRIMARY KEY AUTOINCREMENT, nom TEXT NOT NULL,
     duree_minutes INTEGER NOT NULL, prix INTEGER NOT NULL, actif INTEGER NOT NULL DEFAULT 1)''',
  '''CREATE TABLE lots(id INTEGER PRIMARY KEY AUTOINCREMENT, nom TEXT NOT NULL,
     forfait_id INTEGER NOT NULL REFERENCES forfaits(id), source TEXT NOT NULL,
     fichier TEXT, login_url TEXT, cree_le INTEGER NOT NULL)''',
  '''CREATE TABLE clients(id INTEGER PRIMARY KEY AUTOINCREMENT, nom TEXT NOT NULL,
     telephone TEXT, cree_le INTEGER NOT NULL)''',
  '''CREATE TABLE vendeurs(id INTEGER PRIMARY KEY AUTOINCREMENT, nom TEXT NOT NULL,
     actif INTEGER NOT NULL DEFAULT 1)''',
  '''CREATE TABLE tickets(id INTEGER PRIMARY KEY AUTOINCREMENT,
     lot_id INTEGER NOT NULL REFERENCES lots(id) ON DELETE CASCADE,
     position INTEGER NOT NULL, numero INTEGER, code TEXT NOT NULL UNIQUE,
     mot_de_passe TEXT, qr_texte TEXT, prix INTEGER NOT NULL,
     forfait_id INTEGER NOT NULL REFERENCES forfaits(id),
     vendu INTEGER NOT NULL DEFAULT 0, vendu_le INTEGER,
     defectueux INTEGER NOT NULL DEFAULT 0,
     paiement TEXT NOT NULL DEFAULT 'especes',
     client_id INTEGER REFERENCES clients(id), paye_le INTEGER,
     vendeur_id INTEGER REFERENCES vendeurs(id))''',
  '''CREATE TABLE ticket_images(ticket_id INTEGER PRIMARY KEY REFERENCES tickets(id) ON DELETE CASCADE,
     data BLOB NOT NULL)''',
  'CREATE TABLE settings(cle TEXT PRIMARY KEY, valeur TEXT)',
];

late Directory _tmp;
var _n = 0;
String _chemin() => '${_tmp.path}/b${_n++}.db';

Future<Database> _neuve() => databaseFactoryFfi.openDatabase(
      _chemin(),
      options: OpenDatabaseOptions(
        version: AppDb.version,
        onConfigure: AppDb.configurer,
        onCreate: AppDb.creer,
        onUpgrade: AppDb.migrer,
      ),
    );

Future<(Repo, int)> _repoAvecLot({int prix = 5000}) async {
  final repo = Repo(await _neuve());
  appState.utiliserPourTest(repo);
  final f = (await repo.forfaits()).first;
  await repo.modifierForfait(f.id, prix: prix);
  final lot = await repo.importerLot(
    nom: 'Lot',
    forfait: (await repo.forfaits()).first,
    source: 'texte',
    tickets: [for (var i = 1; i <= 4; i++) ParsedTicket(code: 'C$i')],
  );
  return (repo, lot.lotId!);
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    await initializeDateFormatting('fr');
    _tmp = Directory.systemTemp.createTempSync('mtandao_v3_');
  });
  tearDownAll(() => _tmp.deleteSync(recursive: true));

  group('Migration v2 vers v3', () {
    test('conserve les données et donne des valeurs par défaut', () async {
      final chemin = _chemin();
      final v2 = await databaseFactoryFfi.openDatabase(chemin,
          options: OpenDatabaseOptions(
            version: 2,
            onCreate: (db, _) async {
              for (final ddl in _v2) {
                await db.execute(ddl);
              }
            },
          ));
      await v2.insert('forfaits',
          {'nom': '1 jour', 'duree_minutes': 1440, 'prix': 1000, 'actif': 1});
      await v2.insert('lots',
          {'nom': 'L', 'forfait_id': 1, 'source': 'texte', 'cree_le': 1});
      await v2.insert('vendeurs', {'nom': 'Jean', 'actif': 1});
      await v2.insert('tickets', {
        'lot_id': 1, 'position': 0, 'code': 'A1', 'prix': 1000,
        'forfait_id': 1, 'vendu': 1, 'vendu_le': 5000, 'paiement': 'mobile',
      });
      await v2.close();

      final v3 = await databaseFactoryFfi.openDatabase(chemin,
          options: OpenDatabaseOptions(
            version: 3,
            onConfigure: AppDb.configurer,
            onUpgrade: AppDb.migrer,
          ));
      final repo = Repo(v3);
      final t = (await repo.ticketsDuLot(1)).single;
      expect(t.vendu, isTrue);
      expect(t.paiement, Paiement.mobile);
      expect(t.devise, Devise.cdf);
      expect(t.taux, isNull);
      expect(t.montantDevise, isNull);
      final v = (await repo.vendeurs()).single;
      expect(v.nom, 'Jean');
      expect(v.aUnCode, isFalse);
      await v3.close();
    });
  });

  group('Conversion en dollars', () {
    test('centimes, au centime près', () {
      expect(Devise.centimesDollar(5000, 2800), 179); // 1,7857 $
      expect(Devise.centimesDollar(1000, 2800), 36);
      expect(Devise.centimesDollar(2800, 2800), 100);
      expect(Devise.centimesDollar(1000, 0), 0);
    });

    test('affichage', () {
      expect(Devise.formaterDollar(179), '1,79 USD');
      expect(Devise.formaterDollar(5), '0,05 USD');
      expect(Devise.formaterDollar(1200), '12,00 USD');
      expect(Devise.formaterDollar(0), '0,00 USD');
    });
  });

  group('Vente en dollars', () {
    test('enregistre devise, taux et montant reçu ; encaissé reste en francs', () async {
      final (repo, lotId) = await _repoAvecLot();
      final t = (await repo.ticketsDuLot(lotId)).first;
      expect(await repo.vendre(t.id, devise: Devise.usd, taux: 2800), isTrue);

      final apres = (await repo.ticketsDuLot(lotId)).first;
      expect(apres.devise, Devise.usd);
      expect(apres.taux, 2800);
      expect(apres.montantDevise, 179);
      expect((await repo.stats(lotId)).montant, 5000);
    });

    test('le taux du jour est conservé même si le taux change ensuite', () async {
      final (repo, lotId) = await _repoAvecLot();
      final ts = await repo.ticketsDuLot(lotId);
      await repo.vendre(ts[0].id, devise: Devise.usd, taux: 2800);
      await repo.vendre(ts[1].id, devise: Devise.usd, taux: 3000);
      final apres = await repo.ticketsDuLot(lotId);
      expect(apres[0].montantDevise, 179);
      expect(apres[1].montantDevise, 167);
      expect(apres[0].taux, 2800);
      expect(apres[1].taux, 3000);
    });

    test('exige un taux, et seulement espèces ou mobile money', () async {
      final (repo, lotId) = await _repoAvecLot();
      final t = (await repo.ticketsDuLot(lotId)).first;
      final client = await repo.ajouterClient('X');
      expect(() => repo.vendre(t.id, devise: Devise.usd), throwsArgumentError);
      expect(() => repo.vendre(t.id, devise: Devise.usd, taux: 0), throwsArgumentError);
      expect(
          () => repo.vendre(t.id,
              devise: Devise.usd, taux: 2800, paiement: Paiement.credit, clientId: client),
          throwsArgumentError);
      expect(
          () => repo.vendre(t.id,
              devise: Devise.usd, taux: 2800, paiement: Paiement.offert),
          throwsArgumentError);
      expect(() => repo.vendre(t.id, devise: 'EUR'), throwsArgumentError);
      // Rien n'a été vendu par erreur.
      expect((await repo.ticketsDuLot(lotId)).first.vendu, isFalse);
      // Mobile money en dollars : accepté.
      expect(
          await repo.vendre(t.id,
              devise: Devise.usd, taux: 2800, paiement: Paiement.mobile),
          isTrue);
    });

    test('annuler la vente efface les dollars', () async {
      final (repo, lotId) = await _repoAvecLot();
      final t = (await repo.ticketsDuLot(lotId)).first;
      await repo.vendre(t.id, devise: Devise.usd, taux: 2800);
      await repo.annulerDerniereVente(lotId);
      final apres = (await repo.ticketsDuLot(lotId)).first;
      expect(apres.devise, Devise.cdf);
      expect(apres.taux, isNull);
      expect(apres.montantDevise, isNull);
    });

    test('rapport : total reçu en dollars, export CSV et texte', () async {
      final (repo, lotId) = await _repoAvecLot();
      final ts = await repo.ticketsDuLot(lotId);
      await repo.vendre(ts[0].id, devise: Devise.usd, taux: 2800);
      await repo.vendre(ts[1].id, devise: Devise.usd, taux: 2800);
      await repo.vendre(ts[2].id);

      final lignes = await repo.ventes(
          DateTime.now().subtract(const Duration(hours: 1)),
          DateTime.now().add(const Duration(hours: 1)));
      final r = Rapport(lignes);
      expect(r.nombre, 3);
      expect(r.encaisse, 15000);
      expect(r.ventesDollar, 2);
      expect(r.dollarsRecus, 358);
      expect(r.texte('Jour', detailParJour: false),
          contains('Dont payé en dollars : 2 tickets, 3,58 USD'));

      final csv = RapportExport.csv(lignes);
      expect(csv, contains(';USD;1,79;'));
      expect(csv, contains(';CDF;;'));
    });

    test('la sauvegarde conserve les ventes en dollars', () async {
      final (repo, lotId) = await _repoAvecLot();
      final t = (await repo.ticketsDuLot(lotId)).first;
      await repo.vendre(t.id, devise: Devise.usd, taux: 2800);
      final octets = await Sauvegarde.contenu(repo);

      final autre = Repo(await _neuve());
      await Sauvegarde.restaurer(autre, octets);
      final lot = (await autre.lots()).single;
      final restaure = (await autre.ticketsDuLot(lot.id)).first;
      expect(restaure.devise, Devise.usd);
      expect(restaure.montantDevise, 179);
      appState.utiliserPourTest(repo);
    });

    test('taux du dollar : lu depuis les réglages, 0 par défaut', () async {
      final (repo, _) = await _repoAvecLot();
      expect(await repo.tauxDollar(), 0);
      await repo.setSetting(cleTauxDollar, '2800');
      expect(await repo.tauxDollar(), 2800);
      await repo.setSetting(cleTauxDollar, 'abc');
      expect(await repo.tauxDollar(), 0);
    });
  });

  group('Code des vendeurs', () {
    test('définir, vérifier, retirer ; jamais en clair', () async {
      final (repo, _) = await _repoAvecLot();
      final id = await repo.ajouterVendeur('Anne');
      expect((await repo.vendeurs()).single.aUnCode, isFalse);
      expect(await repo.verifierPinVendeur(id, '1234'), isFalse);

      await repo.definirPinVendeur(id, '1234');
      expect((await repo.vendeurs()).single.aUnCode, isTrue);
      expect(await repo.verifierPinVendeur(id, '1234'), isTrue);
      expect(await repo.verifierPinVendeur(id, '4321'), isFalse);
      final ligne = (await repo.db.query('vendeurs')).single;
      expect(ligne.values.map((v) => '$v').any((v) => v.contains('1234')), isFalse);

      await repo.definirPinVendeur(id, null);
      expect((await repo.vendeurs()).single.aUnCode, isFalse);
      expect(await repo.verifierPinVendeur(id, '1234'), isFalse);
    });

    test('deux vendeurs avec le même code ont des empreintes différentes (sel)', () async {
      final (repo, _) = await _repoAvecLot();
      final a = await repo.ajouterVendeur('A');
      final b = await repo.ajouterVendeur('B');
      await repo.definirPinVendeur(a, '1111');
      await repo.definirPinVendeur(b, '1111');
      final lignes = await repo.db.query('vendeurs', orderBy: 'id');
      expect(lignes[0]['pin_hash'], isNot(lignes[1]['pin_hash']));
    });

    test('essais limités et blocage enregistré, propres à chaque vendeur', () async {
      final (repo, _) = await _repoAvecLot();
      final a = await repo.ajouterVendeur('A');
      final b = await repo.ajouterVendeur('B');
      await repo.definirPinVendeur(a, '1111');
      await repo.definirPinVendeur(b, '2222');
      final t0 = DateTime(2026, 11, 3, 8);

      var r = const ResultatPin(StatutPin.correct);
      for (var i = 0; i < 5; i++) {
        r = await PinService.verifierVendeur(a, '000$i', maintenant: t0);
      }
      expect(r.statut, StatutPin.bloque);
      // Bloqué : même le bon code est refusé, et l'état est enregistré.
      expect(
          (await PinService.verifierVendeur(a, '1111',
                  maintenant: t0.add(const Duration(seconds: 5))))
              .statut,
          StatutPin.bloque);
      expect(await repo.getSetting('pin_v${a}_echecs'), '5');
      // L'autre vendeur n'est pas touché.
      expect((await PinService.verifierVendeur(b, '2222', maintenant: t0)).statut,
          StatutPin.correct);
      // Après l'attente, le bon code passe.
      expect(
          (await PinService.verifierVendeur(a, '1111',
                  maintenant: t0.add(const Duration(seconds: 40))))
              .statut,
          StatutPin.correct);
    });

    test('un changement de code remet les essais à zéro', () async {
      final (repo, _) = await _repoAvecLot();
      final a = await repo.ajouterVendeur('A');
      await repo.definirPinVendeur(a, '1111');
      for (var i = 0; i < 5; i++) {
        await PinService.verifierVendeur(a, '999$i');
      }
      await repo.definirPinVendeur(a, '3333');
      await PinService.reinitialiserEchecsVendeur(a);
      expect((await PinService.verifierVendeur(a, '3333')).statut,
          StatutPin.correct);
    });

    test('le vendeur protégé est oublié au verrouillage, pas les autres', () async {
      final (repo, _) = await _repoAvecLot();
      final libre = await repo.ajouterVendeur('Libre');
      final protege = await repo.ajouterVendeur('Protégé');
      await repo.definirPinVendeur(protege, '1234');

      await repo.definirVendeurActif(libre);
      await repo.oublierVendeurActifProtege();
      expect(await repo.vendeurActifId(), libre);

      await repo.definirVendeurActif(protege);
      await repo.oublierVendeurActifProtege();
      expect(await repo.vendeurActifId(), isNull);
    });

    test('les codes ne sont pas dans la sauvegarde, mais restent sur ce téléphone', () async {
      final (repo, _) = await _repoAvecLot();
      final id = await repo.ajouterVendeur('Anne');
      await repo.definirPinVendeur(id, '1234');

      final json = await Sauvegarde.decoderPourTest(await Sauvegarde.contenu(repo));
      final v = (json['vendeurs'] as List).single as Map;
      expect(v.containsKey('pin_hash'), isFalse);
      expect(v.containsKey('pin_sel'), isFalse);

      // Restauration sur le même téléphone : le code de Anne est conservé.
      await Sauvegarde.restaurer(repo, await Sauvegarde.contenu(repo));
      expect(await repo.verifierPinVendeur(id, '1234'), isTrue);

      // Un vendeur de même numéro mais de nom différent ne reprend pas ce code.
      final autre = Repo(await _neuve());
      final x = await autre.ajouterVendeur('Zoé');
      await autre.definirPinVendeur(x, '9999');
      await Sauvegarde.restaurer(autre, await Sauvegarde.contenu(repo));
      expect((await autre.vendeurs()).single.nom, 'Anne');
      expect(await autre.verifierPinVendeur(x, '9999'), isFalse);
      appState.utiliserPourTest(repo);
    });
  });
}
