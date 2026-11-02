import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao/drive_backup.dart';

FichierDrive f(String nom, int jour) =>
    FichierDrive(nom, nom, DateTime(2026, 1, jour));

String sauvegarde(int jour) => 'mtandao_sauvegarde_202601${jour.toString().padLeft(2, '0')}_0800.mtandao';

void main() {
  group('DriveBackup.estSauvegarde', () {
    test('reconnaît les fichiers créés par Mtandao', () {
      expect(DriveBackup.estSauvegarde('mtandao_sauvegarde_20260105_0830.mtandao'), isTrue);
    });

    test('refuse les autres fichiers', () {
      expect(DriveBackup.estSauvegarde('photo.jpg'), isFalse);
      expect(DriveBackup.estSauvegarde('mtandao_sauvegarde_20260105_0830.zip'), isFalse);
      expect(DriveBackup.estSauvegarde('ma_sauvegarde.mtandao'), isFalse);
    });
  });

  group('DriveBackup.aSupprimer', () {
    test('ne supprime rien jusqu\'à 10 fichiers', () {
      final fichiers = [for (var i = 1; i <= 10; i++) f(sauvegarde(i), i)];
      expect(DriveBackup.aSupprimer(fichiers), isEmpty);
    });

    test('garde les 10 plus récents et supprime les plus anciens', () {
      final fichiers = [for (var i = 1; i <= 13; i++) f(sauvegarde(i), i)];
      final supprimes = DriveBackup.aSupprimer(fichiers).map((x) => x.nom).toSet();
      expect(supprimes, {sauvegarde(1), sauvegarde(2), sauvegarde(3)});
    });

    test('fonctionne quel que soit l\'ordre de la liste', () {
      final fichiers = [for (var i = 12; i >= 1; i--) f(sauvegarde(i), i)];
      final supprimes = DriveBackup.aSupprimer(fichiers).map((x) => x.nom).toSet();
      expect(supprimes, {sauvegarde(1), sauvegarde(2)});
    });

    test('ne touche jamais aux fichiers qui ne sont pas des sauvegardes', () {
      final fichiers = [
        for (var i = 1; i <= 11; i++) f(sauvegarde(i), i),
        f('important.pdf', 1),
        f('notes.txt', 2),
      ];
      final supprimes = DriveBackup.aSupprimer(fichiers).map((x) => x.nom).toList();
      expect(supprimes, [sauvegarde(1)]);
    });

    test('départage les dates identiques par le nom, sans en perdre', () {
      final fichiers = [
        for (var i = 1; i <= 11; i++)
          FichierDrive('$i', 'mtandao_sauvegarde_${i.toString().padLeft(2, '0')}.mtandao', DateTime(2026)),
      ];
      expect(DriveBackup.aSupprimer(fichiers), hasLength(1));
    });

    test('accepte un autre nombre à garder', () {
      final fichiers = [for (var i = 1; i <= 5; i++) f(sauvegarde(i), i)];
      expect(DriveBackup.aSupprimer(fichiers, garder: 3), hasLength(2));
    });
  });
}
