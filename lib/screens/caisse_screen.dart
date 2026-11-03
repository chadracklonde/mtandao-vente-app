import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../models.dart';
import '../state.dart';

/// Clôture de caisse : l'argent liquide que l'application attend pour une
/// journée, l'argent réellement compté, et l'écart.
class CaisseScreen extends StatefulWidget {
  const CaisseScreen({super.key});

  @override
  State<CaisseScreen> createState() => _CaisseScreenState();
}

class _CaisseScreenState extends State<CaisseScreen> {
  DateTime _jour = debutJour(DateTime.now());
  int? _vendeurId;
  List<Vendeur> _vendeurs = [];
  ({int especesCdf, int dettesCdf, int usd}) _attendu =
      (especesCdf: 0, dettesCdf: 0, usd: 0);
  List<Cloture> _historique = [];
  int _tauxDollar = 0;
  final _compteCdf = TextEditingController();
  final _compteUsd = TextEditingController();
  final _note = TextEditingController();
  bool _chargement = true;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _compteCdf.dispose();
    _compteUsd.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    final repo = appState.repo;
    final vendeurs = await repo.vendeurs();
    final attendu = await repo.attenduCaisse(_jour, vendeurId: _vendeurId);
    final histo = await repo.clotures();
    final taux = await repo.tauxDollar();
    if (!mounted) return;
    setState(() {
      _vendeurs = vendeurs;
      _attendu = attendu;
      _historique = histo;
      _tauxDollar = taux;
      _chargement = false;
    });
  }

  int get _attenduCdf => _attendu.especesCdf + _attendu.dettesCdf;

  int? get _compteCdfValeur => int.tryParse(_compteCdf.text.replaceAll(' ', ''));

  /// Dollars saisis (« 12,50 » ou « 12.5 ») en centimes.
  int? get _compteUsdValeur {
    final t = _compteUsd.text.trim().replaceAll(',', '.');
    if (t.isEmpty) return 0;
    final v = double.tryParse(t);
    return v == null ? null : (v * 100).round();
  }

  bool get _usdUtile => _tauxDollar > 0 || _attendu.usd > 0;

  Future<void> _choisirJour() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _jour,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (d == null) return;
    _jour = debutJour(d);
    await _charger();
  }

  Future<void> _enregistrer() async {
    final cdfCompte = _compteCdfValeur;
    final usdCompte = _compteUsdValeur;
    if (cdfCompte == null || cdfCompte < 0 || usdCompte == null || usdCompte < 0) {
      return;
    }
    await appState.repo.enregistrerCloture(
      jour: _jour,
      vendeurId: _vendeurId,
      attenduCdf: _attenduCdf,
      compteCdf: cdfCompte,
      attenduUsd: _attendu.usd,
      compteUsd: usdCompte,
      note: _note.text,
    );
    _compteCdf.clear();
    _compteUsd.clear();
    _note.clear();
    await _charger();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('Clôture enregistrée.')));
  }

  String _ecart(int v) =>
      v == 0 ? 'Aucun écart' : '${v > 0 ? 'En trop' : 'Manque'} : ${cdf(v.abs())}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final compte = _compteCdfValeur;
    final ecart = compte == null ? null : compte - _attenduCdf;
    return Scaffold(
      appBar: AppBar(title: const Text('Clôture de caisse')),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _choisirJour,
                        icon: const Icon(Icons.calendar_today_outlined),
                        label: Text(fmtJourLong(_jour)),
                      ),
                    ),
                  ],
                ),
                if (_vendeurs.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    key: ValueKey('vendeur-$_vendeurId'),
                    initialValue: _vendeurId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Vendeur', border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('Tous les vendeurs')),
                      for (final v in _vendeurs)
                        DropdownMenuItem<int?>(value: v.id, child: Text(v.nom)),
                    ],
                    onChanged: (v) {
                      _vendeurId = v;
                      _charger();
                    },
                  ),
                ],
                const SizedBox(height: 16),
                Card(
                  color: cs.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Attendu en caisse',
                            style: TextStyle(color: cs.onSecondaryContainer)),
                        Text(cdf(_attenduCdf),
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: cs.onSecondaryContainer)),
                        const SizedBox(height: 4),
                        Text(
                          'Ventes en espèces : ${cdf(_attendu.especesCdf)}'
                          '${_attendu.dettesCdf > 0 ? '\nDettes payées ce jour : ${cdf(_attendu.dettesCdf)}' : ''}'
                          '${_attendu.usd > 0 ? '\nDollars en espèces : ${Devise.formaterDollar(_attendu.usd)}' : ''}',
                          style: TextStyle(color: cs.onSecondaryContainer),
                        ),
                        const SizedBox(height: 4),
                        Text(
                            'Le mobile money et les tickets offerts n\'entrent pas en caisse.',
                            style: TextStyle(
                                fontSize: 12, color: cs.onSecondaryContainer)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _compteCdf,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                      labelText: 'Argent compté (CDF)',
                      border: OutlineInputBorder()),
                ),
                if (_usdUtile) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _compteUsd,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                        labelText: 'Dollars comptés (USD)',
                        border: OutlineInputBorder()),
                  ),
                ],
                if (ecart != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(_ecart(ecart),
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: ecart == 0 ? Colors.green.shade700 : cs.error)),
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _note,
                  decoration: const InputDecoration(
                      labelText: 'Remarque (facultatif)',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: compte == null ? null : _enregistrer,
                  icon: const Icon(Icons.lock_clock_outlined),
                  label: const Text('Enregistrer la clôture'),
                ),
                if (_historique.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text('Clôtures précédentes',
                      style: Theme.of(context).textTheme.titleMedium),
                  for (final c in _historique)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                          '${c.jour}${c.vendeurNom == null ? '' : '  ·  ${c.vendeurNom}'}'),
                      subtitle: Text(
                          'Attendu ${cdf(c.attenduCdf)}  ·  compté ${cdf(c.compteCdf)}'
                          '${c.attenduUsd + c.compteUsd > 0 ? '\nDollars : attendu ${Devise.formaterDollar(c.attenduUsd)}, compté ${Devise.formaterDollar(c.compteUsd)}' : ''}'
                          '${c.note == null ? '' : '\n${c.note}'}'),
                      isThreeLine: c.note != null || c.attenduUsd + c.compteUsd > 0,
                      trailing: Text(
                        c.ecartCdf == 0 && c.ecartUsd == 0
                            ? 'OK'
                            : (c.ecartCdf == 0
                                ? Devise.formaterDollar(c.ecartUsd)
                                : '${c.ecartCdf > 0 ? '+' : '-'}${fmtInt(c.ecartCdf.abs())}'),
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: c.ecartCdf == 0 && c.ecartUsd == 0
                                ? Colors.green.shade700
                                : cs.error),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}
