import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import 'dialogues.dart';

/// Ce que le vendeur a choisi dans la fenêtre de confirmation d'une vente.
class ChoixVente {
  const ChoixVente(this.paiement, this.clientId,
      {this.devise = Devise.cdf, this.taux});
  final String paiement;
  final int? clientId;

  /// Devise reçue ; pour le dollar, [taux] = francs pour 1 dollar.
  final String devise;
  final int? taux;
}

/// Fenêtre « Confirmer la vente ? » : ticket, montant, mode de paiement et,
/// pour une vente à crédit, le client. Retourne null si la vente est annulée.
Future<ChoixVente?> demanderVente(
  BuildContext context, {
  required Ticket ticket,
  required List<Client> clients,
  required Future<int> Function(String nom, String? telephone) creerClient,
  String? vendeurNom,
  int tauxDollar = 0,
}) {
  return showDialog<ChoixVente>(
    context: context,
    builder: (_) => DialogueVente(
      ticket: ticket,
      clients: clients,
      creerClient: creerClient,
      vendeurNom: vendeurNom,
      tauxDollar: tauxDollar,
    ),
  );
}

class DialogueVente extends StatefulWidget {
  const DialogueVente({
    super.key,
    required this.ticket,
    required this.clients,
    required this.creerClient,
    this.vendeurNom,
    this.tauxDollar = 0,
  });

  final Ticket ticket;
  final List<Client> clients;
  final Future<int> Function(String nom, String? telephone) creerClient;
  final String? vendeurNom;

  /// Francs pour 1 dollar ; 0 : le paiement en dollars n'est pas proposé.
  final int tauxDollar;

  @override
  State<DialogueVente> createState() => _DialogueVenteState();
}

class _DialogueVenteState extends State<DialogueVente> {
  String _paiement = Paiement.especes;
  String _devise = Devise.cdf;
  int? _clientId;
  late List<Client> _clients;

  @override
  void initState() {
    super.initState();
    _clients = List.of(widget.clients);
  }

  bool get _valide => _paiement != Paiement.credit || _clientId != null;

  /// Le dollar est proposé seulement si un taux est réglé, et pour un paiement
  /// qui rentre tout de suite (espèces ou mobile money).
  bool get _dollarPossible =>
      widget.tauxDollar > 0 &&
      (_paiement == Paiement.especes || _paiement == Paiement.mobile);

  Future<void> _nouveauClient() async {
    final saisi = await demanderClient(context);
    if (saisi == null) return;
    final (nom, tel) = saisi;
    final id = await widget.creerClient(nom, tel);
    if (!mounted) return;
    setState(() {
      _clients.add(Client(id: id, nom: nom, telephone: tel));
      _clients.sort((a, b) => a.nom.toLowerCase().compareTo(b.nom.toLowerCase()));
      _clientId = id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.ticket;
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Confirmer la vente ?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ticket ${t.code}\nMontant : ${cdf(t.prix)}'),
            if (widget.vendeurNom != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Vendeur : ${widget.vendeurNom}',
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            const SizedBox(height: 14),
            Text('Paiement', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final p in Paiement.tous)
                  ChoiceChip(
                    label: Text(Paiement.libelle(p)),
                    selected: _paiement == p,
                    onSelected: (_) => setState(() {
                      _paiement = p;
                      if (!_dollarPossible) _devise = Devise.cdf;
                    }),
                  ),
              ],
            ),
            if (_dollarPossible) ...[
              const SizedBox(height: 12),
              Text('Monnaie reçue',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Francs (CDF)'),
                    selected: _devise == Devise.cdf,
                    onSelected: (_) => setState(() => _devise = Devise.cdf),
                  ),
                  ChoiceChip(
                    label: const Text('Dollars (USD)'),
                    selected: _devise == Devise.usd,
                    onSelected: (_) => setState(() => _devise = Devise.usd),
                  ),
                ],
              ),
              if (_devise == Devise.usd)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'À recevoir : ${Devise.formaterDollar(Devise.centimesDollar(t.prix, widget.tauxDollar))}'
                    '  (1 dollar = ${cdf(widget.tauxDollar)})',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
            ],
            if (_paiement == Paiement.offert)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Ticket offert : aucun montant ne sera encaissé.'),
              ),
            if (_paiement == Paiement.credit) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                // Recréé quand le client change (nouveau client choisi
                // d'office) : « initialValue » n'est lu qu'à la création.
                key: ValueKey('client-${_clients.length}-$_clientId'),
                initialValue: _clientId,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Client', border: OutlineInputBorder()),
                items: [
                  for (final c in _clients)
                    DropdownMenuItem(
                      value: c.id,
                      child: Text(c.nom, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _clientId = v),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _nouveauClient,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Nouveau client'),
                ),
              ),
              Text('Le montant sera à recevoir tant que le client n\'a pas payé.',
                  style: TextStyle(color: cs.onSurfaceVariant)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Non'),
        ),
        FilledButton(
          autofocus: true,
          onPressed: _valide
              ? () => Navigator.pop(
                  context,
                  ChoixVente(
                    _paiement,
                    _clientId,
                    devise: _devise,
                    taux: _devise == Devise.usd ? widget.tauxDollar : null,
                  ))
              : null,
          child: const Text('Oui, vendu'),
        ),
      ],
    );
  }
}
