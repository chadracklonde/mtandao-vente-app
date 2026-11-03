import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../state.dart';

/// Journal des annulations : quel ticket, quand, par le vendeur (bouton
/// Annuler) ou par le patron (avec son code).
class JournalAnnulationsScreen extends StatefulWidget {
  const JournalAnnulationsScreen({super.key});

  @override
  State<JournalAnnulationsScreen> createState() =>
      _JournalAnnulationsScreenState();
}

class _JournalAnnulationsScreenState extends State<JournalAnnulationsScreen> {
  List<AnnulationLigne> _lignes = [];
  bool _chargement = true;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final l = await appState.repo.journalAnnulations();
    if (!mounted) return;
    setState(() {
      _lignes = l;
      _chargement = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Journal des annulations')),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _lignes.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Aucune annulation pour le moment.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: _lignes.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final a = _lignes[i];
                    final patron = a.origine == 'patron';
                    return ListTile(
                      leading: Icon(
                          patron
                              ? Icons.admin_panel_settings_outlined
                              : Icons.undo_rounded,
                          color: patron ? cs.primary : null),
                      title: Text(a.code,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, letterSpacing: 1)),
                      subtitle: Text([
                        'Annulé le ${fmtDateHeure(a.annuleLe)}',
                        if (a.venduLe != null) 'vendu le ${fmtDateHeure(a.venduLe!)}',
                        if (a.vendeurNom != null) 'vendeur : ${a.vendeurNom}',
                      ].join('  ·  ')),
                      trailing: Text(patron ? 'Patron' : 'Vendeur',
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    );
                  },
                ),
    );
  }
}
