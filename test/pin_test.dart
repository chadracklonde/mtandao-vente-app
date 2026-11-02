import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao/backup.dart';
import 'package:mtandao/db.dart';
import 'package:mtandao/repo.dart';
import 'package:mtandao/security.dart';
import 'package:mtandao/state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tmp;
  late Repo repo;
  final debut = DateTime(2026, 11, 2, 8);

  setUpAll(() async {
    sqfliteFfiInit();
    tmp = Directory.systemTemp.createTempSync('mtandao_pin_');
    final db = await databaseFactoryFfi.openDatabase(
      '${tmp.path}/pin.db',
      options: OpenDatabaseOptions(
        version: AppDb.version,
        onConfigure: AppDb.configurer,
        onCreate: AppDb.creer,
      ),
    );
    repo = Repo(db);
    appState.utiliserPourTest(repo);
  });
  tearDownAll(() => tmp.deleteSync(recursive: true));

  setUp(() async {
    await PinService.definir('1234');
    await PinService.reinitialiserEchecs();
  });

  group('Durée du blocage', () {
    test('aucun blocage avant 5 échecs', () {
      for (var n = 0; n < 5; n++) {
        expect(PinService.delaiBlocage(n), Duration.zero);
      }
    });

    test('de plus en plus long, plafonné à une heure', () {
      expect(PinService.delaiBlocage(5), const Duration(seconds: 30));
      expect(PinService.delaiBlocage(9), const Duration(seconds: 30));
      expect(PinService.delaiBlocage(10), const Duration(minutes: 1));
      expect(PinService.delaiBlocage(15), const Duration(minutes: 5));
      expect(PinService.delaiBlocage(20), const Duration(minutes: 15));
      expect(PinService.delaiBlocage(25), const Duration(hours: 1));
      expect(PinService.delaiBlocage(500), const Duration(hours: 1));
    });
  });

  group('Vérification avec limitation des essais', () {
    test('le bon code est accepté', () async {
      final r = await PinService.verifierAvecLimite('1234', maintenant: debut);
      expect(r.statut, StatutPin.correct);
    });

    test('un mauvais code est refusé et on compte les essais restants', () async {
      final r1 = await PinService.verifierAvecLimite('0000', maintenant: debut);
      expect(r1.statut, StatutPin.incorrect);
      expect(r1.essaisRestants, 4);
      final r2 = await PinService.verifierAvecLimite('0001', maintenant: debut);
      expect(r2.essaisRestants, 3);
    });

    test('au 5e échec : blocage de 30 secondes', () async {
      StatutPin dernier = StatutPin.correct;
      var secondes = 0;
      for (var i = 0; i < 5; i++) {
        final r = await PinService.verifierAvecLimite('000$i', maintenant: debut);
        dernier = r.statut;
        secondes = r.secondes;
      }
      expect(dernier, StatutPin.bloque);
      expect(secondes, 30);
    });

    test('pendant le blocage, même le bon code est refusé', () async {
      for (var i = 0; i < 5; i++) {
        await PinService.verifierAvecLimite('999$i', maintenant: debut);
      }
      final r = await PinService.verifierAvecLimite('1234',
          maintenant: debut.add(const Duration(seconds: 10)));
      expect(r.statut, StatutPin.bloque);
      expect(r.secondes, inInclusiveRange(20, 21));
    });

    test('le blocage survit à une fermeture de l\'application (état enregistré)', () async {
      for (var i = 0; i < 5; i++) {
        await PinService.verifierAvecLimite('888$i', maintenant: debut);
      }
      // Aucun état en mémoire n'est utilisé : seul le réglage enregistré compte.
      expect(await repo.getSetting('pin_bloque_jusqua'), isNotNull);
      expect(await repo.getSetting('pin_echecs'), '5');
      final r = await PinService.verifierAvecLimite('1234',
          maintenant: debut.add(const Duration(seconds: 1)));
      expect(r.statut, StatutPin.bloque);
    });

    test('après le blocage on peut réessayer, et un succès remet tout à zéro', () async {
      for (var i = 0; i < 5; i++) {
        await PinService.verifierAvecLimite('777$i', maintenant: debut);
      }
      final apres = debut.add(const Duration(seconds: 31));
      final ok = await PinService.verifierAvecLimite('1234', maintenant: apres);
      expect(ok.statut, StatutPin.correct);
      expect(await repo.getSetting('pin_echecs'), isNull);
      expect(await repo.getSetting('pin_bloque_jusqua'), isNull);
    });

    test('les séries suivantes bloquent plus longtemps', () async {
      var t = debut;
      for (var i = 0; i < 5; i++) {
        await PinService.verifierAvecLimite('666$i', maintenant: t);
      }
      t = t.add(const Duration(seconds: 31));
      var r = const ResultatPin(StatutPin.correct);
      for (var i = 0; i < 5; i++) {
        r = await PinService.verifierAvecLimite('555$i', maintenant: t);
      }
      expect(r.statut, StatutPin.bloque);
      expect(r.secondes, 60);
    });

    test('les échecs ne sont jamais inclus dans une sauvegarde', () {
      expect(Sauvegarde.estExclu('pin_echecs'), isTrue);
      expect(Sauvegarde.estExclu('pin_bloque_jusqua'), isTrue);
    });
  });
}
