import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';
import 'package:zxing2/qrcode.dart';

import 'models.dart';
import 'planche_qr.dart';
import 'text_parser.dart';
import 'xlsx_import.dart';

class ImportException implements Exception {
  ImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Résultat de la lecture d'un PDF.
class ParsedPdf {
  ParsedPdf({
    required this.source,
    required this.slots,
    required this.echecs,
    this.dureeMinutes,
    this.loginUrl,
    this.prix,
    this.ignores = 0,
  });

  /// 'mikhmon' (tickets en image avec QR), 'texte' (Code / Durée) ou 'excel'.
  final String source;

  /// Tickets dans l'ordre du PDF. Une case illisible vaut null (voir [echecs]).
  final List<ParsedTicket?> slots;

  /// Cases illisibles : indice dans [slots] -> image PNG de la case.
  final Map<int, Uint8List> echecs;

  final int? dureeMinutes;
  final String? loginUrl;

  /// Prix lu dans le PDF quand il y est imprimé en texte (modèle « Code /
  /// Durée »). Les planches Mikhmon sont des images : leur prix n'est pas lu.
  final int? prix;

  /// Tickets du fichier laissés de côté (tableur : déjà utilisés).
  final int ignores;
}

typedef Progression = void Function(double fraction, String message);

// --------------------------------------------------------------------------
// Géométrie du modèle Mikhmon (page A4/Letter paysage, 792 x 612 pt, 4 x 4).
// Valeurs mesurées sur le PDF « 24h 200 tickets ».
// --------------------------------------------------------------------------
const double _pageLargeurRef = 792.0;
const double _caseX0 = 21.7;
const double _casePasX = 171.15;
const double _caseY0 = 27.7;
const double _casePasY = 138.9;
const double _caseL = 163.7;
const double _caseH = 132.2;
const int _colonnes = 4;
const int _lignes = 4;

// Zone du QR code dans une case (avec marge blanche), relative à la case.
const double _qrX0 = 80.0;
const double _qrX1 = 162.0;
const double _qrY0 = 23.0;
const double _qrY1 = 104.0;

// Zone du logo (pour détecter l'ordre des canaux de couleur), relative à la case.
const double _logoX0 = 3.0;
const double _logoX1 = 70.0;
const double _logoY0 = 3.0;
const double _logoY1 = 25.0;

const double _dpiNormal = 300;
const double _dpiRetentative = 400;

class PdfImporter {
  /// Lit un PDF de tickets (détection automatique du modèle).
  static Future<ParsedPdf> lire(String chemin, Progression progression) async {
    if (chemin.toLowerCase().endsWith('.xlsx')) {
      return XlsxImporter.lire(chemin, progression);
    }
    PdfDocument doc;
    try {
      doc = await PdfDocument.openFile(chemin);
    } catch (e) {
      throw ImportException('Impossible d\'ouvrir ce PDF. Le fichier est peut-être abîmé.');
    }
    try {
      if (doc.pages.isEmpty) {
        throw ImportException('Ce PDF ne contient aucune page.');
      }
      final texte1 = await _texteDePage(doc.pages.first);
      if (TextTicketParser.ressembleAuModele(texte1)) {
        return await _lireTexte(doc, progression);
      }
      return await _lireMikhmon(doc, progression);
    } finally {
      await _fermer(doc);
    }
  }

  static Future<void> _fermer(PdfDocument doc) async {
    // Selon la version de pdfrx, la méthode s'appelle dispose() ou close().
    try {
      await (doc as dynamic).dispose();
    } catch (_) {
      try {
        await (doc as dynamic).close();
      } catch (_) {}
    }
  }

  static Future<String> _texteDePage(PdfPage page) async {
    try {
      final t = await page.loadText();
      return t?.fullText ?? '';
    } catch (_) {
      return '';
    }
  }

  // ------------------------------------------------------------ modèle texte

  static Future<ParsedPdf> _lireTexte(
      PdfDocument doc, Progression progression) async {
    final tous = <TexteTicket>[];
    final n = doc.pages.length;
    for (var i = 0; i < n; i++) {
      progression(i / n, 'Lecture de la page ${i + 1} sur $n…');
      final texte = await _texteDePage(doc.pages[i]);
      tous.addAll(TextTicketParser.parse(texte));
    }
    if (tous.isEmpty) {
      throw ImportException('Aucun ticket reconnu dans ce PDF.');
    }
    final slots = <ParsedTicket?>[];
    for (var i = 0; i < tous.length; i++) {
      slots.add(ParsedTicket(code: tous[i].code, numero: i + 1));
    }
    progression(1, '${slots.length} tickets trouvés');
    return ParsedPdf(
      source: 'texte',
      slots: slots,
      echecs: {},
      dureeMinutes: TextTicketParser.dureeCommune(tous),
      prix: TextTicketParser.prixCommun(tous),
    );
  }

  // ----------------------------------------------------------- modèle Mikhmon

  static Future<ParsedPdf> _lireMikhmon(
      PdfDocument doc, Progression progression) async {
    final slots = <ParsedTicket?>[];
    final echecs = <int, Uint8List>{};
    // indice de slot -> (page, case) pour la seconde tentative
    final origine = <int, (int, int)>{};
    String? loginUrl;
    final n = doc.pages.length;

    // Pages lues par la lecture générale (autre mise en page que le modèle
    // d'origine) : indice de slot -> (page, centre normalisé du ticket).
    final generique = <int, (int, double, double)>{};
    final pagesGeneriques = <int>{};
    var numero = 0;

    for (var p = 0; p < n; p++) {
      progression(p / n, 'Lecture de la page ${p + 1} sur $n…');
      final page = doc.pages[p];

      // Modèle d'origine (Mikhmon paysage 4 × 4) : lecture à positions connues.
      var traitee = false;
      if (_estModeleOrigine(page)) {
        final rendu = await _rendreCases(page, _dpiNormal);
        final sorties = await compute(_traiterLot, rendu);
        final lus = [
          for (final s in sorties) s.vide || s.qr == null ? null : _lireQr(s.qr!)
        ];
        if (lus.any((l) => l != null)) {
          traitee = true;
          for (var k = 0; k < sorties.length; k++) {
            final s = sorties[k];
            if (s.vide) continue;
            final idx = slots.length;
            numero++;
            final lu = lus[k];
            if (lu != null) {
              loginUrl ??= lu.url;
              slots.add(ParsedTicket(
                code: lu.code,
                motDePasse: lu.motDePasse,
                qrTexte: s.qr,
                numero: numero,
                image: s.png,
              ));
            } else {
              slots.add(null);
              echecs[idx] = s.png!;
              origine[idx] = (p, k);
            }
          }
        }
      }
      if (traitee) continue;

      // Toute autre mise en page (portrait, nombre de tickets quelconque…).
      pagesGeneriques.add(p);
      final cases = await _lirePageGenerique(page, _dpiNormal);
      for (final c in cases) {
        final idx = slots.length;
        numero++;
        final lu = c.texte == null ? null : _lireQr(c.texte!);
        if (lu != null) {
          loginUrl ??= lu.url;
          slots.add(ParsedTicket(
            code: lu.code,
            motDePasse: lu.motDePasse,
            qrTexte: c.texte,
            numero: numero,
            image: c.png,
          ));
        } else {
          slots.add(null);
          echecs[idx] = c.png;
          generique[idx] = (p, c.cx, c.cy);
        }
      }
    }

    // Seconde tentative à plus haute résolution pour les cases illisibles.
    if (echecs.isNotEmpty) {
      final parPage = <int, List<int>>{};
      origine.forEach((idx, pk) => parPage.putIfAbsent(pk.$1, () => []).add(idx));
      generique.forEach((idx, pcc) => parPage.putIfAbsent(pcc.$1, () => []).add(idx));
      var fait = 0;
      for (final entree in parPage.entries) {
        progression(fait / parPage.length,
            'Nouvelle tentative sur la page ${entree.key + 1}…');
        fait++;
        if (pagesGeneriques.contains(entree.key)) {
          final cases =
              await _lirePageGenerique(doc.pages[entree.key], _dpiRetentative);
          for (final idx in entree.value) {
            final (_, ox, oy) = generique[idx]!;
            _CelleLue? meilleure;
            var d = double.infinity;
            for (final c in cases) {
              final e = (c.cx - ox) * (c.cx - ox) + (c.cy - oy) * (c.cy - oy);
              if (e < d) {
                d = e;
                meilleure = c;
              }
            }
            final lu = (meilleure == null || meilleure.texte == null || d > 0.0004)
                ? null
                : _lireQr(meilleure.texte!);
            if (lu != null) {
              slots[idx] = ParsedTicket(
                code: lu.code,
                motDePasse: lu.motDePasse,
                qrTexte: meilleure!.texte,
                numero: _numeroDuSlot(slots, idx),
                image: meilleure.png,
              );
              echecs.remove(idx);
            }
          }
          continue;
        }
        final rendu = await _rendreCases(doc.pages[entree.key], _dpiRetentative);
        final sorties = await compute(_traiterLot, rendu);
        for (final idx in entree.value) {
          final k = origine[idx]!.$2;
          final s = sorties[k];
          final lu = s.qr == null ? null : _lireQr(s.qr!);
          if (lu != null) {
            slots[idx] = ParsedTicket(
              code: lu.code,
              motDePasse: lu.motDePasse,
              qrTexte: s.qr,
              numero: _numeroDuSlot(slots, idx),
              image: s.png,
            );
            echecs.remove(idx);
          }
        }
      }
    }

    if (slots.isEmpty) {
      throw ImportException(
          'Aucun ticket reconnu. Ce PDF ne ressemble ni à une planche Mikhmon ni au modèle « Code / Durée ».');
    }
    if (slots.every((t) => t == null)) {
      throw ImportException(
          'Aucun QR code lisible. La mise en page de ce PDF est peut-être différente du modèle attendu.');
    }
    progression(1, '${slots.length} tickets trouvés');
    return ParsedPdf(
      source: 'mikhmon',
      slots: slots,
      echecs: echecs,
      loginUrl: loginUrl,
    );
  }

  /// Numéro de ticket d'un slot : sa position dans le PDF.
  static int _numeroDuSlot(List<ParsedTicket?> slots, int idx) => idx + 1;

  /// Page au format du modèle d'origine (Letter paysage, 792 × 612 pt).
  static bool _estModeleOrigine(PdfPage page) =>
      (page.width - _pageLargeurRef).abs() < 30 && (page.height - 612).abs() < 30;

  /// Lecture générale d'une page : QR repérés où qu'ils soient, tickets
  /// découpés autour. Résolution limitée pour ne pas saturer la mémoire.
  static Future<List<_CelleLue>> _lirePageGenerique(PdfPage page, double dpi) async {
    var echelle = dpi / 72.0;
    final plusLong = page.width > page.height ? page.width : page.height;
    if (plusLong * echelle > 4200) echelle = 4200 / plusLong;
    final image = await page.render(
      fullWidth: page.width * echelle,
      fullHeight: page.height * echelle,
    );
    if (image == null) {
      throw ImportException('Impossible de rendre une page du PDF.');
    }
    final Uint8List px;
    final int w, h;
    try {
      w = image.width;
      h = image.height;
      px = Uint8List.fromList(image.pixels);
    } finally {
      image.dispose();
    }
    return compute(_analyserPageJob, _PageJob(px, w, h));
  }

  /// Rend la page à la résolution voulue et découpe les 16 cases.
  static Future<_LotCases> _rendreCases(PdfPage page, double dpi) async {
    final echelle = dpi / 72.0;
    final image = await page.render(
      fullWidth: page.width * echelle,
      fullHeight: page.height * echelle,
    );
    if (image == null) {
      throw ImportException('Impossible de rendre une page du PDF.');
    }
    try {
      final w = image.width;
      final h = image.height;
      final px = image.pixels; // BGRA (ordre vérifié ci-dessous)
      final f = w / _pageLargeurRef; // pixels par point
      final swap = _canauxRgba(px, w, h, f);

      final cases = <_CaseJob>[];
      for (var r = 0; r < _lignes; r++) {
        for (var c = 0; c < _colonnes; c++) {
          final x = ((_caseX0 + _casePasX * c) * f).round();
          final y = ((_caseY0 + _casePasY * r) * f).round();
          final cw = (_caseL * f).round();
          final ch = (_caseH * f).round();
          final rect = _rogner(px, w, h, x, y, cw, ch);
          cases.add(_CaseJob(rect.octets, rect.largeur, rect.hauteur, swap, f));
        }
      }
      return _LotCases(cases);
    } finally {
      image.dispose();
    }
  }

  /// Vrai si le tampon est en réalité RGBA (et non BGRA).
  /// Le logo Mikhmon est bleu : en lecture BGRA, on doit trouver B > R.
  static bool _canauxRgba(Uint8List px, int w, int h, double f) {
    var sommeB = 0, sommeR = 0, n = 0;
    final x0 = ((_caseX0 + _logoX0) * f).round();
    final x1 = ((_caseX0 + _logoX1) * f).round();
    final y0 = ((_caseY0 + _logoY0) * f).round();
    final y1 = ((_caseY0 + _logoY1) * f).round();
    for (var y = y0; y < y1 && y < h; y += 2) {
      for (var x = x0; x < x1 && x < w; x += 2) {
        final i = (y * w + x) * 4;
        final b = px[i];
        final r = px[i + 2];
        if ((b - r).abs() > 60) {
          sommeB += b;
          sommeR += r;
          n++;
        }
      }
    }
    if (n < 20) return false;
    return sommeB < sommeR;
  }

  static _Rect _rogner(Uint8List px, int w, int h, int x, int y, int cw, int ch) {
    if (x < 0) x = 0;
    if (y < 0) y = 0;
    if (x + cw > w) cw = w - x;
    if (y + ch > h) ch = h - y;
    final out = Uint8List(cw * ch * 4);
    for (var row = 0; row < ch; row++) {
      final src = ((y + row) * w + x) * 4;
      out.setRange(row * cw * 4, (row + 1) * cw * 4, px, src);
    }
    return _Rect(out, cw, ch);
  }

  /// QR Mikhmon : http://mtandao.wifi/login?username=24283&password=24283
  static _QrLu? _lireQr(String texte) {
    final t = texte.trim();
    final uri = Uri.tryParse(t);
    String? url;
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      url = '${uri.scheme}://${uri.host}';
    }
    final user = uri?.queryParameters['username'];
    final pass = uri?.queryParameters['password'];
    if (user != null && user.isNotEmpty) {
      return _QrLu(user, (pass == null || pass.isEmpty) ? null : pass, url);
    }
    // QR contenant seulement le code.
    if (RegExp(r'^[A-Za-z0-9_\-]{3,32}$').hasMatch(t)) {
      return _QrLu(t, null, null);
    }
    return null;
  }
}

class _QrLu {
  _QrLu(this.code, this.motDePasse, this.url);
  final String code;
  final String? motDePasse;
  final String? url;
}

class _Rect {
  _Rect(this.octets, this.largeur, this.hauteur);
  final Uint8List octets;
  final int largeur;
  final int hauteur;
}

// ---------------------------------------------------------------------------
// Travail en arrière-plan (isolate) : décodage du QR et encodage PNG des cases.
// ---------------------------------------------------------------------------

class _CaseJob {
  _CaseJob(this.octets, this.w, this.h, this.swapRb, this.pxParPoint);
  final Uint8List octets; // BGRA (ou RGBA si swapRb)
  final int w;
  final int h;
  final bool swapRb;
  final double pxParPoint;
}

class _LotCases {
  _LotCases(this.cases);
  final List<_CaseJob> cases;
}

class _CaseSortie {
  _CaseSortie({required this.vide, this.qr, this.png});
  final bool vide;
  final String? qr;
  final Uint8List? png;
}

List<_CaseSortie> _traiterLot(_LotCases lot) =>
    lot.cases.map(_traiterCase).toList();

_CaseSortie _traiterCase(_CaseJob j) {
  if (j.w <= 0 || j.h <= 0) return _CaseSortie(vide: true);

  // Reconstruit une image RGBA propre quel que soit l'ordre d'origine.
  final brute = img.Image.fromBytes(
    width: j.w,
    height: j.h,
    bytes: j.octets.buffer,
    numChannels: 4,
    order: j.swapRb ? img.ChannelOrder.rgba : img.ChannelOrder.bgra,
  );
  final rgba = brute.getBytes(order: img.ChannelOrder.rgba);
  final image = img.Image.fromBytes(
    width: j.w,
    height: j.h,
    bytes: rgba.buffer,
    numChannels: 4,
  );

  // Case vide (dernière page) : presque tout blanc.
  var somme = 0, n = 0;
  for (var i = 0; i < rgba.length; i += 4 * 97) {
    somme += rgba[i] + rgba[i + 1] + rgba[i + 2];
    n += 3;
  }
  if (n > 0 && somme / n > 250) return _CaseSortie(vide: true);

  final f = j.pxParPoint;
  int borne(int v, int max) => v < 0 ? 0 : (v > max ? max : v);
  final qx0 = borne((_qrX0 * f).round(), j.w - 1);
  final qx1 = borne((_qrX1 * f).round(), j.w);
  final qy0 = borne((_qrY0 * f).round(), j.h - 1);
  final qy1 = borne((_qrY1 * f).round(), j.h);

  String? qr;
  if (qx1 > qx0 && qy1 > qy0) {
    final zone = img.copyCrop(image,
        x: qx0, y: qy0, width: qx1 - qx0, height: qy1 - qy0);
    qr = _decoderQr(zone);
  }
  qr ??= _decoderQr(image);

  final png = img.encodePng(image.convert(numChannels: 3), level: 6);
  return _CaseSortie(vide: false, qr: qr, png: png);
}

String? _decoderQr(img.Image im) {
  try {
    final octets = im.convert(numChannels: 4).getBytes(order: img.ChannelOrder.rgba);
    final source =
        RGBLuminanceSource(im.width, im.height, octets.buffer.asInt32List());
    final bitmap = BinaryBitmap(HybridBinarizer(source));
    return QRCodeReader().decode(bitmap).text;
  } catch (_) {
    return null;
  }
}

class _PageJob {
  _PageJob(this.px, this.w, this.h);
  final Uint8List px;
  final int w;
  final int h;
}

class _CelleLue {
  _CelleLue(this.texte, this.png, this.cx, this.cy);
  final String? texte;
  final Uint8List png;

  /// Centre du ticket, en fraction de la page (pour retrouver le même ticket
  /// d'une résolution à l'autre).
  final double cx;
  final double cy;
}

List<_CelleLue> _analyserPageJob(_PageJob j) {
  final cellules = analyserPlanche(
    j.px,
    j.w,
    j.h,
    accepter: (t) => PdfImporter._lireQr(t) != null,
  );
  return [
    for (final c in cellules)
      _CelleLue(
        c.texte,
        c.png!,
        (c.cellule.x + c.cellule.l / 2) / j.w,
        (c.cellule.y + c.cellule.h / 2) / j.h,
      ),
  ];
}
