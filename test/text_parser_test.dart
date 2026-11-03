import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao/format.dart';
import 'package:mtandao/text_parser.dart';

void main() {
  prixTests();
  group('TextTicketParser', () {
    test('lit les codes et la durée du modèle « Tickets Wi-Fi »', () {
      const texte = 'Tickets Wi-Fi\n'
          'Code : 461232 Code : 956761\n'
          'Durée : 1jour(s) Durée : 1jour(s)\n'
          'Code : 023221\n'
          'Durée : 1jour(s)\n';
      final r = TextTicketParser.parse(texte);
      expect(r.map((t) => t.code).toList(), ['461232', '956761', '023221']);
      expect(r.every((t) => t.dureeMinutes == 1440), isTrue);
      expect(TextTicketParser.dureeCommune(r), 1440);
    });

    test('garde les zéros du début', () {
      final r = TextTicketParser.parse('Code : 094243\nDurée : 1jour(s)');
      expect(r.single.code, '094243');
    });

    test('supporte un texte sans séparateur entre code et durée', () {
      final r = TextTicketParser.parse('Code : 461232Durée : 1jour(s)');
      expect(r.single.code, '461232');
      expect(r.single.dureeMinutes, 1440);
    });

    test('reconnaît les autres durées', () {
      final r = TextTicketParser.parse(
          'Code : 111111\nDurée : 1heure(s)\nCode : 222222\nDurée : 1semaine(s)\nCode : 333333\nDurée : 1mois');
      expect(r.map((t) => t.dureeMinutes).toList(), [60, 10080, 43200]);
      expect(TextTicketParser.dureeCommune(r), isNull);
    });

    test('un texte quelconque n\'est pas pris pour le modèle', () {
      expect(TextTicketParser.ressembleAuModele('Bonjour le monde'), isFalse);
      expect(
          TextTicketParser.ressembleAuModele('Code : 123\nDurée : 1jour(s)'),
          isTrue);
    });
  });

  group('format', () {
    test('séparateur de milliers', () {
      expect(fmtInt(1000), '1 000');
      expect(fmtInt(12), '12');
      expect(cdf(167000), '167 000 CDF');
    });

    test('libellé de durée', () {
      expect(libelleDuree(60), '1 h');
      expect(libelleDuree(1440), '1 jour');
      expect(libelleDuree(10080), '1 semaine');
      expect(libelleDuree(43200), '1 mois');
    });
  });
}

void prixTests() {
  group('Prix lu dans le texte', () {
    test('un nombre avec séparateurs de milliers', () {
      expect(TextTicketParser.entierDe('1000'), 1000);
      expect(TextTicketParser.entierDe('1 000'), 1000);
      expect(TextTicketParser.entierDe('1 000'), 1000);
      expect(TextTicketParser.entierDe('1.000'), 1000);
      expect(TextTicketParser.entierDe('1,000'), 1000);
      expect(TextTicketParser.entierDe('2.500.000'), 2500000);
    });

    test('une partie décimale est arrondie', () {
      expect(TextTicketParser.entierDe('1500,50'), 1501);
      expect(TextTicketParser.entierDe('1500.4'), 1500);
    });

    test('pas un nombre', () {
      expect(TextTicketParser.entierDe(''), isNull);
      expect(TextTicketParser.entierDe('abc'), isNull);
      expect(TextTicketParser.entierDe('12ab'), isNull);
    });

    test('Prix, Price, Tarif, Montant, avec ou sans monnaie', () {
      for (final ligne in [
        'Prix : 1000 CDF',
        'Price: 1 000',
        'Tarif : 1.000 FC',
        'montant : 1000',
      ]) {
        final r = TextTicketParser.parse('Code : 111111\nDurée : 1jour(s)\n$ligne');
        expect(r.single.prix, 1000, reason: ligne);
      }
    });

    test('un prix par ticket quand les nombres concordent', () {
      final r = TextTicketParser.parse(
          'Code : 111111 Durée : 1jour(s) Prix : 500\nCode : 222222 Durée : 1jour(s) Prix : 800');
      expect(r.map((t) => t.prix), [500, 800]);
      expect(TextTicketParser.prixCommun(r), isNull); // différents : pas de prix commun
    });

    test('un seul prix imprimé pour tout le document : il vaut pour chaque ticket', () {
      final r = TextTicketParser.parse(
          'Prix : 1500\nCode : 111111 Durée : 1jour(s)\nCode : 222222 Durée : 1jour(s)\nCode : 333333 Durée : 1jour(s)');
      expect(r.map((t) => t.prix), [1500, 1500, 1500]);
      expect(TextTicketParser.prixCommun(r), 1500);
    });

    test('aucun prix imprimé : aucun prix', () {
      final r = TextTicketParser.parse('Code : 111111\nDurée : 1jour(s)');
      expect(r.single.prix, isNull);
      expect(TextTicketParser.prixCommun(r), isNull);
    });
  });
}
