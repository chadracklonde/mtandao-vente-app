import 'package:flutter/material.dart';

import '../codes_manuels.dart';
import '../format.dart';
import '../models.dart';
import '../state.dart';

/// Saisie ou collage de codes à la main : crée un nouveau lot, ou ajoute des
/// tickets à un lot existant ([lot]). Utile quand le PDF est introuvable ou
/// mal lu.
class SaisieManuelleScreen extends StatefulWidget {
  const SaisieManuelleScreen({super.key, this.lot});

  /// Si renseigné, les codes sont ajoutés à ce lot (même forfait et même prix).
  final Lot? lot;

  @override
  State<SaisieManuelleScreen> createState() => _SaisieManuelleScreenState();
}

class _SaisieManuelleScreenState extends State<SaisieManuelleScreen> {
  final _codes = TextEditingController();
  late final TextEditingController _nom = TextEditingController(
      text: 'Saisie du ${fmtJourCourt(DateTime.now())}');
  List<Forfait> _forfaits = [];
  Forfait? _forfait;
  bool _occupe = false;

  @override
  void initState() {
    super.initState();
    if (widget.lot == null) _chargerForfaits();
  }

  @override
  void dispose() {
    _codes.dispose();
    _nom.dispose();
    super.dispose();
  }

  Future<void> _chargerForfaits() async {
    final f = await appState.repo.forfaits(seulementActifs: true);
    if (!mounted) return;
    setState(() {
      _forfaits = f;
      _forfait = f.isEmpty ? null : f.first;
    });
  }

  CodesSaisis get _lecture => CodesManuels.lire(_codes.text);

  Future<void> _enregistrer() async {
    final lecture = _lecture;
    if (lecture.tickets.isEmpty || _occupe) return;
    setState(() => _occupe = true);
    try {
      final repo = appState.repo;
      final ImportResult r;
      if (widget.lot != null) {
        r = await repo.ajouterTickets(widget.lot!.id, lecture.tickets);
      } else {
        final f = _forfait;
        if (f == null) return;
        final nom = _nom.text.trim().isEmpty
            ? 'Saisie du ${fmtJourCourt(DateTime.now())}'
            : _nom.text.trim();
        r = await repo.importerLot(
          nom: nom,
          forfait: f,
          source: 'manuel',
          tickets: lecture.tickets,
        );
        if (r.lotId != null) await appState.definirLotActif(r.lotId);
      }
      appState.changed();
      if (!mounted) return;
      final doublons = r.doublons + lecture.doublonsSaisis;
      final message = r.inseres == 0
          ? 'Aucun ticket ajouté : ces codes existent déjà.'
          : '${r.inseres} ticket${r.inseres > 1 ? 's' : ''} ajouté${r.inseres > 1 ? 's' : ''}'
              '${doublons > 0 ? ' ($doublons déjà présent${doublons > 1 ? 's' : ''}, ignoré${doublons > 1 ? 's' : ''})' : ''}.';
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
      if (r.inseres > 0) Navigator.of(context).pop(r);
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lecture = _lecture;
    final n = lecture.tickets.length;
    final ajout = widget.lot != null;
    final pret = n > 0 && (ajout || _forfait != null) && !_occupe;

    return Scaffold(
      appBar: AppBar(
          title: Text(ajout ? 'Ajouter des codes' : 'Saisir des codes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            ajout
                ? 'Les codes seront ajoutés au lot « ${widget.lot!.nom} » (${widget.lot!.forfaitNom}).'
                : 'Tapez ou collez un code par ligne. Pour un ticket avec mot de passe : le code, un espace, puis le mot de passe.',
          ),
          const SizedBox(height: 16),
          if (!ajout) ...[
            DropdownButtonFormField<int>(
              // Recréé quand la liste est chargée : « initialValue » n'est lu
              // qu'à la création du champ.
              key: ValueKey('forfait-${_forfaits.length}-${_forfait?.id}'),
              initialValue: _forfait?.id,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Forfait', border: OutlineInputBorder()),
              items: [
                for (final f in _forfaits)
                  DropdownMenuItem(
                    value: f.id,
                    child: Text('${f.nom}  ·  ${cdf(f.prix)}',
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (id) => setState(() {
                _forfait = _forfaits.firstWhere((f) => f.id == id);
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nom,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Nom du lot', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _codes,
            minLines: 6,
            maxLines: 14,
            keyboardType: TextInputType.multiline,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Codes (un par ligne)',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              n == 0
                  ? 'Aucun code lu pour le moment.'
                  : '$n ticket${n > 1 ? 's' : ''} prêt${n > 1 ? 's' : ''}'
                      '${lecture.doublonsSaisis > 0 ? '  ·  ${lecture.doublonsSaisis} doublon${lecture.doublonsSaisis > 1 ? 's' : ''} dans la saisie' : ''}',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
          if (lecture.lignesRejetees.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'À corriger : ligne${lecture.lignesRejetees.length > 1 ? 's' : ''} '
                '${lecture.lignesRejetees.take(8).join(', ')}'
                '${lecture.lignesRejetees.length > 8 ? '…' : ''} '
                '(caractères interdits ou plus de deux mots).',
                style: TextStyle(color: cs.error),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: pret ? _enregistrer : null,
            icon: _occupe
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_rounded),
            label: Text(ajout ? 'Ajouter au lot' : 'Créer le lot'),
          ),
        ],
      ),
    );
  }
}
