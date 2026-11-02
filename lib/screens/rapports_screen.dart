import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../format.dart';
import '../models.dart';
import '../rapport.dart';
import '../rapport_export.dart';
import '../state.dart';
import '../widgets/graphique_barres.dart';
import 'dettes_screen.dart';

enum _Mode { jour, semaine, mois, periode }

enum _Action { texte, csv, pdf }

/// Vert lisible sur fond clair comme sur fond sombre.
Color _vert(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? Colors.green.shade300
        : Colors.green.shade800;

/// Rapports de ventes : par jour, semaine, mois ou période libre.
class RapportsScreen extends StatefulWidget {
  const RapportsScreen({super.key});

  @override
  State<RapportsScreen> createState() => _RapportsScreenState();
}

class _RapportsScreenState extends State<RapportsScreen> {
  _Mode _mode = _Mode.jour;
  DateTime _ancre = debutJour(DateTime.now());
  DateTimeRange? _periode;
  List<VenteLigne> _ventes = [];
  Rapport _rapport = Rapport(const []);

  /// Argent encaissé sur la période précédente (null : pas de comparaison).
  int? _encaissePrecedent;
  bool _chargement = true;

  @override
  void initState() {
    super.initState();
    final auj = debutJour(DateTime.now());
    _periode = DateTimeRange(
      start: DateTime(auj.year, auj.month, auj.day - 6),
      end: auj,
    );
    appState.addListener(_charger);
    _charger();
  }

  @override
  void dispose() {
    appState.removeListener(_charger);
    super.dispose();
  }

  /// Début inclus et fin exclue de la période affichée.
  (DateTime, DateTime) _bornes() {
    switch (_mode) {
      case _Mode.jour:
        final d = _ancre;
        return (d, DateTime(d.year, d.month, d.day + 1));
      case _Mode.semaine:
        final lundi =
            DateTime(_ancre.year, _ancre.month, _ancre.day - (_ancre.weekday - 1));
        return (lundi, DateTime(lundi.year, lundi.month, lundi.day + 7));
      case _Mode.mois:
        final d = DateTime(_ancre.year, _ancre.month, 1);
        return (d, DateTime(d.year, d.month + 1, 1));
      case _Mode.periode:
        final p = _periode!;
        final s = debutJour(p.start);
        final e = debutJour(p.end);
        return (s, DateTime(e.year, e.month, e.day + 1));
    }
  }

  String _titre() {
    final (debut, fin) = _bornes();
    final dernier = fin.subtract(const Duration(days: 1));
    switch (_mode) {
      case _Mode.jour:
        return fmtJourLong(debut);
      case _Mode.semaine:
        return 'Semaine du ${fmtJourMois(debut)} au ${fmtJourMois(dernier)} ${dernier.year}';
      case _Mode.mois:
        return fmtMoisAnnee(debut);
      case _Mode.periode:
        return 'Du ${fmtJourCourt(debut)} au ${fmtJourCourt(dernier)}';
    }
  }

  /// Période de même nature juste avant celle affichée.
  (DateTime, DateTime) _bornesPrecedentes() {
    final (debut, fin) = _bornes();
    switch (_mode) {
      case _Mode.jour:
        return (DateTime(debut.year, debut.month, debut.day - 1), debut);
      case _Mode.semaine:
        return (DateTime(debut.year, debut.month, debut.day - 7), debut);
      case _Mode.mois:
        return (DateTime(debut.year, debut.month - 1, 1), debut);
      case _Mode.periode:
        final jours = (fin.difference(debut).inHours / 24).round();
        return (DateTime(debut.year, debut.month, debut.day - jours), debut);
    }
  }

  Future<void> _charger() async {
    final (debut, fin) = _bornes();
    final (pDebut, pFin) = _bornesPrecedentes();
    final repo = appState.repo;
    final ventes = await repo.ventes(debut, fin);
    final precedentes = await repo.ventes(pDebut, pFin);
    if (!mounted) return;
    final precedent = Rapport(precedentes);
    setState(() {
      _ventes = ventes;
      _rapport = Rapport(ventes);
      _encaissePrecedent = precedentes.isEmpty ? null : precedent.encaisse;
      _chargement = false;
    });
  }

  void _decaler(int sens) {
    setState(() {
      switch (_mode) {
        case _Mode.jour:
          _ancre = DateTime(_ancre.year, _ancre.month, _ancre.day + sens);
        case _Mode.semaine:
          _ancre = DateTime(_ancre.year, _ancre.month, _ancre.day + 7 * sens);
        case _Mode.mois:
          _ancre = DateTime(_ancre.year, _ancre.month + sens, 1);
        case _Mode.periode:
          break;
      }
    });
    _charger();
  }

  /// Vrai si la période affichée contient aujourd'hui.
  bool get _estCourant {
    if (_mode == _Mode.periode) return true;
    final (debut, fin) = _bornes();
    final maintenant = DateTime.now();
    return !maintenant.isBefore(debut) && maintenant.isBefore(fin);
  }

  bool get _peutAvancer {
    if (_mode == _Mode.periode) return false;
    final (_, fin) = _bornes();
    return !fin.isAfter(DateTime.now());
  }

  Future<void> _choisirPeriode() async {
    final maintenant = DateTime.now();
    final choix = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(maintenant.year, maintenant.month, maintenant.day),
      initialDateRange: _periode,
      helpText: 'Choisir une période',
      saveText: 'Valider',
      cancelText: 'Annuler',
      locale: const Locale('fr'),
    );
    if (choix == null) return;
    setState(() {
      _periode = choix;
      _mode = _Mode.periode;
    });
    _charger();
  }

  Future<void> _partager() async {
    await Share.share(
        _rapport.texte(_titre(), detailParJour: _mode != _Mode.jour));
  }

  /// Écrit le rapport dans un fichier temporaire (CSV ou PDF) et le partage.
  Future<void> _exporter({required bool pdf}) async {
    try {
      final dossier = await getTemporaryDirectory();
      final (debut, fin) = _bornes();
      final dernier = fin.subtract(const Duration(days: 1));
      String ymd(DateTime d) =>
          '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
      final jours = debut == debutJour(dernier)
          ? ymd(debut)
          : '${ymd(debut)}_${ymd(dernier)}';
      final fichier = File(p.join(
          dossier.path, 'mtandao_rapport_$jours.${pdf ? 'pdf' : 'csv'}'));
      if (pdf) {
        await fichier.writeAsBytes(
          await RapportExport.pdf(
            titre: _titre(),
            rapport: _rapport,
            detailParJour: _mode != _Mode.jour,
          ),
          flush: true,
        );
      } else {
        await fichier.writeAsString(RapportExport.csv(_ventes),
            encoding: utf8, flush: true);
      }
      await Share.shareXFiles(
        [XFile(fichier.path, mimeType: pdf ? 'application/pdf' : 'text/csv')],
        subject: 'Rapport Mtandao : ${_titre()}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('Export impossible : $e')));
    }
  }

  void _surAction(_Action a) {
    switch (a) {
      case _Action.texte:
        _partager();
      case _Action.csv:
        _exporter(pdf: false);
      case _Action.pdf:
        _exporter(pdf: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _rapport;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rapports'),
        actions: [
          PopupMenuButton<_Action>(
            tooltip: 'Partager ou exporter le rapport',
            enabled: !_chargement,
            icon: const Icon(Icons.share_rounded),
            onSelected: _surAction,
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: _Action.texte, child: Text('Partager en texte')),
              PopupMenuItem(
                  value: _Action.csv,
                  child: Text('Exporter en CSV (tableur)')),
              PopupMenuItem(value: _Action.pdf, child: Text('Exporter en PDF')),
            ],
          ),
        ],
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                SegmentedButton<_Mode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: _Mode.jour, label: Text('Jour')),
                    ButtonSegment(value: _Mode.semaine, label: Text('Semaine')),
                    ButtonSegment(value: _Mode.mois, label: Text('Mois')),
                    ButtonSegment(value: _Mode.periode, label: Text('Période')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) {
                    final m = s.first;
                    if (m == _Mode.periode) {
                      _choisirPeriode();
                      return;
                    }
                    setState(() {
                      _mode = m;
                      if (m == _Mode.mois) {
                        _ancre = DateTime(_ancre.year, _ancre.month, 1);
                      }
                    });
                    _charger();
                  },
                ),
                const SizedBox(height: 8),
                _navigation(context),
                const SizedBox(height: 8),
                _resume(context, r),
                if (r.aRecevoir > 0) _aRecevoir(context, r),
                if (_ventes.isNotEmpty) ..._graphiques(context, r),
                if (r.parForfait.length > 1)
                  ..._groupe(context, 'Par forfait', r.parForfait),
                if (r.parPaiement.keys.any((k) => k != Paiement.especes))
                  ..._groupe(context, 'Par mode de paiement', {
                    for (final e in r.parPaiement.entries)
                      Paiement.libelle(e.key): e.value,
                  }),
                if (r.aDesVendeurs)
                  ..._groupe(context, 'Par vendeur', r.parVendeur),
                const SizedBox(height: 16),
                if (_ventes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(Icons.bar_chart_rounded,
                            size: 56,
                            color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 8),
                        const Text('Aucune vente sur cette période.'),
                      ],
                    ),
                  )
                else if (_mode == _Mode.jour)
                  ..._detailJour(context)
                else
                  ..._detailParJour(context, r),
              ],
            ),
    );
  }

  Widget _navigation(BuildContext context) {
    if (_mode == _Mode.periode) {
      return OutlinedButton.icon(
        onPressed: _choisirPeriode,
        icon: const Icon(Icons.date_range_rounded),
        label: Text(_titre()),
      );
    }
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Précédent',
              onPressed: () => _decaler(-1),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text(
                _titre(),
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: 'Suivant',
              onPressed: _peutAvancer ? () => _decaler(1) : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        if (!_estCourant)
          TextButton.icon(
            onPressed: () {
              setState(() => _ancre = debutJour(DateTime.now()));
              _charger();
            },
            icon: const Icon(Icons.today_rounded),
            label: const Text("Revenir à aujourd'hui"),
          ),
      ],
    );
  }

  Widget _resume(BuildContext context, Rapport r) {
    final cs = Theme.of(context).colorScheme;
    final evolution = _encaissePrecedent == null
        ? null
        : Rapport.evolution(r.encaisse, _encaissePrecedent!);
    final texteEvolution = evolution == null
        ? null
        : evolution == 0
            ? 'Stable par rapport à la période précédente'
            : '${evolution > 0 ? '▲ +' : '▼ '}$evolution % par rapport à la période précédente';
    return Semantics(
      container: true,
      label: 'Montant encaissé ${cdf(r.encaisse)}, ${Rapport.tickets(r.nombre)} '
          'vendu${r.nombre > 1 ? 's' : ''}'
          '${texteEvolution == null ? '' : ', $texteEvolution'}',
      excludeSemantics: true,
      child: Card(
        color: cs.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Text('Montant encaissé',
                  style: TextStyle(color: cs.onPrimaryContainer)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  cdf(r.encaisse),
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.onPrimaryContainer),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${Rapport.tickets(r.nombre)} vendu${r.nombre > 1 ? 's' : ''}'
                '${r.offerts > 0 ? '  ·  ${r.offerts} offert${r.offerts > 1 ? 's' : ''}' : ''}',
                style: TextStyle(
                    color: cs.onPrimaryContainer, fontWeight: FontWeight.w600),
              ),
              if (_mode != _Mode.jour && r.parJour.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Moyenne : ${cdf((r.encaisse / r.parJour.length).round())} par jour avec ventes',
                    style: TextStyle(color: cs.onPrimaryContainer),
                  ),
                ),
              if (texteEvolution != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    texteEvolution,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _aRecevoir(BuildContext context, Rapport r) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.errorContainer,
      child: ListTile(
        leading: Icon(Icons.hourglass_bottom_rounded,
            color: cs.onErrorContainer),
        title: Text('À recevoir : ${cdf(r.aRecevoir)}',
            style: TextStyle(
                color: cs.onErrorContainer, fontWeight: FontWeight.w700)),
        subtitle: Text('Ventes à crédit pas encore payées',
            style: TextStyle(color: cs.onErrorContainer)),
        trailing: Icon(Icons.chevron_right_rounded, color: cs.onErrorContainer),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const DettesScreen())),
      ),
    );
  }

  /// Argent encaissé chaque jour de la période, jours sans vente compris.
  List<BarreDonnee> _donneesParJour(Rapport r) {
    final (debut, fin) = _bornes();
    final barres = <BarreDonnee>[];
    for (var d = debut;
        d.isBefore(fin);
        d = DateTime(d.year, d.month, d.day + 1)) {
      barres.add(BarreDonnee('${d.day}', r.parJourBrut[d]?.montant ?? 0));
    }
    return barres;
  }

  List<Widget> _graphiques(BuildContext context, Rapport r) {
    final titre = Theme.of(context).textTheme.titleMedium;
    final hPointe = r.heureDePointe;
    final parJour = _mode == _Mode.jour ? null : _donneesParJour(r);
    return [
      if (parJour != null) ...[
        const SizedBox(height: 16),
        Text('Évolution (argent encaissé par jour)', style: titre),
        const SizedBox(height: 8),
        GraphiqueBarres(
          donnees: parJour,
          formater: cdf,
          resume: 'Argent encaissé par jour : '
              '${parJour.where((b) => b.valeur > 0).length} jours avec ventes, '
              'maximum ${cdf(parJour.fold<int>(0, (a, b) => b.valeur > a ? b.valeur : a))}.',
        ),
      ],
      const SizedBox(height: 16),
      Text('Heures de pointe', style: titre),
      const SizedBox(height: 8),
      GraphiqueBarres(
        donnees: [
          for (var h = 0; h < 24; h++) BarreDonnee('${h}h', r.parHeure[h]),
        ],
        formater: (v) => Rapport.tickets(v),
        resume: hPointe == null
            ? 'Aucune vente.'
            : 'Heure la plus chargée : $hPointe heures, ${Rapport.tickets(r.parHeure[hPointe])} vendus.',
      ),
      if (hPointe != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Heure la plus chargée : ${hPointe}h (${Rapport.tickets(r.parHeure[hPointe])})',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
    ];
  }

  List<Widget> _groupe(
      BuildContext context, String titre, Map<String, Total> groupe) {
    return [
      const SizedBox(height: 16),
      Text(titre, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      for (final e in groupe.entries)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(e.key),
          subtitle: Text(Rapport.tickets(e.value.nombre)),
          trailing: Text(cdf(e.value.montant),
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
    ];
  }

  List<Widget> _detailJour(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return [
      Text('Ventes de la journée',
          style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      for (final v in _ventes)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            v.paiement == Paiement.offert
                ? Icons.card_giftcard_rounded
                : v.aRecevoir
                    ? Icons.hourglass_bottom_rounded
                    : Icons.check_circle_rounded,
            color: v.aRecevoir ? cs.error : _vert(context),
            semanticLabel: v.paiement == Paiement.offert
                ? 'Offert'
                : v.aRecevoir
                    ? 'À recevoir'
                    : 'Encaissé',
          ),
          title: Text(v.code,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, letterSpacing: 1)),
          subtitle: Text([
            fmtHeure(v.venduLe),
            v.forfaitNom,
            if (v.paiement != Paiement.especes) Paiement.libelle(v.paiement),
            if (v.clientNom != null) v.clientNom!,
            if (v.vendeurNom != null) v.vendeurNom!,
          ].join('  ·  ')),
          trailing: Text(cdf(v.prix)),
        ),
    ];
  }

  List<Widget> _detailParJour(BuildContext context, Rapport r) {
    var maxi = 1;
    for (final t in r.parJour.values) {
      if (t.montant > maxi) maxi = t.montant;
    }
    return [
      Text('Par jour', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      for (final e in r.parJour.entries)
        Semantics(
          container: true,
          label: '${fmtJourCompact(e.key)}, ${Rapport.tickets(e.value.nombre)}, '
              '${cdf(e.value.montant)}',
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(fmtJourCompact(e.key)),
                    ),
                    Text('${Rapport.tickets(e.value.nombre)}  ·  ',
                        style: Theme.of(context).textTheme.bodySmall),
                    Text(cdf(e.value.montant),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                      minHeight: 10, value: e.value.montant / maxi),
                ),
              ],
            ),
          ),
        ),
    ];
  }
}
