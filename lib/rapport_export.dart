import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'format.dart';
import 'models.dart';
import 'rapport.dart';

/// Export des rapports de ventes en CSV (tableur) et en PDF.
class RapportExport {
  static const String _entetes =
      'Date;Heure;Code;Forfait;Lot;Prix (CDF);Paiement;Encaissé (CDF);Client;Vendeur';

  /// Un champ de texte pour un tableur : entre guillemets s'il le faut, et
  /// neutralisé s'il commence par un caractère que Excel prendrait pour une
  /// formule (`=`, `+`, `-`, `@`) : protection contre l'injection de formules.
  static String champ(String? valeur) {
    var v = valeur ?? '';
    if (RegExp(r'^[=+\-@\t\r]').hasMatch(v)) v = "'$v";
    if (v.contains(';') || v.contains('"') || v.contains('\n') || v.contains('\r')) {
      v = '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  /// CSV lisible par Excel en français : séparateur « ; », UTF-8 avec marque
  /// d'ordre des octets pour que les accents s'affichent bien.
  static String csv(List<VenteLigne> ventes) {
    final lignes = <String>[_entetes];
    for (final v in ventes) {
      lignes.add([
        fmtJourCourt(v.venduLe),
        fmtHeure(v.venduLe),
        champ(v.code),
        champ(v.forfaitNom),
        champ(v.lotNom),
        '${v.prix}',
        champ(Paiement.libelle(v.paiement)),
        '${v.montantEncaisse}',
        champ(v.clientNom),
        champ(v.vendeurNom),
      ].join(';'));
    }
    return '﻿${lignes.join('\r\n')}\r\n';
  }

  // ------------------------------------------------------------------- PDF

  /// Remplace les espaces fines (absentes de la police) par une espace simple.
  static String _t(String s) => s.replaceAll(RegExp(r'[\u202f\u2009]'), ' ');

  /// Police Roboto embarquée (licence Apache 2.0) : accents et symboles
  /// s'affichent correctement, contrairement à la police de base des PDF.
  static Future<pw.ThemeData> _theme() async {
    final normale =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    final grasse =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
    return pw.ThemeData.withFont(base: normale, bold: grasse);
  }

  /// Rapport PDF : chiffres clés, détail par forfait / paiement / vendeur /
  /// jour, puis la liste des ventes.
  static Future<Uint8List> pdf({
    required String titre,
    required Rapport rapport,
    bool detailParJour = false,
  }) async {
    final doc = pw.Document(
        title: 'Rapport Mtandao', author: 'Mtandao', theme: await _theme());
    const gris = PdfColors.grey700;

    pw.Widget section(String nom) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 14, bottom: 4),
          child: pw.Text(_t(nom),
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        );

    pw.Widget tableau(List<String> entetes, List<List<String>> lignes) =>
        pw.TableHelper.fromTextArray(
          headers: entetes.map(_t).toList(),
          data: [for (final l in lignes) l.map(_t).toList()],
          headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          cellAlignments: {
            for (var i = 0; i < entetes.length; i++) i: pw.Alignment.centerLeft,
          },
        );

    String paiementNom(String p) => Paiement.libelle(p);

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Page ${ctx.pageNumber} / ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: gris)),
      ),
      build: (ctx) => [
        pw.Text('Rapport Mtandao',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 2),
        pw.Text(_t(titre), style: const pw.TextStyle(fontSize: 12, color: gris)),
        section('Chiffres clés'),
        tableau(const [
          'Indicateur',
          'Valeur'
        ], [
          ['Tickets vendus', '${rapport.nombre}'],
          ['Montant encaissé', cdf(rapport.encaisse)],
          if (rapport.aRecevoir > 0)
            ['À recevoir (crédits)', cdf(rapport.aRecevoir)],
          if (rapport.offerts > 0) ['Tickets offerts', '${rapport.offerts}'],
        ]),
        if (rapport.parForfait.isNotEmpty) ...[
          section('Par forfait'),
          tableau(const [
            'Forfait',
            'Tickets',
            'Encaissé'
          ], [
            for (final e in rapport.parForfait.entries)
              [e.key, '${e.value.nombre}', cdf(e.value.montant)],
          ]),
        ],
        if (rapport.parPaiement.isNotEmpty) ...[
          section('Par mode de paiement'),
          tableau(const [
            'Paiement',
            'Tickets',
            'Encaissé'
          ], [
            for (final e in rapport.parPaiement.entries)
              [paiementNom(e.key), '${e.value.nombre}', cdf(e.value.montant)],
          ]),
        ],
        if (rapport.aDesVendeurs) ...[
          section('Par vendeur'),
          tableau(const [
            'Vendeur',
            'Tickets',
            'Encaissé'
          ], [
            for (final e in rapport.parVendeur.entries)
              [e.key, '${e.value.nombre}', cdf(e.value.montant)],
          ]),
        ],
        if (detailParJour && rapport.parJour.isNotEmpty) ...[
          section('Par jour'),
          tableau(const [
            'Jour',
            'Tickets',
            'Encaissé'
          ], [
            for (final e in rapport.parJour.entries)
              [fmtJourCourt(e.key), '${e.value.nombre}', cdf(e.value.montant)],
          ]),
        ],
        if (rapport.ventes.isNotEmpty) ...[
          section('Liste des ventes'),
          tableau(const [
            'Date',
            'Code',
            'Forfait',
            'Paiement',
            'Prix'
          ], [
            for (final v in rapport.ventes)
              [
                fmtDateHeure(v.venduLe),
                v.code,
                v.forfaitNom,
                paiementNom(v.paiement) +
                    (v.clientNom == null ? '' : ' (${v.clientNom})'),
                cdf(v.prix),
              ],
          ]),
        ],
      ],
    ));
    return doc.save();
  }
}
