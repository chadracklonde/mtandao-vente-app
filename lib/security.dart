import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

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
