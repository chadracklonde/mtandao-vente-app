import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'pin_hash.dart';
import 'state.dart';

/// Résultat d'une vérification du code PIN avec limitation des essais.
enum StatutPin { correct, incorrect, bloque }

class ResultatPin {
  const ResultatPin(this.statut, {this.essaisRestants = 0, this.secondes = 0});
  final StatutPin statut;

  /// Essais restants avant le prochain blocage (statut incorrect).
  final int essaisRestants;

  /// Secondes à attendre avant de pouvoir réessayer (statut bloqué).
  final int secondes;
}

/// Gestion du code PIN (4 chiffres). Le PIN n'est jamais stocké en clair :
/// seul un hachage salé est enregistré dans la base locale.
class PinService {
  static const int longueur = 4;

  // Compteur d'échecs et blocage : enregistrés (clés « pin_ », donc hors
  // sauvegardes) pour que fermer et rouvrir l'application ne les remette pas à zéro.
  static const String _cleEchecs = 'pin_echecs';
  static const String _cleBlocage = 'pin_bloque_jusqua';

  /// Échecs de suite autorisés avant chaque blocage.
  static const int essaisParSerie = 5;

  /// Durée du blocage après [echecs] mauvais codes de suite (cumulés depuis
  /// la dernière réussite) : aucune avant 5, puis 30 s, 1 min, 5 min, 15 min,
  /// et 1 h à partir du cinquième palier.
  static Duration delaiBlocage(int echecs) {
    if (echecs < essaisParSerie) return Duration.zero;
    const paliers = [30, 60, 300, 900, 3600];
    final palier = echecs ~/ essaisParSerie;
    return Duration(seconds: paliers[(palier - 1).clamp(0, paliers.length - 1)]);
  }

  static Future<bool> estDefini() async =>
      (await appState.repo.getSetting('pin_hash')) != null;

  static Future<void> definir(String pin) async {
    final sel = PinHash.nouveauSel();
    await appState.repo.setSetting('pin_sel', sel);
    await appState.repo.setSetting('pin_hash', PinHash.hacher(sel, pin));
  }

  /// Vérifie le code en limitant les essais : après chaque série d'échecs,
  /// l'application se bloque un moment, même si elle est fermée puis rouverte.
  /// Pendant un blocage, même le bon code est refusé.
  static Future<ResultatPin> verifierAvecLimite(String pin,
          {DateTime? maintenant}) =>
      _avecLimite(pin, verifier, _cleEchecs, _cleBlocage, maintenant);

  /// Code d'un vendeur, avec la même limitation des essais (enregistrée,
  /// propre à chaque vendeur).
  static Future<ResultatPin> verifierVendeur(int vendeurId, String pin,
          {DateTime? maintenant}) =>
      _avecLimite(
        pin,
        (p) => appState.repo.verifierPinVendeur(vendeurId, p),
        'pin_v${vendeurId}_echecs',
        'pin_v${vendeurId}_bloque_jusqua',
        maintenant,
      );

  static Future<ResultatPin> _avecLimite(
    String pin,
    Future<bool> Function(String) verif,
    String cleEchecs,
    String cleBlocage,
    DateTime? maintenant,
  ) async {
    final repo = appState.repo;
    final now = maintenant ?? DateTime.now();

    final jusqua = int.tryParse(await repo.getSetting(cleBlocage) ?? '');
    if (jusqua != null) {
      final fin = DateTime.fromMillisecondsSinceEpoch(jusqua);
      if (now.isBefore(fin)) {
        return ResultatPin(StatutPin.bloque,
            secondes: fin.difference(now).inSeconds + 1);
      }
    }

    if (await verif(pin)) {
      await repo.removeSetting(cleEchecs);
      await repo.removeSetting(cleBlocage);
      return const ResultatPin(StatutPin.correct);
    }

    final echecs =
        (int.tryParse(await repo.getSetting(cleEchecs) ?? '') ?? 0) + 1;
    await repo.setSetting(cleEchecs, '$echecs');
    if (echecs % essaisParSerie == 0) {
      final delai = delaiBlocage(echecs);
      await repo.setSetting(
          cleBlocage, '${now.add(delai).millisecondsSinceEpoch}');
      return ResultatPin(StatutPin.bloque, secondes: delai.inSeconds);
    }
    return ResultatPin(StatutPin.incorrect,
        essaisRestants: essaisParSerie - echecs % essaisParSerie);
  }

  /// « 30 s », « 5 min », « 1 h ».
  static String dureeLisible(int secondes) {
    if (secondes < 60) return '$secondes s';
    if (secondes < 3600) return '${(secondes / 60).ceil()} min';
    return '${(secondes / 3600).ceil()} h';
  }

  /// Efface les échecs d'un vendeur (son code vient d'être changé).
  static Future<void> reinitialiserEchecsVendeur(int vendeurId) async {
    await appState.repo.removeSetting('pin_v${vendeurId}_echecs');
    await appState.repo.removeSetting('pin_v${vendeurId}_bloque_jusqua');
  }

  /// Efface les échecs (code correct, ou déverrouillage par empreinte).
  static Future<void> reinitialiserEchecs() async {
    await appState.repo.removeSetting(_cleEchecs);
    await appState.repo.removeSetting(_cleBlocage);
  }

  static Future<bool> verifier(String pin) async {
    final sel = await appState.repo.getSetting('pin_sel');
    final hash = await appState.repo.getSetting('pin_hash');
    if (sel == null || hash == null) return false;
    return PinHash.hacher(sel, pin) == hash;
  }
}

/// Déverrouillage par empreinte digitale ou reconnaissance du visage (Face ID).
/// Le PIN reste toujours possible. Le choix est local à ce téléphone et
/// n'est pas inclus dans les sauvegardes (clé commençant par « pin_ »).
class Biometrie {
  static const String _cle = 'pin_biometrie';
  static final LocalAuthentication _auth = LocalAuthentication();

  /// Le téléphone a-t-il un capteur utilisable avec une empreinte/un visage enregistré ?
  static Future<bool> disponible() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      final types = await _auth.getAvailableBiometrics();
      return types.isNotEmpty;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> active() async =>
      (await appState.repo.getSetting(_cle)) == '1';

  static Future<void> definirActive(bool v) async {
    if (v) {
      await appState.repo.setSetting(_cle, '1');
    } else {
      await appState.repo.removeSetting(_cle);
    }
  }

  /// Affiche la fenêtre système. Renvoie true si la personne est reconnue.
  static Future<bool> demander(String raison) async {
    try {
      return await _auth.authenticate(
        localizedReason: raison,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }
}
