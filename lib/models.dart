import 'dart:typed_data';

class Forfait {
  Forfait({
    required this.id,
    required this.nom,
    required this.dureeMinutes,
    required this.prix,
    required this.actif,
  });

  final int id;
  final String nom;
  final int dureeMinutes;
  final int prix;
  final bool actif;

  factory Forfait.fromMap(Map<String, Object?> m) => Forfait(
        id: m['id'] as int,
        nom: m['nom'] as String,
        dureeMinutes: m['duree_minutes'] as int,
        prix: m['prix'] as int,
        actif: (m['actif'] as int) == 1,
      );
}

class Lot {
  Lot({
    required this.id,
    required this.nom,
    required this.forfaitId,
    required this.forfaitNom,
    required this.source,
    required this.fichier,
    required this.loginUrl,
    required this.creeLe,
    required this.total,
    required this.vendus,
    required this.montant,
  });

  final int id;
  final String nom;
  final int forfaitId;
  final String forfaitNom;
  final String source; // 'mikhmon' | 'texte'
  final String? fichier;
  final String? loginUrl;
  final DateTime creeLe;
  final int total;
  final int vendus;
  final int montant;

  int get restants => total - vendus;

  factory Lot.fromMap(Map<String, Object?> m) => Lot(
        id: m['id'] as int,
        nom: m['nom'] as String,
        forfaitId: m['forfait_id'] as int,
        forfaitNom: (m['forfait_nom'] as String?) ?? '',
        source: m['source'] as String,
        fichier: m['fichier'] as String?,
        loginUrl: m['login_url'] as String?,
        creeLe: DateTime.fromMillisecondsSinceEpoch(m['cree_le'] as int),
        total: (m['total'] as int?) ?? 0,
        vendus: (m['vendus'] as int?) ?? 0,
        montant: (m['montant'] as int?) ?? 0,
      );
}

class Ticket {
  Ticket({
    required this.id,
    required this.lotId,
    required this.position,
    required this.numero,
    required this.code,
    required this.motDePasse,
    required this.qrTexte,
    required this.prix,
    required this.forfaitId,
    required this.vendu,
    required this.venduLe,
  });

  final int id;
  final int lotId;
  final int position;
  final int? numero;
  final String code;
  final String? motDePasse;
  final String? qrTexte;
  final int prix;
  final int forfaitId;
  final bool vendu;
  final DateTime? venduLe;

  /// Vrai si le mot de passe diffère du code (ticket « utilisateur + mot de passe »).
  bool get aMotDePasseDistinct =>
      motDePasse != null && motDePasse!.isNotEmpty && motDePasse != code;

  factory Ticket.fromMap(Map<String, Object?> m) => Ticket(
        id: m['id'] as int,
        lotId: m['lot_id'] as int,
        position: m['position'] as int,
        numero: m['numero'] as int?,
        code: m['code'] as String,
        motDePasse: m['mot_de_passe'] as String?,
        qrTexte: m['qr_texte'] as String?,
        prix: m['prix'] as int,
        forfaitId: m['forfait_id'] as int,
        vendu: (m['vendu'] as int) == 1,
        venduLe: m['vendu_le'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['vendu_le'] as int),
      );
}

class LotStats {
  const LotStats({required this.total, required this.vendus, required this.montant});
  final int total;
  final int vendus;
  final int montant;
  int get restants => total - vendus;
}

/// Ticket lu dans un PDF, avant insertion en base.
class ParsedTicket {
  ParsedTicket({
    required this.code,
    this.motDePasse,
    this.qrTexte,
    this.numero,
    this.image,
  });

  final String code;
  final String? motDePasse;
  final String? qrTexte;
  final int? numero;
  final Uint8List? image; // PNG de la case du ticket (modèle Mikhmon)
}

class ImportResult {
  const ImportResult({required this.lotId, required this.inseres, required this.doublons});
  final int? lotId;
  final int inseres;
  final int doublons;
}

/// Ligne de vente pour les rapports.
class VenteLigne {
  VenteLigne({
    required this.code,
    required this.prix,
    required this.venduLe,
    required this.forfaitNom,
    required this.lotNom,
  });

  final String code;
  final int prix;
  final DateTime venduLe;
  final String forfaitNom;
  final String lotNom;
}
