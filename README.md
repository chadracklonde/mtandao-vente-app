# Mtandao — vente de tickets Wi-Fi

Application Android, 100 % hors ligne, pour gérer la vente des tickets Wi-Fi :
un seul ticket affiché à la fois, un bouton **VENDU**, un compteur en haut,
des rapports par jour, semaine, mois ou période libre.

- Identifiant Android : `cd.mtandao`
- Langue : français
- Aucune connexion Internet nécessaire (l'application ne demande pas la permission Internet)

## Ce que fait l'application

| Fonction | Détail |
|---|---|
| **Import de PDF** | Lit directement le PDF sur le téléphone. Deux modèles reconnus automatiquement (voir plus bas). |
| **Vente** | Un ticket en grand (image d'origine avec son QR, ou carte dessinée) + le code à copier. **VENDU** passe au suivant. |
| **Compteur** | En haut : tickets déjà vendus, restants, montant encaissé, dernier ticket vendu. |
| **Annuler** | Remet en vente la dernière vente (bouton, ou « ANNULER » juste après une vente). |
| **Lots** | Un lot par PDF importé, avec historique, recherche d'un code, correction d'un ticket (marquer vendu / remettre en vente). |
| **Rapports** | Jour, semaine, mois, période au choix. Total, détail par forfait, par jour, partage en texte (WhatsApp…). |
| **Forfaits** | 1 jour = 1 000 CDF au départ. On ajoute 1 h, 1 semaine, 1 mois dans Réglages > Forfaits, chacun avec son prix. |
| **PIN** | Code à 4 chiffres au lancement et après 1 minute en arrière-plan. Stocké haché, jamais en clair. |
| **Sauvegarde** | Un fichier `.mtandao` à envoyer sur WhatsApp, Drive ou e-mail. Restauration sur un autre téléphone. Le PIN n'est pas inclus. |
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
flutter build apk --release
```

L'APK est dans `build/app/outputs/flutter-apk/app-release.apk`.

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
```

## Pistes pour la suite

- Rappel automatique de sauvegarde.
- Marquer un ticket « défectueux » (exclu du stock sans compter comme vente).
- Plusieurs vendeurs avec synchronisation (non prévu pour l'instant).
