import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../format.dart';
import '../models.dart';
import '../pdf_import.dart';
import '../state.dart';
import 'saisie_manuelle.dart';

/// Importation d'un fichier de tickets (PDF ou Excel) : choix du fichier, lecture, corrections
/// éventuelles, choix du forfait, création du lot.
class ImportFlow {
  static Future<void> demarrer(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);

    final choix = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'xlsx'],
      withData: false,
    );
    if (choix == null || choix.files.isEmpty) return;
    final chemin = choix.files.single.path;
    if (chemin == null) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Impossible d\'accéder à ce fichier.')));
      return;
    }
    if (!context.mounted) return;

    // ------------------------------------------------------------- lecture
    final progression =
        ValueNotifier<({double f, String m})>((f: 0.0, m: 'Ouverture du fichier…'));
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: _DialogueProgression(progression: progression),
      ),
    );

    ParsedPdf? lu;
    String? erreur;
    try {
      lu = await PdfImporter.lire(chemin, (f, m) {
        progression.value = (f: f, m: m);
      });
    } on ImportException catch (e) {
      erreur = e.message;
    } catch (e) {
      erreur = 'La lecture du PDF a échoué : $e';
    }
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();

    if (erreur != null || lu == null) {
      if (!context.mounted) return;
      final saisie = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.error_outline_rounded),
          title: const Text('Import impossible'),
          content: Text(
              '${erreur ?? 'Erreur inconnue.'}\n\nVous pouvez aussi saisir ou coller les codes à la main.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Saisir les codes')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('OK')),
          ],
        ),
      );
      if (saisie == true && context.mounted) {
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const SaisieManuelleScreen()));
      }
      return;
    }

    final parsed = lu;

    // ------------------------------------------- cases illisibles : saisie
    final slots = List<ParsedTicket?>.from(parsed.slots);
    var ignorees = 0;
    final aCorriger = parsed.echecs.keys.toList()..sort();
    for (var i = 0; i < aCorriger.length; i++) {
      if (!context.mounted) return;
      final idx = aCorriger[i];
      final saisi = await _saisirCode(
        context,
        parsed.echecs[idx]!,
        idx + 1,
        i + 1,
        aCorriger.length,
      );
      if (saisi == null || saisi.isEmpty) {
        ignorees++;
      } else {
        slots[idx] = ParsedTicket(
          code: saisi,
          motDePasse: null,
          numero: idx + 1,
          image: parsed.echecs[idx],
        );
      }
    }
    final tickets = slots.whereType<ParsedTicket>().toList();
    if (tickets.isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Aucun ticket à importer.')));
      return;
    }

    // --------------------------------------------- confirmation et forfait
    final repo = appState.repo;
    final forfaits = await repo.forfaits(seulementActifs: true);
    final existants = await repo.codesExistants();
    final vus = <String>{};
    var doublons = 0;
    for (final t in tickets) {
      if (existants.contains(t.code) || !vus.add(t.code)) doublons++;
    }
    if (!context.mounted) return;
    final nomParDefaut = p.basenameWithoutExtension(chemin);
    final confirmation = await showDialog<ConfirmationImport>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DialogueConfirmationImport(
        nomParDefaut: nomParDefaut,
        forfaits: forfaits,
        nombre: tickets.length,
        doublons: doublons,
        ignorees: ignorees,
        dureeMinutes: parsed.dureeMinutes,
        source: parsed.source,
        prixDetecte: parsed.prix,
      ),
    );
    if (confirmation == null) return;

    // ------------------------------------------------------------ insertion
    final resultat = await repo.importerLot(
      nom: confirmation.nom,
      forfait: confirmation.forfait,
      source: parsed.source,
      fichier: p.basename(chemin),
      loginUrl: parsed.loginUrl,
      tickets: tickets,
      prix: confirmation.prix,
    );
    // « Retenir ce prix » : le forfait prend ce prix pour les prochains imports.
    if (confirmation.retenirPrix &&
        confirmation.prix != confirmation.forfait.prix) {
      await repo.modifierForfait(confirmation.forfait.id,
          prix: confirmation.prix);
    }
    if (resultat.lotId != null) {
      final actif = appState.lotActifId;
      var changer = actif == null;
      if (!changer) {
        final lot = await repo.lot(actif);
        changer = lot == null || lot.restants == 0;
      }
      if (changer) await appState.definirLotActif(resultat.lotId);
    }
    appState.changed();

    final msg = resultat.lotId == null
        ? 'Rien d\'importé : ces tickets étaient déjà enregistrés.'
        : '${resultat.inseres} tickets importés'
            '${resultat.doublons > 0 ? ' · ${resultat.doublons} déjà connus ignorés' : ''}'
            '${ignorees > 0 ? ' · $ignorees illisibles ignorés' : ''}'
            '${parsed.ignores > 0 ? ' · ${parsed.ignores} déjà utilisés ignorés' : ''}';
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  static Future<String?> _saisirCode(BuildContext context, Uint8List image,
      int numero, int rang, int total) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('Code illisible ($rang/$total)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Le QR du ticket n° $numero n\'a pas pu être lu. '
                  'Saisissez le code écrit sur le ticket :'),
              const SizedBox(height: 10),
              Container(
                color: Colors.white,
                child: Image.memory(image, fit: BoxFit.fitWidth),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Code du ticket',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('Ignorer ce ticket')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Valider')),
        ],
      ),
    );
  }
}

/// Ce que l'utilisateur a validé avant l'import : nom du lot, forfait, prix
/// de chaque ticket, et s'il faut retenir ce prix pour le forfait.
class ConfirmationImport {
  ConfirmationImport(this.nom, this.forfait, this.prix,
      {this.retenirPrix = false});
  final String nom;
  final Forfait forfait;
  final int prix;
  final bool retenirPrix;
}

class _DialogueProgression extends StatelessWidget {
  const _DialogueProgression({required this.progression});
  final ValueNotifier<({double f, String m})> progression;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Lecture du fichier'),
      content: ValueListenableBuilder<({double f, String m})>(
        valueListenable: progression,
        builder: (context, v, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: v.f <= 0 ? null : v.f),
            const SizedBox(height: 14),
            Text(v.m),
            const SizedBox(height: 6),
            Text('Tout se passe sur ce téléphone, sans Internet.',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class DialogueConfirmationImport extends StatefulWidget {
  const DialogueConfirmationImport({
    super.key,
    required this.nomParDefaut,
    required this.forfaits,
    required this.nombre,
    required this.doublons,
    required this.ignorees,
    required this.dureeMinutes,
    required this.source,
    this.prixDetecte,
  });

  /// Prix lu dans le PDF, s'il y en avait un d'imprimé en texte.
  final int? prixDetecte;
  final String nomParDefaut;
  final List<Forfait> forfaits;
  final int nombre;
  final int doublons;
  final int ignorees;
  final int? dureeMinutes;
  final String source;

  @override
  State<DialogueConfirmationImport> createState() => DialogueConfirmationImportImportState();
}

class DialogueConfirmationImportImportState extends State<DialogueConfirmationImport> {
  late final TextEditingController _nom;
  late final TextEditingController _prix;
  Forfait? _forfait;
  bool _prixModifie = false;
  bool _retenir = false;

  @override
  void initState() {
    super.initState();
    _nom = TextEditingController(text: widget.nomParDefaut);
    _prix = TextEditingController();
    final duree = widget.dureeMinutes;
    if (duree != null) {
      for (final f in widget.forfaits) {
        if (f.dureeMinutes == duree) _forfait = f;
      }
    }
    _forfait ??= widget.forfaits.isNotEmpty ? widget.forfaits.first : null;
    // Prix proposé : celui du PDF, sinon celui du forfait.
    _prix.text = '${widget.prixDetecte ?? _forfait?.prix ?? ''}';
  }

  @override
  void dispose() {
    _nom.dispose();
    _prix.dispose();
    super.dispose();
  }

  int? get _prixSaisi => int.tryParse(_prix.text.trim());

  @override
  Widget build(BuildContext context) {
    final aImporter = widget.nombre - widget.doublons;
    final duree = widget.dureeMinutes;
    final dureeSansForfait = duree != null &&
        !widget.forfaits.any((f) => f.dureeMinutes == duree);

    return AlertDialog(
      title: const Text('Importer ces tickets ?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.nombre} tickets lus'
              '${widget.doublons > 0 ? ' dont ${widget.doublons} déjà enregistrés (ignorés)' : ''}.\n'
              '$aImporter seront ajoutés.',
            ),
            if (widget.ignorees > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${widget.ignorees} illisibles ignorés.'),
              ),
            const SizedBox(height: 14),
            TextField(
              controller: _nom,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Nom du lot',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            Text('Forfait de ces tickets',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            if (widget.forfaits.isEmpty)
              const Text('Aucun forfait actif. Créez-en un dans Réglages.')
            else
              DropdownButton<int>(
                isExpanded: true,
                value: _forfait?.id,
                items: [
                  for (final f in widget.forfaits)
                    DropdownMenuItem(
                      value: f.id,
                      child: Text('${f.nom}  ·  ${cdf(f.prix)}'),
                    ),
                ],
                onChanged: (id) => setState(() {
                  _forfait = widget.forfaits.firstWhere((f) => f.id == id);
                  // Sans prix lu dans le PDF ni modification, on suit le forfait.
                  if (!_prixModifie && widget.prixDetecte == null) {
                    _prix.text = '${_forfait!.prix}';
                  }
                }),
              ),
            const SizedBox(height: 10),
            TextField(
              controller: _prix,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() => _prixModifie = true),
              decoration: InputDecoration(
                labelText: 'Prix de chaque ticket (CDF)',
                helperText: widget.prixDetecte != null
                    ? 'Prix lu dans le PDF. Vous pouvez le modifier.'
                    : 'Prix non lu dans ce PDF : vérifiez-le ou saisissez-le. Proposé : le prix du forfait.',
                helperMaxLines: 3,
                // Sans prix lu, l'aide ressort pour qu'on ne l'importe pas sans y penser.
                helperStyle: widget.prixDetecte == null
                    ? TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600)
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
            if (_forfait != null &&
                _prixSaisi != null &&
                _prixSaisi != _forfait!.prix)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _retenir,
                onChanged: (v) => setState(() => _retenir = v ?? false),
                title: Text(
                    'Retenir ce prix pour « ${_forfait!.nom} » (actuellement ${cdf(_forfait!.prix)})'),
              ),
            const SizedBox(height: 6),
            Text(
              dureeSansForfait
                  ? 'Ce PDF indique ${libelleDuree(duree)} : aucun forfait de cette durée n\'existe encore. Ajoutez-le dans Réglages > Forfaits, ou choisissez-en un ci-dessus.'
                  : widget.source == 'mikhmon'
                      ? 'Vérifiez que le forfait correspond à la durée imprimée sur les tickets.'
                      : widget.source == 'excel'
                          ? 'Le tableur ne donne pas de prix : vérifiez-le ci-dessus. Les tickets déjà utilisés ne sont pas importés.'
                          : '',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        FilledButton(
          onPressed: _forfait == null ||
                  _nom.text.trim().isEmpty ||
                  aImporter <= 0 ||
                  _prixSaisi == null
              ? null
              : () => Navigator.pop(
                  context,
                  ConfirmationImport(_nom.text.trim(), _forfait!, _prixSaisi!,
                      retenirPrix: _retenir &&
                          _prixSaisi != _forfait!.prix)),
          child: const Text('Importer'),
        ),
      ],
    );
  }
}
