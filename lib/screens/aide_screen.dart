import 'package:flutter/material.dart';

import '../state.dart';

/// Réglage mémorisant que le guide de première utilisation a été vu.
const String cleGuideVu = 'guide_vu';

/// Guide « Comment ça marche » : affiché automatiquement à la première
/// utilisation, puis disponible dans Réglages.
class AideScreen extends StatelessWidget {
  const AideScreen({super.key, this.premiereFois = false});

  /// Vrai à la première utilisation : bouton « Commencer » en bas.
  final bool premiereFois;

  static const List<_Etape> _etapes = [
    _Etape(
      Icons.picture_as_pdf_rounded,
      'Ajouter des tickets',
      'Importez le PDF de tickets : il est lu directement sur le téléphone, sans Internet. '
          'Si le PDF est introuvable ou mal lu, saisissez les codes à la main (Lots, bouton clavier).',
    ),
    _Etape(
      Icons.point_of_sale_rounded,
      'Vendre',
      'L\'écran Vente montre un ticket à la fois. Appuyez sur VENDU, choisissez le paiement '
          '(espèces par défaut), le client si vous voulez (facultatif) et la quantité si le client en prend plusieurs. '
          'Confirmez : le ticket suivant apparaît. La flèche d\'envoi du bandeau envoie le code au client.',
    ),
    _Etape(
      Icons.undo_rounded,
      'Se tromper ? Annuler',
      'Juste après une vente, le bouton ANNULER en haut remet le ticket en vente. '
          'Plus tard, utilisez Annuler (dernière vente) ou corrigez dans Lots.',
    ),
    _Etape(
      Icons.account_balance_wallet_outlined,
      'Crédit, mobile money, offert',
      'À la vente, choisissez À crédit pour un client qui paiera plus tard : le montant '
          'reste « à recevoir » jusqu\'à son paiement (Réglages > Clients et dettes).',
    ),
    _Etape(
      Icons.search_rounded,
      'Retrouver un ticket',
      'La loupe en haut de l\'écran Vente cherche un ticket par son code, ou les achats d\'un client. '
          'Dans Réglages : Clôture de caisse (argent compté contre argent attendu) et Suivi d\'utilisation (Excel du routeur).',
    ),
    _Etape(
      Icons.bar_chart_rounded,
      'Rapports',
      'Jour, semaine, mois ou période : argent encaissé, graphiques, heures de pointe. '
          'Partagez en texte, ou exportez en CSV (tableur) ou en PDF.',
    ),
    _Etape(
      Icons.cloud_done_outlined,
      'Protéger vos données',
      'Toutes vos ventes sont sur ce téléphone. Connectez Google Drive dans Réglages : '
          'une sauvegarde part automatiquement chaque heure, et les 10 dernières sont gardées.',
    ),
    _Etape(
      Icons.lock_outline_rounded,
      'Code PIN',
      'Votre code à 4 chiffres protège l\'application. Pensez-y bien : il n\'est pas '
          'dans les sauvegardes et ne peut pas être retrouvé.',
    ),
  ];

  Future<void> _terminer(BuildContext context) async {
    await appState.repo.setSetting(cleGuideVu, '1');
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      // À la première utilisation, on marque le guide comme vu quoi qu'il arrive.
      onPopInvokedWithResult: (_, _) {
        if (premiereFois) appState.repo.setSetting(cleGuideVu, '1');
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(premiereFois ? 'Bienvenue dans Mtandao' : 'Comment ça marche'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (premiereFois)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                    'Mtandao gère la vente de vos tickets Wi-Fi, même sans Internet. En bref :'),
              ),
            for (var i = 0; i < _etapes.length; i++)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        backgroundColor: cs.primaryContainer,
                        foregroundColor: cs.onPrimaryContainer,
                        child: Icon(_etapes[i].icone),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${i + 1}. ${_etapes[i].titre}',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(_etapes[i].texte),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (premiereFois) ...[
              const SizedBox(height: 12),
              FilledButton(
                style:
                    FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () => _terminer(context),
                child: const Text('Commencer'),
              ),
              const SizedBox(height: 4),
              const Text(
                'Vous retrouverez ce guide dans Réglages > Comment ça marche.',
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Etape {
  const _Etape(this.icone, this.titre, this.texte);
  final IconData icone;
  final String titre;
  final String texte;
}
