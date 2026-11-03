import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import 'models.dart';
import 'pdf_import.dart';
import 'text_parser.dart';

/// Lecture d'un tableur Excel (.xlsx) de tickets, par exemple l'export
/// « Voucher » d'un routeur : colonnes « ID de coupon », « Statut », « Durée ».
///
/// Les tickets déjà utilisés (statut « En utilisation », « Utilisé »,
/// « Expiré »…) ne sont pas importés : ils ne peuvent plus être vendus.
class XlsxImporter {
  static Future<ParsedPdf> lire(String chemin, Progression progression) async {
    progression(0.1, 'Ouverture du tableur…');
    final Uint8List octets;
    try {
      octets = await File(chemin).readAsBytes();
    } catch (_) {
      throw ImportException('Impossible d\'ouvrir ce fichier Excel.');
    }
    progression(0.4, 'Lecture des tickets…');
    final res = await compute(lireOctets, octets);
    progression(1, '${res.slots.length} tickets trouvés');
    return res;
  }

  /// Statuts de l'export du routeur : codes déjà utilisés, et codes encore
  /// disponibles (« Inutilisé »). Sert au suivi d'utilisation.
  static Future<({Set<String> utilises, Set<String> disponibles})> lireStatuts(
      String chemin) async {
    final Uint8List octets;
    try {
      octets = await File(chemin).readAsBytes();
    } catch (_) {
      throw ImportException('Impossible d\'ouvrir ce fichier Excel.');
    }
    return compute(statutsOctets, octets);
  }

  @visibleForTesting
  static ({Set<String> utilises, Set<String> disponibles}) statutsOctets(
      Uint8List octets) {
    final t = _tableau(octets);
    if (t.colStatut == null) {
      throw ImportException(
          'Ce tableur n\'a pas de colonne « Statut » : impossible de savoir quels tickets sont utilisés.');
    }
    final utilises = <String>{}, disponibles = <String>{};
    for (var i = t.debut; i < t.lignes.length; i++) {
      final l = t.lignes[i];
      final code = (l[t.colCode] ?? '').trim();
      if (!RegExp(r'^[A-Za-z0-9_\-]{3,32}$').hasMatch(code)) continue;
      (_dejaUtilise(l[t.colStatut!] ?? '') ? utilises : disponibles).add(code);
    }
    return (utilises: utilises, disponibles: disponibles);
  }

  /// Lecture pure (testable) d'un classeur déjà chargé en mémoire.
  @visibleForTesting
  static ParsedPdf lireOctets(Uint8List octets) {
    final t = _tableau(octets);
    final lignes = t.lignes;
    final colCode = t.colCode, colStatut = t.colStatut, colDuree = t.colDuree;
    final debut = t.debut;
    final tickets = <TexteTicket>[];
    final codes = <ParsedTicket>[];
    var dejaUtilises = 0;
    for (var i = debut; i < lignes.length; i++) {
      final l = lignes[i];
      final code = (l[colCode] ?? '').trim();
      if (!RegExp(r'^[A-Za-z0-9_\-]{3,32}$').hasMatch(code)) continue;
      final statut = colStatut == null ? '' : (l[colStatut] ?? '');
      if (_dejaUtilise(statut)) {
        dejaUtilises++;
        continue;
      }
      final duree =
          colDuree == null ? null : TextTicketParser.dureeDe(l[colDuree] ?? '');
      tickets.add(TexteTicket(code, duree));
      codes.add(ParsedTicket(code: code, numero: codes.length + 1));
    }
    if (codes.isEmpty) {
      throw ImportException(dejaUtilises > 0
          ? 'Les $dejaUtilises tickets de ce tableur sont déjà utilisés : aucun n\'est disponible à la vente.'
          : 'Aucun ticket reconnu dans ce tableur. Une colonne « ID de coupon » (ou « Code ») est attendue.');
    }
    return ParsedPdf(
      source: 'excel',
      slots: codes,
      echecs: {},
      dureeMinutes: TextTicketParser.dureeCommune(tickets),
      ignores: dejaUtilises,
    );
  }

  /// Ouvre le classeur et repère les colonnes utiles.
  static ({
    List<Map<int, String>> lignes,
    int colCode,
    int? colStatut,
    int? colDuree,
    int debut,
  }) _tableau(Uint8List octets) {
    final Archive zip;
    try {
      zip = ZipDecoder().decodeBytes(octets);
    } catch (_) {
      throw ImportException(
          'Ce fichier n\'est pas un classeur Excel (.xlsx) lisible.');
    }
    String? texteDe(String nom) {
      for (final f in zip) {
        if (f.isFile && f.name == nom) {
          return utf8.decode(f.content as List<int>, allowMalformed: true);
        }
      }
      return null;
    }

    var feuille = texteDe('xl/worksheets/sheet1.xml');
    if (feuille == null) {
      final noms = [
        for (final f in zip)
          if (f.isFile &&
              f.name.startsWith('xl/worksheets/') &&
              f.name.endsWith('.xml'))
            f.name
      ]..sort();
      if (noms.isNotEmpty) feuille = texteDe(noms.first);
    }
    if (feuille == null) {
      throw ImportException('Ce classeur Excel ne contient aucune feuille.');
    }
    final partages = _chainesPartagees(texteDe('xl/sharedStrings.xml'));
    final lignes = _lignes(feuille, partages);
    if (lignes.isEmpty) {
      throw ImportException('Ce tableur est vide.');
    }

    // Colonnes d'après l'en-tête ; à défaut, le code est dans la colonne A.
    int? colCode, colStatut, colDuree;
    final entete = lignes.first;
    entete.forEach((col, v) {
      final t = v.toLowerCase();
      if (colCode == null &&
          (t.contains('coupon') ||
              t.contains('voucher') ||
              t.contains('code') ||
              t.contains('username') ||
              t.contains('utilisateur'))) {
        colCode = col;
      } else if (colStatut == null &&
          (t.contains('statut') || t.contains('status') || t.contains('état'))) {
        colStatut = col;
      } else if (colDuree == null &&
          (t.contains('durée') ||
              t.contains('duree') ||
              t.contains('duration'))) {
        colDuree = col;
      }
    });
    final avecEntete = colCode != null;
    return (
      lignes: lignes,
      colCode: colCode ?? 0,
      colStatut: colStatut,
      colDuree: colDuree,
      debut: avecEntete ? 1 : 0,
    );
  }

  /// « Inutilisé » / « Unused » : disponible. Tout autre statut mentionnant
  /// une utilisation ou une expiration : indisponible.
  static bool _dejaUtilise(String statut) {
    final s = statut.trim().toLowerCase();
    if (s.isEmpty) return false;
    if (s.startsWith('inutilis') ||
        s.startsWith('non utilis') ||
        s.startsWith('unused') ||
        s.startsWith('not used')) {
      return false;
    }
    return s.contains('utili') ||
        s.contains('used') ||
        s.contains('expir') ||
        s.contains('épuis') ||
        s.contains('epuis');
  }

  static String _decoder(String s) => s
      .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'),
          (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)))
      .replaceAllMapped(RegExp(r'&#(\d+);'),
          (m) => String.fromCharCode(int.parse(m[1]!)))
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');

  static String _textes(String xml) => _decoder([
        for (final m in RegExp(r'<t\b[^>]*>(.*?)</t>', dotAll: true)
            .allMatches(xml))
          m[1]!
      ].join());

  static List<String> _chainesPartagees(String? xml) {
    if (xml == null) return const [];
    return [
      for (final m
          in RegExp(r'<si\b[^>]*>(.*?)</si>', dotAll: true).allMatches(xml))
        _textes(m[1]!)
    ];
  }

  static int _colonne(String ref) {
    var n = 0;
    for (final c in ref.codeUnits) {
      if (c >= 65 && c <= 90) {
        n = n * 26 + (c - 64);
      } else {
        break;
      }
    }
    return n - 1;
  }

  /// Lignes de la feuille : colonne -> texte.
  static List<Map<int, String>> _lignes(String feuille, List<String> partages) {
    final res = <Map<int, String>>[];
    for (final r in RegExp(r'<row\b[^>]*>(.*?)</row>', dotAll: true)
        .allMatches(feuille)) {
      final ligne = <int, String>{};
      for (final c in RegExp(r'<c\b([^>]*?)(?:/>|>(.*?)</c>)', dotAll: true)
          .allMatches(r[1]!)) {
        final attrs = c[1]!;
        final corps = c[2] ?? '';
        final ref = RegExp(r'\br="([A-Z]+)\d+"').firstMatch(attrs)?.group(1);
        if (ref == null) continue;
        final type = RegExp(r'\bt="(\w+)"').firstMatch(attrs)?.group(1);
        String valeur;
        if (type == 'inlineStr') {
          valeur = _textes(corps);
        } else {
          final v = RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(corps)?[1];
          if (v == null) {
            valeur = '';
          } else if (type == 's') {
            final i = int.tryParse(v.trim());
            valeur = (i != null && i >= 0 && i < partages.length)
                ? partages[i]
                : '';
          } else {
            valeur = _decoder(v);
          }
        }
        ligne[_colonne(ref)] = valeur;
      }
      if (ligne.isNotEmpty) res.add(ligne);
    }
    return res;
  }
}
