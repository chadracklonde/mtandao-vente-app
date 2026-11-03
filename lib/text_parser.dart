/// Lecture des PDF « Tickets Wi-Fi » en texte simple :
///   Code : 461232
///   Durée : 1jour(s)
/// (Fonctions pures, testables sans Flutter.)
class TexteTicket {
  const TexteTicket(this.code, this.dureeMinutes, {this.prix});
  final String code;
  final int? dureeMinutes;

  /// Prix lu dans le texte (en entier, sans monnaie), s'il y en a un.
  final int? prix;
}

class TextTicketParser {
  static final RegExp _code =
      RegExp(r'Code\s*:\s*([0-9A-Za-z_\-]+?)(?=\s|Dur|Code|$)');
  static final RegExp _duree = RegExp(r'Dur\S{1,3}\s*:\s*(\d+)\s*([A-Za-z]+)');
  static final RegExp _dureeEntete = RegExp(r'Dur\S{1,3}\s*:');

  /// « Prix : 1 000 CDF », « Price: 500 », « Tarif : 2.500 FC », « Montant : 1000 ».
  static final RegExp _prix = RegExp(
      r'(?:Prix|Price|Tarif|Montant)\s*:\s*([0-9][0-9 \u00a0\u202f.,]*[0-9]|[0-9])',
      caseSensitive: false);

  /// Convertit « 1 000 », « 1.000 », « 1,000 », « 1000 » ou « 1500,50 » en entier
  /// (les séparateurs de milliers sont ignorés ; une partie décimale de 1 ou
  /// 2 chiffres est arrondie). Retourne null si ce n'est pas un nombre.
  static int? entierDe(String texte) {
    final t = texte.trim().replaceAll(RegExp(r'[ \u00a0\u202f]'), '');
    if (t.isEmpty) return null;
    final decimal = RegExp(r'^(\d+)[.,](\d{1,2})$').firstMatch(t);
    if (decimal != null) {
      return double.parse('${decimal.group(1)}.${decimal.group(2)}').round();
    }
    final chiffres = t.replaceAll(RegExp(r'[.,]'), '');
    if (!RegExp(r'^\d+$').hasMatch(chiffres)) return null;
    return int.tryParse(chiffres);
  }

  /// Vrai si le texte ressemble au modèle « Code : … / Durée : … ».
  static bool ressembleAuModele(String texte) =>
      _code.hasMatch(texte) && _dureeEntete.hasMatch(texte);

  static int? _minutes(int n, String unite) {
    final u = unite.toLowerCase();
    if (u.startsWith('jour') || u == 'j' || u == 'd') return n * 1440;
    if (u.startsWith('heure') || u == 'h') return n * 60;
    if (u.startsWith('semaine')) return n * 10080;
    if (u.startsWith('mois')) return n * 43200;
    return null;
  }

  /// Durée écrite dans une cellule : « 1jour(s) », « 2 heures », « 1 mois »…
  static int? dureeDe(String texte) {
    final m = RegExp(r'(\d+)\s*([A-Za-zéû]+)').firstMatch(texte);
    if (m == null) return null;
    return _minutes(int.parse(m.group(1)!), m.group(2)!);
  }

  /// Extrait les tickets d'un texte (une ou plusieurs pages).
  static List<TexteTicket> parse(String texte) {
    final codes = _code.allMatches(texte).map((m) => m.group(1)!).toList();
    final durees = _duree
        .allMatches(texte)
        .map((m) => _minutes(int.parse(m.group(1)!), m.group(2)!))
        .toList();

    // Durée la plus fréquente, utilisée si l'appariement code/durée est impossible.
    int? commune;
    final compte = <int, int>{};
    for (final d in durees) {
      if (d != null) compte[d] = (compte[d] ?? 0) + 1;
    }
    var max = 0;
    compte.forEach((k, v) {
      if (v > max) {
        max = v;
        commune = k;
      }
    });

    // Prix : un par ticket si les nombres concordent, sinon le prix le plus
    // fréquent, sinon aucun.
    final prix = [
      for (final m in _prix.allMatches(texte)) entierDe(m.group(1)!),
    ].whereType<int>().toList();
    int? prixCommun;
    final comptePrix = <int, int>{};
    for (final p in prix) {
      comptePrix[p] = (comptePrix[p] ?? 0) + 1;
    }
    var maxPrix = 0;
    comptePrix.forEach((k, v) {
      if (v > maxPrix) {
        maxPrix = v;
        prixCommun = k;
      }
    });

    final memeNombre = codes.length == durees.length;
    final memePrix = codes.length == prix.length;
    final res = <TexteTicket>[];
    for (var i = 0; i < codes.length; i++) {
      res.add(TexteTicket(codes[i], memeNombre ? durees[i] : commune,
          prix: memePrix ? prix[i] : prixCommun));
    }
    return res;
  }

  /// Prix commun à tous les tickets, ou null s'il diffère ou est inconnu.
  static int? prixCommun(List<TexteTicket> tickets) {
    final set = tickets.map((t) => t.prix).toSet();
    return set.length == 1 ? set.first : null;
  }

  /// Durée commune à tous les tickets, ou null si elles diffèrent / sont inconnues.
  static int? dureeCommune(List<TexteTicket> tickets) {
    final set = tickets.map((t) => t.dureeMinutes).toSet();
    if (set.length == 1) return set.first;
    return null;
  }
}
