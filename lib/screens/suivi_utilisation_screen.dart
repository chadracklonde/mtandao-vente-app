import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../pdf_import.dart';
import '../state.dart';
import '../xlsx_import.dart';

/// Compare l'export Excel du routeur (colonne « Statut ») à nos ventes :
/// quels tickets vendus n'ont jamais servi, et quels tickets ont servi sans
/// avoir été vendus.
class SuiviUtilisationScreen extends StatefulWidget {
  const SuiviUtilisationScreen({super.key});

  @override
  State<SuiviUtilisationScreen> createState() => _SuiviUtilisationScreenState();
}

class _SuiviUtilisationScreenState extends State<SuiviUtilisationScreen> {
  bool _occupe = false;
  String? _erreur;
  RapportUtilisation? _rapport;

  Future<void> _choisir() async {
    final choix = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: false,
    );
    final chemin = choix?.files.single.path;
    if (chemin == null) return;
    setState(() {
      _occupe = true;
      _erreur = null;
      _rapport = null;
    });
    try {
      final statuts = await XlsxImporter.lireStatuts(chemin);
      final r = await appState.repo.appliquerUtilisation(
          utilises: statuts.utilises, disponibles: statuts.disponibles);
      appState.changed();
      if (!mounted) return;
      setState(() => _rapport = r);
    } on ImportException catch (e) {
      if (mounted) setState(() => _erreur = e.message);
    } catch (e) {
      if (mounted) setState(() => _erreur = 'Lecture impossible : $e');
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Future<void> _enregistrerCommeVendus(List<Ticket> tickets) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enregistrer comme vendus ?'),
        content: Text(
            '${tickets.length} ticket${tickets.length > 1 ? 's' : ''} seront enregistrés comme vendus en espèces, au prix du ticket. À utiliser si vous êtes sûr que le client a payé.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Non')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Oui, enregistrer')),
        ],
      ),
    );
    if (ok != true) return;
    final repo = appState.repo;
    final vendeur = await repo.vendeurActifId();
    for (final t in tickets) {
      await repo.vendre(t.id, vendeurId: vendeur);
    }
    appState.changed();
    if (!mounted) return;
    setState(() {
      final r = _rapport!;
      _rapport = RapportUtilisation(
        marques: r.marques,
        vendusNonUtilises: r.vendusNonUtilises,
        utilisesNonVendus: const [],
        inconnus: r.inconnus,
      );
    });
  }

  Widget _liste(String titre, String aide, List<Ticket> l, {Widget? action}) {
    if (l.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text('$titre (${l.length})',
            style: Theme.of(context).textTheme.titleMedium),
        Text(aide, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in l.take(200))
              Chip(
                label: Text(t.code),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        if (l.length > 200) Text('… et ${l.length - 200} autres'),
        if (action != null) ...[const SizedBox(height: 8), action],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _rapport;
    return Scaffold(
      appBar: AppBar(title: const Text('Suivi d\'utilisation')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
              'Importez l\'export Excel de votre routeur (avec la colonne « Statut »). '
              'L\'application marque les tickets déjà utilisés et signale les écarts avec vos ventes.'),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _occupe ? null : _choisir,
            icon: const Icon(Icons.table_chart_outlined),
            label: const Text('Choisir le fichier Excel'),
          ),
          if (_occupe)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: LinearProgressIndicator(),
            ),
          if (_erreur != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_erreur!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (r != null) ...[
            const SizedBox(height: 20),
            Text(
                '${r.marques} ticket${r.marques > 1 ? 's' : ''} marqué${r.marques > 1 ? 's' : ''} comme utilisé${r.marques > 1 ? 's' : ''}.',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            if (r.inconnus > 0)
              Text('${r.inconnus} code${r.inconnus > 1 ? 's' : ''} du fichier ne sont pas dans l\'application.'),
            if (r.vendusNonUtilises.isEmpty && r.utilisesNonVendus.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Aucun écart : tout est cohérent.'),
              ),
            _liste(
              'Utilisés mais non vendus',
              'Ces tickets ont servi sur le réseau alors qu\'ils sont encore en stock : vente oubliée ou ticket pris sans payer.',
              r.utilisesNonVendus,
              action: OutlinedButton.icon(
                onPressed: () => _enregistrerCommeVendus(r.utilisesNonVendus),
                icon: const Icon(Icons.playlist_add_check_rounded),
                label: const Text('Les enregistrer comme vendus'),
              ),
            ),
            _liste(
              'Vendus mais pas encore utilisés',
              'Le client a payé mais ne s\'est pas encore connecté (ou n\'a pas reçu son code).',
              r.vendusNonUtilises,
            ),
          ],
        ],
      ),
    );
  }
}
