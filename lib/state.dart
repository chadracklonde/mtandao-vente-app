import 'package:flutter/foundation.dart';

import 'db.dart';
import 'repo.dart';

/// État global minimal : accès aux données + lot actif + notification de changement.
class AppState extends ChangeNotifier {
  late final Repo repo;
  int? lotActifId;

  Future<void> init() async {
    repo = Repo(await AppDb.open());
    lotActifId = int.tryParse(await repo.getSetting('lot_actif') ?? '');
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
