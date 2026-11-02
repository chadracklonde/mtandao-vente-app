import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import 'db.dart';
import 'repo.dart';

/// Réglage de l'apparence : `auto` (suit le téléphone), `clair` ou `sombre`.
const String cleTheme = 'theme';

/// Convertit la valeur enregistrée en mode de thème ; inconnue = automatique.
ThemeMode themeDepuis(String? valeur) {
  switch (valeur) {
    case 'clair':
      return ThemeMode.light;
    case 'sombre':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

String themeVersTexte(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return 'clair';
    case ThemeMode.dark:
      return 'sombre';
    case ThemeMode.system:
      return 'auto';
  }
}

/// Apparence courante : l'application se redessine quand elle change.
final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);

/// État global minimal : accès aux données + lot actif + notification de changement.
class AppState extends ChangeNotifier {
  late final Repo repo;
  int? lotActifId;

  Future<void> init() async {
    repo = Repo(await AppDb.open());
    lotActifId = int.tryParse(await repo.getSetting('lot_actif') ?? '');
    themeMode.value = themeDepuis(await repo.getSetting(cleTheme));
  }

  Future<void> definirTheme(ThemeMode mode) async {
    await repo.setSetting(cleTheme, themeVersTexte(mode));
    themeMode.value = mode;
  }

  /// Réservé aux tests : utilise un dépôt de données déjà ouvert.
  @visibleForTesting
  void utiliserPourTest(Repo depot) => repo = depot;

  /// À appeler après toute écriture pour rafraîchir les écrans.
  void changed() => notifyListeners();

  Future<void> definirLotActif(int? id) async {
    lotActifId = id;
    if (id == null) {
      await repo.removeSetting('lot_actif');
    } else {
      await repo.setSetting('lot_actif', '$id');
    }
    notifyListeners();
  }
}

final AppState appState = AppState();
