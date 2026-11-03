import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// Lecture d'une planche de tickets à QR code, quelle que soit sa mise en
/// page : portrait ou paysage, un ticket par page ou des dizaines, grille
/// régulière quelconque. (Fonctions pures, sans pdfrx : testables avec une
/// image de page fabriquée.)
///
/// Principe : on repère les QR codes de la page (zones carrées au motif
/// dense), on les décode un par un, puis on découpe chaque ticket autour de
/// son QR en cherchant les couloirs blancs entre les tickets.

/// Un rectangle en pixels.
class RectPx {
  const RectPx(this.x, this.y, this.l, this.h);
  final int x;
  final int y;
  final int l;
  final int h;

  int get droite => x + l;
  int get bas => y + h;
  double get cx => x + l / 2;
  double get cy => y + h / 2;

  bool contient(double px, double py) =>
      px >= x && px < droite && py >= y && py < bas;

  @override
  String toString() => 'RectPx($x, $y, $l×$h)';
}

/// Un ticket trouvé sur la page.
class CelluleTicket {
  const CelluleTicket({
    required this.cellule,
    required this.qr,
    required this.texte,
    this.png,
  });

  /// Zone du ticket entier (QR, textes, cadre).
  final RectPx cellule;

  /// Zone du QR code.
  final RectPx qr;

  /// Contenu du QR ; null si le QR a été repéré mais n'a pas pu être lu.
  final String? texte;

  /// Image du ticket (PNG), si demandée.
  final Uint8List? png;
}

/// Analyse une page rendue en BGRA ([bgra], [w] × [h] pixels).
///
/// [accepter] décide si un texte de QR est un ticket (les autres QR de la page,
/// par exemple un lien en pied de page, sont ignorés). Les tickets sont rendus
/// dans l'ordre de lecture : ligne par ligne, de gauche à droite.
List<CelluleTicket> analyserPlanche(
  Uint8List bgra,
  int w,
  int h, {
  bool Function(String texte)? accepter,
  bool avecPng = true,
}) {
  if (w <= 0 || h <= 0 || bgra.length < w * h * 4) return const [];
  final gris = _gris(bgra, w, h);
  final candidats = _candidatsQr(gris, w, h);

  final lus = <_Lu>[];
  final rates = <RectPx>[];
  for (final c in candidats) {
    final t = _decoder(gris, w, h, c);
    if (t == null) {
      rates.add(c);
    } else if (accepter == null || accepter(t)) {
      lus.add(_Lu(c, t));
    }
  }
  if (lus.isEmpty) return const [];

  final taille = _mediane([for (final l in lus) math.max(l.qr.l, l.qr.h).toDouble()]);
  final grille = _Grille.calculer(gris, w, h, lus, taille);

  final cellules = <_Brut>[];
  for (final l in lus) {
    cellules.add(_Brut(grille.cellule(l), l.qr, l.texte));
  }

  // QR repérés mais illisibles : de la taille des autres, et pas déjà dans un ticket.
  final cw = _mediane([for (final c in cellules) c.cellule.l.toDouble()]);
  final ch = _mediane([for (final c in cellules) c.cellule.h.toDouble()]);
  final fx = _mediane([
    for (final c in cellules) (c.qr.cx - c.cellule.x) / math.max(1, c.cellule.l),
  ]);
  final fy = _mediane([
    for (final c in cellules) (c.qr.cy - c.cellule.y) / math.max(1, c.cellule.h),
  ]);
  for (final r in rates) {
    final cote = math.max(r.l, r.h);
    if ((cote - taille).abs() > 0.3 * taille) continue;
    if (cellules.any((c) => c.cellule.contient(r.cx, r.cy))) continue;
    if (cellules.any((c) => _seChevauchent(c.qr, r))) continue;
    final x = (r.cx - fx * cw).round().clamp(0, math.max(0, w - 1)).toInt();
    final y = (r.cy - fy * ch).round().clamp(0, math.max(0, h - 1)).toInt();
    final cell = RectPx(x, y, math.min(cw.round(), w - x), math.min(ch.round(), h - y));
    cellules.add(_Brut(cell, r, null));
  }

  _ordonner(cellules, ch);

  img.Image? page;
  if (avecPng) {
    page = img.Image.fromBytes(
      width: w,
      height: h,
      bytes: bgra.buffer,
      bytesOffset: bgra.offsetInBytes,
      numChannels: 4,
      order: img.ChannelOrder.bgra,
    );
  }
  return [
    for (final c in cellules)
      CelluleTicket(
        cellule: c.cellule,
        qr: c.qr,
        texte: c.texte,
        png: page == null ? null : _png(page, c.cellule),
      ),
  ];
}

Uint8List _png(img.Image page, RectPx r) {
  final rec = img.copyCrop(page, x: r.x, y: r.y, width: r.l, height: r.h);
  return img.encodePng(rec.convert(numChannels: 3), level: 6);
}

// --------------------------------------------------------------------------
// Repérage des QR codes
// --------------------------------------------------------------------------

Uint8List _gris(Uint8List bgra, int w, int h) {
  final g = Uint8List(w * h);
  for (var i = 0, j = 0; i < g.length; i++, j += 4) {
    g[i] = (bgra[j] * 29 + bgra[j + 1] * 150 + bgra[j + 2] * 77) >> 8;
  }
  return g;
}

const int _seuilSombre = 140;

/// Réservé aux tests : zones repérées comme QR possibles sur une page rendue.
@visibleForTesting
List<RectPx> candidatsQrPourTest(Uint8List bgra, int w, int h) =>
    _candidatsQr(_gris(bgra, w, h), w, h);

class _Finder {
  _Finder(this.x, this.y, this.m);
  double x;
  double y;
  double m; // taille d'un module, en pixels
  int n = 1;
}

/// Longueurs des 5 plages (noir, blanc, noir, blanc, noir) autour de (x, y)
/// le long d'une ligne ou d'une colonne ; null si le point central n'est pas noir.
({List<int> l, double centre})? _plages(
    Uint8List g, int w, int h, int x, int y, bool vertical) {
  final n = vertical ? h : w;
  final p0 = vertical ? y : x;
  bool noir(int i) {
    final v = vertical ? g[i * w + x] : g[y * w + i];
    return v < _seuilSombre;
  }

  if (!noir(p0)) return null;
  final run = [0, 0, 0, 0, 0];
  var i = p0;
  while (i >= 0 && noir(i)) {
    run[2]++;
    i--;
  }
  final debut2 = i + 1;
  while (i >= 0 && !noir(i)) {
    run[1]++;
    i--;
  }
  while (i >= 0 && noir(i)) {
    run[0]++;
    i--;
  }
  i = p0 + 1;
  while (i < n && noir(i)) {
    run[2]++;
    i++;
  }
  final fin2 = i;
  while (i < n && !noir(i)) {
    run[3]++;
    i++;
  }
  while (i < n && noir(i)) {
    run[4]++;
    i++;
  }
  if (run.any((r) => r == 0)) return null;
  return (l: run, centre: (debut2 + fin2 - 1) / 2);
}

bool _rapport11311(List<int> r) {
  final total = r.reduce((a, b) => a + b);
  if (total < 7) return false;
  final m = total / 7;
  final tol = 0.5 * m;
  return (r[0] - m).abs() <= tol &&
      (r[1] - m).abs() <= tol &&
      (r[2] - 3 * m).abs() <= 1.1 * m &&
      (r[3] - m).abs() <= tol &&
      (r[4] - m).abs() <= tol;
}

/// QR codes possibles : on cherche les trois grands carrés de coin (motif
/// 1:1:3:1:1 en largeur et en hauteur) puis on les regroupe par trois. Le texte,
/// le logo ou le cadre d'un ticket ne les imitent pas.
List<RectPx> _candidatsQr(Uint8List g, int w, int h) {
  final trouves = <_Finder>[];
  final pas = math.max(1, h ~/ 1500);
  for (var y = 0; y < h; y += pas) {
    final off = y * w;
    // Plages successives de la ligne.
    final debuts = <int>[];
    final noirs = <bool>[];
    var cur = g[off] < _seuilSombre;
    debuts.add(0);
    noirs.add(cur);
    for (var x = 1; x < w; x++) {
      final d = g[off + x] < _seuilSombre;
      if (d != cur) {
        debuts.add(x);
        noirs.add(d);
        cur = d;
      }
    }
    debuts.add(w);
    for (var k = 0; k + 4 < noirs.length; k++) {
      if (!noirs[k]) continue;
      final r = [for (var j = 0; j < 5; j++) debuts[k + j + 1] - debuts[k + j]];
      if (!_rapport11311(r)) continue;
      final total = r.reduce((a, b) => a + b);
      final cx = debuts[k] + total / 2;
      final xi = cx.floor().clamp(0, w - 1);
      final v = _plages(g, w, h, xi, y, true);
      if (v == null || !_rapport11311(v.l)) continue;
      final tv = v.l.reduce((a, b) => a + b);
      if ((tv - total).abs() > 0.5 * total) continue;
      final yi = v.centre.floor().clamp(0, h - 1);
      final hz = _plages(g, w, h, xi, yi, false);
      if (hz == null || !_rapport11311(hz.l)) continue;
      final m = (total + tv) / 14;
      final fx = hz.centre, fy = v.centre;
      _Finder? deja;
      for (final f in trouves) {
        if ((f.x - fx).abs() < 2 * m && (f.y - fy).abs() < 2 * m) {
          deja = f;
          break;
        }
      }
      if (deja != null) {
        deja.x = (deja.x * deja.n + fx) / (deja.n + 1);
        deja.y = (deja.y * deja.n + fy) / (deja.n + 1);
        deja.m = (deja.m * deja.n + m) / (deja.n + 1);
        deja.n++;
      } else {
        trouves.add(_Finder(fx, fy, m));
      }
    }
  }

  // Regroupement : coin haut-gauche A, haut-droite B (même ligne), bas-gauche C.
  // On liste tous les triangles possibles et on garde d'abord les plus petits :
  // les vrais QR sont toujours plus petits que les faux regroupements.
  final triplets = <(double, _Finder, _Finder, _Finder)>[];
  for (final a in trouves) {
    for (final b in trouves) {
      if (b == a ||
          (b.y - a.y).abs() >= 1.5 * a.m ||
          b.x - a.x <= 9 * a.m ||
          (b.m - a.m).abs() >= 0.35 * a.m) {
        continue;
      }
      final d = b.x - a.x;
      // Taille cohérente avec un QR : (modules − 7) = 14, 18, 22… 170 modules.
      final mods = d / ((a.m + b.m) / 2);
      final k = ((mods - 14) / 4).round();
      if (k < 0 || k > 39 || (mods - (14 + 4 * k)).abs() > 1.5) continue;
      for (final c in trouves) {
        if (c == a || c == b) continue;
        if ((c.x - a.x).abs() < 1.5 * a.m &&
            (c.y - a.y - d).abs() < 0.12 * d + a.m &&
            (c.m - a.m).abs() < 0.35 * a.m) {
          triplets.add((d, a, b, c));
        }
      }
    }
  }
  triplets.sort((p, q) => p.$1.compareTo(q.$1));
  final pris = <_Finder>{};
  final sortie = <RectPx>[];
  for (final (_, a, b, c) in triplets) {
    if (pris.contains(a) || pris.contains(b) || pris.contains(c)) continue;
    pris..add(a)..add(b)..add(c);
    final m = (a.m + b.m + c.m) / 3;
    final x0 = math.max(0, (a.x - 3.5 * m).round());
    final y0 = math.max(0, (a.y - 3.5 * m).round());
    final x1 = math.min(w, (b.x + 3.5 * m).round());
    final y1 = math.min(h, (c.y + 3.5 * m).round());
    sortie.add(RectPx(x0, y0, x1 - x0, y1 - y0));
  }
  // Un QR n'en contient pas un autre : on écarte les faux grands regroupements.
  return [
    for (final r in sortie)
      if (!sortie.any((o) => o != r && r.contient(o.cx, o.cy))) r,
  ];
}

// --------------------------------------------------------------------------
// Décodage
// --------------------------------------------------------------------------

String? _decoder(Uint8List g, int w, int h, RectPx qr) {
  final cote = math.max(qr.l, qr.h);
  for (final marge in [0.15, 0.35, 0.05]) {
    final m = math.max(3, (cote * marge).round());
    final x0 = math.max(0, qr.x - m), y0 = math.max(0, qr.y - m);
    final x1 = math.min(w, qr.droite + m), y1 = math.min(h, qr.bas + m);
    final cw = x1 - x0, ch = y1 - y0;
    if (cw < 8 || ch < 8) continue;
    final px = Int32List(cw * ch);
    for (var y = 0; y < ch; y++) {
      final src = (y0 + y) * w + x0;
      for (var x = 0; x < cw; x++) {
        final v = g[src + x];
        px[y * cw + x] = 0xFF000000 | (v << 16) | (v << 8) | v;
      }
    }
    final hints = DecodeHints()..put(DecodeHintType.tryHarder);
    for (final hybride in [true, false]) {
      try {
        final source = RGBLuminanceSource(cw, ch, px);
        final bitmap = BinaryBitmap(
            hybride ? HybridBinarizer(source) : GlobalHistogramBinarizer(source));
        final t = QRCodeReader().decode(bitmap, hints: hints).text;
        if (t.isNotEmpty) return t;
      } catch (_) {
        // Pas lisible avec ce réglage : on essaie le suivant.
      }
    }
  }
  return null;
}

// --------------------------------------------------------------------------
// Grille et découpe des tickets
// --------------------------------------------------------------------------

class _Lu {
  _Lu(this.qr, this.texte);
  final RectPx qr;
  final String texte;
}

class _Brut {
  _Brut(this.cellule, this.qr, this.texte);
  final RectPx cellule;
  final RectPx qr;
  final String? texte;
}

bool _seChevauchent(RectPx a, RectPx b) =>
    a.x < b.droite && b.x < a.droite && a.y < b.bas && b.y < a.bas;

double _mediane(List<double> v) {
  if (v.isEmpty) return 0;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

/// Regroupe des valeurs triées en paquets : une nouvelle valeur s'ajoute au
/// paquet courant si elle reste à moins de [tolerance] de sa première valeur.
List<List<double>> _paquets(List<double> valeurs, double tolerance) {
  final s = [...valeurs]..sort();
  final res = <List<double>>[];
  for (final v in s) {
    if (res.isNotEmpty && (v - res.last.first).abs() <= tolerance) {
      res.last.add(v);
    } else {
      res.add([v]);
    }
  }
  return res;
}

class _Grille {
  _Grille(this.lignes, this.colonnes, this.limY, this.limX);

  /// Centres des lignes et des colonnes de QR.
  final List<double> lignes;
  final List<double> colonnes;

  /// Limites des tickets : limY[i]..limY[i+1] pour la ligne i.
  final List<int> limY;
  final List<int> limX;

  RectPx cellule(_Lu l) {
    final r = _plusProche(lignes, l.qr.cy);
    final c = _plusProche(colonnes, l.qr.cx);
    return RectPx(limX[c], limY[r], limX[c + 1] - limX[c],
        limY[r + 1] - limY[r]);
  }

  static int _plusProche(List<double> centres, double v) {
    var best = 0;
    var d = double.infinity;
    for (var i = 0; i < centres.length; i++) {
      final e = (centres[i] - v).abs();
      if (e < d) {
        d = e;
        best = i;
      }
    }
    return best;
  }

  static _Grille calculer(
      Uint8List g, int w, int h, List<_Lu> lus, double taille) {
    final lignes = [
      for (final p in _paquets([for (final l in lus) l.qr.cy], 0.5 * taille))
        p.reduce((a, b) => a + b) / p.length,
    ];
    final colonnes = [
      for (final p in _paquets([for (final l in lus) l.qr.cx], 0.5 * taille))
        p.reduce((a, b) => a + b) / p.length,
    ];

    // Bandes de ticket : lignes d'abord (couloirs entre lignes), colonnes ensuite.
    final cy = _limites(g, w, h, lignes, taille, vertical: true, bande: null);
    final bande = (cy.first, cy.last);
    final cx = _limites(g, w, h, colonnes, taille, vertical: false, bande: bande);
    return _Grille(lignes, colonnes, cy, cx);
  }

  /// Limites des tickets le long d'un axe : couloirs blancs entre deux
  /// rangées de QR, et bords extérieurs d'après le pas ou le contenu.
  static List<int> _limites(Uint8List g, int w, int h, List<double> centres,
      double taille,
      {required bool vertical, required (int, int)? bande}) {
    final longueur = vertical ? h : w;
    // Encre par position, sur toute la largeur (ou dans la bande de lignes).
    int encre(int pos) {
      var n = 0;
      if (vertical) {
        final off = pos * w;
        for (var x = 0; x < w; x++) {
          if (g[off + x] < 160) n++;
        }
      } else {
        final y0 = bande?.$1 ?? 0, y1 = bande?.$2 ?? h;
        for (var y = y0; y < y1; y++) {
          if (g[y * w + pos] < 160) n++;
        }
      }
      return n;
    }

    final interieurs = <int>[];
    final pas = <double>[];
    for (var i = 0; i + 1 < centres.length; i++) {
      pas.add(centres[i + 1] - centres[i]);
      final a = (centres[i] + taille / 2).round();
      final b = (centres[i + 1] - taille / 2).round();
      final milieu = ((centres[i] + centres[i + 1]) / 2).round();
      if (b - a < 3) {
        interieurs.add(milieu);
        continue;
      }
      var meilleur = milieu;
      var mini = 1 << 30;
      for (var p = a; p <= b; p++) {
        // Moyenne sur 3 positions voisines : un trait isolé ne trompe pas.
        final e = encre(p) +
            (p > 0 ? encre(p - 1) : 0) +
            (p + 1 < longueur ? encre(p + 1) : 0);
        if (e < mini || (e == mini && (p - milieu).abs() < (meilleur - milieu).abs())) {
          mini = e;
          meilleur = p;
        }
      }
      interieurs.add(meilleur);
    }

    int borne(double v) => v.round().clamp(0, longueur);
    if (centres.length >= 2) {
      final p = _mediane(pas);
      final debut = borne(interieurs.first - p);
      final fin = borne(interieurs.last + p);
      return [debut, ...interieurs, fin];
    }

    // Un seul ticket dans ce sens : on prend le contenu de la page.
    var premier = -1, dernier = -1;
    final yDeb = vertical ? 0 : (bande?.$1 ?? 0);
    final yFin = vertical ? h : (bande?.$2 ?? h);
    for (var p = 0; p < longueur; p++) {
      bool a = false;
      if (vertical) {
        final off = p * w;
        for (var x = 0; x < w && !a; x++) {
          if (g[off + x] < 160) a = true;
        }
      } else {
        for (var y = yDeb; y < yFin && !a; y++) {
          if (g[y * w + p] < 160) a = true;
        }
      }
      if (a) {
        if (premier < 0) premier = p;
        dernier = p;
      }
    }
    final marge = (0.01 * longueur).round();
    if (premier < 0) return [0, longueur];
    return [math.max(0, premier - marge), math.min(longueur, dernier + 1 + marge)];
  }
}

/// Ordre de lecture : de haut en bas, puis de gauche à droite.
void _ordonner(List<_Brut> l, double hauteurCellule) {
  l.sort((a, b) {
    final dy = a.cellule.y - b.cellule.y;
    if (dy.abs() > 0.5 * hauteurCellule) return dy;
    return a.cellule.x.compareTo(b.cellule.x);
  });
}
