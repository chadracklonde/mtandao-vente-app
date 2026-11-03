import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao/format.dart';
import 'package:mtandao/models.dart';
import 'package:mtandao/widgets/dialogue_vente.dart';

Ticket _ticket() => Ticket(
      id: 1,
      lotId: 1,
      position: 0,
      numero: 1,
      code: 'ABC123',
      motDePasse: null,
      qrTexte: null,
      prix: 1000,
      forfaitId: 1,
      vendu: false,
      venduLe: null,
    );

/// Ouvre la fenêtre et mémorise le choix retourné.
Future<Future<ChoixVente?> Function()> _ouvrir(
  WidgetTester tester, {
  List<Client> clients = const [],
  String? vendeurNom,
  int tauxDollar = 0,
  Future<int> Function(String, String?)? creerClient,
}) async {
  ChoixVente? resultat;
  var termine = false;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              resultat = await demanderVente(
                context,
                ticket: _ticket(),
                clients: clients,
                vendeurNom: vendeurNom,
                tauxDollar: tauxDollar,
                creerClient: creerClient ?? (n, t) async => 99,
              );
              termine = true;
            },
            child: const Text('ouvrir'),
          ),
        ),
      ),
    ),
  ));
  return () async {
    expect(termine, isTrue);
    return resultat;
  };
}

void main() {
  testWidgets('espèces par défaut, une seule action pour valider', (tester) async {
    final resultat = await _ouvrir(tester, vendeurNom: 'Jean');
    await tester.pumpAndSettle();
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();

    expect(find.textContaining('ABC123'), findsOneWidget);
    expect(find.textContaining(cdf(1000)), findsOneWidget);
    expect(find.text('Vendeur : Jean'), findsOneWidget);

    await tester.tap(find.text('Oui, vendu'));
    await tester.pumpAndSettle();
    final choix = await resultat();
    expect(choix!.paiement, Paiement.especes);
    expect(choix.clientId, isNull);
  });

  testWidgets('« Non » annule la vente', (tester) async {
    final resultat = await _ouvrir(tester);
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Non'));
    await tester.pumpAndSettle();
    expect(await resultat(), isNull);
  });

  testWidgets('mobile money et offert sont possibles', (tester) async {
    final resultat = await _ouvrir(tester);
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Offert'));
    await tester.pumpAndSettle();
    expect(find.textContaining('aucun montant ne sera encaissé'), findsOneWidget);
    await tester.tap(find.text('Mobile money'));
    await tester.pumpAndSettle();
    expect(find.textContaining('aucun montant ne sera encaissé'), findsNothing);
    await tester.tap(find.text('Oui, vendu'));
    await tester.pumpAndSettle();
    expect((await resultat())!.paiement, Paiement.mobile);
  });

  testWidgets('à crédit : impossible de valider sans client', (tester) async {
    final resultat = await _ouvrir(tester, clients: const [Client(id: 5, nom: 'Marie')]);
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('À crédit'));
    await tester.pumpAndSettle();

    FilledButton bouton() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Oui, vendu'));
    expect(bouton().onPressed, isNull);

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marie').last);
    await tester.pumpAndSettle();
    expect(bouton().onPressed, isNotNull);

    await tester.tap(find.text('Oui, vendu'));
    await tester.pumpAndSettle();
    final choix = (await resultat())!;
    expect(choix.paiement, Paiement.credit);
    expect(choix.clientId, 5);
  });

  testWidgets('à crédit : création d\'un nouveau client', (tester) async {
    String? nomCree;
    String? telCree;
    final resultat = await _ouvrir(tester, creerClient: (nom, tel) async {
      nomCree = nom;
      telCree = tel;
      return 42;
    });
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('À crédit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nouveau client'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Nom'), '  Paul ');
    await tester.enterText(
        find.widgetWithText(TextField, 'Téléphone (facultatif)'), '0812345678');
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();

    expect(nomCree, 'Paul');
    expect(telCree, '0812345678');
    // Le nouveau client est affiché comme choisi dans la liste.
    expect(find.text('Paul'), findsOneWidget);
    await tester.tap(find.text('Oui, vendu'));
    await tester.pumpAndSettle();
    final choix = (await resultat())!;
    expect(choix.paiement, Paiement.credit);
    expect(choix.clientId, 42);
  });

  group('paiement en dollars', () {
    testWidgets('sans taux, la monnaie n\'est pas proposée', (tester) async {
      final resultat = await _ouvrir(tester);
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      expect(find.text('Monnaie reçue'), findsNothing);
      await tester.tap(find.text('Oui, vendu'));
      await tester.pumpAndSettle();
      final choix = (await resultat())!;
      expect(choix.devise, Devise.cdf);
      expect(choix.taux, isNull);
    });

    testWidgets('avec un taux : le montant à recevoir en dollars et le taux sont retournés', (tester) async {
      final resultat = await _ouvrir(tester, tauxDollar: 2800);
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      expect(find.text('Monnaie reçue'), findsOneWidget);
      expect(find.textContaining('À recevoir :'), findsNothing); // francs par défaut

      await tester.tap(find.text('Dollars (USD)'));
      await tester.pumpAndSettle();
      // 1 000 CDF au taux de 2 800 = 0,36 dollar.
      expect(find.textContaining('À recevoir : 0,36 USD'), findsOneWidget);

      await tester.tap(find.text('Oui, vendu'));
      await tester.pumpAndSettle();
      final choix = (await resultat())!;
      expect(choix.paiement, Paiement.especes);
      expect(choix.devise, Devise.usd);
      expect(choix.taux, 2800);
    });

    testWidgets('le dollar disparaît pour un crédit ou un ticket offert, et revient avec le mobile money', (tester) async {
      await _ouvrir(tester, tauxDollar: 2800, clients: const [Client(id: 1, nom: 'M')]);
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dollars (USD)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Offert'));
      await tester.pumpAndSettle();
      expect(find.text('Monnaie reçue'), findsNothing);

      await tester.tap(find.text('Mobile money'));
      await tester.pumpAndSettle();
      // On repasse en francs quand le dollar a été indisponible.
      expect(find.text('Monnaie reçue'), findsOneWidget);
      expect(find.textContaining('À recevoir :'), findsNothing);

      await tester.tap(find.text('À crédit'));
      await tester.pumpAndSettle();
      expect(find.text('Monnaie reçue'), findsNothing);
    });
  });
}
