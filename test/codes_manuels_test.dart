import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao/codes_manuels.dart';

void main() {
  group('CodesManuels.lire', () {
    test('un code par ligne', () {
      final r = CodesManuels.lire('461232\n461233\n461234');
      expect(r.tickets.map((t) => t.code), ['461232', '461233', '461234']);
      expect(r.tickets.every((t) => t.motDePasse == null), isTrue);
      expect(r.lignesRejetees, isEmpty);
    });

    test('code et mot de passe, séparés par espace, tabulation, virgule ou point-virgule', () {
      final r = CodesManuels.lire('a1 b1\nc2\td2\ne3,f3\ng4;h4');
      expect(r.tickets.map((t) => (t.code, t.motDePasse)),
          [('a1', 'b1'), ('c2', 'd2'), ('e3', 'f3'), ('g4', 'h4')]);
    });

    test('ignore les lignes vides et les espaces autour, accepte \\r\\n', () {
      final r = CodesManuels.lire('  111  \r\n\r\n\n 222 \r\n');
      expect(r.tickets.map((t) => t.code), ['111', '222']);
      expect(r.lignesRejetees, isEmpty);
    });

    test('rejette les lignes illisibles en donnant leur numéro', () {
      final r = CodesManuels.lire('ok1\nun deux trois\nok2\nabc\$def\nok3');
      expect(r.tickets.map((t) => t.code), ['ok1', 'ok2', 'ok3']);
      expect(r.lignesRejetees, [2, 4]);
    });

    test('un code écrit deux fois n\'est gardé qu\'une fois', () {
      final r = CodesManuels.lire('x1\nx2\nx1\nx1');
      expect(r.tickets.map((t) => t.code), ['x1', 'x2']);
      expect(r.doublonsSaisis, 2);
    });

    test('texte vide', () {
      final r = CodesManuels.lire('  \n \n');
      expect(r.tickets, isEmpty);
      expect(r.lignesRejetees, isEmpty);
    });

    test('accepte les caractères courants des codes Wi-Fi', () {
      final r = CodesManuels.lire('AB-12_cd.3\nuser@wifi');
      expect(r.tickets, hasLength(2));
    });

    test('refuse un code trop long', () {
      final r = CodesManuels.lire('a' * 65);
      expect(r.tickets, isEmpty);
      expect(r.lignesRejetees, [1]);
    });
  });
}
