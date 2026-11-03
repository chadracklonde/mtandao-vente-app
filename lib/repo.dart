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

  /// Dernière vente (un ou plusieurs tickets vendus ensemble).
  Future<List<Ticket>> derniereVente() async {
    final dernier = await dernierVenduGlobal();
    if (dernier == null || dernier.venduLe == null) return const [];
    final r = await db.query('tickets',
        where: 'vendu = 1 AND vendu_le = ?',
        whereArgs: [dernier.venduLe!.millisecondsSinceEpoch],
        orderBy: 'id ASC');
    return r.map(Ticket.fromMap).toList();
  }

  /// Annule la dernière vente, tous forfaits confondus (tous les tickets
  /// vendus ensemble). Retourne le dernier ticket vendu, ou null.
  Future<Ticket?> annulerDerniereVenteGlobale() async {
    final dernier = await dernierVenduGlobal();
    final groupe = await derniereVente();
    for (final t in groupe) {
      await remettreEnStock(t.id);
    }
    return dernier;
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
  /// [paiement] : espèces par défaut. Une vente à crédit exige un [clientId] ;
  /// pour les autres paiements, le client est facultatif (simple nom noté).
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
    _verifierVente(paiement, clientId, devise, taux);
    final maintenant = DateTime.now().millisecondsSinceEpoch;
    return db.transaction((txn) => _vendreDans(txn, ticketId,
        paiement: paiement,
        clientId: clientId,
        vendeurId: vendeurId,
        devise: devise,
        taux: taux,
        venduLe: maintenant));
  }

  void _verifierVente(String paiement, int? clientId, String devise, int? taux) {
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
  }

  Future<bool> _vendreDans(
    Transaction txn,
    int ticketId, {
    required String paiement,
    required int? clientId,
    required int? vendeurId,
    required String devise,
    required int? taux,
    required int venduLe,
  }) async {
    final r = await txn.query('tickets',
        columns: ['prix'], where: 'id = ?', whereArgs: [ticketId], limit: 1);
    if (r.isEmpty) return false;
    final prix = r.first['prix'] as int;
    final n = await txn.update(
      'tickets',
      {
        'vendu': 1,
        'vendu_le': venduLe,
        'paiement': paiement,
        'client_id': clientId,
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
  }

  /// Les [n] prochains tickets à vendre pour un forfait, dans l'ordre de vente
  /// (lot préféré d'abord, puis lots du plus ancien au plus récent).
  Future<List<Ticket>> prochainsTicketsForfait(int forfaitId, int n,
      {int? lotPrefereId}) async {
    final r = await db.rawQuery('''
      SELECT t.* FROM tickets t JOIN lots l ON l.id = t.lot_id
      WHERE t.forfait_id = ? AND t.vendu = 0 AND t.defectueux = 0
      ORDER BY (t.lot_id = ?) DESC, l.cree_le ASC, l.id ASC, t.position ASC, t.id ASC
      LIMIT ?''', [forfaitId, lotPrefereId ?? -1, n]);
    return r.map(Ticket.fromMap).toList();
  }

  /// Vend d'un coup les [quantite] prochains tickets d'un forfait (même
  /// client, même paiement). Tout ou rien : liste vide s'il n'y en a pas assez.
  /// Les tickets partagent la même heure de vente, ce qui permet de les annuler
  /// ensemble.
  Future<List<Ticket>> vendreQuantite(
    int forfaitId,
    int quantite, {
    int? lotPrefereId,
    String paiement = Paiement.especes,
    int? clientId,
    int? vendeurId,
    String devise = Devise.cdf,
    int? taux,
  }) async {
    if (quantite < 1) throw ArgumentError('La quantité doit être au moins 1.');
    _verifierVente(paiement, clientId, devise, taux);
    final maintenant = DateTime.now().millisecondsSinceEpoch;
    return db.transaction((txn) async {
      final r = await txn.rawQuery('''
        SELECT t.id FROM tickets t JOIN lots l ON l.id = t.lot_id
        WHERE t.forfait_id = ? AND t.vendu = 0 AND t.defectueux = 0
        ORDER BY (t.lot_id = ?) DESC, l.cree_le ASC, l.id ASC, t.position ASC, t.id ASC
        LIMIT ?''', [forfaitId, lotPrefereId ?? -1, quantite]);
      final ids = [for (final m in r) m['id'] as int];
      if (ids.length < quantite) return <Ticket>[];
      for (final id in ids) {
        final ok = await _vendreDans(txn, id,
            paiement: paiement,
            clientId: clientId,
            vendeurId: vendeurId,
            devise: devise,
            taux: taux,
            venduLe: maintenant);
        if (!ok) return <Ticket>[];
      }
      final lignes =
          await txn.query('tickets', where: 'id IN (${ids.join(',')})');
      final parId = {for (final m in lignes) m['id'] as int: Ticket.fromMap(m)};
      return [for (final id in ids) parId[id]!];
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

  // ------------------------------------------------------------- recherche

  /// Cherche des tickets par code, nom ou téléphone du client, ou vendeur.
  /// Sans texte : les ventes les plus récentes.
  Future<List<TicketRecherche>> rechercher(String texte, {int limite = 100}) async {
    final q = texte.trim();
    final args = <Object?>[];
    var where = 't.vendu = 1';
    if (q.isNotEmpty) {
      final motif = '%${q.replaceAll('%', '').replaceAll('_', '')}%';
      where = '(t.code LIKE ? OR c.nom LIKE ? OR c.telephone LIKE ? OR v.nom LIKE ?)';
      args.addAll([motif, motif, motif, motif]);
    }
    final r = await db.rawQuery('''
      SELECT t.*, f.nom AS forfait_nom, l.nom AS lot_nom,
             c.nom AS client_nom, c.telephone AS client_tel, v.nom AS vendeur_nom
      FROM tickets t
      JOIN forfaits f ON f.id = t.forfait_id
      JOIN lots l ON l.id = t.lot_id
      LEFT JOIN clients c ON c.id = t.client_id
      LEFT JOIN vendeurs v ON v.id = t.vendeur_id
      WHERE $where
      ORDER BY t.vendu DESC, t.vendu_le DESC, t.id DESC
      LIMIT ?''', [...args, limite]);
    return [
      for (final m in r)
        TicketRecherche(
          ticket: Ticket.fromMap(m),
          forfaitNom: m['forfait_nom'] as String,
          lotNom: m['lot_nom'] as String,
          clientNom: m['client_nom'] as String?,
          clientTelephone: m['client_tel'] as String?,
          vendeurNom: m['vendeur_nom'] as String?,
        ),
    ];
  }

  // ------------------------------------------------------ suivi d'utilisation

  /// Compare l'export du routeur à nos tickets : marque ceux qui ont été
  /// utilisés, et repère les écarts (vendus jamais utilisés ; utilisés sans
  /// avoir été vendus). [utilises] : codes déjà consommés ; [disponibles] :
  /// codes que le routeur dit encore inutilisés.
  Future<RapportUtilisation> appliquerUtilisation({
    required Set<String> utilises,
    required Set<String> disponibles,
  }) async {
    final maintenant = DateTime.now().millisecondsSinceEpoch;
    Future<List<Ticket>> trouver(Set<String> codes) async {
      final liste = codes.toList();
      final res = <Ticket>[];
      for (var i = 0; i < liste.length; i += 400) {
        final lot = liste.sublist(i, i + 400 > liste.length ? liste.length : i + 400);
        final r = await db.query('tickets',
            where: 'code IN (${List.filled(lot.length, '?').join(',')})',
            whereArgs: lot);
        res.addAll(r.map(Ticket.fromMap));
      }
      return res;
    }

    final tUtilises = await trouver(utilises);
    final tDispos = await trouver(disponibles);
    var marques = 0;
    final nonVendus = <Ticket>[];
    await db.transaction((txn) async {
      for (final t in tUtilises) {
        if (t.utiliseLe == null) {
          await txn.update('tickets', {'utilise_le': maintenant},
              where: 'id = ?', whereArgs: [t.id]);
          marques++;
        }
        if (!t.vendu && !t.defectueux) nonVendus.add(t);
      }
    });
    final connus = {for (final t in [...tUtilises, ...tDispos]) t.code};
    return RapportUtilisation(
      marques: marques,
      vendusNonUtilises: [
        for (final t in tDispos)
          if (t.vendu && t.utiliseLe == null) t,
      ],
      utilisesNonVendus: nonVendus,
      inconnus: {...utilises, ...disponibles}.difference(connus).length,
    );
  }

  // ------------------------------------------------------ clôture de caisse

  static String jourTexte(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Argent liquide attendu en caisse pour un jour (et un vendeur, ou tous) :
  /// espèces en francs, espèces en dollars (centimes), et dettes payées ce
  /// jour-là. Le mobile money et les tickets offerts n'entrent pas en caisse.
  Future<({int especesCdf, int dettesCdf, int usd})> attenduCaisse(
      DateTime jour, {int? vendeurId}) async {
    final debut = DateTime(jour.year, jour.month, jour.day).millisecondsSinceEpoch;
    final fin = DateTime(jour.year, jour.month, jour.day + 1).millisecondsSinceEpoch;
    final v = vendeurId == null ? '' : ' AND vendeur_id = $vendeurId';
    final a = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN paiement = 'especes' AND devise = 'CDF' THEN prix ELSE 0 END), 0) AS cdf,
        COALESCE(SUM(CASE WHEN paiement = 'especes' AND devise = 'USD' THEN montant_devise ELSE 0 END), 0) AS usd
      FROM tickets WHERE vendu = 1 AND vendu_le >= ? AND vendu_le < ?$v''',
        [debut, fin]);
    final d = await db.rawQuery('''
      SELECT COALESCE(SUM(prix), 0) AS dettes FROM tickets
      WHERE vendu = 1 AND paiement = 'credit' AND paye_le >= ? AND paye_le < ?$v''',
        [debut, fin]);
    return (
      especesCdf: (a.first['cdf'] as int?) ?? 0,
      dettesCdf: (d.first['dettes'] as int?) ?? 0,
      usd: (a.first['usd'] as int?) ?? 0,
    );
  }

  Future<void> enregistrerCloture({
    required DateTime jour,
    int? vendeurId,
    required int attenduCdf,
    required int compteCdf,
    int attenduUsd = 0,
    int compteUsd = 0,
    String? note,
  }) async {
    final n = note?.trim();
    await db.insert('clotures', {
      'jour': jourTexte(jour),
      'vendeur_id': vendeurId,
      'attendu_cdf': attenduCdf,
      'compte_cdf': compteCdf,
      'attendu_usd': attenduUsd,
      'compte_usd': compteUsd,
      'note': (n == null || n.isEmpty) ? null : n,
      'cree_le': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Cloture>> clotures({int limite = 60}) async {
    final r = await db.rawQuery('''
      SELECT c.*, v.nom AS vendeur_nom FROM clotures c
      LEFT JOIN vendeurs v ON v.id = c.vendeur_id
      ORDER BY c.jour DESC, c.id DESC LIMIT ?''', [limite]);
    return [
      for (final m in r)
        Cloture(
          id: m['id'] as int,
          jour: m['jour'] as String,
          vendeurId: m['vendeur_id'] as int?,
          vendeurNom: m['vendeur_nom'] as String?,
          attenduCdf: m['attendu_cdf'] as int,
          compteCdf: m['compte_cdf'] as int,
          attenduUsd: (m['attendu_usd'] as int?) ?? 0,
          compteUsd: (m['compte_usd'] as int?) ?? 0,
          note: m['note'] as String?,
          creeLe: DateTime.fromMillisecondsSinceEpoch(m['cree_le'] as int),
        ),
    ];
  }

  Future<void> supprimerCloture(int id) =>
      db.delete('clotures', where: 'id = ?', whereArgs: [id]);

  // ------------------------------------------------------- dettes en retard

  /// Délai de paiement en jours (0 : pas de rappel de retard).
  Future<int> delaiDetteJours() async =>
      int.tryParse(await getSetting(cleDelaiDette) ?? '') ?? delaiDetteParDefaut;

  /// Une dette est en retard quand le ticket a été vendu il y a plus de
  /// [delai] jours (0 : jamais en retard).
  static bool detteEnRetard(DetteLigne d, int delai, DateTime maintenant) =>
      delai > 0 && maintenant.difference(d.venduLe).inDays >= delai;

  Future<List<DetteLigne>> dettesEnRetard() async {
    final delai = await delaiDetteJours();
    final maintenant = DateTime.now();
    return [
      for (final d in await dettes())
        if (detteEnRetard(d, delai, maintenant)) d,
    ];
  }
}
