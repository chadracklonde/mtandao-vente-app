import 'models.dart';

/// Résultat de la lecture de codes saisis à la main.
class CodesSaisis {
  const CodesSaisis({
    required this.tickets,
    required this.lignesRejetees,
    required this.doublonsSaisis,
  });

  /// Tickets valides, dans l'ordre de saisie.
  final List<ParsedTicket> tickets;

  /// Numéros (à partir de 1) des lignes qu'on n'a pas pu lire.
  final List<int> lignesRejetees;

  /// Codes écrits plusieurs fois dans la saisie (un seul est gardé).
  final int doublonsSaisis;
}

/// Lecture de codes saisis ou collés, un ticket par ligne :
///   `461232`                  → code seul (mot de passe = code)
///   `abc123 xyz789`           → code puis mot de passe
/// Les séparateurs possibles sont l'espace, la tabulation, la virgule et le
/// point-virgule. (Fonctions pures, testables sans Flutter.)
class CodesManuels {
  static final RegExp _separateurs = RegExp(r'[\s;,]+');
  static final RegExp _valide = RegExp(r'^[0-9A-Za-z._@\-]{1,64}$');

  static CodesSaisis lire(String texte) {
    final tickets = <ParsedTicket>[];
    final rejetees = <int>[];
    final vus = <String>{};
    var doublons = 0;

    final lignes = texte.split(RegExp(r'\r\n|\r|\n'));
    for (var i = 0; i < lignes.length; i++) {
      final ligne = lignes[i].trim();
      if (ligne.isEmpty) continue;
      final morceaux =
          ligne.split(_separateurs).where((m) => m.isNotEmpty).toList();
      if (morceaux.isEmpty ||
          morceaux.length > 2 ||
          !morceaux.every(_valide.hasMatch)) {
        rejetees.add(i + 1);
        continue;
      }
      final code = morceaux.first;
      if (!vus.add(code)) {
        doublons++;
        continue;
      }
      tickets.add(ParsedTicket(
        code: code,
        motDePasse: morceaux.length == 2 ? morceaux[1] : null,
      ));
    }
    return CodesSaisis(
      tickets: tickets,
      lignesRejetees: rejetees,
      doublonsSaisis: doublons,
    );
  }
}
