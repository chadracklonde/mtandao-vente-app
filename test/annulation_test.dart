import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao/backup.dart';
import 'package:mtandao/db.dart';
import 'package:mtandao/models.dart';
import 'package:mtandao/repo.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

late Directory _tmp;
var _n = 0;

Future<Repo> _neuf() async {
  final db = await databaseFactoryFfi.openDatabase(
    '${_tmp.path}/an_${_n++}.db',
    options: OpenDatabaseOptions(
      version: AppDb.version,
      onConfigure: AppDb.configurer,
      onCreate: AppDb.creer,
    ),
  );
  final repo = Repo(db);
  await repo.importerLot(
    nom: 'Lot',
    forfait: (await repo.forfaits()).first,
    source: 'texte',
    tickets: [for (var i = 1; i <= 6; i++) ParsedTicket(code: 'A$i', numero: i)],
  );
  return repo;
}

Future<void> _pause() => Future<void>.delayed(const Duration(milliseconds: 3));

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    _tmp = Directory.systemTemp.createTempSync('mtandao_annul_');
  });
  tearDownAll(() => _tmp.deleteSync(recursive: true));

  test('annule la dernière vente, une seule fois, et note l\'annulation', () async {
    final repo = await _neuf();
    final f = (await repo.forfaits()).first;
    final ts = await repo.ticketsDuLot(1);
    await repo.vendre(ts[0].id);
    expect(await repo.refusAnnulation(), isNull);
    final r = await repo.annulerVenteRecente();
    expect(r.ok, isTrue);
    expect(r.tickets.single.code, 'A1');
    final t = (await repo.ticketsDuLot(1)).first;
    expect(t.vendu, isFalse);
    expect(t.annulations, 1);

    // Le même ticket, revendu, ne peut plus être annulé par le vendeur.
    await _pause();
    await repo.vendre((await repo.prochainsTicketsForfait(f.id, 1)).single.id);
    expect(await repo.refusAnnulation(), RefusAnnulation.dejaAnnulee);
    final refus = await repo.annulerVenteRecente();
    expect(refus.refus, RefusAnnulation.dejaAnnulee);
    expect((await repo.ticketsDuLot(1)).first.vendu, isTrue);
  });

  test('impossible de remonter dans l\'historique vente après vente', () async {
    final repo = await _neuf();
    final ts = await repo.ticketsDuLot(1);
    await repo.vendre(ts[0].id);
    await _pause();
    await repo.vendre(ts[1].id);
    await _pause();
    await repo.vendre(ts[2].id);

    expect((await repo.annulerVenteRecente()).ok, isTrue); // A3
    // A2 est plus ancienne que l'annulation : refusée, comme A1.
    expect(await repo.refusAnnulation(), RefusAnnulation.ventePrecedente);
    expect((await repo.annulerVenteRecente()).ok, isFalse);
    final vendus = (await repo.ticketsDuLot(1)).where((t) => t.vendu).map((t) => t.code);
    expect(vendus, ['A1', 'A2']);

    // Une nouvelle vente, elle, peut être annulée.
    await _pause();
    await repo.vendre(ts[3].id);
    expect(await repo.refusAnnulation(), isNull);
  });

  test('au bout de 10 minutes, le vendeur ne peut plus annuler', () async {
    final repo = await _neuf();
    final ts = await repo.ticketsDuLot(1);
    await repo.vendre(ts[0].id);
    final tard = DateTime.now().add(const Duration(minutes: 11));
    expect(await repo.refusAnnulation(maintenant: tard), RefusAnnulation.tropAncienne);
    final presque = DateTime.now().add(const Duration(minutes: 9));
    expect(await repo.refusAnnulation(maintenant: presque), isNull);
  });

  test('aucune vente : rien à annuler', () async {
    final repo = await _neuf();
    expect(await repo.refusAnnulation(), RefusAnnulation.aucuneVente);
    expect(await repo.annulerDerniereVenteGlobale(), isNull);
  });

  test('une vente de plusieurs tickets s\'annule en bloc, une fois', () async {
    final repo = await _neuf();
    final f = (await repo.forfaits()).first;
    await repo.vendreQuantite(f.id, 3);
    final r = await repo.annulerVenteRecente();
    expect(r.tickets.length, 3);
    final ts = await repo.ticketsDuLot(1);
    expect(ts.take(3).every((t) => !t.vendu && t.annulations == 1), isTrue);
    expect((await repo.journalAnnulations()).length, 3);
  });

  test('correction du patron : possible, sans limite, mais toujours notée', () async {
    final repo = await _neuf();
    final ts = await repo.ticketsDuLot(1);
    final anne = await repo.ajouterVendeur('Anne');
    for (var i = 0; i < 3; i++) {
      await repo.vendre(ts[0].id, vendeurId: anne);
      await repo.remettreEnStock(ts[0].id);
    }
    expect((await repo.ticketsDuLot(1)).first.annulations, 3);
    final j = await repo.journalAnnulations();
    expect(j.length, 3);
    expect(j.every((l) => l.origine == 'patron' && l.vendeurNom == 'Anne'), isTrue);
    // Une correction du patron n'empêche pas d'annuler une vente toute fraîche.
    await _pause();
    await repo.vendre(ts[1].id);
    expect(await repo.refusAnnulation(), isNull);
    // Remettre en stock un ticket qui n'est pas vendu ne note rien.
    await repo.remettreEnStock(ts[5].id);
    expect((await repo.journalAnnulations()).length, 3);
  });

  test('le journal et le compteur font partie de la sauvegarde', () async {
    final repo = await _neuf();
    final ts = await repo.ticketsDuLot(1);
    await repo.vendre(ts[0].id);
    await repo.annulerVenteRecente();
    final octets = await Sauvegarde.contenu(repo);
    await repo.db.delete('annulations');
    await repo.db.update('tickets', {'annulations': 0});
    await Sauvegarde.restaurer(repo, octets);
    expect((await repo.journalAnnulations()).single.code, 'A1');
    expect((await repo.ticketsDuLot(1)).first.annulations, 1);
  });
}
