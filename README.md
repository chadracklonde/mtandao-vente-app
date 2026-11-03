# Mtandao — vente de tickets Wi-Fi

Application Android, 100 % hors ligne, pour gérer la vente des tickets Wi-Fi :
un seul ticket affiché à la fois, un bouton **VENDU**, un compteur en haut,
des rapports par jour, semaine, mois ou période libre.

- Identifiant Android : `cd.mtandao`
- Langue : français
- Fonctionne sans Internet. La permission Internet ne sert qu'à la sauvegarde automatique Google Drive, facultative (voir plus bas)

## Ce que fait l'application

| Fonction | Détail |
|---|---|
| **Import de PDF** | Lit directement le PDF sur le téléphone. Deux modèles reconnus automatiquement (voir plus bas). |
| **Vente** | Un ticket en grand (image d'origine avec son QR, ou carte dessinée) + le code à copier. **VENDU** passe au suivant. À la confirmation on choisit le paiement : **espèces** (par défaut), **mobile money**, **à crédit** (avec un client) ou **offert**. |
| **Saisie manuelle** | Coller ou taper un code par ligne (ou « code mot_de_passe ») : nouveau lot, ou ajout à un lot existant. Utile si le PDF est introuvable ou mal lu. |
| **Alertes** | Stock bas (seuil réglable, 20 par défaut), rappel de sauvegarde, et alerte si la sauvegarde Google Drive échoue. |
| **Compteur** | En haut : tickets déjà vendus, restants, montant encaissé, dernier ticket vendu. |
| **Annuler** | Remet en vente la dernière vente (bouton, ou « ANNULER » juste après une vente). |
| **Lots** | Un lot par PDF importé, avec historique, recherche d'un code, correction d'un ticket (marquer vendu / remettre en vente) et **tickets défectueux** (non proposés, non comptés dans les restants). |
| **Rapports** | Jour, semaine, mois, période au choix. Argent encaissé (hors offerts et crédits non payés), à recevoir, comparaison avec la période précédente, graphiques (par jour, heures de pointe), détail par forfait, mode de paiement, vendeur et jour. Partage en texte, **export CSV** (Excel) et **PDF**. |
| **Clients et dettes** | Réglages > Clients et dettes : ce que chaque client doit, payer un ticket ou tout, rappel par partage. |
| **Vendeurs** | Une pastille « qui vend » sur l'écran de vente ; chaque vente garde le nom du vendeur, et les rapports montrent un total par vendeur. Un **code personnel à 4 chiffres** (facultatif, Réglages > Vendeurs) est demandé pour vendre au nom d'un vendeur ; il est redemandé à chaque verrouillage de l'application, avec la même limitation des essais que le code principal. Les codes des vendeurs restent sur le téléphone : ils ne sont pas dans les sauvegardes. |
| **Paiement en dollars** | Réglages > Paiement en dollars : on indique combien de francs valent 1 dollar. La fenêtre de vente propose alors « Dollars » (espèces ou mobile money) et affiche le montant à recevoir. Chaque vente garde le taux du jour (changer le taux ne modifie pas le passé) ; les rapports montrent le total reçu en dollars, et le CSV les colonnes devise et montant reçu. L'argent encaissé reste compté en francs, au prix du ticket. |
| **Apparence et aide** | Clair, sombre ou automatique ; guide « Comment ça marche » au premier lancement et dans Réglages. |
| **Forfaits** | 1 jour = 1 000 CDF au départ. On ajoute 1 h, 1 semaine, 1 mois dans Réglages > Forfaits, chacun avec son prix. |
| **PIN** | Code à 4 chiffres au lancement et après 1 minute en arrière-plan. Stocké haché, jamais en clair. Après 5 mauvais codes, l'application se bloque (30 s, puis 1 min, 5 min, 15 min, 1 h) **même si on la ferme et la rouvre**. |
| **Sauvegarde** | Un fichier `.mtandao` à envoyer sur WhatsApp, Drive ou e-mail. Restauration sur un autre téléphone. Le PIN n'est pas inclus. |
| **Sauvegarde Google Drive** | Facultative et automatique : toutes les heures (si les données ont changé), dans le dossier « Mtandao Sauvegardes » de votre Drive. Les 10 plus récentes sont gardées. Voir la section ci-dessous. |
| **Partage d'un ticket** | Envoie code + lien de connexion au client. |

Un code déjà importé n'est jamais ajouté deux fois.
Le prix est enregistré sur chaque ticket à l'import : changer un tarif plus tard ne modifie pas l'historique.

## Modèles de PDF reconnus

1. **Planche Mikhmon** (logo MIKHMON, QR code, 4 × 4 tickets par page en paysage).
   Les pages n'ont pas de texte : l'application lit le code **dans le QR**
   (`...login?username=24283&password=24283`) et garde l'image du ticket.
   Rendu à 300 dpi, deuxième essai à 400 dpi pour les QR difficiles,
   saisie manuelle en dernier recours.
2. **« Tickets Wi-Fi »** en texte simple : `Code : 461232` / `Durée : 1jour(s)`.

La mise en page Mikhmon est lue par position (valeurs mesurées sur le PDF « 24h 200 tickets »,
dans `lib/pdf_import.dart`). Si une autre planche a une grille différente, il suffit
d'ajuster les constantes `_caseX0`, `_casePasX`, `_caseY0`, `_casePasY`… en haut de ce fichier.

## Installer et compiler

Prérequis : Flutter (`flutter doctor` sans erreur) et le SDK Android.

```bash
git clone https://github.com/chadracklonde/mtandao-vente-app
cd mtandao-vente-app
./setup.sh                 # crée le projet Android, les icônes, installe les dépendances
flutter run                # test sur un téléphone branché
```

## Sauvegarde automatique Google Drive

Une fois connectée dans **Réglages**, l'application envoie un fichier `.mtandao` sur votre Google Drive,
dans le dossier visible **« Mtandao Sauvegardes »** :

- **toutes les heures**, quand il y a du réseau (Wi-Fi ou données mobiles), même application fermée ;
- **seulement si les données ont changé** depuis la dernière sauvegarde (sinon les 10 fichiers seraient
  vite remplacés par des copies identiques et l'historique utile disparaîtrait) ;
- **les 10 plus récents sont gardés**, les autres sont supprimés après chaque envoi réussi. Seuls les fichiers
  `mtandao_sauvegarde_*.mtandao` créés par l'application sont concernés ;
- l'application ne demande que l'accès `drive.file` : elle ne voit **que** ses propres fichiers, jamais le reste du Drive ;
- le code PIN n'est jamais envoyé.

Android peut retarder la tâche d'arrière-plan (économie de batterie, téléphone au repos). Quand l'application est
ouverte ou reprise et que la dernière tentative date de plus d'une heure, elle sauvegarde aussitôt.
Pour restaurer : téléchargez le fichier depuis Drive, puis **Réglages > Restaurer une sauvegarde**.

### Configuration (une seule fois)

Google exige que l'application soit déclarée. Il n'y a **aucun secret** à mettre dans le code.

1. Sur [console.cloud.google.com](https://console.cloud.google.com), créez un projet (par exemple « Mtandao »).
2. **API et services > Bibliothèque** : activez **Google Drive API**.
3. **API et services > Écran de consentement OAuth** : type *Externe*, nom « Mtandao », votre e-mail.
   Ajoutez la portée `https://www.googleapis.com/auth/drive.file`.
   **Passez ensuite l'application en production** (« Publier l'application »). Tant qu'elle reste en mode
   *Test*, Google coupe l'accès au bout de **7 jours** et les sauvegardes s'arrêtent. La portée `drive.file`
   n'est pas sensible : aucune vérification Google n'est demandée.
4. **API et services > Identifiants > Créer des identifiants > ID client OAuth** :
   - type **Android** : nom du paquet `cd.mtandao`, et l'empreinte **SHA-1** de votre clé de signature :
     `keytool -list -v -keystore mtandao-release.jks -alias mtandao` (ligne « SHA1 ») ;
   - type **Application Web** : notez son **ID client** (il ressemble à `123456-abc.apps.googleusercontent.com`).
5. Dans GitHub : **Settings > Secrets and variables > Actions > onglet Variables > New repository variable** :
   nom `GOOGLE_SERVER_CLIENT_ID`, valeur : l'ID client **Web** de l'étape 4. (Ce n'est pas un secret.)
6. Refabriquez l'APK (onglet **Actions > Run workflow**), installez-le, puis **Réglages > Sauvegarde automatique
   Google Drive > Connecter**.

Fabrication en local : `GOOGLE_SERVER_CLIENT_ID=... ./build_release.sh`.
Sans cet identifiant, l'APK fonctionne normalement mais la sauvegarde Google Drive est indisponible.

## Signer l'application avec GitHub

GitHub Actions fabrique l'APK et le signe avec ta clé personnelle, gardée dans les « secrets » du dépôt
(workflow `.github/workflows/build-apk.yml`). Tu n'as pas besoin d'installer Flutter sur ton ordinateur.
À chaque envoi sur `main`, GitHub vérifie aussi que le code compile (onglet **Actions**).

**1. Créer la clé (une seule fois)** : il faut `keytool`, fourni par le JDK ou par Android Studio.

```bash
./tool/creer_cle_signature.sh
```

Sans bash (Windows) : `keytool -genkeypair -keystore mtandao-release.jks -storetype PKCS12 -alias mtandao -keyalg RSA -keysize 2048 -validity 10000`.
Tu peux aussi réutiliser la clé d'une autre de tes applications.

**2. Donner la clé à GitHub (une seule fois)**

```bash
./tool/exporter_cle_pour_github.sh
```

Avec l'outil `gh` connecté, le script envoie les secrets lui-même. Sinon il te dit quoi coller dans
*Settings > Secrets and variables > Actions* :

| Secret | Contenu |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | le texte de la clé (fichier `mtandao-cle.base64.txt`) |
| `ANDROID_KEYSTORE_PASSWORD` | le mot de passe de la clé |
| `ANDROID_KEY_ALIAS` | l'alias (facultatif si c'est `mtandao`) |

Sans bash : le texte de la clé s'obtient en PowerShell avec
`[Convert]::ToBase64String([IO.File]::ReadAllBytes("mtandao-release.jks"))`.

**3. Fabriquer l'APK signé**

- À la main : onglet **Actions** > « Mtandao - APK signé » > **Run workflow**. L'APK est dans la section *Artifacts* de l'exécution (30 jours).
- Pour une version publiée : `git tag v1.0.0 && git push origin v1.0.0`. L'APK est joint à la page **Releases**
  (attention : si le dépôt est public, ce lien est public).

Le numéro de build augmente tout seul à chaque exécution, et le workflow refuse un APK signé avec la clé de test.

**Garde la clé précieusement.** Copie le fichier `.jks` et son mot de passe dans un endroit sûr
(Drive privé, clé USB). Si tu les perds, tu ne pourras plus publier de mise à jour qui remplace l'application
installée : il faudra la désinstaller, et les données du téléphone seront perdues (pense aux sauvegardes `.mtandao`).
La clé ne doit jamais être dans le dépôt : `*.jks`, `key.properties` et `mtandao-cle.base64.txt` sont ignorés par Git.

*Alternative sans GitHub* : sur ton ordinateur avec Flutter, `./setup.sh` puis `./build_release.sh`
(il utilise la clé créée à l'étape 1).

Les icônes sont générées par `python3 tool/make_icons.py` (Pillow) ; `setup.sh` les applique.

## Organisation du code

```
lib/
  main.dart               démarrage, thème, verrou PIN
  db.dart / repo.dart     base SQLite locale et requêtes
  state.dart              état global (lot actif)
  pdf_import.dart         lecture des PDF (rendu, QR, découpe des cases)
  text_parser.dart        lecture du modèle « Code / Durée » (fonctions pures)
  backup.dart             sauvegarde / restauration (.mtandao)
  security.dart           PIN haché
  screens/                vente, lots, rapports, réglages, import, verrou
  widgets/                carte du ticket, clavier PIN
test/                     tests du lecteur de texte et des formats
tool/make_icons.py        logo et icônes
tool/creer_cle_signature.sh   création de la clé de signature
tool/exporter_cle_pour_github.sh  envoi de la clé aux secrets GitHub
.github/workflows/build-apk.yml   vérification + APK signé
tool/configurer_signature.py  branche la signature dans Gradle
build_release.sh          APK / bundle signé
```

## Pistes pour la suite

- Rappel automatique de sauvegarde.
- Marquer un ticket « défectueux » (exclu du stock sans compter comme vente).
- Plusieurs vendeurs avec synchronisation (non prévu pour l'instant).
