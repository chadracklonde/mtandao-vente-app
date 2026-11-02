import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import 'backup.dart';
import 'repo.dart';

/// Un fichier de sauvegarde présent sur Google Drive.
class FichierDrive {
  const FichierDrive(this.id, this.nom, this.date);
  final String id;
  final String nom;
  final DateTime date;
}

/// Résultat d'une tentative de sauvegarde vers Google Drive.
class ResultatDrive {
  const ResultatDrive({required this.ok, required this.message, this.envoye = false});

  /// Vrai si tout s'est bien passé (même si rien n'a dû être envoyé).
  final bool ok;

  /// Vrai si un nouveau fichier a été envoyé sur Drive.
  final bool envoye;
  final String message;
}

/// Sauvegarde automatique vers Google Drive : un fichier `.mtandao` par envoi,
/// rangé dans le dossier « Mtandao Sauvegardes ». Seuls les [garder] plus
/// récents sont conservés.
///
/// Seule l'autorisation `drive.file` est demandée : l'application ne voit et ne
/// modifie que les fichiers qu'elle a elle-même créés, jamais le reste du Drive.
class DriveBackup {
  static const String dossierNom = 'Mtandao Sauvegardes';
  static const int garder = 10;

  static const List<String> _scopes = [drive.DriveApi.driveFileScope];

  /// Identifiant du client OAuth « Web » de Google Cloud (pas un secret).
  /// Passé à la fabrication de l'APK : --dart-define=GOOGLE_SERVER_CLIENT_ID=...
  static const String _clientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  /// Faux si cet APK a été fabriqué sans identifiant Google.
  static bool get configure => _clientId.isNotEmpty;

  // Clés de la table des réglages (jamais incluses dans les sauvegardes).
  static const String cleActif = 'drive_actif';
  static const String cleEmail = 'drive_email';
  static const String cleEmpreinte = 'drive_empreinte';
  static const String cleSucces = 'drive_dernier_succes';
  static const String cleEssai = 'drive_dernier_essai';
  static const String cleErreur = 'drive_erreur';

  static bool _initialise = false;
  static bool _enCours = false;

  // ------------------------------------------------------- règles (testables)

  /// Vrai si [nom] est un fichier de sauvegarde créé par Mtandao.
  static bool estSauvegarde(String nom) =>
      nom.startsWith('mtandao_sauvegarde_') &&
      nom.endsWith('.${Sauvegarde.extension}');

  /// Fichiers à supprimer pour n'en garder que les [garder] plus récents.
  /// Les fichiers qui ne ressemblent pas à une sauvegarde Mtandao ne sont
  /// jamais touchés.
  static List<FichierDrive> aSupprimer(List<FichierDrive> fichiers,
      {int garder = DriveBackup.garder}) {
    final sauvegardes = fichiers.where((f) => estSauvegarde(f.nom)).toList()
      ..sort((a, b) {
        final c = b.date.compareTo(a.date);
        return c != 0 ? c : b.nom.compareTo(a.nom);
      });
    if (sauvegardes.length <= garder) return const [];
    return sauvegardes.sublist(garder);
  }

  // ------------------------------------------------------------- connexion

  static Future<void> _initialiser() async {
    if (_initialise) return;
    await GoogleSignIn.instance
        .initialize(serverClientId: _clientId.isEmpty ? null : _clientId);
    _initialise = true;
  }

  /// Connecte un compte Google et demande l'accès au dossier de sauvegarde.
  /// À appeler depuis un bouton (une fenêtre Google s'ouvre). Retourne l'e-mail.
  static Future<String> connecter() async {
    await _initialiser();
    final compte = await GoogleSignIn.instance.authenticate(scopeHint: _scopes);
    await compte.authorizationClient.authorizeScopes(_scopes);
    return compte.email;
  }

  /// Retire l'accès de Mtandao au compte Google.
  static Future<void> deconnecter() async {
    try {
      await _initialiser();
      await GoogleSignIn.instance.disconnect();
    } catch (_) {
      // Déjà déconnecté, ou plus de réseau : on oublie quand même le compte.
    }
  }

  /// Message lisible pour une erreur de connexion Google.
  static String messageErreur(Object e) {
    if (e is GoogleSignInException) {
      switch (e.code) {
        case GoogleSignInExceptionCode.canceled:
          return 'Connexion annulée.';
        case GoogleSignInExceptionCode.clientConfigurationError:
          return 'Configuration Google manquante ou incorrecte (voir le README).';
        default:
          return 'Connexion Google impossible : ${e.description ?? e.code.name}';
      }
    }
    return 'Erreur : $e';
  }

  static Future<drive.DriveApi?> _api({required bool interactif}) async {
    await _initialiser();
    final client = GoogleSignIn.instance.authorizationClient;
    final autorisation = await client.authorizationForScopes(_scopes) ??
        (interactif ? await client.authorizeScopes(_scopes) : null);
    if (autorisation == null) return null;
    return drive.DriveApi(autorisation.authClient(scopes: _scopes));
  }

  // ----------------------------------------------------------- sauvegarde

  /// Empreinte des données : change dès qu'une vente, un lot, un forfait ou
  /// un réglage change. Évite d'envoyer dix fois le même fichier et d'effacer
  /// ainsi les anciennes sauvegardes utiles.
  static Future<String> empreinte(Repo repo) async {
    final db = repo.db;
    final tickets = await db.rawQuery('''
      SELECT COUNT(*) AS n,
             COALESCE(SUM(vendu), 0) AS v,
             COALESCE(SUM(vendu_le), 0) AS t,
             COALESCE(SUM(CASE WHEN vendu = 1 THEN id ELSE 0 END), 0) AS i
      FROM tickets''');
    final reglages = (await db.query('settings', orderBy: 'cle'))
        .where((r) => !Sauvegarde.estExclu(r['cle'] as String))
        .toList();
    final texte = jsonEncode([
      await db.query('forfaits', orderBy: 'id'),
      await db.query('lots', orderBy: 'id'),
      tickets,
      reglages,
    ]);
    return sha1.convert(utf8.encode(texte)).toString();
  }

  static Future<String> _dossierId(drive.DriveApi api) async {
    final existants = await api.files.list(
      q: "mimeType = 'application/vnd.google-apps.folder' "
          "and name = '$dossierNom' and trashed = false",
      spaces: 'drive',
      pageSize: 1,
      $fields: 'files(id)',
    );
    final trouves = existants.files;
    if (trouves != null && trouves.isNotEmpty && trouves.first.id != null) {
      return trouves.first.id!;
    }
    final cree = await api.files.create(
      drive.File(
        name: dossierNom,
        mimeType: 'application/vnd.google-apps.folder',
      ),
      $fields: 'id',
    );
    return cree.id!;
  }

  /// Envoie une sauvegarde sur Drive si les données ont changé depuis la
  /// précédente (ou si [force]), puis supprime les plus anciennes.
  /// Ne lève jamais d'exception : le résultat dit ce qui s'est passé.
  static Future<ResultatDrive> sauvegarder(
    Repo repo, {
    bool force = false,
    bool interactif = false,
  }) async {
    if (await repo.getSetting(cleActif) != '1') {
      return const ResultatDrive(ok: true, message: 'Sauvegarde Drive désactivée.');
    }
    if (_enCours) {
      return const ResultatDrive(ok: true, message: 'Une sauvegarde est déjà en cours.');
    }
    _enCours = true;
    File? fichier;
    try {
      await repo.setSetting(cleEssai, '${DateTime.now().millisecondsSinceEpoch}');
      final api = await _api(interactif: interactif);
      if (api == null) {
        const m = 'Reconnexion à Google nécessaire : ouvrez Réglages > Sauvegarde Google Drive.';
        await repo.setSetting(cleErreur, m);
        return const ResultatDrive(ok: false, message: m);
      }

      final actuelle = await empreinte(repo);
      final derniere = await repo.getSetting(cleEmpreinte);
      if (!force && actuelle == derniere) {
        await repo.removeSetting(cleErreur);
        return const ResultatDrive(ok: true, message: 'Rien de nouveau depuis la dernière sauvegarde.');
      }

      final dossier = await _dossierId(api);
      fichier = await Sauvegarde.exporter(repo);
      final nom = fichier.uri.pathSegments.last;
      await api.files.create(
        drive.File(name: nom, parents: [dossier]),
        uploadMedia: drive.Media(fichier.openRead(), await fichier.length(),
            contentType: 'application/octet-stream'),
        $fields: 'id',
      );

      // Le nouveau fichier est bien parti : on peut ranger les anciens.
      await _nettoyer(api, dossier);

      final maintenant = '${DateTime.now().millisecondsSinceEpoch}';
      await repo.setSetting(cleEmpreinte, actuelle);
      await repo.setSetting(cleSucces, maintenant);
      await repo.setSetting('derniere_sauvegarde', maintenant);
      await repo.removeSetting(cleErreur);
      return const ResultatDrive(ok: true, envoye: true, message: 'Sauvegarde envoyée sur Google Drive.');
    } catch (e) {
      final m = e is GoogleSignInException
          ? messageErreur(e)
          : 'Sauvegarde Drive impossible : $e';
      await repo.setSetting(cleErreur, m);
      return ResultatDrive(ok: false, message: m);
    } finally {
      _enCours = false;
      try {
        await fichier?.delete();
      } catch (_) {}
    }
  }

  static Future<void> _nettoyer(drive.DriveApi api, String dossier) async {
    final liste = await api.files.list(
      q: "'$dossier' in parents and trashed = false",
      spaces: 'drive',
      orderBy: 'createdTime desc',
      pageSize: 100,
      $fields: 'files(id,name,createdTime)',
    );
    final fichiers = [
      for (final f in liste.files ?? const <drive.File>[])
        if (f.id != null && f.name != null)
          FichierDrive(f.id!, f.name!,
              f.createdTime ?? DateTime.fromMillisecondsSinceEpoch(0)),
    ];
    for (final f in aSupprimer(fichiers)) {
      try {
        await api.files.delete(f.id);
      } catch (_) {
        // Un échec ici n'est pas grave : réessayé à la prochaine sauvegarde.
      }
    }
  }
}
