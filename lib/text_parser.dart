/// Lecture des PDF « Tickets Wi-Fi » en texte simple :
///   Code : 461232
///   Durée : 1jour(s)
/// (Fonctions pures, testables sans Flutter.)
class TexteTicket {
  const TexteTicket(this.code, this.dureeMinutes);
  final String code;
  final int? dureeMinutes;
}

class TextTicketParser {
  static final RegExp _code =
      RegExp(r'Code\s*:\s*([0-9A-Za-z_\-]+?)(?=\s|Dur|Code|$)');
  static final RegExp _duree = RegExp(r'Dur\S{1,3}\s*:\s*(\d+)\s*([A-Za-z]+)');
  static final RegExp _dureeEntete = RegExp(r'Dur\S{1,3}\s*:');

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

    final memeNombre = codes.length == durees.length;
    final res = <TexteTicket>[];
    for (var i = 0; i < codes.length; i++) {
      res.add(TexteTicket(codes[i], memeNombre ? durees[i] : commune));
    }
    return res;
  }

  /// Durée commune à tous les tickets, ou null si elles diffèrent / sont inconnues.
  static int? dureeCommune(List<TexteTicket> tickets) {
    final set = tickets.map((t) => t.dureeMinutes).toSet();
    if (set.length == 1) return set.first;
    return null;
  }
}
