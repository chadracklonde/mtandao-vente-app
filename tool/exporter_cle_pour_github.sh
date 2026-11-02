#!/usr/bin/env bash
# Prépare la clé de signature pour GitHub : crée le texte à coller dans les « secrets »
# du dépôt, ou les envoie directement si l'outil GitHub (gh) est installé et connecté.
#
# À lancer après ./tool/creer_cle_signature.sh (ou avec une clé existante :
#   ./tool/exporter_cle_pour_github.sh chemin/ma-cle.jks).
set -euo pipefail
cd "$(dirname "$0")/.."

DEPOT="chadracklonde/mtandao-vente-app"
CLE="${1:-android/app/mtandao-release.jks}"
PROPS="android/key.properties"
SORTIE="mtandao-cle.base64.txt" # ignoré par Git

if [ ! -f "$CLE" ]; then
  echo "Clé introuvable : $CLE" >&2
  echo "Créez-la d'abord avec ./tool/creer_cle_signature.sh" >&2
  exit 1
fi

# Mot de passe : lu dans key.properties si présent, sinon demandé.
MDP=""
ALIAS="mtandao"
if [ -f "$PROPS" ] && [ "$CLE" = "android/app/mtandao-release.jks" ]; then
  MDP="$(sed -n 's/^storePassword=//p' "$PROPS" | sed 's/\\\\/\\/g')"
  ALIAS="$(sed -n 's/^keyAlias=//p' "$PROPS")"
fi
if [ -z "$MDP" ]; then
  read -r -s -p "Mot de passe de la clé : " MDP; echo
  read -r -p "Alias de la clé [mtandao] : " A; ALIAS="${A:-mtandao}"
fi

base64 < "$CLE" | tr -d '\n' > "$SORTIE"
chmod 600 "$SORTIE"

echo "Texte de la clé enregistré dans : $SORTIE (ne le partagez pas)"
echo

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  read -r -p "Envoyer les secrets directement à $DEPOT avec gh ? [o/N] " REP
  if [ "${REP:-n}" = "o" ] || [ "${REP:-n}" = "O" ]; then
    gh secret set ANDROID_KEYSTORE_BASE64 --repo "$DEPOT" < "$SORTIE"
    printf '%s' "$MDP" | gh secret set ANDROID_KEYSTORE_PASSWORD --repo "$DEPOT"
    printf '%s' "$ALIAS" | gh secret set ANDROID_KEY_ALIAS --repo "$DEPOT"
    echo
    echo "Secrets enregistrés. Vous pouvez supprimer $SORTIE."
    exit 0
  fi
fi

cat <<FIN
Ajoutez ces secrets sur GitHub :
  https://github.com/$DEPOT/settings/secrets/actions  >  « New repository secret »

  Nom : ANDROID_KEYSTORE_BASE64      Valeur : tout le contenu du fichier $SORTIE
  Nom : ANDROID_KEYSTORE_PASSWORD    Valeur : le mot de passe de la clé
  Nom : ANDROID_KEY_ALIAS            Valeur : $ALIAS      (facultatif si c'est « mtandao »)

Ensuite, supprimez $SORTIE.
FIN
