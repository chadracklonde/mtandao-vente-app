import 'package:flutter/material.dart';

/// Une barre du graphique.
class BarreDonnee {
  const BarreDonnee(this.etiquette, this.valeur);
  final String etiquette;
  final int valeur;
}

/// Graphique en barres simple, dessiné sans bibliothèque externe.
/// [resume] est lu par le lecteur d'écran à la place du dessin.
class GraphiqueBarres extends StatelessWidget {
  const GraphiqueBarres({
    super.key,
    required this.donnees,
    required this.resume,
    this.hauteur = 150,
    this.formater,
  });

  final List<BarreDonnee> donnees;
  final String resume;
  final double hauteur;

  /// Texte affiché au-dessus de la plus grande barre (par défaut : la valeur).
  final String Function(int valeur)? formater;

  /// Indices des barres dont on écrit l'étiquette : une sur [pas], de façon
  /// que les étiquettes ne se chevauchent pas. Toujours la première, et la
  /// dernière si elle n'est pas trop près de la précédente.
  static List<int> indicesEtiquettes(
      int nombre, double largeur, double largeurEtiquette) {
    if (nombre <= 0 || largeur <= 0) return const [];
    final parBarre = largeur / nombre;
    final pas = (largeurEtiquette / parBarre).ceil().clamp(1, nombre);
    return [for (var i = 0; i < nombre; i += pas) i];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: resume,
      image: true,
      child: ExcludeSemantics(
        child: SizedBox(
          height: hauteur,
          width: double.infinity,
          child: CustomPaint(
            painter: _Peintre(
              donnees: donnees,
              barre: cs.primary,
              pic: cs.tertiary,
              axe: cs.outlineVariant,
              texte: cs.onSurfaceVariant,
              formater: formater ?? (v) => '$v',
            ),
          ),
        ),
      ),
    );
  }
}

class _Peintre extends CustomPainter {
  _Peintre({
    required this.donnees,
    required this.barre,
    required this.pic,
    required this.axe,
    required this.texte,
    required this.formater,
  });

  final List<BarreDonnee> donnees;
  final Color barre;
  final Color pic;
  final Color axe;
  final Color texte;
  final String Function(int) formater;

  TextPainter _tp(String s, {double taille = 11, Color? couleur}) =>
      TextPainter(
        text: TextSpan(
            text: s,
            style: TextStyle(fontSize: taille, color: couleur ?? texte)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    if (donnees.isEmpty) return;
    const basEtiquettes = 18.0;
    const hautValeur = 16.0;
    final zone = size.height - basEtiquettes - hautValeur;
    final base = hautValeur + zone;
    final n = donnees.length;
    final pas = size.width / n;
    final largeur = (pas * 0.7).clamp(1.0, 28.0);

    var max = 0;
    var indexMax = -1;
    for (var i = 0; i < n; i++) {
      if (donnees[i].valeur > max) {
        max = donnees[i].valeur;
        indexMax = i;
      }
    }

    canvas.drawLine(Offset(0, base), Offset(size.width, base),
        Paint()..color = axe..strokeWidth = 1);

    for (var i = 0; i < n; i++) {
      final v = donnees[i].valeur;
      final h = max == 0 ? 0.0 : zone * v / max;
      final x = i * pas + (pas - largeur) / 2;
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(x, base - h, largeur, h < 1 && v > 0 ? 1 : h),
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
      );
      canvas.drawRRect(rect, Paint()..color = i == indexMax ? pic : barre);
    }

    // Valeur de la plus grande barre.
    if (indexMax >= 0) {
      final t = _tp(formater(max), couleur: pic);
      final h = zone;
      var x = indexMax * pas + pas / 2 - t.width / 2;
      x = x.clamp(0.0, size.width - t.width);
      t.paint(canvas, Offset(x, base - h - t.height - 1 < 0 ? 0 : base - h - t.height - 1));
    }

    for (final i in GraphiqueBarres.indicesEtiquettes(n, size.width, 30)) {
      final t = _tp(donnees[i].etiquette, taille: 10);
      var x = i * pas + pas / 2 - t.width / 2;
      x = x.clamp(0.0, size.width - t.width);
      t.paint(canvas, Offset(x, base + 3));
    }
  }

  @override
  bool shouldRepaint(_Peintre old) =>
      old.donnees != donnees ||
      old.barre != barre ||
      old.pic != pic ||
      old.axe != axe ||
      old.texte != texte;
}
