import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao/format.dart';
import 'package:mtandao/text_parser.dart';

void main() {
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
