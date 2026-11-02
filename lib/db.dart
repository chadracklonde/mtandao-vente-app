import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Ouverture de la base SQLite locale (aucune connexion Internet requise).
///
/// Versions du schéma :
///  1. forfaits, lots, tickets, images, réglages.
///  2. tickets défectueux, mode de paiement, clients (dettes), vendeurs.
class AppDb {
  static const int version = 2;
  static Database? _db;

  static Future<Database> open() async {
    final existing = _db;
    if (existing != null) return existing;
    final dir = await getDatabasesPath();
    final chemin = p.join(dir, 'mtandao.db');
    await copieAvantMigration(chemin);
    final db = await openDatabase(
      chemin,
      version: version,
      onConfigure: configurer,
      onCreate: creer,
      onUpgrade: migrer,
    );
    _db = db;
    return db;
  }

  /// Avant de changer le schéma d'une base existante, garde une copie du
  /// fichier (`mtandao.db.vN.bak`) : si la migration échouait, rien n'est perdu.
  static Future<void> copieAvantMigration(String chemin) async {
    try {
      if (!await databaseExists(chemin)) return;
      final lecture = await openReadOnlyDatabase(chemin);
      final actuelle = await lecture.getVersion();
      await lecture.close();
      if (actuelle == 0 || actuelle >= version) return;
      final copie = File('$chemin.v$actuelle.bak');
      if (!await copie.exists()) await File(chemin).copy(copie.path);
    } catch (_) {
      // La copie est une précaution : son échec ne doit pas empêcher d'ouvrir.
    }
  }

  static Future<void> configurer(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Nouvelle base : schéma d'origine puis migrations, pour que une base neuve
  /// et une base migrée soient strictement identiques.
  static Future<void> creer(Database db, int version) async {
    await _creerV1(db);
    await _migrerV1versV2(db);
  }

  static Future<void> migrer(Database db, int ancienne, int nouvelle) async {
    if (ancienne < 2) await _migrerV1versV2(db);
  }

  /// v2 : n'efface ni ne modifie aucune donnée. Les ventes existantes restent
  /// des ventes « espèces », comptées comme avant.
  static Future<void> _migrerV1versV2(Database db) async {
    await db.execute('''
      CREATE TABLE clients(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nom TEXT NOT NULL,
        telephone TEXT,
        cree_le INTEGER NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE vendeurs(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nom TEXT NOT NULL,
        actif INTEGER NOT NULL DEFAULT 1
      )''');
    await db.execute(
        'ALTER TABLE tickets ADD COLUMN defectueux INTEGER NOT NULL DEFAULT 0');
    await db.execute(
        "ALTER TABLE tickets ADD COLUMN paiement TEXT NOT NULL DEFAULT 'especes'");
    await db.execute(
        'ALTER TABLE tickets ADD COLUMN client_id INTEGER REFERENCES clients(id)');
    await db.execute('ALTER TABLE tickets ADD COLUMN paye_le INTEGER');
    await db.execute(
        'ALTER TABLE tickets ADD COLUMN vendeur_id INTEGER REFERENCES vendeurs(id)');
    await db.execute(
        'CREATE INDEX idx_tickets_client ON tickets(client_id, paye_le)');
  }

  static Future<void> _creerV1(Database db) async {
    await db.execute('''
      CREATE TABLE forfaits(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nom TEXT NOT NULL,
        duree_minutes INTEGER NOT NULL,
        prix INTEGER NOT NULL,
        actif INTEGER NOT NULL DEFAULT 1
      )''');
    await db.execute('''
      CREATE TABLE lots(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nom TEXT NOT NULL,
        forfait_id INTEGER NOT NULL REFERENCES forfaits(id),
        source TEXT NOT NULL,
        fichier TEXT,
        login_url TEXT,
        cree_le INTEGER NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE tickets(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        lot_id INTEGER NOT NULL REFERENCES lots(id) ON DELETE CASCADE,
        position INTEGER NOT NULL,
        numero INTEGER,
        code TEXT NOT NULL UNIQUE,
        mot_de_passe TEXT,
        qr_texte TEXT,
        prix INTEGER NOT NULL,
        forfait_id INTEGER NOT NULL REFERENCES forfaits(id),
        vendu INTEGER NOT NULL DEFAULT 0,
        vendu_le INTEGER
      )''');
    await db.execute(
        'CREATE INDEX idx_tickets_lot ON tickets(lot_id, vendu, position)');
    await db.execute('CREATE INDEX idx_tickets_vendu_le ON tickets(vendu_le)');
    await db.execute('''
      CREATE TABLE ticket_images(
        ticket_id INTEGER PRIMARY KEY REFERENCES tickets(id) ON DELETE CASCADE,
        data BLOB NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE settings(
        cle TEXT PRIMARY KEY,
        valeur TEXT
      )''');

    // Forfait par défaut : 1 jour (24 h) = 1 000 CDF.
    await db.insert('forfaits', {
      'nom': '1 jour (24 h)',
      'duree_minutes': 1440,
      'prix': 1000,
      'actif': 1,
    });
    await db.insert('settings', {
      'cle': 'login_url',
      'valeur': 'http://mtandao.wifi',
    });
  }
}
