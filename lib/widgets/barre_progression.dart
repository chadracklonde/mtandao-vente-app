import 'package:flutter/material.dart';

/// Barre de progression arrondie, lue en une phrase par le lecteur d'écran.
///
/// On n'utilise pas `semanticsValue` de LinearProgressIndicator : Flutter y
/// attend un nombre (et non une phrase) et signale une erreur sinon quand
/// TalkBack est actif.
class BarreProgression extends StatelessWidget {
  const BarreProgression({
    super.key,
    required this.valeur,
    required this.phrase,
    this.hauteur = 8,
  });

  /// Entre 0 et 1.
  final double valeur;

  /// Phrase lue par le lecteur d'écran, par exemple « 3 tickets vendus sur 10 ».
  final String phrase;
  final double hauteur;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: phrase,
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            minHeight: hauteur,
            value: valeur.isNaN ? 0 : valeur.clamp(0.0, 1.0),
          ),
        ),
      ),
    );
  }
}
