import 'dart:typed_data';

/// Réglage : alerte de stock bas (nombre de tickets restants, tous lots
/// confondus). 0 = pas d'alerte.
const String cleSeuilStock = 'seuil_stock';
const int seuilStockParDefaut = 20;

/// Délai (en jours) après lequel un ticket vendu à crédit et non payé est en retard.
const String cleDelaiDette = 'delai_dette_jours';
const int delaiDetteParDefaut = 7;

/// Réglage : francs congolais pour 1 dollar. 0 ou absent : paiement en dollars
/// désactivé (tout se passe en francs).
const String cleTauxDollar = 'taux_dollar';

/// Devises de paiement.
class Devise {
  static const String cdf = 'CDF';
  static const String usd = 'USD';

  /// Montant en dollars (centimes) pour un prix en francs, au [taux] donné.
  /// Arrondi au centime.
  static int centimesDollar(int prixCdf, int taux) =>
      taux <= 0 ? 0 : ((prixCdf * 100) / taux).round();

  /// « 2,50 USD ».
  static String formaterDollar(int centimes) {
    final negatif = centimes < 0;
    final c = centimes.abs();
    final entier = c ~/ 100;
    final reste = (c % 100).toString().padLeft(2, '0');
    return '${negatif ? '-' : ''}$entier,$reste USD';
  }
}

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
  final String source; // 'mikhmon' | 'texte' | 'excel'
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
    this.devise = Devise.cdf,
    this.taux,
    this.montantDevise,
    this.utiliseLe,
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

  /// Devise reçue ; pour le dollar : taux (francs pour 1 dollar) et montant
  /// reçu en centimes de dollar.
  final String devise;
  final int? taux;
  final int? montantDevise;

  /// Date d'utilisation sur le réseau, lue dans l'export Excel du routeur.
  final DateTime? utiliseLe;

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
        devise: (m['devise'] as String?) ?? Devise.cdf,
        taux: m['taux'] as int?,
        montantDevise: m['montant_devise'] as int?,
        utiliseLe: m['utilise_le'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['utilise_le'] as int),
      );
}

/// Un forfait (profil de ticket : 1 h, 24 h, 1 semaine…) avec l'état de son
/// stock, tous lots confondus. C'est ce que l'écran de vente propose de choisir.
class ProfilStock {
  const ProfilStock({
    required this.forfait,
    required this.total,
    required this.vendus,
    required this.defectueux,
    required this.montant,
  });
  final Forfait forfait;

  /// Tickets importés pour ce forfait, vendus, et signalés défectueux (non vendus).
  final int total;
  final int vendus;
  final int defectueux;

  /// Argent encaissé sur les ventes de ce forfait.
  final int montant;

  int get restants => total - vendus - defectueux;
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
  const Vendeur({
    required this.id,
    required this.nom,
    required this.actif,
    this.aUnCode = false,
  });
  final int id;
  final String nom;
  final bool actif;

  /// Vrai si le vendeur a un code personnel (demandé pour vendre en son nom).
  final bool aUnCode;

  factory Vendeur.fromMap(Map<String, Object?> m) => Vendeur(
        id: m['id'] as int,
        nom: m['nom'] as String,
        actif: (m['actif'] as int) == 1,
        aUnCode: m['pin_hash'] != null,
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
    this.devise = Devise.cdf,
    this.montantDevise,
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

  /// Devise reçue et, pour le dollar, montant reçu en centimes.
  final String devise;
  final int? montantDevise;

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

/// Un ticket trouvé par la recherche, avec ce qu'il faut pour l'afficher.
class TicketRecherche {
  TicketRecherche({
    required this.ticket,
    required this.forfaitNom,
    required this.lotNom,
    this.clientNom,
    this.clientTelephone,
    this.vendeurNom,
  });
  final Ticket ticket;
  final String forfaitNom;
  final String lotNom;
  final String? clientNom;
  final String? clientTelephone;
  final String? vendeurNom;
}

/// Résultat de la comparaison avec l'export Excel du routeur.
class RapportUtilisation {
  RapportUtilisation({
    required this.marques,
    required this.vendusNonUtilises,
    required this.utilisesNonVendus,
    required this.inconnus,
  });

  /// Tickets nouvellement marqués « utilisés ».
  final int marques;

  /// Vendus, mais jamais utilisés par le client (d'après le routeur).
  final List<Ticket> vendusNonUtilises;

  /// Utilisés sur le réseau alors qu'ils sont encore en stock (non vendus).
  final List<Ticket> utilisesNonVendus;

  /// Codes du fichier absents de l'application.
  final int inconnus;
}

/// Une clôture de caisse enregistrée.
class Cloture {
  Cloture({
    required this.id,
    required this.jour,
    this.vendeurId,
    this.vendeurNom,
    required this.attenduCdf,
    required this.compteCdf,
    required this.attenduUsd,
    required this.compteUsd,
    this.note,
    required this.creeLe,
  });
  final int id;
  final String jour; // AAAA-MM-JJ
  final int? vendeurId;
  final String? vendeurNom;
  final int attenduCdf;
  final int compteCdf;

  /// Dollars, en centimes.
  final int attenduUsd;
  final int compteUsd;
  final String? note;
  final DateTime creeLe;

  int get ecartCdf => compteCdf - attenduCdf;
  int get ecartUsd => compteUsd - attenduUsd;
}
