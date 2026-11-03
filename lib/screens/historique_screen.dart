import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../format.dart';
import '../message_ticket.dart';
import '../models.dart';
import '../widgets/code_vendeur.dart';
import '../state.dart';

/// Recherche d'un ticket par son code, ou par le nom / téléphone du client ou
/// du vendeur. Sans texte : les ventes les plus récentes.
class HistoriqueScreen extends StatefulWidget {
  const HistoriqueScreen({super.key});

  @override
  State<HistoriqueScreen> createState() => _HistoriqueScreenState();
}

class _HistoriqueScreenState extends State<HistoriqueScreen> {
  final _champ = TextEditingController();
  List<TicketRecherche> _resultats = [];
  bool _chargement = true;
  int _requete = 0;

  @override
  void initState() {
    super.initState();
    appState.addListener(_chercher);
    _chercher();
  }

  @override
  void dispose() {
    appState.removeListener(_chercher);
    _champ.dispose();
    super.dispose();
  }

  Future<void> _chercher() async {
    final numero = ++_requete;
    final r = await appState.repo.rechercher(_champ.text);
    // Une recherche plus récente est partie entre-temps : on ignore celle-ci.
    if (!mounted || numero != _requete) return;
    setState(() {
      _resultats = r;
      _chargement = false;
    });
  }

  static String _statut(Ticket t) {
    if (t.defectueux && !t.vendu) return 'Défectueux';
    if (!t.vendu) return 'En stock';
    if (t.paiement == Paiement.credit) {
      return t.payeLe == null ? 'À crédit, non payé' : 'Crédit payé';
    }
    return 'Vendu · ${Paiement.libelle(t.paiement)}';
  }

  Future<void> _details(TicketRecherche r) async {
    final t = r.ticket;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.code,
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 2)),
              const SizedBox(height: 6),
              Text('${r.forfaitNom}  ·  ${cdf(t.prix)}'),
              Text(_statut(t)),
              if (t.venduLe != null) Text('Vendu le ${fmtDateHeure(t.venduLe!)}'),
              if (r.clientNom != null)
                Text(
                    'Client : ${r.clientNom}${r.clientTelephone == null ? '' : '  ·  ${r.clientTelephone}'}'),
              if (r.vendeurNom != null) Text('Vendeur : ${r.vendeurNom}'),
              if (t.annulations > 0)
                Text('Vente annulée ${t.annulations} fois'),
              if (t.utiliseLe != null)
                Text('Utilisé sur le réseau (${fmtDateHeure(t.utiliseLe!)})'),
              Text('Lot : ${r.lotNom}'),
              const SizedBox(height: 14),
              if (t.vendu)
                FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'envoyer'),
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Envoyer le code'),
                ),
              if (t.vendu && t.paiement == Paiement.credit && t.payeLe == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(ctx, 'paye'),
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Le client a payé'),
                  ),
                ),
              if (t.vendu)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(ctx, 'annuler'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(ctx).colorScheme.error),
                    icon: const Icon(Icons.undo_rounded),
                    label: const Text('Annuler cette vente'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    final repo = appState.repo;
    switch (action) {
      case 'envoyer':
        final lot = await repo.lot(t.lotId);
        final url = lot?.loginUrl ??
            (await repo.getSetting('login_url')) ??
            'http://mtandao.wifi';
        await Share.share(messageTickets(
            tickets: [t],
            forfaitNom: r.forfaitNom,
            url: url,
            clientNom: r.clientNom));
      case 'paye':
        await repo.marquerPaye(t.id);
        appState.changed();
      case 'annuler':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Annuler cette vente ?'),
            content: Text(
                'Le ticket ${t.code} sera remis en vente et son montant retiré des totaux.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Non')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Oui, annuler')),
            ],
          ),
        );
        if (ok == true) {
          if (!mounted) return;
          if (!await demanderCodePatron(context,
              raison: 'Annuler une vente ici est réservé au patron.')) {
            return;
          }
          await repo.remettreEnStock(t.id);
          appState.changed();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Rechercher un ticket')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _champ,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: (_) => _chercher(),
              decoration: InputDecoration(
                hintText: 'Code, nom ou téléphone du client…',
                prefixIcon: const Icon(Icons.search_rounded),
                border: const OutlineInputBorder(),
                suffixIcon: _champ.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Effacer',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _champ.clear();
                          _chercher();
                          setState(() {});
                        },
                      ),
              ),
            ),
          ),
          if (_champ.text.trim().isEmpty && !_chargement)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Dernières ventes',
                    style: Theme.of(context).textTheme.labelLarge),
              ),
            ),
          Expanded(
            child: _chargement
                ? const Center(child: CircularProgressIndicator())
                : _resultats.isEmpty
                    ? const Center(child: Text('Aucun ticket trouvé.'))
                    : ListView.separated(
                        itemCount: _resultats.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final r = _resultats[i];
                          final t = r.ticket;
                          final enAttente = t.vendu &&
                              t.paiement == Paiement.credit &&
                              t.payeLe == null;
                          return ListTile(
                            onTap: () => _details(r),
                            title: Text(t.code,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1)),
                            subtitle: Text([
                              r.forfaitNom,
                              _statut(t),
                              if (r.clientNom != null) r.clientNom!,
                              if (t.venduLe != null) fmtDateHeure(t.venduLe!),
                            ].join('  ·  ')),
                            trailing: Text(cdf(t.prix),
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: enAttente ? cs.error : null)),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
