import 'package:flutter/material.dart';

import '../models.dart';
import '../security.dart';
import '../state.dart';
import '../widgets/dialogues.dart';

/// Liste des vendeurs. Le vendeur qui vend se choisit sur l'écran de vente ;
/// chaque vente enregistre qui l'a faite, pour le rapport par vendeur.
class VendeursScreen extends StatefulWidget {
  const VendeursScreen({super.key});

  @override
  State<VendeursScreen> createState() => _VendeursScreenState();
}

class _VendeursScreenState extends State<VendeursScreen> {
  List<Vendeur> _vendeurs = [];
  bool _chargement = true;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final v = await appState.repo.vendeurs();
    if (!mounted) return;
    setState(() {
      _vendeurs = v;
      _chargement = false;
    });
  }

  Future<void> _editer([Vendeur? v]) async {
    final nom = await demanderTexte(
      context,
      titre: v == null ? 'Nouveau vendeur' : 'Renommer le vendeur',
      libelle: 'Nom',
      initial: v?.nom ?? '',
      majuscules: TextCapitalization.words,
    );
    if (nom == null || nom.isEmpty) return;
    if (v == null) {
      await appState.repo.ajouterVendeur(nom);
    } else {
      await appState.repo.modifierVendeur(v.id, nom: nom);
    }
    appState.changed();
    await _charger();
  }

  void _info(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Définit ou change le code personnel d'un vendeur (saisi deux fois).
  Future<void> _definirCode(Vendeur v) async {
    final a = await demanderTexte(
      context,
      titre: 'Code de ${v.nom}',
      libelle: 'Code à 4 chiffres',
      clavier: TextInputType.number,
      masquer: true,
    );
    if (a == null || !mounted) return;
    if (!RegExp('^\\d{${PinService.longueur}}\$').hasMatch(a)) {
      _info('Le code doit avoir exactement ${PinService.longueur} chiffres.');
      return;
    }
    final b = await demanderTexte(
      context,
      titre: 'Confirmez le code',
      libelle: 'Saisissez le code à nouveau',
      clavier: TextInputType.number,
      masquer: true,
    );
    if (b == null || !mounted) return;
    if (b != a) {
      _info('Les deux codes ne correspondent pas.');
      return;
    }
    await appState.repo.definirPinVendeur(v.id, a);
    await PinService.reinitialiserEchecsVendeur(v.id);
    appState.changed();
    _info('Code de ${v.nom} enregistré.');
    await _charger();
  }

  Future<void> _retirerCode(Vendeur v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retirer le code ?'),
        content: Text(
            '${v.nom} pourra de nouveau vendre en son nom sans code.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Non')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Retirer')),
        ],
      ),
    );
    if (ok != true) return;
    await appState.repo.definirPinVendeur(v.id, null);
    await PinService.reinitialiserEchecsVendeur(v.id);
    appState.changed();
    await _charger();
  }

  Future<void> _menuCode(Vendeur v) async {
    final choix = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.pin_outlined),
              title: Text(v.aUnCode ? 'Changer le code' : 'Définir un code'),
              onTap: () => Navigator.pop(ctx, 'definir'),
            ),
            if (v.aUnCode)
              ListTile(
                leading: const Icon(Icons.lock_open_rounded),
                title: const Text('Retirer le code'),
                onTap: () => Navigator.pop(ctx, 'retirer'),
              ),
          ],
        ),
      ),
    );
    if (choix == 'definir') await _definirCode(v);
    if (choix == 'retirer') await _retirerCode(v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vendeurs')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editer(),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Ajouter un vendeur'),
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Text(
                    'Ajoutez les personnes qui vendent. Sur l\'écran de vente, une pastille permet de choisir qui vend ; chaque vente garde son nom et les rapports montrent le total par vendeur. Un code personnel (4 chiffres) peut être demandé pour vendre au nom d\'un vendeur : il est redemandé à chaque verrouillage de l\'application.',
                  ),
                ),
                if (_vendeurs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('Aucun vendeur pour le moment.')),
                  ),
                for (final v in _vendeurs)
                  ListTile(
                    title: Text(v.nom,
                        style: TextStyle(
                            decoration:
                                v.actif ? null : TextDecoration.lineThrough)),
                    subtitle: Text(
                        '${v.actif ? 'Actif' : 'Désactivé'}${v.aUnCode ? '  ·  protégé par un code' : ''}'),
                    onTap: () => _editer(v),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: v.aUnCode
                              ? 'Changer ou retirer le code de ${v.nom}'
                              : 'Définir un code pour ${v.nom}',
                          onPressed: () => _menuCode(v),
                          icon: Icon(v.aUnCode
                              ? Icons.lock_rounded
                              : Icons.lock_open_rounded),
                        ),
                        Semantics(
                          label: v.actif
                              ? 'Vendeur ${v.nom} actif'
                              : 'Vendeur ${v.nom} désactivé',
                          child: Switch(
                            value: v.actif,
                            onChanged: (actif) async {
                              await appState.repo
                                  .modifierVendeur(v.id, actif: actif);
                              appState.changed();
                              await _charger();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
