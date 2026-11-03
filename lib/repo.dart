import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import 'models.dart';
import 'pin_hash.dart';

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

  /// Condition SQL : l'argent d'un ticket vendu est réellement rentré
  /// (espèces, mobile money, ou crédit payé). Exclut offerts et crédits dus.
  static String encaisse([String t = '']) =>
      "(${t}paiement IN ('especes','mobile') "
      "OR (${t}paiement = 'credit' AND ${t}paye_le IS NOT NULL))";

  static final _lotsSql = '''
    SELECT l.*, f.nom AS forfait_nom,
      (SELECT COUNT(*) FROM tickets t WHERE t.lot_id = l.id) AS total,
      (SELECT COUNT(*) FROM tickets t WHERE t.lot_id = l.id AND t.vendu = 1) AS vendus,
      (SELECT COUNT(*) FROM tickets t
         WHERE t.lot_id = l.id AND t.vendu = 0 AND t.defectueux = 1) AS defectueux,
      (SELECT COALESCE(SUM(t.prix), 0) FROM tickets t
         WHERE t.lot_id = l.id AND t.vendu = 1 AND ${encaisse('t.')}) AS montant
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

  /// Change le prix des tickets **non vendus** d'un lot. Les tickets déjà
  /// vendus gardent leur prix : les rapports passés ne changent pas.
  /// Retourne le nombre de tickets modifiés.
  Future<int> modifierPrixLot(int lotId, int prix) {
    _verifierPrix(prix);
    return db.update('tickets', {'prix': prix},
        where: 'lot_id = ? AND vendu = 0', whereArgs: [lotId]);
  }

  /// Change le prix de tous les tickets non vendus d'un forfait (tous lots).
  Future<int> modifierPrixStockForfait(int forfaitId, int prix) {
    _verifierPrix(prix);
    return db.update('tickets', {'prix': prix},
        where: 'forfait_id = ? AND vendu = 0', whereArgs: [forfaitId]);
  }

  /// Nombre de tickets non vendus d'un forfait (défectueux compris).
  Future<int> stockForfait(int forfaitId) async {
    final r = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM tickets WHERE forfait_id = ? AND vendu = 0',
        [forfaitId]);
    return (r.first['n'] as int?) ?? 0;
  }

  /// Prix des tickets non vendus d'un lot : le prix commun, ou null s'ils
  /// diffèrent (ou s'il n'en reste aucun).
  Future<int?> prixDuLot(int lotId) async {
    final r = await db.rawQuery(
        'SELECT MIN(prix) AS mini, MAX(prix) AS maxi FROM tickets WHERE lot_id = ? AND vendu = 0',
        [lotId]);
    final mini = r.first['mini'] as int?;
    final maxi = r.first['maxi'] as int?;
    return (mini != null && mini == maxi) ? mini : null;
  }

  static void _verifierPrix(int prix) {
    if (prix < 0) throw ArgumentError('Le prix ne peut pas être négatif.');
  }

  /// Crédits pas encore payés sur les tickets d'un lot (avant de le supprimer).
  Future<int> aRecevoirDuLot(int lotId) async {
    final r = await db.rawQuery('''
      SELECT COALESCE(SUM(prix), 0) AS total FROM tickets
      WHERE lot_id = ? AND vendu = 1 AND paiement = 'credit' AND paye_le IS NULL''',
        [lotId]);
    return (r.first['total'] as int?) ?? 0;
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

    /// Prix de chaque ticket de ce lot ; par défaut, le prix du forfait.
    int? prix,
  }) {
    final prixTicket = prix ?? forfait.prix;
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
          'prix': prixTicket,
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

  /// Ajoute des tickets à un lot existant (saisie manuelle). Les codes déjà
  /// présents dans l'application sont ignorés. Ils prennent le prix du forfait
  /// du lot et se placent après les tickets existants.
  Future<ImportResult> ajouterTickets(int lotId, List<ParsedTicket> tickets,
      {int? prix}) {
    return db.transaction((txn) async {
      final lots = await txn.query('lots', where: 'id = ?', whereArgs: [lotId]);
      if (lots.isEmpty) {
        throw StateError('Lot introuvable : $lotId');
      }
      final forfaitId = lots.first['forfait_id'] as int;
      final forfaits =
          await txn.query('forfaits', where: 'id = ?', whereArgs: [forfaitId]);
      // Prix donné, sinon celui des tickets déjà dans le lot, sinon le prix du forfait.
      final dernier = await txn.query('tickets',
          columns: ['prix'],
          where: 'lot_id = ?',
          whereArgs: [lotId],
          orderBy: 'position DESC, id DESC',
          limit: 1);
      final prixTicket = prix ??
          (dernier.isNotEmpty
              ? dernier.first['prix'] as int
              : forfaits.first['prix'] as int);

      final existants = <String>{
        for (final r in await txn.query('tickets', columns: ['code']))
          r['code'] as String,
      };
      final pos = await txn.rawQuery(
          'SELECT COALESCE(MAX(position), -1) AS m FROM tickets WHERE lot_id = ?',
          [lotId]);
      var position = (pos.first['m'] as int) + 1;

      var inseres = 0;
      var doublons = 0;
      for (final t in tickets) {
        if (!existants.add(t.code)) {
          doublons++;
          continue;
        }
        await txn.insert('tickets', {
          'lot_id': lotId,
          'position': position++,
          'numero': t.numero,
          'code': t.code,
          'mot_de_passe': t.motDePasse,
          'qr_texte': t.qrTexte,
          'prix': prixTicket,
          'forfait_id': forfaitId,
          'vendu': 0,
        });
        inseres++;
      }
      return ImportResult(lotId: lotId, inseres: inseres, doublons: doublons);
    });
  }

  // ----------------------------------------------------------------- tickets

  Future<Ticket?> prochainTicket(int lotId) async {
    final r = await db.query('tickets',
        where: 'lot_id = ? AND vendu = 0 AND defectueux = 0',
        whereArgs: [lotId],
        orderBy: 'position ASC, id ASC',
        limit: 1);
    if (r.isEmpty) return null;
    return Ticket.fromMap(r.first);
  }

  /// Les forfaits qui ont des tickets, classés par durée, avec leur stock.
  /// Un forfait désactivé n'apparaît que s'il lui reste des tickets.
  Future<List<ProfilStock>> profils() async {
    final r = await db.rawQuery('''
      SELECT f.*,
        COUNT(t.id) AS total,
        COALESCE(SUM(CASE WHEN t.vendu = 1 THEN 1 ELSE 0 END), 0) AS vendus,
        COALESCE(SUM(CASE WHEN t.vendu = 0 AND t.defectueux = 1 THEN 1 ELSE 0 END), 0) AS defectueux,
        COALESCE(SUM(CASE WHEN t.vendu = 1 AND ${encaisse('t.')} THEN t.prix ELSE 0 END), 0) AS montant
      FROM forfaits f JOIN tickets t ON t.forfait_id = f.id
      GROUP BY f.id
      ORDER BY f.duree_minutes ASC, f.id ASC''');
    final liste = [
      for (final m in r)
        ProfilStock(
          forfait: Forfait.fromMap(m),
          total: m['total'] as int,
          vendus: m['vendus'] as int,
          defectueux: m['defectueux'] as int,
          montant: m['montant'] as int,
        ),
    ];
    return liste.where((p) => p.forfait.actif || p.restants > 0).toList();
  }

  /// Prochain ticket à vendre pour un forfait. On prend d'abord dans le lot
  /// préféré ([lotPrefereId], s'il est de ce forfait et qu'il lui reste des
  /// tickets), sinon dans le lot le plus ancien.
  Future<Ticket?> prochainTicketForfait(int forfaitId,
      {int? lotPrefereId}) async {
    if (lotPrefereId != null) {
      final r = await db.rawQuery('''
        SELECT t.* FROM tickets t
        WHERE t.lot_id = ? AND t.forfait_id = ? AND t.vendu = 0 AND t.defectueux = 0
        ORDER BY t.position ASC, t.id ASC LIMIT 1''', [lotPrefereId, forfaitId]);
      if (r.isNotEmpty) return Ticket.fromMap(r.first);
    }
    final r = await db.rawQuery('''
      SELECT t.* FROM tickets t JOIN lots l ON l.id = t.lot_id
      WHERE t.forfait_id = ? AND t.vendu = 0 AND t.defectueux = 0
      ORDER BY l.cree_le ASC, l.id ASC, t.position ASC, t.id ASC LIMIT 1''',
        [forfaitId]);
    return r.isEmpty ? null : Ticket.fromMap(r.first);
  }

  /// Dernier ticket vendu, tous forfaits confondus (pour « Annuler »).
  Future<Ticket?> dernierVenduGlobal() async {
    final r = await db.query('tickets',
        where: 'vendu = 1', orderBy: 'vendu_le DESC, id DESC', limit: 1);
    return r.isEmpty ? null : Ticket.fromMap(r.first);
  }

  /// Annule la dernière vente, tous forfaits confondus.
  Future<Ticket?> annulerDerniereVenteGlobale() async {
    final t = await dernierVenduGlobal();
    if (t == null) return null;
    await remettreEnStock(t.id);
    return t;
  }

  /// Tickets vendus et argent encaissé entre [debut] (inclus) et [fin]
  /// (exclue), tous forfaits confondus.
  Future<({int vendus, int montant})> statsPeriode(
      DateTime debut, DateTime fin) async {
    final r = await db.rawQuery('''
      SELECT COUNT(*) AS vendus,
             COALESCE(SUM(CASE WHEN ${encaisse()} THEN prix ELSE 0 END), 0) AS montant
      FROM tickets WHERE vendu = 1 AND vendu_le >= ? AND vendu_le < ?''', [
      debut.millisecondsSinceEpoch,
      fin.millisecondsSinceEpoch,
    ]);
    return (
      vendus: (r.first['vendus'] as int?) ?? 0,
      montant: (r.first['montant'] as int?) ?? 0,
    );
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
             COALESCE(SUM(CASE WHEN vendu = 0 AND defectueux = 1 THEN 1 ELSE 0 END), 0) AS defectueux,
             COALESCE(SUM(CASE WHEN vendu = 1 AND ${encaisse()} THEN prix ELSE 0 END), 0) AS montant
      FROM tickets WHERE lot_id = ?''', [lotId]);
    final m = r.first;
    return LotStats(
      total: (m['total'] as int?) ?? 0,
      vendus: (m['vendus'] as int?) ?? 0,
      defectueux: (m['defectueux'] as int?) ?? 0,
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

  /// Marque un ticket comme vendu. Retourne faux s'il l'était déjà, ou s'il
  /// est signalé défectueux.
  ///
  /// [paiement] : espèces par défaut. Une vente à crédit exige un [clientId].
  ///
  /// [devise] : francs par défaut. Pour un paiement en dollars, [taux] est le
  /// nombre de francs pour 1 dollar ; le montant reçu en dollars est calculé
  /// et enregistré avec le taux, pour que les rapports restent justes même si
  /// le taux change plus tard. Le dollar n'est possible qu'en espèces ou mobile
  /// money (pas pour un crédit, ni un ticket offert).
  Future<bool> vendre(
    int ticketId, {
    String paiement = Paiement.especes,
    int? clientId,
    int? vendeurId,
    String devise = Devise.cdf,
    int? taux,
  }) async {
    if (!Paiement.tous.contains(paiement)) {
      throw ArgumentError('Mode de paiement inconnu : $paiement');
    }
    if (paiement == Paiement.credit && clientId == null) {
      throw ArgumentError('Une vente à crédit exige un client.');
    }
    if (devise != Devise.cdf && devise != Devise.usd) {
      throw ArgumentError('Devise inconnue : $devise');
    }
    if (devise == Devise.usd) {
      if (taux == null || taux <= 0) {
        throw ArgumentError('Un paiement en dollars exige un taux.');
      }
      if (paiement != Paiement.especes && paiement != Paiement.mobile) {
        throw ArgumentError('Le dollar est possible en espèces ou mobile money.');
      }
    }
    return db.transaction((txn) async {
      final r = await txn.query('tickets',
          columns: ['prix'], where: 'id = ?', whereArgs: [ticketId], limit: 1);
      if (r.isEmpty) return false;
      final prix = r.first['prix'] as int;
      final n = await txn.update(
        'tickets',
        {
          'vendu': 1,
          'vendu_le': DateTime.now().millisecondsSinceEpoch,
          'paiement': paiement,
          'client_id': paiement == Paiement.credit ? clientId : null,
          'paye_le': null,
          'vendeur_id': vendeurId,
          'devise': devise,
          'taux': devise == Devise.usd ? taux : null,
          'montant_devise':
              devise == Devise.usd ? Devise.centimesDollar(prix, taux!) : null,
        },
        where: 'id = ? AND vendu = 0 AND defectueux = 0',
        whereArgs: [ticketId],
      );
      return n > 0;
    });
  }

  /// Remet un ticket en stock (annule la vente : paiement, client et vendeur
  /// sont effacés, une dette éventuelle disparaît).
  Future<void> remettreEnStock(int ticketId) async {
    await db.update(
        'tickets',
        {
          'vendu': 0,
          'vendu_le': null,
          'paiement': Paiement.especes,
          'client_id': null,
          'paye_le': null,
          'vendeur_id': null,
          'devise': Devise.cdf,
          'taux': null,
          'montant_devise': null,
        },
        where: 'id = ?',
        whereArgs: [ticketId]);
  }

  /// Signale un ticket non vendu comme défectueux : il n'est plus proposé et
  /// n'est plus compté dans les restants. Retourne faux s'il est déjà vendu.
  Future<bool> signalerDefectueux(int ticketId) async {
    final n = await db.update('tickets', {'defectueux': 1},
        where: 'id = ? AND vendu = 0', whereArgs: [ticketId]);
    return n > 0;
  }

  /// Annule le signalement : le ticket peut de nouveau être vendu.
  Future<void> reactiverTicket(int ticketId) async {
    await db.update('tickets', {'defectueux': 0},
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
      SELECT t.code, t.prix, t.vendu_le, t.paiement, t.paye_le,
             t.devise, t.montant_devise,
             f.nom AS forfait_nom, l.nom AS lot_nom,
             v.nom AS vendeur_nom, c.nom AS client_nom
      FROM tickets t
      JOIN forfaits f ON f.id = t.forfait_id
      JOIN lots l ON l.id = t.lot_id
      LEFT JOIN vendeurs v ON v.id = t.vendeur_id
      LEFT JOIN clients c ON c.id = t.client_id
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
              paiement: (m['paiement'] as String?) ?? Paiement.especes,
              vendeurNom: m['vendeur_nom'] as String?,
              clientNom: m['client_nom'] as String?,
              devise: (m['devise'] as String?) ?? Devise.cdf,
              montantDevise: m['montant_devise'] as int?,
              payeLe: m['paye_le'] == null
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(m['paye_le'] as int),
            ))
        .toList();
  }

  // ----------------------------------------------------------------- clients

  Future<List<Client>> clients() async {
    final r = await db.query('clients', orderBy: 'nom COLLATE NOCASE');
    return r.map(Client.fromMap).toList();
  }

  Future<int> ajouterClient(String nom, {String? telephone}) {
    final tel = telephone?.trim();
    return db.insert('clients', {
      'nom': nom.trim(),
      'telephone': (tel == null || tel.isEmpty) ? null : tel,
      'cree_le': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Tickets vendus à crédit et pas encore payés, du plus ancien au plus récent.
  Future<List<DetteLigne>> dettes() async {
    final r = await db.rawQuery('''
      SELECT t.id AS ticket_id, t.code, t.prix, t.vendu_le,
             c.id AS client_id, c.nom AS client_nom, c.telephone
      FROM tickets t JOIN clients c ON c.id = t.client_id
      WHERE t.vendu = 1 AND t.paiement = 'credit' AND t.paye_le IS NULL
      ORDER BY c.nom COLLATE NOCASE, t.vendu_le''');
    return r
        .map((m) => DetteLigne(
              ticketId: m['ticket_id'] as int,
              code: m['code'] as String,
              prix: m['prix'] as int,
              venduLe:
                  DateTime.fromMillisecondsSinceEpoch(m['vendu_le'] as int),
              clientId: m['client_id'] as int,
              clientNom: m['client_nom'] as String,
              clientTelephone: m['telephone'] as String?,
            ))
        .toList();
  }

  /// Enregistre le paiement d'un ticket vendu à crédit.
  Future<void> marquerPaye(int ticketId) async {
    await db.update('tickets',
        {'paye_le': DateTime.now().millisecondsSinceEpoch},
        where: "id = ? AND paiement = 'credit' AND paye_le IS NULL",
        whereArgs: [ticketId]);
  }

  /// Le client a tout payé : solde toutes ses dettes.
  Future<void> marquerClientPaye(int clientId) async {
    await db.update('tickets',
        {'paye_le': DateTime.now().millisecondsSinceEpoch},
        where: "client_id = ? AND paiement = 'credit' AND paye_le IS NULL",
        whereArgs: [clientId]);
  }

  // ---------------------------------------------------------------- vendeurs

  static const String cleVendeurActif = 'vendeur_actif';

  Future<List<Vendeur>> vendeurs({bool seulementActifs = false}) async {
    final r = await db.query('vendeurs',
        where: seulementActifs ? 'actif = 1' : null,
        orderBy: 'nom COLLATE NOCASE');
    return r.map(Vendeur.fromMap).toList();
  }

  Future<int> ajouterVendeur(String nom) =>
      db.insert('vendeurs', {'nom': nom.trim(), 'actif': 1});

  Future<void> modifierVendeur(int id, {String? nom, bool? actif}) async {
    final v = <String, Object?>{};
    if (nom != null) v['nom'] = nom.trim();
    if (actif != null) v['actif'] = actif ? 1 : 0;
    if (v.isEmpty) return;
    await db.update('vendeurs', v, where: 'id = ?', whereArgs: [id]);
  }

  /// Définit (ou, avec null, retire) le code personnel d'un vendeur. Le code
  /// n'est jamais stocké en clair.
  Future<void> definirPinVendeur(int id, String? pin) async {
    if (pin == null) {
      await db.update('vendeurs', {'pin_sel': null, 'pin_hash': null},
          where: 'id = ?', whereArgs: [id]);
      return;
    }
    final sel = PinHash.nouveauSel();
    await db.update(
        'vendeurs', {'pin_sel': sel, 'pin_hash': PinHash.hacher(sel, pin)},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Vrai si [pin] est le code du vendeur. Faux s'il n'en a pas.
  Future<bool> verifierPinVendeur(int id, String pin) async {
    final r = await db.query('vendeurs',
        columns: ['pin_sel', 'pin_hash'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1);
    if (r.isEmpty) return false;
    final sel = r.first['pin_sel'] as String?;
    final hash = r.first['pin_hash'] as String?;
    if (sel == null || hash == null) return false;
    return PinHash.hacher(sel, pin) == hash;
  }

  /// Si le vendeur actif a un code, on l'oublie (à chaque verrouillage de
  /// l'application) : il faudra ressaisir son code pour vendre en son nom.
  Future<void> oublierVendeurActifProtege() async {
    final id = int.tryParse(await getSetting(cleVendeurActif) ?? '');
    if (id == null) return;
    final r = await db.query('vendeurs',
        columns: ['pin_hash'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (r.isNotEmpty && r.first['pin_hash'] != null) {
      await removeSetting(cleVendeurActif);
    }
  }

  /// Francs congolais pour 1 dollar, ou 0 si le dollar n'est pas activé.
  Future<int> tauxDollar() async =>
      int.tryParse(await getSetting(cleTauxDollar) ?? '') ?? 0;

  /// Vendeur choisi sur ce téléphone, ou null (ventes sans vendeur).
  Future<int?> vendeurActifId() async {
    final id = int.tryParse(await getSetting(cleVendeurActif) ?? '');
    if (id == null) return null;
    final r = await db.query('vendeurs',
        where: 'id = ? AND actif = 1', whereArgs: [id], limit: 1);
    return r.isEmpty ? null : id;
  }

  Future<void> definirVendeurActif(int? id) async {
    if (id == null) {
      await removeSetting(cleVendeurActif);
    } else {
      await setSetting(cleVendeurActif, '$id');
    }
  }
}
