import 'package:flutter/material.dart';

import '../models.dart';
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
                    'Ajoutez les personnes qui vendent. Sur l\'écran de vente, une pastille permet de choisir qui vend ; chaque vente garde son nom et les rapports montrent le total par vendeur.',
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
                    subtitle: Text(v.actif ? 'Actif' : 'Désactivé'),
                    onTap: () => _editer(v),
                    trailing: Semantics(
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
                  ),
              ],
            ),
    );
  }
}
