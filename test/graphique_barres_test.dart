import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao/widgets/graphique_barres.dart';

void main() {
  group('indicesEtiquettes', () {
    test('peu de barres : toutes étiquetées', () {
      expect(GraphiqueBarres.indicesEtiquettes(7, 350, 30), [0, 1, 2, 3, 4, 5, 6]);
    });

    test('beaucoup de barres : une étiquette sur plusieurs, sans chevauchement', () {
      final i = GraphiqueBarres.indicesEtiquettes(31, 310, 30);
      expect(i.first, 0);
      // 10 px par barre, 30 px par étiquette : une sur trois.
      expect(i.take(4).toList(), [0, 3, 6, 9]);
      for (var k = 1; k < i.length; k++) {
        expect((i[k] - i[k - 1]) * (310 / 31), greaterThanOrEqualTo(30));
      }
    });

    test('cas limites', () {
      expect(GraphiqueBarres.indicesEtiquettes(0, 300, 30), isEmpty);
      expect(GraphiqueBarres.indicesEtiquettes(5, 0, 30), isEmpty);
      expect(GraphiqueBarres.indicesEtiquettes(1, 300, 30), [0]);
    });
  });

  group('GraphiqueBarres', () {
    Future<void> afficher(WidgetTester t, List<BarreDonnee> d, {double largeur = 320}) =>
        t.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: largeur,
                child: GraphiqueBarres(donnees: d, resume: 'Résumé du graphique'),
              ),
            ),
          ),
        ));

    testWidgets('se dessine sans erreur : vide, zéros, une barre, 31 barres', (t) async {
      await afficher(t, const []);
      await afficher(t, const [BarreDonnee('1', 0), BarreDonnee('2', 0)]);
      await afficher(t, const [BarreDonnee('1', 5)]);
      await afficher(t, [for (var i = 1; i <= 31; i++) BarreDonnee('$i', i * 100)]);
      await afficher(t, [for (var i = 0; i < 24; i++) BarreDonnee('$i', i % 5)], largeur: 120);
      expect(tester(t), isNull);
    });

    testWidgets('le lecteur d\'écran lit le résumé, pas le dessin', (t) async {
      final poignee = t.ensureSemantics();
      await afficher(t, const [BarreDonnee('1', 5)]);
      expect(find.bySemanticsLabel('Résumé du graphique'), findsOneWidget);
      poignee.dispose();
    });
  });
}

// Aucune exception ne doit avoir été levée pendant les dessins ci-dessus.
Object? tester(WidgetTester t) => t.takeException();
