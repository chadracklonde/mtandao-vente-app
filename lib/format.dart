import 'package:intl/intl.dart';

/// Entier avec espace insécable comme séparateur de milliers : 12 000.
String fmtInt(int v) {
  final s = v.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return (v < 0 ? '-' : '') + b.toString();
}

/// Montant en francs congolais : 1 000 CDF.
String cdf(int v) => '${fmtInt(v)} CDF';

final DateFormat _heure = DateFormat('HH:mm', 'fr');
final DateFormat _jourCourt = DateFormat('dd/MM/yyyy', 'fr');
final DateFormat _jourLong = DateFormat('EEEE d MMMM yyyy', 'fr');
final DateFormat _jourMois = DateFormat('d MMM', 'fr');
final DateFormat _moisAnnee = DateFormat('MMMM yyyy', 'fr');
final DateFormat _dateHeure = DateFormat('dd/MM HH:mm', 'fr');

String fmtHeure(DateTime d) => _heure.format(d);
String fmtJourCourt(DateTime d) => _jourCourt.format(d);
String fmtJourLong(DateTime d) {
  final s = _jourLong.format(d);
  return s[0].toUpperCase() + s.substring(1);
}

String fmtJourMois(DateTime d) => _jourMois.format(d);
String fmtMoisAnnee(DateTime d) {
  final s = _moisAnnee.format(d);
  return s[0].toUpperCase() + s.substring(1);
}

String fmtDateHeure(DateTime d) => _dateHeure.format(d);

final DateFormat _jourCompact = DateFormat('EEE d MMM', 'fr');

/// Exemple : « lun. 2 nov. »
String fmtJourCompact(DateTime d) => _jourCompact.format(d);

/// Début de journée locale.
DateTime debutJour(DateTime d) => DateTime(d.year, d.month, d.day);

/// Libellé lisible d'une durée en minutes : 1 h, 1 jour, 1 semaine, 1 mois.
String libelleDuree(int minutes) {
  if (minutes % 43200 == 0) {
    final n = minutes ~/ 43200;
    return '$n mois';
  }
  if (minutes % 10080 == 0) {
    final n = minutes ~/ 10080;
    return n == 1 ? '1 semaine' : '$n semaines';
  }
  if (minutes % 1440 == 0) {
    final n = minutes ~/ 1440;
    return n == 1 ? '1 jour' : '$n jours';
  }
  if (minutes % 60 == 0) {
    return '${minutes ~/ 60} h';
  }
  return '$minutes min';
}
