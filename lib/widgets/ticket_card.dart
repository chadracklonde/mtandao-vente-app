import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../models.dart';

const Color bleuMtandao = Color(0xFF0A8FD0);

/// Affiche un ticket : l'image d'origine du PDF (avec son QR) ou, à défaut,
/// une carte dessinée à partir du code.
class TicketCard extends StatelessWidget {
  const TicketCard({
    super.key,
    required this.ticket,
    required this.image,
    required this.forfaitNom,
  });

  final Ticket ticket;
  final Uint8List? image;
  final String forfaitNom;

  @override
  Widget build(BuildContext context) {
    final texte = Theme.of(context).textTheme;
    return Column(
      children: [
        if (image != null)
          Card(
            clipBehavior: Clip.antiAlias,
            elevation: 2,
            child: Container(
              color: Colors.white,
              child: Image.memory(image!,
                  fit: BoxFit.fitWidth, gaplessPlayback: true),
            ),
          )
        else
          _TicketTexte(ticket: ticket, forfaitNom: forfaitNom),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: SelectableText(
                ticket.code,
                style: texte.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            IconButton(
              tooltip: 'Copier le code',
              icon: const Icon(Icons.copy_rounded),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: ticket.code));
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(const SnackBar(
                      content: Text('Code copié'),
                      duration: Duration(seconds: 1)));
              },
            ),
          ],
        ),
        if (ticket.aMotDePasseDistinct)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('Mot de passe : ${ticket.motDePasse}',
                style: texte.titleMedium),
          ),
        const SizedBox(height: 4),
        Text(
          [
            if (ticket.numero != null) 'Ticket n° ${ticket.numero}',
            forfaitNom,
            cdf(ticket.prix),
          ].join('  ·  '),
          style: texte.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _TicketTexte extends StatelessWidget {
  const _TicketTexte({required this.ticket, required this.forfaitNom});
  final Ticket ticket;
  final String forfaitNom;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black87, width: 2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text('MTANDAO',
                  style: TextStyle(
                      color: bleuMtandao,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1)),
              const Spacer(),
              Text(forfaitNom,
                  style: const TextStyle(
                      color: Colors.black87, fontWeight: FontWeight.bold)),
            ],
          ),
          const Divider(color: Colors.black87, thickness: 1.2),
          const SizedBox(height: 6),
          const Text('Code', style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black87),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              ticket.code,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.black,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3),
            ),
          ),
          const SizedBox(height: 10),
          Text(cdf(ticket.prix),
              style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
