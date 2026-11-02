import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mtandao/models.dart';
import 'package:mtandao/rapport.dart';
import 'package:mtandao/rapport_export.dart';

VenteLigne vente(
  String code, {
  int prix = 1000,
  String paiement = Paiement.especes,
  String? client,
  String? vendeur,
  String forfait = '1 jour',
}) =>
    VenteLigne(
      code: code,
      prix: prix,
      venduLe: DateTime(2026, 11, 2, 14, 30),
      forfaitNom: forfait,
      lotNom: 'Lot A',
      paiement: paiement,
      clientNom: client,
      vendeurNom: vendeur,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('fr'));

  group('CSV', () {
    test('commence par la marque UTF-8 et l\'en-tête, lignes séparées par CRLF', () {
      final csv = RapportExport.csv([vente('123456')]);
      expect(csv.startsWith('﻿Date;Heure;Code;'), isTrue);
      final lignes = csv.trim().split('\r\n');
      expect(lignes, hasLength(2));
      expect(lignes[1], '02/11/2026;14:30;123456;1 jour;Lot A;1000;Espèces;1000;;');
    });

    test('donne le montant encaissé selon le paiement', () {
      final csv = RapportExport.csv([
        vente('a', paiement: Paiement.credit, client: 'Marie'),
        vente('b', paiement: Paiement.offert),
        vente('c', paiement: Paiement.mobile),
      ]);
      final l = csv.trim().split('\r\n');
      expect(l[1], endsWith(';À crédit;0;Marie;'));
      expect(l[2], contains(';Offert;0;'));
      expect(l[3], contains(';Mobile money;1000;'));
    });

    test('met entre guillemets les champs avec point-virgule ou guillemet', () {
      expect(RapportExport.champ('a;b'), '"a;b"');
      expect(RapportExport.champ('dit "oui"'), '"dit ""oui"""');
      expect(RapportExport.champ('ligne\nsuivante'), '"ligne\nsuivante"');
      expect(RapportExport.champ('simple'), 'simple');
      expect(RapportExport.champ(null), '');
    });

    test('neutralise les formules de tableur', () {
      expect(RapportExport.champ('=SOMME(A1)'), "'=SOMME(A1)");
      expect(RapportExport.champ('+33 1 23'), "'+33 1 23");
      expect(RapportExport.champ('@cmd'), "'@cmd");
      expect(RapportExport.champ('-abc'), "'-abc");
      final csv = RapportExport.csv([vente('1', client: '=HYPERLINK("x")')]);
      expect(csv, contains("'=HYPERLINK"));
    });
  });

  group('PDF', () {
    test('produit un vrai PDF avec accents, crédits et vendeurs', () async {
      final rapport = Rapport([
        vente('111', vendeur: 'Éloïse'),
        vente('222', paiement: Paiement.credit, client: 'Amélie', vendeur: 'Éloïse'),
        vente('333', paiement: Paiement.offert),
        vente('444', forfait: '1 semaine', prix: 5000),
      ]);
      final octets = await RapportExport.pdf(
          titre: 'Lundi 2 novembre 2026', rapport: rapport, detailParJour: true);
      expect(String.fromCharCodes(octets.take(5)), '%PDF-');
      expect(octets.length, greaterThan(1000));
    });

    test('un rapport sans vente se génère aussi', () async {
      final octets =
          await RapportExport.pdf(titre: 'Période vide', rapport: Rapport(const []));
      expect(String.fromCharCodes(octets.take(5)), '%PDF-');
    });

    test('beaucoup de ventes : plusieurs pages, sans erreur', () async {
      final rapport = Rapport([for (var i = 0; i < 400; i++) vente('C$i')]);
      final octets = await RapportExport.pdf(titre: 'Gros mois', rapport: rapport);
      expect(String.fromCharCodes(octets.take(5)), '%PDF-');
    });
  });
}
