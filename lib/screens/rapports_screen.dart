import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../format.dart';
import '../models.dart';
import '../state.dart';

enum _Mode { jour, semaine, mois, periode }

class _Total {
  int nombre = 0;
  int montant = 0;
}

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

  Future<void> _charger() async {
    final (debut, fin) = _bornes();
    final ventes = await appState.repo.ventes(debut, fin);
    if (!mounted) return;
    setState(() {
      _ventes = ventes;
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
    final r = _agreger();
    final lignes = <String>[
      'Rapport Mtandao',
      _titre(),
      '',
      'Tickets vendus : ${r.total.nombre}',
      'Montant encaissé : ${cdf(r.total.montant)}',
    ];
    if (r.parForfait.length > 1) {
      lignes.add('');
      lignes.add('Par forfait :');
      r.parForfait.forEach((nom, t) {
        lignes.add('- $nom : ${t.nombre} tickets, ${cdf(t.montant)}');
      });
    }
    if (_mode != _Mode.jour && r.parJour.isNotEmpty) {
      lignes.add('');
      lignes.add('Par jour :');
      for (final e in r.parJour.entries) {
        lignes.add(
            '- ${fmtJourCourt(e.key)} : ${e.value.nombre} tickets, ${cdf(e.value.montant)}');
      }
    }
    await Share.share(lignes.join('\n'));
  }

  _Agregat _agreger() {
    final total = _Total();
    final parForfait = <String, _Total>{};
    final parJourBrut = <DateTime, _Total>{};
    for (final v in _ventes) {
      total
        ..nombre += 1
        ..montant += v.prix;
      final f = parForfait.putIfAbsent(v.forfaitNom, _Total.new);
      f
        ..nombre += 1
        ..montant += v.prix;
      final jour = debutJour(v.venduLe);
      final j = parJourBrut.putIfAbsent(jour, _Total.new);
      j
        ..nombre += 1
        ..montant += v.prix;
    }
    final cles = parJourBrut.keys.toList()..sort((a, b) => b.compareTo(a));
    final parJour = <DateTime, _Total>{for (final k in cles) k: parJourBrut[k]!};
    return _Agregat(total, parForfait, parJour);
  }

  @override
  Widget build(BuildContext context) {
    final r = _agreger();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rapports'),
        actions: [
          IconButton(
            tooltip: 'Partager le rapport',
            onPressed: _chargement ? null : _partager,
            icon: const Icon(Icons.share_rounded),
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
                if (r.parForfait.length > 1) ...[
                  const SizedBox(height: 16),
                  Text('Par forfait',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  for (final e in r.parForfait.entries)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(e.key),
                      subtitle: Text('${e.value.nombre} tickets'),
                      trailing: Text(cdf(e.value.montant),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                ],
                const SizedBox(height: 16),
                if (_ventes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('Aucune vente sur cette période.')),
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
    return Row(
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
    );
  }

  Widget _resume(BuildContext context, _Agregat r) {
    final cs = Theme.of(context).colorScheme;
    return Card(
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
                cdf(r.total.montant),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800, color: cs.onPrimaryContainer),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${r.total.nombre} ticket${r.total.nombre > 1 ? 's' : ''} vendu${r.total.nombre > 1 ? 's' : ''}',
              style: TextStyle(
                  color: cs.onPrimaryContainer, fontWeight: FontWeight.w600),
            ),
            if (_mode != _Mode.jour && r.parJour.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Moyenne : ${cdf((r.total.montant / r.parJour.length).round())} par jour avec ventes',
                  style: TextStyle(color: cs.onPrimaryContainer),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _detailJour(BuildContext context) {
    return [
      Text('Ventes de la journée',
          style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      for (final v in _ventes)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.check_circle_rounded, color: Colors.green),
          title: Text(v.code,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, letterSpacing: 1)),
          subtitle: Text('${fmtHeure(v.venduLe)}  ·  ${v.forfaitNom}'),
          trailing: Text(cdf(v.prix)),
        ),
    ];
  }

  List<Widget> _detailParJour(BuildContext context, _Agregat r) {
    var maxi = 1;
    for (final t in r.parJour.values) {
      if (t.montant > maxi) maxi = t.montant;
    }
    return [
      Text('Par jour', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      for (final e in r.parJour.entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(fmtJourCompact(e.key)),
                  ),
                  Text('${e.value.nombre} tickets  ·  ',
                      style: Theme.of(context).textTheme.bodySmall),
                  Text(cdf(e.value.montant),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                    minHeight: 6, value: e.value.montant / maxi),
              ),
            ],
          ),
        ),
    ];
  }
}

class _Agregat {
  _Agregat(this.total, this.parForfait, this.parJour);
  final _Total total;
  final Map<String, _Total> parForfait;
  final Map<DateTime, _Total> parJour;
}
