import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Hachage salé des codes PIN (fonctions pures, partagées par le code de
/// l'application et ceux des vendeurs). Un code n'est jamais stocké en clair.
class PinHash {
  static const int tours = 5000;

  /// Sel aléatoire, en base64.
  static String nouveauSel() {
    final rnd = Random.secure();
    return base64Encode(List<int>.generate(16, (_) => rnd.nextInt(256)));
  }

  static String hacher(String sel, String pin) {
    var h = sha256.convert(utf8.encode('$sel:$pin')).bytes;
    for (var i = 0; i < tours; i++) {
      h = sha256.convert([...h, ...utf8.encode(sel)]).bytes;
    }
    return base64Encode(h);
  }
}
