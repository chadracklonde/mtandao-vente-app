import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Accès aux données. Toutes les opérations sont locales.
class Repo {
  Repo(this.db);
  final Database db;

  // ---------------------------------------------------------------- réglages

  Future<String?> getSetting(String cle) async {
    final r = await db.query('settings',
        where: 'cle = ?', whereArgs: [cle], limit: 1);
    if (r.isEmpty) return null;
    return r.first['valeur'] as String?;
  }

  Future<void> setSetting(String cle, String valeur) async {
    await db.insert('settings', {'cle': cle, 'valeur': valeur},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeSetting(String cle) async {
    await db.delete('settings', where: 'cle = ?', whereArgs: [cle]);
  }

  // ---------------------------------------------------------------- forfaits

  Future<List<Forfait>> forfaits({bool seulementActifs = false}) async {
    final r = await db.query('forfaits',
        where: seulementActifs ? 'actif = 1' : null,
        orderBy: 'duree_minutes ASC, id ASC');
    return r.map(Forfait.fromMap).toList();
  }

  Future<int> ajouterForfait(String nom, int dureeMinutes, int prix) {
    return db.insert('forfaits', {
      'nom': nom,
      'duree_minutes': dureeMinutes,
      'prix': prix,
      'actif': 1,
    });
  }

  Future<void> modifierForfait(int id,
      {String? nom, int? dureeMinutes, int? prix, bool? actif}) async {
    final values = <String, Object?>{};
    if (nom != null) values['nom'] = nom;
    if (dureeMinutes != null) values['duree_minutes'] = dureeMinutes;
    if (prix != null) values['prix'] = prix;
    if (actif != null) values['actif'] = actif ? 1 : 0;
    if (values.isEmpty) return;
    await db.update('forfaits', values, where: 'id = ?', whereArgs: [id]);
  }

  // -------------------------------------------------------------------- lots

  static const _lotsSql = '''
    SELECT l.*, f.nom AS forfait_nom,
      (SELECT COUNT(*) FROM tickets t WHERE t.lot_id = l.id) AS total,
      (SELECT COUNT(*) FROM tickets t WHERE t.lot_id = l.id AND t.vendu = 1) AS vendus,
      (SELECT COALESCE(SUM(t.prix), 0) FROM tickets t
         WHERE t.lot_id = l.id AND t.vendu = 1) AS montant
    FROM lots l JOIN forfaits f ON f.id = l.forfait_id
  ''';

  Future<List<Lot>> lots() async {
    final r = await db.rawQuery('$_lotsSql ORDER BY l.cree_le DESC, l.id DESC');
    return r.map(Lot.fromMap).toList();
  }

  Future<Lot?> lot(int id) async {
    final r = await db.rawQuery('$_lotsSql WHERE l.id = ?', [id]);
    if (r.isEmpty) return null;
    return Lot.fromMap(r.first);
  }

  Future<void> renommerLot(int id, String nom) async {
    await db.update('lots', {'nom': nom}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> supprimerLot(int id) async {
    await db.transaction((txn) async {
      await txn.delete('ticket_images',
          where: 'ticket_id IN (SELECT id FROM tickets WHERE lot_id = ?)',
          whereArgs: [id]);
      await txn.delete('tickets', where: 'lot_id = ?', whereArgs: [id]);
      await txn.delete('lots', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Codes déjà présents en base (pour ignorer les doublons à l'import).
  Future<Set<String>> codesExistants() async {
    final r = await db.query('tickets', columns: ['code']);
    return r.map((e) => e['code'] as String).toSet();
  }

  /// Crée un lot et ses tickets. Les codes déjà importés sont ignorés.
  Future<ImportResult> importerLot({
    required String nom,
    required Forfait forfait,
    required String source,
    String? fichier,
    String? loginUrl,
    required List<ParsedTicket> tickets,
  }) {
    return db.transaction((txn) async {
      final existants = <String>{};
      final rows = await txn.query('tickets', columns: ['code']);
      for (final r in rows) {
        existants.add(r['code'] as String);
      }

      final lotId = await txn.insert('lots', {
        'nom': nom,
        'forfait_id': forfait.id,
        'source': source,
        'fichier': fichier,
        'login_url': loginUrl,
        'cree_le': DateTime.now().millisecondsSinceEpoch,
      });

      var inseres = 0;
      var doublons = 0;
      final vus = <String>{};
      for (final t in tickets) {
        if (existants.contains(t.code) || !vus.add(t.code)) {
          doublons++;
          continue;
        }
        final id = await txn.insert('tickets', {
          'lot_id': lotId,
          'position': inseres,
          'numero': t.numero,
          'code': t.code,
          'mot_de_passe': t.motDePasse,
          'qr_texte': t.qrTexte,
          'prix': forfait.prix,
          'forfait_id': forfait.id,
          'vendu': 0,
        });
        if (t.image != null) {
          await txn.insert('ticket_images', {'ticket_id': id, 'data': t.image});
        }
        inseres++;
      }

      if (inseres == 0) {
        await txn.delete('lots', where: 'id = ?', whereArgs: [lotId]);
        return ImportResult(lotId: null, inseres: 0, doublons: doublons);
      }
      return ImportResult(lotId: lotId, inseres: inseres, doublons: doublons);
    });
  }

  // ----------------------------------------------------------------- tickets

  Future<Ticket?> prochainTicket(int lotId) async {
    final r = await db.query('tickets',
        where: 'lot_id = ? AND vendu = 0',
        whereArgs: [lotId],
        orderBy: 'position ASC, id ASC',
        limit: 1);
    if (r.isEmpty) return null;
    return Ticket.fromMap(r.first);
  }

  Future<Ticket?> dernierVendu(int lotId) async {
    final r = await db.query('tickets',
        where: 'lot_id = ? AND vendu = 1',
        whereArgs: [lotId],
        orderBy: 'vendu_le DESC, id DESC',
        limit: 1);
    if (r.isEmpty) return null;
    return Ticket.fromMap(r.first);
  }

  Future<LotStats> stats(int lotId) async {
    final r = await db.rawQuery('''
      SELECT COUNT(*) AS total,
             COALESCE(SUM(CASE WHEN vendu = 1 THEN 1 ELSE 0 END), 0) AS vendus,
             COALESCE(SUM(CASE WHEN vendu = 1 THEN prix ELSE 0 END), 0) AS montant
      FROM tickets WHERE lot_id = ?''', [lotId]);
    final m = r.first;
    return LotStats(
      total: (m['total'] as int?) ?? 0,
      vendus: (m['vendus'] as int?) ?? 0,
      montant: (m['montant'] as int?) ?? 0,
    );
  }

  Future<List<Ticket>> ticketsDuLot(int lotId) async {
    final r = await db.query('tickets',
        where: 'lot_id = ?',
        whereArgs: [lotId],
        orderBy: 'position ASC, id ASC');
    return r.map(Ticket.fromMap).toList();
  }

  Future<Uint8List?> imageTicket(int ticketId) async {
    final r = await db.query('ticket_images',
        where: 'ticket_id = ?', whereArgs: [ticketId], limit: 1);
    if (r.isEmpty) return null;
    return r.first['data'] as Uint8List;
  }

  /// Marque un ticket comme vendu. Retourne faux s'il l'était déjà.
  Future<bool> vendre(int ticketId) async {
    final n = await db.update(
      'tickets',
      {'vendu': 1, 'vendu_le': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ? AND vendu = 0',
      whereArgs: [ticketId],
    );
    return n > 0;
  }

  /// Remet un ticket en stock.
  Future<void> remettreEnStock(int ticketId) async {
    await db.update('tickets', {'vendu': 0, 'vendu_le': null},
        where: 'id = ?', whereArgs: [ticketId]);
  }

  /// Annule la dernière vente du lot. Retourne le ticket remis en stock.
  Future<Ticket?> annulerDerniereVente(int lotId) async {
    final t = await dernierVendu(lotId);
    if (t == null) return null;
    await remettreEnStock(t.id);
    return t;
  }

  // ---------------------------------------------------------------- rapports

  Future<List<VenteLigne>> ventes(DateTime debut, DateTime finExclue) async {
    final r = await db.rawQuery('''
      SELECT t.code, t.prix, t.vendu_le, f.nom AS forfait_nom, l.nom AS lot_nom
      FROM tickets t
      JOIN forfaits f ON f.id = t.forfait_id
      JOIN lots l ON l.id = t.lot_id
      WHERE t.vendu = 1 AND t.vendu_le >= ? AND t.vendu_le < ?
      ORDER BY t.vendu_le DESC''', [
      debut.millisecondsSinceEpoch,
      finExclue.millisecondsSinceEpoch,
    ]);
    return r
        .map((m) => VenteLigne(
              code: m['code'] as String,
              prix: m['prix'] as int,
              venduLe:
                  DateTime.fromMillisecondsSinceEpoch(m['vendu_le'] as int),
              forfaitNom: m['forfait_nom'] as String,
              lotNom: m['lot_nom'] as String,
            ))
        .toList();
  }
}
