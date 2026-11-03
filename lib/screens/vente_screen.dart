import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../drive_backup.dart';
import '../format.dart';
import '../message_ticket.dart';
import '../models.dart';
import '../state.dart';
import '../widgets/barre_progression.dart';
import '../widgets/code_vendeur.dart';
import '../widgets/dialogue_vente.dart';
import '../widgets/ticket_card.dart';
import 'dettes_screen.dart';
import 'historique_screen.dart';
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
  // Les forfaits (profils de ticket) qui ont des tickets, et celui qu'on vend.
  List<ProfilStock> _profils = [];
  ProfilStock? _profil;
  Ticket? _ticket;
  Lot? _lotTicket; // lot du ticket affiché (lien de connexion pour le partage)
  Uint8List? _image;
  Ticket? _dernier; // dernière vente, tous forfaits confondus
  ({int vendus, int montant}) _jour = (vendus: 0, montant: 0);
  int _seuil = seuilStockParDefaut;
  List<Vendeur> _vendeurs = [];
  int? _vendeurActifId;

  // Alerte de sauvegarde (l'alerte de stock bas se calcule à l'affichage).
  String? _alerteSauvegarde;
  String? _alerteDettes;
  bool _dettesMasquees = false;
  bool _rappelMasque = false;
  bool _chargement = true;
  bool _occupe = false;

  // Bannière de confirmation (remplace la barre du bas, qui masquait VENDU).
  String? _bandeau;
  bool _bandeauAnnulable = false;
  VoidCallback? _bandeauEnvoi; // « Envoyer le code au client »
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

  /// Message d'alerte sur la sauvegarde, ou null si tout va bien.
  Future<String?> _calculerAlerteSauvegarde(bool aDesVentes) async {
    final repo = appState.repo;
    final driveActif = await repo.getSetting(DriveBackup.cleActif) == '1';
    if (driveActif) {
      final erreur = await repo.getSetting(DriveBackup.cleErreur);
      return erreur == null
          ? null
          : 'La sauvegarde Google Drive a échoué : $erreur';
    }
    if (!aDesVentes) return null;
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

  /// Étiquette courte d'une pastille : « 1 h », « 1 semaine »… Si deux forfaits
  /// ont la même durée, on affiche leur nom pour les distinguer.
  String _etiquette(ProfilStock p) {
    final memeDuree = _profils
        .where((x) => x.forfait.dureeMinutes == p.forfait.dureeMinutes)
        .length;
    return memeDuree > 1 ? p.forfait.nom : libelleDuree(p.forfait.dureeMinutes);
  }

  /// Vrai si le stock de ce forfait est bas (mais pas vide).
  bool _stockBas(ProfilStock p) =>
      _seuil > 0 && p.restants > 0 && p.restants <= _seuil;

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
      {bool annulable = false, int secondes = 4, VoidCallback? envoi}) {
    _minuteurBandeau?.cancel();
    setState(() {
      _bandeau = message;
      _bandeauAnnulable = annulable;
      _bandeauEnvoi = envoi;
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
    final premier = _chargement;
    final profils = await repo.profils();

    // Forfait affiché : le dernier choisi. À l'ouverture, s'il n'a plus de
    // tickets (ou n'existe plus), on prend le premier qui en a. En cours de
    // journée on ne change pas tout seul : on affiche « plus de tickets ».
    ProfilStock? profil;
    for (final p in profils) {
      if (p.forfait.id == appState.forfaitActifId) profil = p;
    }
    if (profil == null || (premier && profil.restants == 0)) {
      profil = profils.where((p) => p.restants > 0).firstOrNull ??
          profils.firstOrNull;
    }

    Ticket? ticket;
    Lot? lotTicket;
    Uint8List? image;
    if (profil != null) {
      ticket = await repo.prochainTicketForfait(profil.forfait.id,
          lotPrefereId: appState.lotActifId);
      if (ticket != null) {
        image = await repo.imageTicket(ticket.id);
        lotTicket = await repo.lot(ticket.lotId);
      }
    }
    final dernier = await repo.dernierVenduGlobal();
    final auj = debutJour(DateTime.now());
    final jour = await repo.statsPeriode(
        auj, DateTime(auj.year, auj.month, auj.day + 1));
    final seuil =
        int.tryParse(await repo.getSetting(cleSeuilStock) ?? '') ??
            seuilStockParDefaut;
    final vendeurs = await repo.vendeurs(seulementActifs: true);
    final vendeurActif = await repo.vendeurActifId();
    final alerteSauvegarde = await _calculerAlerteSauvegarde(dernier != null);
    final retards = await repo.dettesEnRetard();
    final alerteDettes = retards.isEmpty
        ? null
        : '${retards.length} ticket${retards.length > 1 ? 's' : ''} à crédit non payé${retards.length > 1 ? 's' : ''} en retard (${cdf(retards.fold(0, (a, d) => a + d.prix))}).';
    if (!mounted) return;
    setState(() {
      _profils = profils;
      _profil = profil;
      _ticket = ticket;
      _lotTicket = lotTicket;
      _image = image;
      _dernier = dernier;
      _jour = jour;
      _seuil = seuil;
      _vendeurs = vendeurs;
      _vendeurActifId = vendeurActif;
      _alerteSauvegarde = alerteSauvegarde;
      _alerteDettes = alerteDettes;
      _chargement = false;
    });
  }

  Future<void> _vendre() async {
    final t = _ticket;
    if (t == null || _occupe) return;
    _occupe = true;
    try {
      // Confirmation pour éviter un appui par inadvertance : on choisit aussi
      // le mode de paiement (espèces par défaut) et, si besoin, la quantité.
      final repo = appState.repo;
      final clients = await repo.clients();
      final taux = await repo.tauxDollar();
      final prochains = await repo.prochainsTicketsForfait(t.forfaitId, 30,
          lotPrefereId: appState.lotActifId);
      if (!mounted) return;
      final vendeur = _vendeurActif;
      final choix = await demanderVente(
        context,
        ticket: t,
        prochains: prochains,
        clients: clients,
        creerClient: (nom, tel) => repo.ajouterClient(nom, telephone: tel),
        vendeurNom: vendeur?.nom,
        tauxDollar: taux,
      );
      if (choix == null) return;
      final List<Ticket> vendus;
      if (choix.quantite <= 1) {
        final ok = await repo.vendre(
          t.id,
          paiement: choix.paiement,
          clientId: choix.clientId,
          vendeurId: vendeur?.id,
          devise: choix.devise,
          taux: choix.taux,
        );
        vendus = ok ? [t] : [];
      } else {
        vendus = await repo.vendreQuantite(
          t.forfaitId,
          choix.quantite,
          lotPrefereId: appState.lotActifId,
          paiement: choix.paiement,
          clientId: choix.clientId,
          vendeurId: vendeur?.id,
          devise: choix.devise,
          taux: choix.taux,
        );
      }
      HapticFeedback.mediumImpact();
      appState.changed();
      if (!mounted) return;
      if (vendus.isNotEmpty) {
        // Le client a pu être créé pendant la vente : on relit la liste.
        final client = choix.clientId == null
            ? null
            : (await repo.clients())
                .where((c) => c.id == choix.clientId)
                .firstOrNull;
        final nomClient = client?.nom;
        if (!mounted) return;
        final total = vendus.fold(0, (a, x) => a + x.prix);
        final dollars = choix.devise == Devise.usd
            ? '  ·  reçu ${Devise.formaterDollar(vendus.fold(0, (a, x) => a + Devise.centimesDollar(x.prix, choix.taux!)))}'
            : '';
        final pour = nomClient == null ? '' : '  ·  $nomClient';
        final detail = switch (choix.paiement) {
          Paiement.especes => pour,
          Paiement.credit => '  ·  à crédit (${nomClient ?? 'client'})',
          final p => '  ·  ${Paiement.libelle(p).toLowerCase()}$pour',
        };
        final quoi = vendus.length == 1
            ? 'Ticket ${t.code} vendu'
            : '${vendus.length} tickets vendus';
        final url = _lotTicket?.loginUrl ??
            (await repo.getSetting('login_url')) ??
            'http://mtandao.wifi';
        if (!mounted) return;
        _afficherBandeau('$quoi  ·  ${cdf(total)}$detail$dollars',
            annulable: true,
            secondes: 8,
            envoi: () => Share.share(messageTickets(
                  tickets: vendus,
                  forfaitNom: _profil?.forfait.nom ?? '',
                  url: url,
                  clientNom: nomClient,
                )));
      } else {
        _afficherBandeau('Ticket ${t.code} indisponible : il a déjà été vendu '
            'ou signalé défectueux.');
      }
    } finally {
      _occupe = false;
    }
  }

  Future<void> _annuler({bool confirmer = true}) async {
    if (_occupe) return;
    // La dernière vente (un ou plusieurs tickets), quel que soit le forfait :
    // une erreur de forfait peut ainsi s'annuler sans changer d'écran.
    final groupe = await appState.repo.derniereVente();
    if (groupe.isEmpty) return;
    final dernier = groupe.last;
    final forfait = _profils
        .where((p) => p.forfait.id == dernier.forfaitId)
        .map((p) => _etiquette(p))
        .firstOrNull;
    final quoi = groupe.length == 1
        ? 'Ticket ${dernier.code}${forfait == null ? '' : ' ($forfait)'}'
        : '${groupe.length} tickets (${groupe.map((t) => t.code).join(', ')})';
    if (confirmer) {
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Annuler la dernière vente ?'),
          content: Text(groupe.length == 1
              ? 'Le ${quoi[0].toLowerCase()}${quoi.substring(1)} sera remis en vente et son montant retiré du total.'
              : '$quoi seront remis en vente et leur montant retiré du total.'),
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
    await appState.repo.annulerDerniereVenteGlobale();
    appState.changed();
    if (!mounted) return;
    _afficherBandeau(
        groupe.length == 1
            ? '$quoi remis en vente'
            : '${groupe.length} tickets remis en vente',
        secondes: 3);
  }

  Future<void> _partager() async {
    final t = _ticket;
    final profil = _profil;
    if (t == null || profil == null) return;
    final url = _lotTicket?.loginUrl ??
        (await appState.repo.getSetting('login_url')) ??
        'http://mtandao.wifi';
    final lignes = <String>[
      'Wi-Fi MTANDAO - ticket ${profil.forfait.nom}',
      if (t.aMotDePasseDistinct) 'Utilisateur : ${t.code}' else 'Code : ${t.code}',
      if (t.aMotDePasseDistinct) 'Mot de passe : ${t.motDePasse}',
      'Connexion : $url',
    ];
    await Share.share(lignes.join('\n'));
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
        actions: [
          IconButton(
            tooltip: 'Rechercher un ticket',
            icon: const Icon(Icons.search_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const HistoriqueScreen())),
          ),
        ],
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _profil == null
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

  /// Pastilles de forfait : un appui pour passer de 1 h à 24 h, etc.
  Widget _pastilles(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final p in _profils)
            ChoiceChip(
              selected: p.forfait.id == _profil?.forfait.id,
              onSelected: (_) => appState.definirForfaitActif(p.forfait.id),
              showCheckmark: false,
              label: Text(
                '${_etiquette(p)}  ${p.restants}',
                semanticsLabel:
                    '${_etiquette(p)}, ${p.restants == 0 ? 'plus de tickets' : '${p.restants} restants'}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  decoration:
                      p.restants == 0 ? TextDecoration.lineThrough : null,
                  color: p.forfait.id == _profil?.forfait.id
                      ? null
                      : p.restants == 0
                          ? cs.outline
                          : _stockBas(p)
                              ? cs.error
                              : null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _contenu(BuildContext context) {
    final profil = _profil!;
    final cs = Theme.of(context).colorScheme;
    final termine = _ticket == null;

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
              // Un seul forfait : rien à choisir, l'écran reste aussi simple qu'avant.
              if (_profils.length > 1) _pastilles(context),
              const SizedBox(height: 4),
              Row(
                children: [
                  _stat(context, '${profil.vendus}', 'déjà vendus', cs.primary),
                  _stat(context, '${profil.restants}', 'restants', cs.onSurface,
                      grand: true),
                  _stat(context, cdf(profil.montant), 'encaissé', _vert(context)),
                ],
              ),
              const SizedBox(height: 8),
              BarreProgression(
                valeur: profil.total == 0 ? 0 : profil.vendus / profil.total,
                phrase:
                    'Progression de ${profil.forfait.nom} : ${profil.vendus} tickets vendus sur ${profil.total}',
              ),
              // Total de la journée, tous forfaits confondus.
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Aujourd\'hui, tous forfaits : ${_jour.vendus} ticket${_jour.vendus > 1 ? 's' : ''}  ·  ${cdf(_jour.montant)}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              if (_dernier != null)
                Text(
                  'Dernier vendu : ${_dernier!.code}'
                  '${_dernier!.venduLe != null ? '  ·  ${fmtHeure(_dernier!.venduLe!)}' : ''}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
            ],
          ),
        ),

        // ------------------------------------------------------------- alertes
        if (_stockBas(profil))
          _carteAlerte(
            context,
            icone: Icons.inventory_2_outlined,
            texte:
                'Plus que ${profil.restants} ticket${profil.restants > 1 ? 's' : ''} « ${profil.forfait.nom} ». Pensez à importer un nouveau PDF.',
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

        if (_alerteDettes != null && !_dettesMasquees)
          _carteAlerte(
            context,
            icone: Icons.event_busy_outlined,
            texte: _alerteDettes!,
            action: 'Voir',
            surAction: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DettesScreen())),
            surFermer: () => setState(() => _dettesMasquees = true),
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
              ? _profilEpuise(context, profil)
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    children: [
                      // Forfait et prix en grand : on ne vend pas le mauvais ticket.
                      Semantics(
                        header: true,
                        child: Text(
                          '${profil.forfait.nom.toUpperCase()}  ·  ${cdf(_ticket!.prix)}',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: cs.primary),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TicketCard(
                        ticket: _ticket!,
                        image: _image,
                        forfaitNom: profil.forfait.nom,
                      ),
                    ],
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
            if (_bandeauEnvoi != null)
              IconButton(
                tooltip: 'Envoyer le code au client',
                onPressed: _bandeauEnvoi,
                icon: const Icon(Icons.send_rounded),
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

  Widget _profilEpuise(BuildContext context, ProfilStock profil) {
    final autres = _profils.where((p) => p.restants > 0).toList();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.task_alt_rounded, size: 72, color: _vert(context)),
            const SizedBox(height: 12),
            Text('Plus de tickets',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(
                profil.defectueux > 0
                    ? 'Plus aucun ticket à vendre pour « ${profil.forfait.nom} » (${profil.defectueux} défectueux).'
                    : 'Tous les tickets « ${profil.forfait.nom} » sont vendus.',
                textAlign: TextAlign.center),
            if (autres.isNotEmpty) ...[
              const SizedBox(height: 6),
              const Text('Choisissez un autre forfait ci-dessus.',
                  textAlign: TextAlign.center),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
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
              onPressed: _dernier == null ? null : () => _annuler(),
              icon: const Icon(Icons.undo_rounded),
              label: const Text('Annuler la dernière vente'),
            ),
          ],
        ),
      ),
    );
  }
}
