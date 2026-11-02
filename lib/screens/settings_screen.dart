import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../backup.dart';
import '../format.dart';
import '../models.dart';
import '../security.dart';
import '../state.dart';
import '../widgets/pin_pad.dart';

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
    if (!mounted) return;
    setState(() {
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
    final ctrl = TextEditingController(text: _loginUrl);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lien de connexion'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Adresse envoyée aux clients quand vous partagez un ticket (pour les PDF qui n\'en contiennent pas).'),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Enregistrer')),
        ],
      ),
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
            leading: const Icon(Icons.link_rounded),
            title: const Text('Lien de connexion'),
            subtitle: Text(_loginUrl),
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
            leading: const Icon(Icons.cloud_upload_outlined),
            title: const Text('Sauvegarder mes données'),
            subtitle: Text(_derniereSauvegarde == null
                ? 'Jamais sauvegardé. Envoyez le fichier sur WhatsApp, Drive ou e-mail.'
                : 'Dernière sauvegarde : ${fmtJourCourt(_derniereSauvegarde!)} à ${fmtHeure(_derniereSauvegarde!)}'),
            onTap: _sauvegarder,
          ),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore_rounded),
            title: const Text('Restaurer une sauvegarde'),
            subtitle: const Text('Utile si vous changez ou perdez de téléphone.'),
            onTap: _restaurer,
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

class _Entete extends StatelessWidget {
  const _Entete(this.texte);
  final String texte;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
      child: Text(texte,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700)),
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
    final r = await showDialog<_ChampsForfait>(
      context: context,
      builder: (_) => _DialogueForfait(existant: f),
    );
    if (r == null) return;
    if (f == null) {
      await appState.repo.ajouterForfait(r.nom, r.minutes, r.prix);
    } else {
      await appState.repo.modifierForfait(f.id,
          nom: r.nom, dureeMinutes: r.minutes, prix: r.prix);
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
              'Un nouveau prix s\'applique aux prochains lots importés. Les lots déjà importés gardent leur prix, pour que les rapports restent justes.',
            ),
          ),
          for (final f in _forfaits)
            ListTile(
              title: Text(f.nom,
                  style: TextStyle(
                      decoration: f.actif ? null : TextDecoration.lineThrough)),
              subtitle: Text('${libelleDuree(f.dureeMinutes)}  ·  ${cdf(f.prix)}'),
              onTap: () => _editer(f),
              trailing: Switch(
                value: f.actif,
                onChanged: (v) async {
                  await appState.repo.modifierForfait(f.id, actif: v);
                  _charger();
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ChampsForfait {
  _ChampsForfait(this.nom, this.minutes, this.prix);
  final String nom;
  final int minutes;
  final int prix;
}

class _DialogueForfait extends StatefulWidget {
  const _DialogueForfait({this.existant});
  final Forfait? existant;

  @override
  State<_DialogueForfait> createState() => _DialogueForfaitState();
}

class _DialogueForfaitState extends State<_DialogueForfait> {
  static const Map<int, String> _durees = {
    60: '1 heure',
    1440: '1 jour (24 h)',
    10080: '1 semaine',
    43200: '1 mois',
  };

  late final TextEditingController _nom;
  late final TextEditingController _prix;
  late int _minutes;

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
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  labelText: 'Prix (CDF)', border: OutlineInputBorder()),
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
                  context, _ChampsForfait(_nom.text.trim(), _minutes, prix!))
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
