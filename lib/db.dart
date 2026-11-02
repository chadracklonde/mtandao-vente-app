import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Ouverture de la base SQLite locale (aucune connexion Internet requise).
class AppDb {
  static Database? _db;

  static Future<Database> open() async {
    final existing = _db;
    if (existing != null) return existing;
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, 'mtandao.db'),
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _create,
    );
    _db = db;
    return db;
  }

  static Future<void> _create(Database db, int version) async {
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
