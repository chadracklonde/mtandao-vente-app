import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../format.dart';
import '../models.dart';
import '../state.dart';
import '../widgets/ticket_card.dart';
import 'import_flow.dart';

/// Écran principal : un seul ticket à la fois, un gros bouton « Vendu ».
class VenteScreen extends StatefulWidget {
  const VenteScreen({super.key});

  @override
  State<VenteScreen> createState() => _VenteScreenState();
}

class _VenteScreenState extends State<VenteScreen> {
  List<Lot> _lots = [];
  Lot? _lot;
  Ticket? _ticket;
  Uint8List? _image;
  LotStats? _stats;
  Ticket? _dernier;
  bool _chargement = true;
  bool _occupe = false;

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
    final repo = appState.repo;
    final lots = await repo.lots();
    Lot? lot;
    final id = appState.lotActifId;
    if (id != null) {
      for (final l in lots) {
        if (l.id == id) lot = l;
      }
    }
    if (lot == null) {
      // Premier lot non terminé, en commençant par le plus ancien.
      for (final l in lots.reversed) {
        if (l.restants > 0) {
          lot = l;
          break;
        }
      }
    }
    Ticket? ticket;
    Uint8List? image;
    LotStats? stats;
    Ticket? dernier;
    if (lot != null) {
      ticket = await repo.prochainTicket(lot.id);
      if (ticket != null) image = await repo.imageTicket(ticket.id);
      stats = await repo.stats(lot.id);
      dernier = await repo.dernierVendu(lot.id);
    }
    if (!mounted) return;
    setState(() {
      _lots = lots;
      _lot = lot;
      _ticket = ticket;
      _image = image;
      _stats = stats;
      _dernier = dernier;
      _chargement = false;
    });
  }

  Future<void> _vendre() async {
    final t = _ticket;
    if (t == null || _occupe) return;
    _occupe = true;
    try {
      // Confirmation pour éviter un appui par inadvertance.
      final confirme = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirmer la vente ?'),
          content: Text(
              'Ticket ${t.code}\nMontant : ${cdf(t.prix)}\n\nCe ticket sera marqué comme vendu.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Non'),
            ),
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Oui, vendu'),
            ),
          ],
        ),
      );
      if (confirme != true) return;
      final ok = await appState.repo.vendre(t.id);
      HapticFeedback.mediumImpact();
      appState.changed();
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: Text('Ticket ${t.code} vendu  ·  ${cdf(t.prix)}'),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'ANNULER',
              onPressed: () => _annuler(confirmer: false),
            ),
          ));
      }
    } finally {
      _occupe = false;
    }
  }

  Future<void> _annuler({bool confirmer = true}) async {
    final lot = _lot;
    if (lot == null || _occupe) return;
    final dernier = await appState.repo.dernierVendu(lot.id);
    if (dernier == null) return;
    if (confirmer) {
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Annuler la dernière vente ?'),
          content: Text(
              'Le ticket ${dernier.code} sera remis en vente et son montant retiré du total.'),
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
      if (ok != true) return;
    }
    await appState.repo.annulerDerniereVente(lot.id);
    appState.changed();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('Ticket ${dernier.code} remis en vente'),
        duration: const Duration(seconds: 2),
      ));
  }

  Future<void> _partager() async {
    final t = _ticket;
    final lot = _lot;
    if (t == null || lot == null) return;
    final url = lot.loginUrl ??
        (await appState.repo.getSetting('login_url')) ??
        'http://mtandao.wifi';
    final lignes = <String>[
      'Wi-Fi MTANDAO - ticket ${lot.forfaitNom}',
      if (t.aMotDePasseDistinct) 'Utilisateur : ${t.code}' else 'Code : ${t.code}',
      if (t.aMotDePasseDistinct) 'Mot de passe : ${t.motDePasse}',
      'Connexion : $url',
    ];
    await Share.share(lignes.join('\n'));
  }

  Future<void> _changerLot(int? id) async {
    if (id == null) return;
    await appState.definirLotActif(id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          children: [
            Image.asset('assets/logo.png', height: 32),
            const SizedBox(width: 10),
            const Text('Mtandao',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _lot == null
              ? _etatVide(context)
              : _contenu(context),
    );
  }

  Widget _etatVide(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/logo.png', height: 110),
            const SizedBox(height: 20),
            Text('Aucun ticket à vendre',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Importez un fichier PDF de tickets. Il est lu directement sur ce téléphone, sans Internet.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => ImportFlow.demarrer(context),
              icon: const Icon(Icons.picture_as_pdf_rounded),
              label: const Text('Importer un PDF'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contenu(BuildContext context) {
    final lot = _lot!;
    final stats = _stats ?? const LotStats(total: 0, vendus: 0, montant: 0);
    final cs = Theme.of(context).colorScheme;
    final termine = _ticket == null;

    final lotsChoix = _lots.where((l) => l.restants > 0 || l.id == lot.id).toList();

    return Column(
      children: [
        // --------------------------------------------------- compteur en haut
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            border: Border(bottom: BorderSide(color: cs.outlineVariant)),
          ),
          child: Column(
            children: [
              if (lotsChoix.length > 1)
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: DropdownButton<int>(
                    value: lot.id,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final l in lotsChoix)
                        DropdownMenuItem(
                          value: l.id,
                          child: Text(
                            '${l.nom}  ·  ${l.restants} restants',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _changerLot,
                  ),
                )
              else
                Text(lot.nom,
                    style: Theme.of(context).textTheme.labelLarge,
                    overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Row(
                children: [
                  _stat(context, '${stats.vendus}', 'déjà vendus', cs.primary),
                  _stat(context, '${stats.restants}', 'restants', cs.onSurface,
                      grand: true),
                  _stat(context, cdf(stats.montant), 'encaissé', _vert(context)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: stats.total == 0 ? 0 : stats.vendus / stats.total,
                  semanticsLabel: 'Progression du lot',
                  semanticsValue:
                      '${stats.vendus} tickets vendus sur ${stats.total}',
                ),
              ),
              if (_dernier != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Dernier vendu : ${_dernier!.code}'
                    '${_dernier!.venduLe != null ? '  ·  ${fmtHeure(_dernier!.venduLe!)}' : ''}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),

        // ---------------------------------------------------------- le ticket
        Expanded(
          child: termine
              ? _lotTermine(context, lot)
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: TicketCard(
                    ticket: _ticket!,
                    image: _image,
                    forfaitNom: lot.forfaitNom,
                  ),
                ),
        ),

        // ------------------------------------------------------------ boutons
        if (!termine)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 72,
                    child: FilledButton.icon(
                      onPressed: _vendre,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade800,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        textStyle: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w800),
                      ),
                      icon: const Icon(Icons.check_circle_rounded, size: 30),
                      label: const Text('VENDU'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              _dernier == null ? null : () => _annuler(),
                          style: OutlinedButton.styleFrom(
                              foregroundColor: cs.error,
                              minimumSize: const Size.fromHeight(52)),
                          icon: const Icon(Icons.undo_rounded),
                          label: const Text('Annuler'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _partager,
                          style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(52)),
                          icon: const Icon(Icons.share_rounded),
                          label: const Text('Partager'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Vert lisible sur fond clair comme sur fond sombre.
  Color _vert(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.green.shade300
          : Colors.green.shade800;

  Widget _stat(BuildContext context, String valeur, String libelle, Color c,
      {bool grand = false}) {
    final texte = Theme.of(context).textTheme;
    return Expanded(
      child: Semantics(
        label: '$valeur $libelle',
        excludeSemantics: true,
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(valeur,
                  style: (grand ? texte.headlineMedium : texte.headlineSmall)
                      ?.copyWith(fontWeight: FontWeight.w800, color: c)),
            ),
            Text(libelle, style: texte.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _lotTermine(BuildContext context, Lot lot) {
    final suivant = _lots.where((l) => l.id != lot.id && l.restants > 0).toList();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.task_alt_rounded,
                size: 72, color: _vert(context)),
            const SizedBox(height: 12),
            Text('Lot terminé', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text('Tous les tickets de « ${lot.nom} » sont vendus.',
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            if (suivant.isNotEmpty)
              FilledButton.icon(
                onPressed: () => appState.definirLotActif(suivant.last.id),
                icon: const Icon(Icons.skip_next_rounded),
                label: Text('Passer à « ${suivant.last.nom} »'),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => ImportFlow.demarrer(context),
              icon: const Icon(Icons.picture_as_pdf_rounded),
              label: const Text('Importer un nouveau PDF'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _annuler(),
              icon: const Icon(Icons.undo_rounded),
              label: const Text('Annuler la dernière vente'),
            ),
          ],
        ),
      ),
    );
  }
}
