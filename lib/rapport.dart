import 'format.dart';
import 'models.dart';

/// Nombre de tickets et montant d'un groupe de ventes.
class Total {
  int nombre = 0;
  int montant = 0;
}

/// Chiffres d'une période de ventes (fonctions pures, testables sans Flutter).
///
/// Vocabulaire :
///  - « encaissé » : l'argent est réellement rentré (espèces, mobile money,
///    crédit déjà payé) ;
///  - « à recevoir » : vendu à crédit et pas encore payé ;
///  - « offerts » : tickets donnés, rien encaissé.
class Rapport {
  Rapport(this.ventes) {
    for (final v in ventes) {
      nombre++;
      encaisse += v.montantEncaisse;
      if (v.aRecevoir) aRecevoir += v.prix;
      if (v.paiement == Paiement.offert) offerts++;
      if (v.devise == Devise.usd && v.montantDevise != null) {
        ventesDollar++;
        dollarsRecus += v.montantDevise!;
      }

      _ajouter(parForfait, v.forfaitNom, v);
      _ajouter(parPaiement, v.paiement, v);
      _ajouter(parVendeur, v.vendeurNom ?? 'Sans vendeur', v);
      _ajouter(parJourBrut, debutJour(v.venduLe), v);

      parHeure[v.venduLe.hour]++;
    }
    final cles = parJourBrut.keys.toList()..sort((a, b) => b.compareTo(a));
    parJour = {for (final k in cles) k: parJourBrut[k]!};
  }

  final List<VenteLigne> ventes;

  /// Tickets vendus (tous modes de paiement).
  int nombre = 0;

  /// Argent réellement rentré.
  int encaisse = 0;

  /// Montant des crédits pas encore payés.
  int aRecevoir = 0;

  /// Tickets offerts.
  int offerts = 0;

  /// Tickets payés en dollars, et total reçu en dollars (en centimes). Ces
  /// ventes sont déjà comptées en francs dans [encaisse], au prix du ticket.
  int ventesDollar = 0;
  int dollarsRecus = 0;

  /// Par forfait : nombre de tickets et argent encaissé.
  final Map<String, Total> parForfait = {};

  /// Par mode de paiement : nombre de tickets et prix des tickets.
  final Map<String, Total> parPaiement = {};

  /// Par vendeur : nombre de tickets et argent encaissé.
  final Map<String, Total> parVendeur = {};

  final Map<DateTime, Total> parJourBrut = {};

  /// Par jour, du plus récent au plus ancien : tickets et argent encaissé.
  late final Map<DateTime, Total> parJour;

  /// Tickets vendus par heure de la journée (0 à 23).
  final List<int> parHeure = List<int>.filled(24, 0);

  /// Vrai si au moins une vente a un vendeur renseigné.
  bool get aDesVendeurs => ventes.any((v) => v.vendeurNom != null);

  /// Heure la plus chargée, ou null s'il n'y a aucune vente.
  int? get heureDePointe {
    var meilleure = -1;
    var max = 0;
    for (var h = 0; h < 24; h++) {
      if (parHeure[h] > max) {
        max = parHeure[h];
        meilleure = h;
      }
    }
    return meilleure < 0 ? null : meilleure;
  }

  static void _ajouter<K>(Map<K, Total> m, K cle, VenteLigne v) {
    final t = m.putIfAbsent(cle, Total.new);
    t.nombre++;
    t.montant += v.montantEncaisse;
  }

  /// Évolution en pourcentage par rapport à [precedent] (argent encaissé),
  /// ou null si la période précédente n'a rien encaissé.
  static int? evolution(int actuel, int precedent) {
    if (precedent <= 0) return null;
    return (((actuel - precedent) * 100) / precedent).round();
  }

  /// « 1 ticket », « 3 tickets ».
  static String tickets(int n) => '$n ticket${n > 1 ? 's' : ''}';

  /// Texte à partager (WhatsApp…).
  String texte(String titre, {required bool detailParJour}) {
    final l = <String>[
      'Rapport Mtandao',
      titre,
      '',
      'Tickets vendus : $nombre',
      'Montant encaissé : ${cdf(encaisse)}',
      if (aRecevoir > 0) 'À recevoir (crédits) : ${cdf(aRecevoir)}',
      if (offerts > 0) 'Tickets offerts : $offerts',
      if (ventesDollar > 0)
        'Dont payé en dollars : ${tickets(ventesDollar)}, ${Devise.formaterDollar(dollarsRecus)}',
    ];
    if (parForfait.length > 1) {
      l..add('')..add('Par forfait :');
      parForfait.forEach((nom, t) {
        l.add('- $nom : ${tickets(t.nombre)}, ${cdf(t.montant)}');
      });
    }
    if (aDesVendeurs) {
      l..add('')..add('Par vendeur :');
      parVendeur.forEach((nom, t) {
        l.add('- $nom : ${tickets(t.nombre)}, ${cdf(t.montant)}');
      });
    }
    if (detailParJour && parJour.isNotEmpty) {
      l..add('')..add('Par jour :');
      for (final e in parJour.entries) {
        l.add(
            '- ${fmtJourCourt(e.key)} : ${tickets(e.value.nombre)}, ${cdf(e.value.montant)}');
      }
    }
    return l.join('\n');
  }
}
