import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../format.dart';
import '../models.dart';
import '../state.dart';

/// Tickets vendus à crédit et pas encore payés, regroupés par client.
class DettesScreen extends StatefulWidget {
  const DettesScreen({super.key});

  @override
  State<DettesScreen> createState() => _DettesScreenState();
}

class _DettesScreenState extends State<DettesScreen> {
  List<DetteLigne> _lignes = [];
  bool _chargement = true;

  @override
  void initState() {
    super.initState();
    appState.addListener(_charger);
    _charger();
  }

  @override
  void dispose() {
    appState.removeListener(_charger);
    super.dispose();
  }

  Future<void> _charger() async {
    final l = await appState.repo.dettes();
    if (!mounted) return;
    setState(() {
      _lignes = l;
      _chargement = false;
    });
  }

  Future<bool> _confirmer(String titre, String message, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titre),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Non')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _payerTicket(DetteLigne d) async {
    if (!await _confirmer('Ticket payé ?',
        '${d.clientNom} a payé le ticket ${d.code} (${cdf(d.prix)}). Le montant sera compté comme encaissé.',
        'Oui, payé')) {
      return;
    }
    await appState.repo.marquerPaye(d.ticketId);
    appState.changed();
  }

  Future<void> _payerClient(String nom, int clientId, int total) async {
    if (!await _confirmer('Tout est payé ?',
        '$nom a payé ses dettes : ${cdf(total)}. Le montant sera compté comme encaissé.',
        'Oui, tout payé')) {
      return;
    }
    await appState.repo.marquerClientPaye(clientId);
    appState.changed();
  }

  Future<void> _relancer(String nom, int total, int nombre) async {
    await Share.share('Bonjour $nom, il vous reste ${cdf(total)} à payer '
        'pour ${nombre == 1 ? '1 ticket' : '$nombre tickets'} Wi-Fi Mtandao. Merci !');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final parClient = <int, List<DetteLigne>>{};
    for (final l in _lignes) {
      parClient.putIfAbsent(l.clientId, () => []).add(l);
    }
    final total = _lignes.fold<int>(0, (a, l) => a + l.prix);

    return Scaffold(
      appBar: AppBar(title: const Text('Clients et dettes')),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _lignes.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Aucune dette en cours.\nUne vente « À crédit » apparaît ici jusqu\'à ce que le client paie.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    Card(
                      color: cs.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Semantics(
                          container: true,
                          label:
                              'À recevoir ${cdf(total)}, ${parClient.length} clients',
                          excludeSemantics: true,
                          child: Column(
                            children: [
                              Text('À recevoir',
                                  style:
                                      TextStyle(color: cs.onErrorContainer)),
                              FittedBox(
                                child: Text(cdf(total),
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium
                                        ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            color: cs.onErrorContainer)),
                              ),
                              Text(
                                '${_lignes.length} ticket${_lignes.length > 1 ? 's' : ''}  ·  ${parClient.length} client${parClient.length > 1 ? 's' : ''}',
                                style: TextStyle(color: cs.onErrorContainer),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    for (final e in parClient.entries) ..._client(context, e.value),
                  ],
                ),
    );
  }

  List<Widget> _client(BuildContext context, List<DetteLigne> lignes) {
    final premier = lignes.first;
    final somme = lignes.fold<int>(0, (a, l) => a + l.prix);
    return [
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: Text(
              '${premier.clientNom}  ·  ${cdf(somme)}',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'Envoyer un rappel',
            onPressed: () => _relancer(premier.clientNom, somme, lignes.length),
            icon: const Icon(Icons.send_rounded),
          ),
          TextButton(
            onPressed: () => _payerClient(premier.clientNom, premier.clientId, somme),
            child: const Text('Tout payé'),
          ),
        ],
      ),
      if (premier.clientTelephone != null)
        Text(premier.clientTelephone!,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      for (final d in lignes)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(d.code,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, letterSpacing: 1)),
          subtitle: Text('${fmtDateHeure(d.venduLe)}  ·  ${cdf(d.prix)}'),
          trailing: TextButton(
            onPressed: () => _payerTicket(d),
            child: const Text('Payé'),
          ),
        ),
      const Divider(),
    ];
  }
}
