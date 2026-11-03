import 'models.dart';

/// Texte à envoyer au client (WhatsApp, SMS…) après une vente : le ou les
/// codes, le forfait et l'adresse de connexion.
String messageTickets({
  required List<Ticket> tickets,
  required String forfaitNom,
  required String url,
  String? clientNom,
}) {
  final nom = clientNom?.trim();
  final l = <String>[
    if (nom != null && nom.isNotEmpty) 'Bonjour $nom,',
    'Wi-Fi MTANDAO - ticket $forfaitNom',
  ];
  if (tickets.length == 1) {
    final t = tickets.first;
    l.add(t.aMotDePasseDistinct ? 'Utilisateur : ${t.code}' : 'Code : ${t.code}');
    if (t.aMotDePasseDistinct) l.add('Mot de passe : ${t.motDePasse}');
  } else {
    for (var i = 0; i < tickets.length; i++) {
      final t = tickets[i];
      l.add(t.aMotDePasseDistinct
          ? '${i + 1}) ${t.code} (mot de passe : ${t.motDePasse})'
          : '${i + 1}) ${t.code}');
    }
  }
  l.add('Connexion : $url');
  l.add('Merci !');
  return l.join('\n');
}
