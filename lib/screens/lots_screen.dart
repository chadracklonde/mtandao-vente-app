import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../state.dart';
import '../widgets/dialogues.dart';
import 'import_flow.dart';
import 'saisie_manuelle.dart';

/// Liste des lots de tickets importés (un lot = un PDF).
class LotsScreen extends StatefulWidget {
  const LotsScreen({super.key, required this.surVendre});

  /// Appelé quand l'utilisateur choisit de vendre depuis un lot.
  final VoidCallback surVendre;

  @override
  State<LotsScreen> createState() => _LotsScreenState();
}

class _LotsScreenState extends State<LotsScreen> {
  List<Lot> _lots = [];
  bool _chargement = true;

  @override
  void initState() {
    super.initState();
    appState.addListener(_charger);
    _charger();
  }

  @override
  void dispose() {
    appState.removeListener(_charger);
    super.dispose();
  }

  Future<void> _charger() async {
    final lots = await appState.repo.lots();
    if (!mounted) return;
    setState(() {
      _lots = lots;
      _chargement = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lots de tickets'),
        actions: [
          IconButton(
            tooltip: 'Saisir des codes à la main',
            icon: const Icon(Icons.keyboard_alt_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const SaisieManuelleScreen())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => ImportFlow.demarrer(context),
        icon: const Icon(Icons.picture_as_pdf_rounded),
        label: const Text('Importer un PDF'),
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _lots.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.confirmation_number_outlined,
                            size: 64,
                            color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 12),
                        Text('Aucun lot pour le moment',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        const Text(
                          'Importez un PDF de tickets pour commencer.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                  itemCount: _lots.length,
                  itemBuilder: (context, i) => _carte(context, _lots[i]),
                ),
    );
  }

  Widget _carte(BuildContext context, Lot lot) {
    final actif = appState.lotActifId == lot.id;
    final fini = lot.restants == 0;
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final r = await Navigator.of(context).push<String>(
            MaterialPageRoute(builder: (_) => LotDetailScreen(lotId: lot.id)),
          );
          if (r == 'vente') widget.surVendre();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(lot.nom,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (actif)
                    Chip(
                      label: const Text('En vente'),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: cs.primaryContainer,
                    )
                  else if (fini)
                    const Chip(
                      label: Text('Terminé'),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              Text(
                '${lot.forfaitNom}  ·  importé le ${fmtJourCourt(lot.creeLe)}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: lot.total == 0 ? 0 : lot.vendus / lot.total,
                  semanticsLabel: 'Progression du lot',
                  semanticsValue: '${lot.vendus} tickets vendus sur ${lot.total}',
                ),
              ),
              const SizedBox(height: 8),
              Text.rich(TextSpan(children: [
                TextSpan(
                  text: '${lot.restants} restants',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text:
                      '  ·  ${lot.vendus} vendus sur ${lot.total}  ·  ${cdf(lot.montant)}'
                      '${lot.defectueux > 0 ? '  ·  ${lot.defectueux} défectueux' : ''}',
                ),
              ])),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vert lisible sur fond clair comme sur fond sombre.
Color _vert(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? Colors.green.shade300
        : Colors.green.shade800;

enum _Filtre { tous, restants, vendus, defectueux }

/// Détail d'un lot : liste des tickets, recherche, corrections.
class LotDetailScreen extends StatefulWidget {
  const LotDetailScreen({super.key, required this.lotId});
  final int lotId;

  @override
  State<LotDetailScreen> createState() => _LotDetailScreenState();
}

class _LotDetailScreenState extends State<LotDetailScreen> {
  Lot? _lot;
  List<Ticket> _tickets = [];
  bool _chargement = true;
  _Filtre _filtre = _Filtre.tous;
  String _recherche = '';

  @override
  void initState() {
    super.initState();
    appState.addListener(_charger);
    _charger();
  }

  @override
  void dispose() {
    appState.removeListener(_charger);
    super.dispose();
  }

  Future<void> _charger() async {
    final lot = await appState.repo.lot(widget.lotId);
    final tickets = lot == null
        ? <Ticket>[]
        : await appState.repo.ticketsDuLot(widget.lotId);
    if (!mounted) return;
    if (lot == null) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _lot = lot;
      _tickets = tickets;
      _chargement = false;
    });
  }

  Future<void> _renommer() async {
    final lot = _lot;
    if (lot == null) return;
    final nom = await demanderTexte(
      context,
      titre: 'Renommer le lot',
      libelle: 'Nom du lot',
      initial: lot.nom,
    );
    if (nom == null || nom.isEmpty) return;
    await appState.repo.renommerLot(lot.id, nom);
    appState.changed();
  }

  Future<void> _supprimer() async {
    final lot = _lot;
    if (lot == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: const Text('Supprimer ce lot ?'),
        content: Text(
            'Les ${lot.total} tickets de « ${lot.nom} » seront effacés, y compris l\'historique de ${lot.vendus} ventes (${cdf(lot.montant)}). Les rapports changeront. Cette action est définitive.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await appState.repo.supprimerLot(lot.id);
    if (appState.lotActifId == lot.id) await appState.definirLotActif(null);
    appState.changed();
  }

  Future<void> _basculer(Ticket t) async {
    if (t.vendu) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Remettre en vente ?'),
          content: Text(
              'Le ticket ${t.code} sera de nouveau disponible et son montant retiré des rapports.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Non')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Oui')),
          ],
        ),
      );
      if (ok != true) return;
      await appState.repo.remettreEnStock(t.id);
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Marquer comme vendu ?'),
          content: Text(
              'Le ticket ${t.code} sera compté comme vendu maintenant (${cdf(t.prix)}).'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Non')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Oui')),
          ],
        ),
      );
      if (ok != true) return;
      await appState.repo.vendre(t.id);
    }
    appState.changed();
  }

  Future<void> _signalerDefectueux(Ticket t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Signaler ce ticket défectueux ?'),
        content: Text(
            'Le ticket ${t.code} ne sera plus proposé à la vente ni compté dans les restants. Vous pourrez l\'annuler plus tard.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Non')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Oui, défectueux')),
        ],
      ),
    );
    if (ok != true) return;
    await appState.repo.signalerDefectueux(t.id);
    appState.changed();
  }

  Future<void> _reactiver(Ticket t) async {
    await appState.repo.reactiverTicket(t.id);
    appState.changed();
  }

  @override
  Widget build(BuildContext context) {
    final lot = _lot;
    return Scaffold(
      appBar: AppBar(
        title: Text(lot?.nom ?? 'Lot', overflow: TextOverflow.ellipsis),
        actions: [
          if (lot != null)
            IconButton(
              tooltip: 'Ajouter des codes à ce lot',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SaisieManuelleScreen(lot: lot))),
              icon: const Icon(Icons.playlist_add_rounded),
            ),
          IconButton(
              tooltip: 'Renommer',
              onPressed: _renommer,
              icon: const Icon(Icons.edit_outlined)),
          IconButton(
              tooltip: 'Supprimer',
              onPressed: _supprimer,
              icon: const Icon(Icons.delete_outline_rounded)),
        ],
      ),
      body: _chargement || lot == null
          ? const Center(child: CircularProgressIndicator())
          : _corps(context, lot),
    );
  }

  Widget _corps(BuildContext context, Lot lot) {
    final q = _recherche.trim();
    // Le filtre « Défectueux » n'existe que s'il y en a.
    final filtre =
        _filtre == _Filtre.defectueux && lot.defectueux == 0 ? _Filtre.tous : _filtre;
    final liste = _tickets.where((t) {
      if (filtre == _Filtre.restants && (t.vendu || t.defectueux)) return false;
      if (filtre == _Filtre.vendus && !t.vendu) return false;
      if (filtre == _Filtre.defectueux && !t.defectueux) return false;
      if (q.isNotEmpty && !t.code.toLowerCase().contains(q.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            children: [
              Text(
                '${lot.vendus} vendus sur ${lot.total}  ·  ${lot.restants} restants\n${cdf(lot.montant)} encaissés',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                  onPressed: lot.restants == 0
                      ? null
                      : () async {
                          await appState.definirLotActif(lot.id);
                          if (context.mounted) Navigator.pop(context, 'vente');
                        },
                  icon: const Icon(Icons.point_of_sale_rounded),
                  label: const Text('Vendre depuis ce lot'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.search,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Chercher un code',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _recherche = v),
              ),
              const SizedBox(height: 8),
              SegmentedButton<_Filtre>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                      value: _Filtre.tous, label: Text('Tous (${lot.total})')),
                  ButtonSegment(
                      value: _Filtre.restants,
                      label: Text('Restants (${lot.restants})')),
                  ButtonSegment(
                      value: _Filtre.vendus,
                      label: Text('Vendus (${lot.vendus})')),
                  if (lot.defectueux > 0)
                    ButtonSegment(
                        value: _Filtre.defectueux,
                        label: Text('Défect. (${lot.defectueux})')),
                ],
                selected: {filtre},
                onSelectionChanged: (s) => setState(() => _filtre = s.first),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: liste.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      q.isNotEmpty
                          ? 'Aucun code ne correspond à « $q »'
                          : 'Aucun ticket dans ce filtre',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: liste.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final t = liste[i];
                    return ListTile(
                      leading: Icon(
                        t.defectueux
                            ? Icons.report_problem_rounded
                            : t.vendu
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                        color: t.defectueux
                            ? cs.error
                            : t.vendu
                                ? _vert(context)
                                : cs.outline,
                        semanticLabel: t.defectueux
                            ? 'Défectueux'
                            : t.vendu
                                ? 'Vendu'
                                : 'À vendre',
                      ),
                      title: Text(t.code,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                              letterSpacing: 1)),
                      subtitle: Text(
                        t.defectueux
                            ? 'Défectueux : non proposé à la vente'
                            : t.vendu && t.venduLe != null
                                ? 'Vendu le ${fmtDateHeure(t.venduLe!)}  ·  ${cdf(t.prix)}'
                                    '${t.paiement == Paiement.especes ? '' : '  ·  ${Paiement.libelle(t.paiement)}'}'
                                : [
                                    if (t.numero != null) 'n° ${t.numero}',
                                    'à vendre',
                                  ].join('  ·  '),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!t.defectueux)
                            TextButton(
                              onPressed: () => _basculer(t),
                              child: Text(t.vendu ? 'Remettre' : 'Marquer vendu'),
                            ),
                          if (!t.vendu)
                            PopupMenuButton<String>(
                              tooltip: 'Plus d\'actions',
                              onSelected: (v) => v == 'def'
                                  ? _signalerDefectueux(t)
                                  : _reactiver(t),
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: t.defectueux ? 'react' : 'def',
                                  child: Text(t.defectueux
                                      ? 'Plus défectueux : remettre en vente'
                                      : 'Signaler défectueux'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
