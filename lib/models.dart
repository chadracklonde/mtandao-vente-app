import 'dart:typed_data';

/// Modes de paiement d'une vente.
///  - espèces et mobile money : encaissé tout de suite ;
///  - crédit : vendu mais pas encore payé (une dette du client) ;
///  - offert : ticket donné, rien n'est encaissé.
class Paiement {
  static const String especes = 'especes';
  static const String mobile = 'mobile';
  static const String credit = 'credit';
  static const String offert = 'offert';

  static const List<String> tous = [especes, mobile, credit, offert];

  static String libelle(String p) {
    switch (p) {
      case mobile:
        return 'Mobile money';
      case credit:
        return 'À crédit';
      case offert:
        return 'Offert';
      default:
        return 'Espèces';
    }
  }
}

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
    this.defectueux = 0,
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

  /// Montant réellement encaissé (hors crédits non payés et tickets offerts).
  final int montant;

  /// Tickets non vendus signalés défectueux : ils ne sont plus proposés.
  final int defectueux;

  int get restants => total - vendus - defectueux;

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
        defectueux: (m['defectueux'] as int?) ?? 0,
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
    this.defectueux = false,
    this.paiement = Paiement.especes,
    this.clientId,
    this.payeLe,
    this.vendeurId,
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
  final bool defectueux;
  final String paiement;
  final int? clientId;
  final DateTime? payeLe;
  final int? vendeurId;

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
        defectueux: ((m['defectueux'] as int?) ?? 0) == 1,
        paiement: (m['paiement'] as String?) ?? Paiement.especes,
        clientId: m['client_id'] as int?,
        payeLe: m['paye_le'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['paye_le'] as int),
        vendeurId: m['vendeur_id'] as int?,
      );
}

class LotStats {
  const LotStats({
    required this.total,
    required this.vendus,
    required this.montant,
    this.defectueux = 0,
  });
  final int total;
  final int vendus;
  final int montant;
  final int defectueux;
  int get restants => total - vendus - defectueux;
}

class Client {
  const Client({required this.id, required this.nom, this.telephone});
  final int id;
  final String nom;
  final String? telephone;

  factory Client.fromMap(Map<String, Object?> m) => Client(
        id: m['id'] as int,
        nom: m['nom'] as String,
        telephone: m['telephone'] as String?,
      );
}

class Vendeur {
  const Vendeur({required this.id, required this.nom, required this.actif});
  final int id;
  final String nom;
  final bool actif;

  factory Vendeur.fromMap(Map<String, Object?> m) => Vendeur(
        id: m['id'] as int,
        nom: m['nom'] as String,
        actif: (m['actif'] as int) == 1,
      );
}

/// Un ticket vendu à crédit et pas encore payé.
class DetteLigne {
  const DetteLigne({
    required this.ticketId,
    required this.code,
    required this.prix,
    required this.venduLe,
    required this.clientId,
    required this.clientNom,
    this.clientTelephone,
  });
  final int ticketId;
  final String code;
  final int prix;
  final DateTime venduLe;
  final int clientId;
  final String clientNom;
  final String? clientTelephone;
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
    this.paiement = Paiement.especes,
    this.vendeurNom,
    this.clientNom,
    this.payeLe,
  });

  final String code;
  final int prix;
  final DateTime venduLe;
  final String forfaitNom;
  final String lotNom;
  final String paiement;
  final String? vendeurNom;
  final String? clientNom;
  final DateTime? payeLe;

  /// Vrai si l'argent est réellement rentré : espèces, mobile money, ou un
  /// crédit qui a été payé depuis.
  bool get encaisse =>
      paiement == Paiement.especes ||
      paiement == Paiement.mobile ||
      (paiement == Paiement.credit && payeLe != null);

  /// Vrai si le client doit encore payer ce ticket.
  bool get aRecevoir => paiement == Paiement.credit && payeLe == null;

  int get montantEncaisse => encaisse ? prix : 0;
}
