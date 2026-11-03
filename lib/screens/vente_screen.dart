import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../drive_backup.dart';
import '../format.dart';
import '../models.dart';
import '../state.dart';
import '../widgets/barre_progression.dart';
import '../widgets/code_vendeur.dart';
import '../widgets/dialogue_vente.dart';
import '../widgets/ticket_card.dart';
import 'import_flow.dart';
import 'saisie_manuelle.dart';

/// Écran principal : un seul ticket à la fois, un gros bouton « Vendu ».
class VenteScreen extends StatefulWidget {
  const VenteScreen({super.key, this.surReglages});

  /// Ouvre l'onglet Réglages (depuis les alertes de sauvegarde).
  final VoidCallback? surReglages;

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
  List<Vendeur> _vendeurs = [];
  int? _vendeurActifId;

  // Alertes : stock bas (nombre de tickets restants) et sauvegarde.
  int? _alerteStock;
  String? _alerteSauvegarde;
  bool _rappelMasque = false;
  bool _chargement = true;
  bool _occupe = false;

  // Bannière de confirmation (remplace la barre du bas, qui masquait VENDU).
  String? _bandeau;
  bool _bandeauAnnulable = false;
  Timer? _minuteurBandeau;

  @override
  void initState() {
    super.initState();
    appState.addListener(_charger);
    _charger();
  }

  @override
  void dispose() {
    _minuteurBandeau?.cancel();
    appState.removeListener(_charger);
    super.dispose();
  }

  /// Nombre de tickets restants si le stock total est bas, sinon null.
  /// Le seuil se règle dans Réglages (20 par défaut, 0 = pas d'alerte).
  Future<int?> _calculerAlerteStock(List<Lot> lots) async {
    final seuil = int.tryParse(
            await appState.repo.getSetting(cleSeuilStock) ?? '') ??
        seuilStockParDefaut;
    if (seuil <= 0) return null;
    final restants = lots.fold<int>(0, (a, l) => a + l.restants);
    return (restants > 0 && restants <= seuil) ? restants : null;
  }

  /// Message d'alerte sur la sauvegarde, ou null si tout va bien.
  Future<String?> _calculerAlerteSauvegarde(List<Lot> lots) async {
    final repo = appState.repo;
    final driveActif = await repo.getSetting(DriveBackup.cleActif) == '1';
    if (driveActif) {
      final erreur = await repo.getSetting(DriveBackup.cleErreur);
      return erreur == null
          ? null
          : 'La sauvegarde Google Drive a échoué : $erreur';
    }
    if (!lots.any((l) => l.vendus > 0)) return null;
    final derniere =
        int.tryParse(await repo.getSetting('derniere_sauvegarde') ?? '');
    if (derniere == null) return 'Vos ventes ne sont pas sauvegardées.';
    final jours = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(derniere))
        .inDays;
    return jours >= 3
        ? 'Dernière sauvegarde il y a $jours jours : vos ventes récentes ne sont pas protégées.'
        : null;
  }

  Vendeur? get _vendeurActif {
    for (final v in _vendeurs) {
      if (v.id == _vendeurActifId) return v;
    }
    return null;
  }

  Future<void> _choisirVendeur() async {
    final choix = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Qui vend ?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            ListTile(
              leading: Icon(_vendeurActifId == null
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked),
              title: const Text('Aucun vendeur précis'),
              onTap: () => Navigator.pop(ctx, -1),
            ),
            for (final v in _vendeurs)
              ListTile(
                leading: Icon(v.id == _vendeurActifId
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked),
                title: Text(v.nom),
                onTap: () => Navigator.pop(ctx, v.id),
              ),
          ],
        ),
      ),
    );
    if (choix == null) return;
    if (choix != -1) {
      final vendeur = _vendeurs.where((v) => v.id == choix).firstOrNull;
      // Un vendeur protégé par un code doit le saisir pour vendre en son nom.
      if (vendeur != null && vendeur.aUnCode) {
        if (!mounted) return;
        if (!await demanderCodeVendeur(context, vendeur)) return;
      }
    }
    await appState.repo.definirVendeurActif(choix == -1 ? null : choix);
    appState.changed();
  }

  /// Affiche un message en haut de l'écran, sans jamais recouvrir les boutons.
  void _afficherBandeau(String message,
      {bool annulable = false, int secondes = 4}) {
    _minuteurBandeau?.cancel();
    setState(() {
      _bandeau = message;
      _bandeauAnnulable = annulable;
    });
    _minuteurBandeau = Timer(Duration(seconds: secondes), () {
      if (mounted) setState(() => _bandeau = null);
    });
  }

  void _fermerBandeau() {
    _minuteurBandeau?.cancel();
    if (mounted) setState(() => _bandeau = null);
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
    final vendeurs = await repo.vendeurs(seulementActifs: true);
    final vendeurActif = await repo.vendeurActifId();
    final alerteStock = await _calculerAlerteStock(lots);
    final alerteSauvegarde = await _calculerAlerteSauvegarde(lots);
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
      _vendeurs = vendeurs;
      _vendeurActifId = vendeurActif;
      _alerteStock = alerteStock;
      _alerteSauvegarde = alerteSauvegarde;
      _chargement = false;
    });
  }

  Future<void> _vendre() async {
    final t = _ticket;
    if (t == null || _occupe) return;
    _occupe = true;
    try {
      // Confirmation pour éviter un appui par inadvertance : on choisit aussi
      // le mode de paiement (espèces par défaut).
      final repo = appState.repo;
      final clients = await repo.clients();
      final taux = await repo.tauxDollar();
      if (!mounted) return;
      final vendeur = _vendeurActif;
      final choix = await demanderVente(
        context,
        ticket: t,
        clients: clients,
        creerClient: (nom, tel) => repo.ajouterClient(nom, telephone: tel),
        vendeurNom: vendeur?.nom,
        tauxDollar: taux,
      );
      if (choix == null) return;
      final ok = await repo.vendre(
        t.id,
        paiement: choix.paiement,
        clientId: choix.clientId,
        vendeurId: vendeur?.id,
        devise: choix.devise,
        taux: choix.taux,
      );
      HapticFeedback.mediumImpact();
      appState.changed();
      if (!mounted) return;
      if (ok) {
        // Le client a pu être créé pendant la vente : on relit la liste.
        final nomClient = choix.paiement == Paiement.credit
            ? (await repo.clients())
                .where((c) => c.id == choix.clientId)
                .map((c) => c.nom)
                .firstOrNull
            : null;
        if (!mounted) return;
        final dollars = choix.devise == Devise.usd
            ? '  ·  reçu ${Devise.formaterDollar(Devise.centimesDollar(t.prix, choix.taux!))}'
            : '';
        final detail = switch (choix.paiement) {
          Paiement.especes => '',
          Paiement.credit => '  ·  à crédit (${nomClient ?? 'client'})',
          final p => '  ·  ${Paiement.libelle(p).toLowerCase()}',
        };
        _afficherBandeau('Ticket ${t.code} vendu  ·  ${cdf(t.prix)}$detail$dollars',
            annulable: true);
      } else {
        _afficherBandeau('Ticket ${t.code} indisponible : il a déjà été vendu '
            'ou signalé défectueux.');
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
    _afficherBandeau('Ticket ${dernier.code} remis en vente', secondes: 3);
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
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _saisirCodes,
              icon: const Icon(Icons.keyboard_alt_outlined),
              label: const Text('Saisir des codes à la main'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saisirCodes() => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SaisieManuelleScreen()));

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
              if (_vendeurs.isNotEmpty)
                Align(
                  alignment: Alignment.centerRight,
                  child: ActionChip(
                    avatar: Icon(
                        _vendeurActif?.aUnCode == true
                            ? Icons.lock_rounded
                            : Icons.person_outline_rounded,
                        size: 18),
                    label: Text(_vendeurActif?.nom ?? 'Choisir le vendeur'),
                    onPressed: _choisirVendeur,
                  ),
                ),
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
              BarreProgression(
                valeur: stats.total == 0 ? 0 : stats.vendus / stats.total,
                phrase:
                    'Progression du lot : ${stats.vendus} tickets vendus sur ${stats.total}',
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

        // ------------------------------------------------------------- alertes
        if (_alerteStock != null)
          _carteAlerte(
            context,
            icone: Icons.inventory_2_outlined,
            texte:
                'Plus que $_alerteStock ticket${_alerteStock! > 1 ? 's' : ''} en stock. Pensez à importer un nouveau PDF.',
            action: 'Importer',
            surAction: () => ImportFlow.demarrer(context),
          ),
        if (_alerteSauvegarde != null && !_rappelMasque)
          _carteAlerte(
            context,
            icone: Icons.cloud_off_outlined,
            texte: _alerteSauvegarde!,
            action: widget.surReglages == null ? null : 'Réglages',
            surAction: widget.surReglages,
            surFermer: () => setState(() => _rappelMasque = true),
          ),

        // ------------------------------------------- confirmation de la vente
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.topCenter,
          child: _bandeau == null
              ? const SizedBox(width: double.infinity)
              : _bandeauVente(context),
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

  Widget _carteAlerte(
    BuildContext context, {
    required IconData icone,
    required String texte,
    String? action,
    VoidCallback? surAction,
    VoidCallback? surFermer,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
        color: cs.tertiaryContainer,
        child: Row(
          children: [
            Icon(icone, color: cs.onTertiaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(texte,
                  style: TextStyle(color: cs.onTertiaryContainer)),
            ),
            if (action != null && surAction != null)
              TextButton(onPressed: surAction, child: Text(action)),
            if (surFermer != null)
              IconButton(
                tooltip: 'Masquer',
                onPressed: surFermer,
                icon: Icon(Icons.close_rounded, color: cs.onTertiaryContainer),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bandeauVente(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        color: cs.secondaryContainer,
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: _vert(context)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _bandeau!,
                style: TextStyle(
                    color: cs.onSecondaryContainer,
                    fontWeight: FontWeight.w600),
              ),
            ),
            if (_bandeauAnnulable)
              TextButton(
                onPressed: () {
                  _fermerBandeau();
                  _annuler(confirmer: false);
                },
                child: const Text('ANNULER'),
              ),
          ],
        ),
      ),
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
            Text(
                lot.defectueux > 0
                    ? 'Plus aucun ticket à vendre dans « ${lot.nom} » (${lot.defectueux} défectueux).'
                    : 'Tous les tickets de « ${lot.nom} » sont vendus.',
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
              onPressed: _saisirCodes,
              icon: const Icon(Icons.keyboard_alt_outlined),
              label: const Text('Saisir des codes à la main'),
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
