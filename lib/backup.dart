import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'repo.dart';

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Sauvegarde / restauration des données dans un seul fichier « .mtandao »
/// (JSON compressé). Le code PIN n'est jamais inclus.
class Sauvegarde {
  static const int version = 2;
  static const String extension = 'mtandao';

  // Réglages exclus de la sauvegarde (PIN, lot actif, état de la sauvegarde
  // Google Drive : propres à ce téléphone).
  static bool estExclu(String cle) =>
      cle.startsWith('pin_') ||
      cle.startsWith('drive_') ||
      cle == 'lot_actif' ||
      cle == 'vendeur_actif' ||
      cle == 'theme' ||
      cle == 'guide_vu' ||
      cle == 'derniere_sauvegarde';

  /// Crée le fichier de sauvegarde dans le dossier temporaire et le retourne.
  static Future<File> exporter(Repo repo) async {
    final octets = await contenu(repo);
    final dossier = await getTemporaryDirectory();
    final d = DateTime.now();
    String deux(int n) => n.toString().padLeft(2, '0');
    final nom =
        'mtandao_sauvegarde_${d.year}${deux(d.month)}${deux(d.day)}_${deux(d.hour)}${deux(d.minute)}.$extension';
    final fichier = File(p.join(dossier.path, nom));
    await fichier.writeAsBytes(octets, flush: true);
    return fichier;
  }

  /// Contenu (JSON compressé) d'une sauvegarde de toutes les données.
  static Future<Uint8List> contenu(Repo repo) async {
    final db = repo.db;
    final reglages = await db.query('settings');
    final donnees = <String, Object?>{
      'app': 'mtandao',
      'version': version,
      'exporte_le': DateTime.now().millisecondsSinceEpoch,
      'forfaits': await db.query('forfaits'),
      'clients': await db.query('clients'),
      'vendeurs': await db.query('vendeurs'),
      'lots': await db.query('lots'),
      'tickets': await db.query('tickets'),
      'images': await db.query('ticket_images'),
      'settings': {
        for (final r in reglages)
          if (!estExclu(r['cle'] as String)) r['cle'] as String: r['valeur'],
      },
    };
    return compute(_encoder, donnees);
  }

  /// Réservé aux tests : lit / écrit le contenu d'un fichier de sauvegarde.
  @visibleForTesting
  static Future<Map<String, Object?>> decoderPourTest(Uint8List octets) async =>
      _decoder(octets);

  @visibleForTesting
  static Future<Uint8List> encoderPourTest(Map<String, Object?> donnees) async =>
      _encoder(donnees);

  /// Remplace toutes les données par celles du fichier. Le PIN est conservé.
  static Future<void> restaurer(Repo repo, Uint8List octets) async {
    if (octets.length < 2 || octets[0] != 0x1f || octets[1] != 0x8b) {
      throw BackupException('Ce fichier n\'est pas une sauvegarde Mtandao.');
    }
    final Map<String, Object?> d;
    try {
      d = await compute(_decoder, octets);
    } catch (_) {
      throw BackupException('Sauvegarde illisible ou abîmée.');
    }
    if (d['app'] != 'mtandao') {
      throw BackupException('Ce fichier n\'est pas une sauvegarde Mtandao.');
    }
    final v = d['version'];
    if (v is! int || v > version) {
      throw BackupException(
          'Cette sauvegarde vient d\'une version plus récente de l\'application. Mettez Mtandao à jour.');
    }

    // Les sauvegardes de la version 1 n'ont ni clients ni vendeurs.
    List<Map<String, Object?>> liste(String cle) =>
        ((d[cle] as List?) ?? const [])
            .map((e) => Map<String, Object?>.from(e as Map))
            .toList();

    final forfaits = liste('forfaits');
    final clients = liste('clients');
    final vendeurs = liste('vendeurs');
    final lots = liste('lots');
    final tickets = liste('tickets');
    final images = liste('images');
    final reglages = Map<String, Object?>.from(d['settings'] as Map);

    await repo.db.transaction((txn) async {
      await txn.delete('ticket_images');
      await txn.delete('tickets');
      await txn.delete('lots');
      await txn.delete('forfaits');
      await txn.delete('clients');
      await txn.delete('vendeurs');
      // On garde le PIN et la connexion à Google Drive (propres à ce téléphone).
      await txn.delete('settings',
          where: "cle NOT LIKE 'pin\\_%' ESCAPE '\\' "
              "AND cle NOT LIKE 'drive\\_%' ESCAPE '\\'");

      final b = txn.batch();
      for (final r in forfaits) {
        b.insert('forfaits', r);
      }
      for (final r in clients) {
        b.insert('clients', r);
      }
      for (final r in vendeurs) {
        b.insert('vendeurs', r);
      }
      for (final r in lots) {
        b.insert('lots', r);
      }
      for (final r in tickets) {
        b.insert('tickets', r);
      }
      for (final r in images) {
        b.insert('ticket_images', r);
      }
      reglages.forEach((cle, valeur) {
        if (estExclu(cle)) return;
        b.insert('settings', {'cle': cle, 'valeur': valeur},
            conflictAlgorithm: ConflictAlgorithm.replace);
      });
      await b.commit(noResult: true);
    });
  }
}

// ------------------------------------------------------- travail en arrière-plan

Uint8List _encoder(Map<String, Object?> donnees) {
  final images = (donnees['images'] as List).map((row) {
    final m = row as Map;
    return <String, Object?>{
      'ticket_id': m['ticket_id'],
      'data': base64Encode(m['data'] as Uint8List),
    };
  }).toList();
  final complet = Map<String, Object?>.from(donnees)..['images'] = images;
  final json = utf8.encode(jsonEncode(complet));
  return Uint8List.fromList(GZipCodec(level: 9).encode(json));
}

Map<String, Object?> _decoder(Uint8List octets) {
  final json = utf8.decode(GZipCodec().decode(octets));
  final d = Map<String, Object?>.from(jsonDecode(json) as Map);
  final images = (d['images'] as List).map((row) {
    final m = Map<String, Object?>.from(row as Map);
    return <String, Object?>{
      'ticket_id': m['ticket_id'],
      'data': base64Decode(m['data'] as String),
    };
  }).toList();
  d['images'] = images;
  return d;
}
