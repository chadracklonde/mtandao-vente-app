import 'package:workmanager/workmanager.dart';

import 'db.dart';
import 'drive_backup.dart';
import 'repo.dart';

const String _nomUnique = 'mtandao-drive';
const String _nomTache = 'sauvegarde_drive';

/// Point d'entrée de la tâche en arrière-plan (autre « isolate » : on rouvre
/// la base nous-mêmes, sans passer par l'état de l'application).
@pragma('vm:entry-point')
void sauvegardeEnArrierePlan() {
  Workmanager().executeTask((tache, donnees) async {
    try {
      final repo = Repo(await AppDb.open());
      await DriveBackup.sauvegarder(repo);
    } catch (_) {
      // Rien à faire : la prochaine exécution réessaiera.
    }
    // Toujours « réussi » : Android ne doit pas multiplier les relances.
    return true;
  });
}

/// Planification de la sauvegarde automatique : toutes les heures, avec du
/// réseau, quand Android le permet. Rattrapage à l'ouverture de l'application.
class SauvegardeAuto {
  static const Duration intervalle = Duration(hours: 1);

  static Future<void> initialiser() =>
      Workmanager().initialize(sauvegardeEnArrierePlan);

  static Future<void> planifier() => Workmanager().registerPeriodicTask(
        _nomUnique,
        _nomTache,
        frequency: intervalle,
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );

  static Future<void> arreter() => Workmanager().cancelByUniqueName(_nomUnique);

  /// À l'ouverture ou au retour dans l'application : si la dernière tentative
  /// date de plus d'une heure, on sauvegarde tout de suite (Android peut
  /// retarder la tâche d'arrière-plan, surtout si le téléphone économise la batterie).
  static Future<void> rattraper(Repo repo) async {
    if (await repo.getSetting(DriveBackup.cleActif) != '1') return;
    final essai =
        int.tryParse(await repo.getSetting(DriveBackup.cleEssai) ?? '');
    if (essai != null) {
      final age = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(essai));
      if (age < intervalle) return;
    }
    await DriveBackup.sauvegarder(repo);
  }
}
