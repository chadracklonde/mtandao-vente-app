import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao/planche_qr.dart';
import 'package:zxing2/qrcode.dart';

/// Page fabriquée : fond blanc, et des tickets (cadre, « logo » rayé, gros
/// code en barres, QR Mikhmon) disposés en grille.
class PageFab {
  PageFab(this.w, this.h) : bgra = Uint8List(w * h * 4)..fillRange(0, w * h * 4, 255);
  final int w;
  final int h;
  final Uint8List bgra;
  final codes = <String>[];
  final cellules = <RectPx>[];
  final qrs = <RectPx>[];

  void pixel(int x, int y, bool noir) {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    final i = (y * w + x) * 4;
    final v = noir ? 0 : 255;
    bgra[i] = v;
    bgra[i + 1] = v;
    bgra[i + 2] = v;
    bgra[i + 3] = 255;
  }

  void rect(int x, int y, int l, int hh, {bool noir = true}) {
    for (var j = y; j < y + hh; j++) {
      for (var i = x; i < x + l; i++) {
        pixel(i, j, noir);
      }
    }
  }

  void cadre(int x, int y, int l, int hh, int e) {
    rect(x, y, l, e);
    rect(x, y + hh - e, l, e);
    rect(x, y, e, hh);
    rect(x + l - e, y, e, hh);
  }

  /// Dessine un QR contenant [texte] ; retourne son rectangle (sans marge blanche).
  RectPx qr(String texte, int x, int y, int module, {double abime = 0}) {
    final m = Encoder.encode(texte, ErrorCorrectionLevel.m).matrix!;
    for (var j = 0; j < m.height; j++) {
      for (var i = 0; i < m.width; i++) {
        if (m.get(i, j) == 1) rect(x + i * module, y + j * module, module, module);
      }
    }
    final r = RectPx(x, y, m.width * module, m.height * module);
    if (abime > 0) {
      final rnd = math.Random(7);
      for (var j = 0; j < m.height; j++) {
        for (var i = 0; i < m.width; i++) {
          final coin = (i < 9 && j < 9) ||
              (i >= m.width - 8 && j < 9) ||
              (i < 9 && j >= m.height - 8);
          if (!coin && rnd.nextDouble() < abime) {
            final noir = rnd.nextBool();
            rect(x + i * module, y + j * module, module, module, noir: noir);
          }
        }
      }
    }
    return r;
  }

  /// Un ticket complet dans la case (x, y, l, hh).
  void ticket(int x, int y, int l, int hh, String code, int module,
      {bool qrAGauche = false, double abime = 0}) {
    cadre(x, y, l, hh, 2);
    // « logo » rayé en haut
    for (var k = 0; k < 6; k++) {
      rect(x + 12, y + 12 + k * 7, (l * 0.28).round(), 3);
    }
    // gros code en barres épaisses
    for (var k = 0; k < 5; k++) {
      rect(x + 12 + k * 22, y + hh - 50, 12, 34);
    }
    final texte = 'http://mtandao.wifi/login?username=$code&password=$code';
    final taille = Encoder.encode(texte, ErrorCorrectionLevel.m).matrix!.width * module;
    final qx = qrAGauche ? x + 10 : x + l - taille - 10;
    final qy = y + ((hh - taille) / 2).round();
    qrs.add(qr(texte, qx, qy, module, abime: abime));
    codes.add(code);
    cellules.add(RectPx(x, y, l, hh));
  }

  /// Grille de [nombre] tickets (ou tous), remplie ligne par ligne.
  static PageFab grille({
    required int w,
    required int h,
    required int colonnes,
    required int lignes,
    int? nombre,
    int module = 4,
    int marge = 30,
    int gouttiere = 24,
    String prefixe = '1',
    bool qrAGauche = false,
    int? abimer,
  }) {
    final p = PageFab(w, h);
    final cl = ((w - 2 * marge - (colonnes - 1) * gouttiere) / colonnes).floor();
    final ch = ((h - 2 * marge - (lignes - 1) * gouttiere) / lignes).floor();
    final total = nombre ?? colonnes * lignes;
    for (var k = 0; k < total; k++) {
      final c = k % colonnes, r = k ~/ colonnes;
      p.ticket(marge + c * (cl + gouttiere), marge + r * (ch + gouttiere), cl, ch,
          '$prefixe${(10000 + k).toString().substring(1)}', module,
          qrAGauche: qrAGauche, abime: abimer == k ? 0.4 : 0);
    }
    return p;
  }
}

bool _contient(RectPx a, RectPx b) =>
    a.x <= b.x && a.y <= b.y && a.droite >= b.droite && a.bas >= b.bas;

String? _code(CelluleTicket c) {
  final m = RegExp(r'username=(\w+)').firstMatch(c.texte ?? '');
  return m?.group(1);
}

bool _accepter(String t) => t.contains('username=');

void main() {
  void verifier(PageFab p, List<CelluleTicket> r) {
    expect(r.length, p.codes.length, reason: 'nombre de tickets');
    // Ordre de lecture et contenu.
    expect(r.map(_code).toList(), p.codes);
    for (var i = 0; i < r.length; i++) {
      // Le ticket trouvé contient tout le ticket réel…
      expect(_contient(r[i].cellule, p.cellules[i]), isTrue,
          reason: 'cellule ${r[i].cellule} ne contient pas ${p.cellules[i]}');
      // …et son QR, sans empiéter sur les voisins.
      expect(_contient(r[i].cellule, p.qrs[i]), isTrue);
      for (var j = 0; j < r.length; j++) {
        if (j != i) {
          expect(r[i].cellule.contient(p.qrs[j].cx, p.qrs[j].cy), isFalse,
              reason: 'ticket $i empiète sur le QR de $j');
        }
      }
    }
  }

  group('Planche en portrait', () {
    test('A4 portrait, 3 colonnes × 6 lignes', () {
      final p = PageFab.grille(w: 1240, h: 1754, colonnes: 3, lignes: 6);
      verifier(p, analyserPlanche(p.bgra, p.w, p.h, accepter: _accepter, avecPng: false));
    });

    test('portrait, 2 colonnes × 5 lignes', () {
      final p = PageFab.grille(w: 1240, h: 1754, colonnes: 2, lignes: 5, qrAGauche: true);
      verifier(p, analyserPlanche(p.bgra, p.w, p.h, accepter: _accepter, avecPng: false));
    });

    test('portrait, une seule colonne de 4 tickets', () {
      final p = PageFab.grille(w: 1240, h: 1754, colonnes: 1, lignes: 4, marge: 60);
      verifier(p, analyserPlanche(p.bgra, p.w, p.h, accepter: _accepter, avecPng: false));
    });

    test('portrait, un seul ticket sur la page', () {
      final p = PageFab(1240, 1754);
      p.ticket(300, 500, 640, 360, '10001', 4);
      final r = analyserPlanche(p.bgra, p.w, p.h, accepter: _accepter, avecPng: false);
      expect(r.length, 1);
      expect(_code(r.single), '10001');
      expect(_contient(r.single.cellule, p.cellules.single), isTrue);
      // Le ticket est découpé sur son contenu, pas sur toute la page.
      expect(r.single.cellule.l, lessThan(900));
    });

    test('portrait, 2 tickets l\'un sous l\'autre', () {
      final p = PageFab(1240, 1754);
      p.ticket(200, 200, 700, 380, '10001', 4);
      p.ticket(200, 700, 700, 380, '10002', 4);
      verifier(p, analyserPlanche(p.bgra, p.w, p.h, accepter: _accepter, avecPng: false));
    });
  });

  group('Autres mises en page', () {
    test('paysage 4 × 4 (le modèle d\'origine) par la lecture générale', () {
      final p = PageFab.grille(w: 1650, h: 1275, colonnes: 4, lignes: 4, module: 3, marge: 20, gouttiere: 14);
      verifier(p, analyserPlanche(p.bgra, p.w, p.h, accepter: _accepter, avecPng: false));
    });

    test('paysage 2 colonnes × 1 ligne', () {
      final p = PageFab.grille(w: 1754, h: 1240, colonnes: 2, lignes: 1, marge: 60);
      verifier(p, analyserPlanche(p.bgra, p.w, p.h, accepter: _accepter, avecPng: false));
    });

    test('grille 5 × 8 : 40 tickets sur une page', () {
      final p = PageFab.grille(w: 1754, h: 2480, colonnes: 5, lignes: 8, module: 3, marge: 20, gouttiere: 12);
      verifier(p, analyserPlanche(p.bgra, p.w, p.h, accepter: _accepter, avecPng: false));
    });

    test('dernière page incomplète : seuls les tickets présents sont trouvés', () {
      final p = PageFab.grille(w: 1240, h: 1754, colonnes: 3, lignes: 6, nombre: 7);
      final r = analyserPlanche(p.bgra, p.w, p.h, accepter: _accepter, avecPng: false);
      expect(r.length, 7);
      expect(r.map(_code).toList(), p.codes);
    });

    test('un QR plus petit (modules de 3 pixels)', () {
      final p = PageFab.grille(w: 1240, h: 1754, colonnes: 3, lignes: 6, module: 3);
      verifier(p, analyserPlanche(p.bgra, p.w, p.h, accepter: _accepter, avecPng: false));
    });

    test('QR à gauche du ticket', () {
      final p = PageFab.grille(w: 1240, h: 1754, colonnes: 3, lignes: 5, qrAGauche: true);
      verifier(p, analyserPlanche(p.bgra, p.w, p.h, accepter: _accepter, avecPng: false));
    });
  });

  group('Cas particuliers', () {
    test('page blanche ou sans QR : aucun ticket', () {
      final blanche = PageFab(1240, 1754);
      expect(analyserPlanche(blanche.bgra, 1240, 1754), isEmpty);
      final texte = PageFab(1240, 1754);
      for (var k = 0; k < 20; k++) {
        texte.rect(100, 100 + k * 30, 900, 8);
      }
      expect(analyserPlanche(texte.bgra, 1240, 1754), isEmpty);
    });

    test('un QR qui n\'est pas un ticket est ignoré', () {
      final p = PageFab.grille(w: 1240, h: 1754, colonnes: 3, lignes: 6, nombre: 17);
      // La 18e case contient le QR d'un site web.
      final cl = ((1240 - 60 - 2 * 24) / 3).floor();
      final ch = ((1754 - 60 - 5 * 24) / 6).floor();
      p.qr('http://site.example/accueil', 30 + 2 * (cl + 24) + 40, 30 + 5 * (ch + 24) + 40, 4);
      final r = analyserPlanche(p.bgra, p.w, p.h, accepter: _accepter, avecPng: false);
      expect(r.length, 17);
      expect(r.every((c) => c.texte != null && c.texte!.contains('username=')), isTrue);
    });

    test('sans filtre, ce QR compte comme un ticket', () {
      final p = PageFab.grille(w: 1240, h: 1754, colonnes: 3, lignes: 6, nombre: 17);
      p.qr('http://site.example/accueil', 30 + 2 * (377 + 24) + 40, 30 + 5 * (253 + 24) + 40, 4);
      final r = analyserPlanche(p.bgra, p.w, p.h, avecPng: false);
      expect(r.length, 18);
    });

    test('un QR abîmé est signalé à sa place, sans texte', () {
      final p = PageFab.grille(w: 1240, h: 1754, colonnes: 3, lignes: 4, abimer: 4);
      final r = analyserPlanche(p.bgra, p.w, p.h, accepter: _accepter, avecPng: false);
      expect(r.length, 12);
      expect(r[4].texte, isNull);
      expect(_contient(r[4].cellule, p.qrs[4]), isTrue);
      // Les autres sont lus, dans l'ordre.
      for (var i = 0; i < 12; i++) {
        if (i != 4) expect(_code(r[i]), p.codes[i]);
      }
    });

    test('le PNG de chaque ticket est produit', () {
      final p = PageFab.grille(w: 1240, h: 1754, colonnes: 3, lignes: 2);
      final r = analyserPlanche(p.bgra, p.w, p.h, accepter: _accepter);
      expect(r.length, 6);
      for (final c in r) {
        expect(c.png, isNotNull);
        // Signature PNG.
        expect(c.png!.sublist(0, 4), [0x89, 0x50, 0x4e, 0x47]);
        expect(c.png!.length, greaterThan(500));
      }
    });

    test('données trop courtes ou page vide : pas d\'erreur', () {
      expect(analyserPlanche(Uint8List(0), 100, 100), isEmpty);
      expect(analyserPlanche(Uint8List(16), 0, 0), isEmpty);
    });

    test('une page A4 entière se traite en un temps raisonnable', () {
      final p = PageFab.grille(w: 1240, h: 1754, colonnes: 3, lignes: 6);
      final t = Stopwatch()..start();
      analyserPlanche(p.bgra, p.w, p.h, accepter: _accepter, avecPng: false);
      t.stop();
      expect(t.elapsed.inSeconds, lessThan(20));
    });
  });
}
