import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao/pdf_import.dart';
import 'package:mtandao/xlsx_import.dart';

Uint8List _classeur(String feuille, {String? partages}) {
  final a = Archive();
  void ajoute(String nom, String contenu) {
    final b = utf8.encode(contenu);
    a.addFile(ArchiveFile(nom, b.length, b));
  }

  ajoute('xl/worksheets/sheet1.xml', feuille);
  if (partages != null) ajoute('xl/sharedStrings.xml', partages);
  return Uint8List.fromList(ZipEncoder().encode(a));
}

String _ligne(int r, List<String> v) => '<row r="$r">${[
      for (var i = 0; i < v.length; i++)
        '<c r="${String.fromCharCode(65 + i)}$r" t="inlineStr"><is><t>${v[i]}</t></is></c>'
    ].join()}</row>';

void main() {
  test('export « Voucher » : codes, durée, tickets déjà utilisés ignorés', () {
    final feuille = '<worksheet><sheetData>'
        '${_ligne(1, ['ID de coupon', ' Statut', ' Durée'])}'
        '${_ligne(2, ['461232', 'En utilistation', '1jour(s) '])}'
        '${_ligne(3, ['023221', 'Inutilisé', '1jour(s) '])}'
        '${_ligne(4, ['956761', 'Inutilisé', '1jour(s) '])}'
        '${_ligne(5, ['956761', 'Inutilisé', '1jour(s) '])}'
        '</sheetData></worksheet>';
    final r = XlsxImporter.lireOctets(_classeur(feuille));
    expect(r.source, 'excel');
    // Le zéro initial est conservé ; le doublon du fichier est laissé à l'import.
    expect(r.slots.map((t) => t!.code), ['023221', '956761', '956761']);
    expect(r.ignores, 1);
    expect(r.dureeMinutes, 1440);
    expect(r.slots.map((t) => t!.numero), [1, 2, 3]);
  });

  test('chaînes partagées (Excel classique) et colonnes dans un autre ordre', () {
    const partages = '<sst><si><t>Durée</t></si><si><t>Code</t></si>'
        '<si><t>2 heures</t></si><si><t>AB12</t></si></sst>';
    const feuille = '<worksheet><sheetData>'
        '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>'
        '<row r="2"><c r="A2" t="s"><v>2</v></c><c r="B2" t="s"><v>3</v></c></row>'
        '</sheetData></worksheet>';
    final r = XlsxImporter.lireOctets(_classeur(feuille, partages: partages));
    expect(r.slots.single!.code, 'AB12');
    expect(r.dureeMinutes, 120);
  });

  test('sans en-tête : la colonne A contient les codes', () {
    final feuille = '<worksheet><sheetData>'
        '${_ligne(1, ['111111'])}${_ligne(2, ['222222'])}</sheetData></worksheet>';
    final r = XlsxImporter.lireOctets(_classeur(feuille));
    expect(r.slots.length, 2);
    expect(r.dureeMinutes, isNull);
  });

  test('tout est déjà utilisé : message clair', () {
    final feuille = '<worksheet><sheetData>'
        '${_ligne(1, ['ID de coupon', 'Statut'])}'
        '${_ligne(2, ['461232', 'En utilisation'])}</sheetData></worksheet>';
    expect(() => XlsxImporter.lireOctets(_classeur(feuille)),
        throwsA(isA<ImportException>()));
  });

  test('fichier qui n\'est pas un classeur', () {
    expect(() => XlsxImporter.lireOctets(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<ImportException>()));
  });

  test('exemple réel fourni (si présent)', () {
    final f = File(Platform.environment['XLSX_EXEMPLE'] ?? '/nonexistent');
    if (!f.existsSync()) return;
    final r = XlsxImporter.lireOctets(f.readAsBytesSync());
    expect(r.slots.length, 91);
    expect(r.ignores, 9);
    expect(r.slots.first!.code, '956761');
    expect(r.dureeMinutes, 1440);
  });
}
