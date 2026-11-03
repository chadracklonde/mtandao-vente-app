import 'package:flutter/material.dart';

import '../models.dart';
import '../security.dart';
import 'pin_pad.dart';

/// Demande le code personnel d'un vendeur avant de vendre en son nom.
/// Retourne vrai si le bon code est saisi. Les essais sont limités et le
/// blocage est enregistré (comme pour le code de l'application).
Future<bool> demanderCodeVendeur(BuildContext context, Vendeur vendeur) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => DialogueCodeVendeur(vendeur: vendeur),
  );
  return ok == true;
}

class DialogueCodeVendeur extends StatefulWidget {
  const DialogueCodeVendeur({super.key, required this.vendeur});
  final Vendeur vendeur;

  @override
  State<DialogueCodeVendeur> createState() => _DialogueCodeVendeurState();
}

class _DialogueCodeVendeurState extends State<DialogueCodeVendeur> {
  String? _message;
  bool _erreur = false;

  Future<void> _verifier(String pin) async {
    final r = await PinService.verifierVendeur(widget.vendeur.id, pin);
    if (!mounted) return;
    switch (r.statut) {
      case StatutPin.correct:
        Navigator.pop(context, true);
      case StatutPin.bloque:
        setState(() {
          _erreur = true;
          _message =
              'Trop d\'essais. Réessayez dans ${PinService.dureeLisible(r.secondes)}.';
        });
      case StatutPin.incorrect:
        setState(() {
          _erreur = true;
          _message = r.essaisRestants <= 2
              ? 'Code incorrect. Encore ${r.essaisRestants} essai${r.essaisRestants > 1 ? 's' : ''} avant un blocage.'
              : 'Code incorrect.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: SingleChildScrollView(
        child: PinPad(
          titre: 'Code de ${widget.vendeur.nom}',
          message: _message ?? 'Saisissez votre code à 4 chiffres.',
          erreur: _erreur,
          onComplete: _verifier,
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler')),
      ],
    );
  }
}
