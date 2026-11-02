import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'state.dart';

/// Gestion du code PIN (4 chiffres). Le PIN n'est jamais stocké en clair :
/// seul un hachage salé est enregistré dans la base locale.
class PinService {
  static const int longueur = 4;
  static const int _tours = 5000;

  static Future<bool> estDefini() async =>
      (await appState.repo.getSetting('pin_hash')) != null;

  static String _hacher(String sel, String pin) {
    var h = sha256.convert(utf8.encode('$sel:$pin')).bytes;
    for (var i = 0; i < _tours; i++) {
      h = sha256.convert([...h, ...utf8.encode(sel)]).bytes;
    }
    return base64Encode(h);
  }

  static Future<void> definir(String pin) async {
    final rnd = Random.secure();
    final sel = base64Encode(List<int>.generate(16, (_) => rnd.nextInt(256)));
    await appState.repo.setSetting('pin_sel', sel);
    await appState.repo.setSetting('pin_hash', _hacher(sel, pin));
  }

  static Future<bool> verifier(String pin) async {
    final sel = await appState.repo.getSetting('pin_sel');
    final hash = await appState.repo.getSetting('pin_hash');
    if (sel == null || hash == null) return false;
    return _hacher(sel, pin) == hash;
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
