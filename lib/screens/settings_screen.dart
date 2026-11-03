import 'caisse_screen.dart';
import 'journal_annulations_screen.dart';
import 'suivi_utilisation_screen.dart';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../backup.dart';
import '../drive_backup.dart';
import '../format.dart';
import '../models.dart';
import '../sauvegarde_auto.dart';
import '../security.dart';
import '../state.dart';
import '../widgets/dialogues.dart';
import '../widgets/pin_pad.dart';
import 'aide_screen.dart';
import 'dettes_screen.dart';
import 'vendeurs_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _loginUrl = 'http://mtandao.wifi';
  DateTime? _derniereSauvegarde;
  bool _bioDispo = false;
  bool _bioActive = false;
  bool _chargee = false;

  int _seuilStock = seuilStockParDefaut;
  int _delaiDette = delaiDetteParDefaut;
  int _tauxDollar = 0;

  // Sauvegarde automatique Google Drive.
  bool _driveActif = false;
  bool _driveOccupe = false;
  bool _driveWifi = false;
  int? _driveTaille;
  String? _driveEmail;
  DateTime? _driveSucces;
  String? _driveErreur;

  /// Données jamais sauvegardées, ou sauvegarde de plus de 7 jours.
  bool get _sauvegardeAncienne =>
      _chargee &&
      (_derniereSauvegarde == null ||
          DateTime.now().difference(_derniereSauvegarde!).inDays >= 7);

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final url = await appState.repo.getSetting('login_url');
    final s = int.tryParse(
        await appState.repo.getSetting('derniere_sauvegarde') ?? '');
    final bioDispo = await Biometrie.disponible();
    final bioActive = await Biometrie.active();
    final seuil = int.tryParse(
            await appState.repo.getSetting(cleSeuilStock) ?? '') ??
        seuilStockParDefaut;
    final delaiDette = await appState.repo.delaiDetteJours();
    final taux = await appState.repo.tauxDollar();
    final driveActif =
        await appState.repo.getSetting(DriveBackup.cleActif) == '1';
    final driveEmail = await appState.repo.getSetting(DriveBackup.cleEmail);
    final driveSucces = int.tryParse(
        await appState.repo.getSetting(DriveBackup.cleSucces) ?? '');
    final driveErreur = await appState.repo.getSetting(DriveBackup.cleErreur);
    final driveWifi =
        await appState.repo.getSetting(DriveBackup.cleWifi) == '1';
    final driveTaille = int.tryParse(
        await appState.repo.getSetting(DriveBackup.cleTaille) ?? '');
    if (!mounted) return;
    setState(() {
      _driveWifi = driveWifi;
      _driveTaille = driveTaille;
      _seuilStock = seuil;
      _delaiDette = delaiDette;
      _tauxDollar = taux;
      _driveActif = driveActif;
      _driveEmail = driveEmail;
      _driveSucces = driveSucces == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(driveSucces);
      _driveErreur = driveErreur;
      _chargee = true;
      _bioDispo = bioDispo;
      _bioActive = bioActive;
      if (url != null && url.isNotEmpty) _loginUrl = url;
      _derniereSauvegarde =
          s == null ? null : DateTime.fromMillisecondsSinceEpoch(s);
    });
  }

  void _info(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _modifierLien() async {
    final v = await demanderTexte(
      context,
      titre: 'Lien de connexion',
      libelle: 'Adresse',
      initial: _loginUrl,
      aide:
          'Adresse envoyée aux clients quand vous partagez un ticket (pour les PDF qui n\'en contiennent pas).',
      clavier: TextInputType.url,
    );
    if (v == null || v.isEmpty) return;
    await appState.repo.setSetting('login_url', v);
    _charger();
  }

  Future<void> _sauvegarder() async {
    try {
      final fichier = await Sauvegarde.exporter(appState.repo);
      await appState.repo.setSetting(
          'derniere_sauvegarde', '${DateTime.now().millisecondsSinceEpoch}');
      await Share.shareXFiles(
        [XFile(fichier.path)],
        text: 'Sauvegarde Mtandao du ${fmtJourCourt(DateTime.now())}',
      );
      _charger();
    } catch (e) {
      _info('Sauvegarde impossible : $e');
    }
  }

  Future<void> _modifierTauxDollar() async {
    final saisi = await demanderTexte(
      context,
      titre: 'Paiement en dollars',
      libelle: 'Francs congolais pour 1 dollar (0 = désactivé)',
      aide:
          'Avec un taux, la fenêtre de vente propose de recevoir des dollars. Chaque vente garde le taux du jour : changer le taux plus tard ne modifie pas les ventes passées.',
      initial: _tauxDollar > 0 ? '$_tauxDollar' : '',
      clavier: TextInputType.number,
    );
    final v = int.tryParse(saisi ?? '');
    if (v == null || v < 0) return;
    if (v == 0) {
      await appState.repo.removeSetting(cleTauxDollar);
    } else {
      await appState.repo.setSetting(cleTauxDollar, '$v');
    }
    appState.changed();
    await _charger();
  }

  Future<void> _modifierSeuilStock() async {
    final saisi = await demanderTexte(
      context,
      titre: 'Alerte de stock bas',
      libelle: 'Prévenir quand il reste ce nombre de tickets (0 = jamais)',
      initial: '$_seuilStock',
      clavier: TextInputType.number,
    );
    final v = int.tryParse(saisi ?? '');
    if (v == null || v < 0) return;
    await appState.repo.setSetting(cleSeuilStock, '$v');
    appState.changed();
    await _charger();
  }

  Future<void> _modifierDelaiDette() async {
    final saisi = await demanderTexte(
      context,
      titre: 'Dettes en retard',
      libelle: 'Signaler un crédit non payé après combien de jours ? (0 = jamais)',
      initial: '$_delaiDette',
      clavier: TextInputType.number,
    );
    final v = int.tryParse(saisi ?? '');
    if (v == null || v < 0) return;
    await appState.repo.setSetting(cleDelaiDette, '$v');
    appState.changed();
    await _charger();
  }

  Future<void> _connecterDrive() async {
    if (_driveOccupe) return;
    if (!DriveBackup.configure) {
      _info('Google Drive n\'est pas configuré dans cette version (voir le README).');
      return;
    }
    setState(() => _driveOccupe = true);
    try {
      final email = await DriveBackup.connecter();
      await appState.repo.setSetting(DriveBackup.cleActif, '1');
      await appState.repo.setSetting(DriveBackup.cleEmail, email);
      await appState.repo.removeSetting(DriveBackup.cleErreur);
      await SauvegardeAuto.planifier();
      final r = await DriveBackup.sauvegarder(appState.repo,
          force: true, interactif: true);
      _info(r.ok
          ? 'Google Drive connecté. ${r.message}'
          : 'Google Drive connecté, mais : ${r.message}');
    } catch (e) {
      _info(DriveBackup.messageErreur(e));
    } finally {
      if (mounted) setState(() => _driveOccupe = false);
      await _charger();
    }
  }

  Future<void> _sauvegarderDriveMaintenant() async {
    if (_driveOccupe) return;
    setState(() => _driveOccupe = true);
    try {
      final r = await DriveBackup.sauvegarder(appState.repo,
          force: true, interactif: true);
      _info(r.message);
    } finally {
      if (mounted) setState(() => _driveOccupe = false);
      await _charger();
    }
  }

  Future<void> _basculerWifiDrive(bool wifiSeulement) async {
    await appState.repo
        .setSetting(DriveBackup.cleWifi, wifiSeulement ? '1' : '0');
    try {
      await SauvegardeAuto.planifier(wifiSeulement: wifiSeulement);
    } catch (_) {}
    await _charger();
  }

  Future<void> _deconnecterDrive() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Déconnecter Google Drive ?'),
        content: Text(
            'Les sauvegardes automatiques s\'arrêtent. Les fichiers déjà envoyés restent dans le dossier « ${DriveBackup.dossierNom} » de votre Drive.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Déconnecter')),
        ],
      ),
    );
    if (ok != true) return;
    await SauvegardeAuto.arreter();
    await DriveBackup.deconnecter();
    for (final cle in [
      DriveBackup.cleWifi,
      DriveBackup.cleTaille,
      DriveBackup.cleActif,
      DriveBackup.cleEmail,
      DriveBackup.cleEmpreinte,
      DriveBackup.cleSucces,
      DriveBackup.cleEssai,
      DriveBackup.cleErreur,
    ]) {
      await appState.repo.removeSetting(cle);
    }
    _info('Google Drive déconnecté.');
    await _charger();
  }

  Future<void> _restaurer() async {
    final choix = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: false,
    );
    if (choix == null || choix.files.isEmpty) return;
    final chemin = choix.files.single.path;
    if (chemin == null) {
      _info('Impossible d\'accéder à ce fichier.');
      return;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: const Text('Restaurer cette sauvegarde ?'),
        content: const Text(
            'Toutes les données actuelles (lots, tickets, ventes, forfaits) seront remplacées par celles de la sauvegarde. Votre code PIN ne change pas.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remplacer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final octets = await File(chemin).readAsBytes();
      await Sauvegarde.restaurer(appState.repo, octets);
      await appState.definirLotActif(null);
      appState.changed();
      await _charger();
      _info('Sauvegarde restaurée.');
    } on BackupException catch (e) {
      _info(e.message);
    } catch (e) {
      _info('Restauration impossible : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        children: [
          const _Entete('Ventes'),
          ListTile(
            leading: const Icon(Icons.sell_outlined),
            title: const Text('Forfaits et prix'),
            subtitle: const Text('1 jour, 1 heure, 1 semaine, 1 mois…'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ForfaitsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.attach_money_rounded),
            title: const Text('Paiement en dollars'),
            subtitle: Text(_tauxDollar > 0
                ? '1 dollar = ${cdf(_tauxDollar)}'
                : 'Désactivé : saisissez le taux pour accepter des dollars'),
            onTap: _modifierTauxDollar,
          ),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text('Alerte de stock bas'),
            subtitle: Text(_seuilStock <= 0
                ? 'Désactivée'
                : 'Prévenir quand il reste $_seuilStock tickets ou moins'),
            onTap: _modifierSeuilStock,
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('Clients et dettes'),
            subtitle: const Text('Ventes à crédit à encaisser'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DettesScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.event_busy_outlined),
            title: const Text('Dettes en retard'),
            subtitle: Text(_delaiDette <= 0
                ? 'Pas de rappel de retard'
                : 'Signaler un crédit non payé après $_delaiDette jours'),
            onTap: _modifierDelaiDette,
          ),
          ListTile(
            leading: const Icon(Icons.history_toggle_off_rounded),
            title: const Text('Journal des annulations'),
            subtitle: const Text('Qui a annulé quelle vente, et quand'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const JournalAnnulationsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.savings_outlined),
            title: const Text('Clôture de caisse'),
            subtitle: const Text('Comparer l\'argent compté à l\'argent attendu'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CaisseScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: const Text('Suivi d\'utilisation'),
            subtitle: const Text('Excel du routeur : tickets utilisés ou jamais utilisés'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const SuiviUtilisationScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.people_alt_outlined),
            title: const Text('Vendeurs'),
            subtitle: const Text('Qui vend : un rapport par vendeur'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const VendeursScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.link_rounded),
            title: const Text('Lien de connexion'),
            subtitle: Text(_loginUrl),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _modifierLien,
          ),
          const _Entete('Sécurité'),
          ListTile(
            leading: const Icon(Icons.lock_outline_rounded),
            title: const Text('Changer le code PIN'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ChangerPinScreen())),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint_rounded),
            title: const Text('Empreinte digitale ou visage'),
            subtitle: Text(_bioDispo
                ? 'Déverrouiller Mtandao sans taper le PIN. Le PIN reste possible.'
                : 'Indisponible : aucune empreinte ou visage enregistré sur ce téléphone.'),
            value: _bioActive && _bioDispo,
            onChanged: _bioDispo
                ? (v) async {
                    if (v) {
                      // On vérifie d'abord que ça marche, pour ne pas s'enfermer dehors.
                      final ok = await Biometrie.demander(
                          'Confirmez pour activer le déverrouillage');
                      if (!ok) return;
                    }
                    await Biometrie.definirActive(v);
                    _charger();
                  }
                : null,
          ),
          const _Entete('Données'),
          ListTile(
            leading: Icon(
              _sauvegardeAncienne
                  ? Icons.warning_amber_rounded
                  : Icons.cloud_upload_outlined,
              color: _sauvegardeAncienne
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
            title: const Text('Sauvegarder mes données'),
            subtitle: Text(
              _derniereSauvegarde == null
                  ? 'Jamais sauvegardé. Envoyez le fichier sur WhatsApp, Drive ou e-mail.'
                  : 'Dernière sauvegarde : ${fmtJourCourt(_derniereSauvegarde!)} à ${fmtHeure(_derniereSauvegarde!)}'
                      '${_sauvegardeAncienne ? '\nPensez à sauvegarder à nouveau.' : ''}',
              style: _sauvegardeAncienne
                  ? TextStyle(color: Theme.of(context).colorScheme.error)
                  : null,
            ),
            onTap: _sauvegarder,
          ),
          ..._tuilesDrive(context),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore_rounded),
            title: const Text('Restaurer une sauvegarde'),
            subtitle: const Text('Utile si vous changez ou perdez de téléphone.'),
            onTap: _restaurer,
          ),
          const _Entete('Affichage et aide'),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Apparence'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ValueListenableBuilder<ThemeMode>(
                valueListenable: themeMode,
                builder: (context, mode, _) => SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                        value: ThemeMode.system, label: Text('Auto')),
                    ButtonSegment(value: ThemeMode.light, label: Text('Clair')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Sombre')),
                  ],
                  selected: {mode},
                  onSelectionChanged: (s) => appState.definirTheme(s.first),
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline_rounded),
            title: const Text('Comment ça marche'),
            subtitle: const Text('Le guide : importer, vendre, rapports, sauvegarde'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const AideScreen())),
          ),
          const _Entete('À propos'),
          const ListTile(
            leading: Icon(Icons.info_outline_rounded),
            title: Text('Mtandao 1.0.0'),
            subtitle: Text(
                'Fonctionne sans Internet. Vos données restent sur ce téléphone.'),
          ),
        ],
      ),
    );
  }
}

extension on _SettingsScreenState {
  List<Widget> _tuilesDrive(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!_driveActif) {
      return [
        ListTile(
          leading: _driveOccupe
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.cloud_sync_outlined),
          title: const Text('Sauvegarde automatique Google Drive'),
          subtitle: Text(DriveBackup.configure
              ? 'Une sauvegarde chaque heure (si les données ont changé), dans le dossier « ${DriveBackup.dossierNom} ». Les ${DriveBackup.garder} plus récentes sont gardées.'
              : 'Indisponible dans cette version : identifiant Google absent (voir le README).'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: DriveBackup.configure ? _connecterDrive : null,
        ),
      ];
    }
    final succes = _driveSucces;
    return [
      ListTile(
        leading: Icon(
          _driveErreur == null
              ? Icons.cloud_done_outlined
              : Icons.cloud_off_outlined,
          color: _driveErreur == null ? null : cs.error,
        ),
        title: const Text('Google Drive connecté'),
        subtitle: Text(
          [
            if (_driveEmail != null) _driveEmail!,
            succes == null
                ? 'Aucune sauvegarde envoyée pour le moment.'
                : 'Dernier envoi : ${fmtJourCourt(succes)} à ${fmtHeure(succes)}',
            'Chaque heure, ${DriveBackup.garder} fichiers gardés dans « ${DriveBackup.dossierNom} ».',
            if (_driveTaille != null)
              'Taille d\'une sauvegarde : ${DriveBackup.tailleLisible(_driveTaille!)}.',
            if (_driveErreur != null) _driveErreur!,
          ].join('\n'),
          style: _driveErreur == null ? null : TextStyle(color: cs.error),
        ),
        isThreeLine: true,
      ),
      SwitchListTile(
        secondary: const Icon(Icons.wifi_rounded),
        title: const Text('Wi-Fi seulement'),
        subtitle: const Text(
            'Évite d\'utiliser vos données mobiles : chaque sauvegarde contient les images des tickets et peut peser plusieurs Mo.'),
        value: _driveWifi,
        onChanged: _driveOccupe ? null : _basculerWifiDrive,
      ),
      ListTile(
        leading: _driveOccupe
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.cloud_upload_rounded),
        title: const Text('Sauvegarder maintenant sur Drive'),
        onTap: _driveOccupe ? null : _sauvegarderDriveMaintenant,
      ),
      ListTile(
        leading: const Icon(Icons.link_off_rounded),
        title: const Text('Déconnecter Google Drive'),
        onTap: _driveOccupe ? null : _deconnecterDrive,
      ),
    ];
  }
}

class _Entete extends StatelessWidget {
  const _Entete(this.texte);
  final String texte;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
        child: Text(texte,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700)),
      ),
    );
  }
}

// ---------------------------------------------------------------- forfaits

class ForfaitsScreen extends StatefulWidget {
  const ForfaitsScreen({super.key});

  @override
  State<ForfaitsScreen> createState() => _ForfaitsScreenState();
}

class _ForfaitsScreenState extends State<ForfaitsScreen> {
  List<Forfait> _forfaits = [];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final f = await appState.repo.forfaits();
    if (!mounted) return;
    setState(() => _forfaits = f);
  }

  Future<void> _editer([Forfait? f]) async {
    // Tickets non vendus de ce forfait : le prix peut aussi leur être appliqué.
    final stock = f == null ? 0 : await appState.repo.stockForfait(f.id);
    if (!mounted) return;
    final r = await showDialog<_ChampsForfait>(
      context: context,
      builder: (_) => _DialogueForfait(existant: f, nbStock: stock),
    );
    if (r == null) return;
    if (f == null) {
      await appState.repo.ajouterForfait(r.nom, r.minutes, r.prix);
    } else {
      await appState.repo.modifierForfait(f.id,
          nom: r.nom, dureeMinutes: r.minutes, prix: r.prix);
      if (r.appliquerAuStock && r.prix != f.prix) {
        await appState.repo.modifierPrixStockForfait(f.id, r.prix);
      }
    }
    appState.changed();
    _charger();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forfaits et prix')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editer(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Ajouter un forfait'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Un nouveau prix s\'applique aux prochains lots importés. Pour les tickets déjà importés mais pas encore vendus, cochez « Appliquer aussi » en modifiant le forfait, ou changez le prix d\'un lot dans Lots. Les ventes passées gardent leur prix : les rapports restent justes.',
            ),
          ),
          for (final f in _forfaits)
            ListTile(
              title: Text(f.nom,
                  style: TextStyle(
                      decoration: f.actif ? null : TextDecoration.lineThrough)),
              subtitle: Text(
                  '${libelleDuree(f.dureeMinutes)}  ·  ${cdf(f.prix)}'
                  '${f.actif ? '' : '  ·  désactivé'}'),
              onTap: () => _editer(f),
              trailing: Semantics(
                label: f.actif
                    ? 'Forfait ${f.nom} activé'
                    : 'Forfait ${f.nom} désactivé',
                child: Switch(
                  value: f.actif,
                  onChanged: (v) async {
                    await appState.repo.modifierForfait(f.id, actif: v);
                    _charger();
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChampsForfait {
  _ChampsForfait(this.nom, this.minutes, this.prix,
      {this.appliquerAuStock = false});
  final String nom;
  final int minutes;
  final int prix;

  /// Appliquer aussi le prix aux tickets non vendus de ce forfait.
  final bool appliquerAuStock;
}

class _DialogueForfait extends StatefulWidget {
  const _DialogueForfait({this.existant, this.nbStock = 0});
  final Forfait? existant;

  /// Tickets non vendus de ce forfait.
  final int nbStock;

  @override
  State<_DialogueForfait> createState() => _DialogueForfaitState();
}

class _DialogueForfaitState extends State<_DialogueForfait> {
  static const Map<int, String> _durees = {
    60: '1 heure',
    120: '2 heures',
    180: '3 heures',
    360: '6 heures',
    720: '12 heures',
    1440: '1 jour (24 h)',
    4320: '3 jours',
    10080: '1 semaine',
    43200: '1 mois',
  };

  late final TextEditingController _nom;
  late final TextEditingController _prix;
  late int _minutes;
  bool _appliquer = false;

  @override
  void initState() {
    super.initState();
    final f = widget.existant;
    _minutes = f?.dureeMinutes ?? 60;
    _nom = TextEditingController(text: f?.nom ?? _durees[_minutes]);
    _prix = TextEditingController(text: f == null ? '' : '${f.prix}');
  }

  @override
  void dispose() {
    _nom.dispose();
    _prix.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = <int, String>{..._durees};
    if (!items.containsKey(_minutes)) items[_minutes] = libelleDuree(_minutes);
    final prix = int.tryParse(_prix.text.trim());
    final valide = _nom.text.trim().isNotEmpty && prix != null && prix >= 0;
    return AlertDialog(
      title: Text(widget.existant == null ? 'Nouveau forfait' : 'Modifier le forfait'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Durée'),
            DropdownButton<int>(
              isExpanded: true,
              value: _minutes,
              items: [
                for (final e in items.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  // Met à jour le nom proposé tant qu'il n'a pas été personnalisé.
                  if (_nom.text.trim().isEmpty ||
                      _durees.values.contains(_nom.text.trim())) {
                    _nom.text = _durees[v] ?? libelleDuree(v);
                  }
                  _minutes = v;
                });
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nom,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  labelText: 'Nom', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _prix,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  labelText: 'Prix (CDF)', border: OutlineInputBorder()),
            ),
            if (widget.existant != null &&
                widget.nbStock > 0 &&
                prix != null &&
                prix != widget.existant!.prix)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _appliquer,
                onChanged: (v) => setState(() => _appliquer = v ?? false),
                title: Text(
                    'Appliquer aussi aux ${widget.nbStock} tickets non vendus de ce forfait'),
                subtitle: const Text('Les ventes déjà faites gardent leur prix.'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        FilledButton(
          onPressed: valide
              ? () => Navigator.pop(
                  context,
                  _ChampsForfait(_nom.text.trim(), _minutes, prix,
                      appliquerAuStock: _appliquer))
              : null,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ PIN

enum _EtapePin { actuel, nouveau, confirmer }

class ChangerPinScreen extends StatefulWidget {
  const ChangerPinScreen({super.key});

  @override
  State<ChangerPinScreen> createState() => _ChangerPinScreenState();
}

class _ChangerPinScreenState extends State<ChangerPinScreen> {
  _EtapePin _etape = _EtapePin.actuel;
  String _nouveau = '';
  String? _message;
  bool _erreur = false;

  Future<void> _surSaisie(String pin) async {
    switch (_etape) {
      case _EtapePin.actuel:
        final ok = await PinService.verifier(pin);
        if (!mounted) return;
        setState(() {
          if (ok) {
            _etape = _EtapePin.nouveau;
            _message = null;
            _erreur = false;
          } else {
            _message = 'Code incorrect.';
            _erreur = true;
          }
        });
      case _EtapePin.nouveau:
        setState(() {
          _nouveau = pin;
          _etape = _EtapePin.confirmer;
          _message = null;
          _erreur = false;
        });
      case _EtapePin.confirmer:
        if (pin == _nouveau) {
          await PinService.definir(pin);
          if (!mounted) return;
          Navigator.pop(context);
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
                const SnackBar(content: Text('Code PIN modifié.')));
        } else {
          setState(() {
            _etape = _EtapePin.nouveau;
            _nouveau = '';
            _message = 'Les deux codes ne correspondent pas.';
            _erreur = true;
          });
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final titre = switch (_etape) {
      _EtapePin.actuel => 'Code PIN actuel',
      _EtapePin.nouveau => 'Nouveau code PIN',
      _EtapePin.confirmer => 'Confirmez le nouveau code',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Changer le code PIN')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: PinPad(
              key: ValueKey(_etape),
              titre: titre,
              message: _message,
              erreur: _erreur,
              onComplete: _surSaisie,
            ),
          ),
        ),
      ),
    );
  }
}
