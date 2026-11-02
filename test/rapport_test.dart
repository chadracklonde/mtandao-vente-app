import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao/models.dart';
import 'package:mtandao/rapport.dart';

VenteLigne v(
  String code,
  int prix, {
  String paiement = Paiement.especes,
  String forfait = '1 jour',
  String? vendeur,
  DateTime? le,
  DateTime? payeLe,
}) =>
    VenteLigne(
      code: code,
      prix: prix,
      venduLe: le ?? DateTime(2026, 11, 2, 10),
      forfaitNom: forfait,
      lotNom: 'Lot',
      paiement: paiement,
      vendeurNom: vendeur,
      clientNom: paiement == Paiement.credit ? 'Client' : null,
      payeLe: payeLe,
    );

void main() {
  group('Rapport', () {
    test('période sans vente', () {
      final r = Rapport(const []);
      expect(r.nombre, 0);
      expect(r.encaisse, 0);
      expect(r.heureDePointe, isNull);
      expect(r.aDesVendeurs, isFalse);
    });

    test('espèces et mobile money sont encaissés', () {
      final r = Rapport([v('a', 1000), v('b', 1000, paiement: Paiement.mobile)]);
      expect(r.nombre, 2);
      expect(r.encaisse, 2000);
      expect(r.aRecevoir, 0);
    });

    test('crédit non payé : à recevoir, pas encaissé ; payé : encaissé', () {
      final r = Rapport([
        v('a', 1000, paiement: Paiement.credit),
        v('b', 500, paiement: Paiement.credit, payeLe: DateTime(2026, 11, 3)),
      ]);
      expect(r.nombre, 2);
      expect(r.encaisse, 500);
      expect(r.aRecevoir, 1000);
    });

    test('offert : compté comme ticket, rien encaissé', () {
      final r = Rapport([v('a', 1000, paiement: Paiement.offert), v('b', 1000)]);
      expect(r.nombre, 2);
      expect(r.offerts, 1);
      expect(r.encaisse, 1000);
    });

    test('totaux par forfait, mode de paiement et vendeur', () {
      final r = Rapport([
        v('a', 1000, vendeur: 'Jean'),
        v('b', 1000, vendeur: 'Jean', paiement: Paiement.mobile),
        v('c', 5000, forfait: '1 semaine', vendeur: 'Anne'),
        v('d', 1000),
      ]);
      expect(r.parForfait['1 jour']!.nombre, 3);
      expect(r.parForfait['1 semaine']!.montant, 5000);
      expect(r.parPaiement[Paiement.especes]!.nombre, 3);
      expect(r.parPaiement[Paiement.mobile]!.nombre, 1);
      expect(r.parVendeur['Jean']!.montant, 2000);
      expect(r.parVendeur['Anne']!.nombre, 1);
      expect(r.parVendeur['Sans vendeur']!.nombre, 1);
      expect(r.aDesVendeurs, isTrue);
    });

    test('par jour du plus récent au plus ancien', () {
      final r = Rapport([
        v('a', 1000, le: DateTime(2026, 11, 1, 9)),
        v('b', 1000, le: DateTime(2026, 11, 3, 9)),
        v('c', 1000, le: DateTime(2026, 11, 3, 15)),
      ]);
      expect(r.parJour.keys.toList(),
          [DateTime(2026, 11, 3), DateTime(2026, 11, 1)]);
      expect(r.parJour[DateTime(2026, 11, 3)]!.nombre, 2);
    });

    test('heures de pointe', () {
      final r = Rapport([
        v('a', 1000, le: DateTime(2026, 11, 2, 9, 5)),
        v('b', 1000, le: DateTime(2026, 11, 2, 18, 5)),
        v('c', 1000, le: DateTime(2026, 11, 2, 18, 55)),
        v('d', 1000, le: DateTime(2026, 11, 3, 18, 1)),
      ]);
      expect(r.parHeure[18], 3);
      expect(r.parHeure[9], 1);
      expect(r.heureDePointe, 18);
      expect(r.parHeure.fold<int>(0, (a, b) => a + b), 4);
    });

    test('évolution par rapport à la période précédente', () {
      expect(Rapport.evolution(1200, 1000), 20);
      expect(Rapport.evolution(500, 1000), -50);
      expect(Rapport.evolution(1000, 1000), 0);
      expect(Rapport.evolution(1000, 0), isNull);
    });

    test('texte partagé : pluriels, crédits, offerts, vendeurs', () {
      final r = Rapport([
        v('a', 1000, vendeur: 'Jean'),
        v('b', 1000, paiement: Paiement.credit, vendeur: 'Jean'),
        v('c', 1000, paiement: Paiement.offert),
      ]);
      final t = r.texte('Lundi', detailParJour: false);
      expect(t, contains('Tickets vendus : 3'));
      expect(t, contains('À recevoir (crédits)'));
      expect(t, contains('Tickets offerts : 1'));
      expect(t, contains('- Jean : 2 tickets'));
      expect(t, contains('- Sans vendeur : 1 ticket,'));
      expect(t, isNot(contains('1 tickets')));
    });
  });
}
