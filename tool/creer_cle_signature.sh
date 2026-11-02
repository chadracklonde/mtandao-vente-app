#!/usr/bin/env bash
# Crée la clé de signature de Mtandao (une seule fois, sur VOTRE ordinateur).
#
# Ce script produit :
#   android/app/mtandao-release.jks   la clé privée (ne quitte jamais votre ordinateur)
#   android/key.properties            ses paramètres, lus par Gradle au moment de signer
# Ces deux fichiers sont ignorés par Git : ils ne seront jamais envoyés sur GitHub.
#
# Prérequis : le JDK (commande keytool). Android Studio en contient un.
set -euo pipefail
cd "$(dirname "$0")/.."

CLE="android/app/mtandao-release.jks"
PROPS="android/key.properties"
ALIAS="mtandao"

if [ ! -d android ]; then
  echo "Le projet Android n'existe pas encore. Lancez d'abord ./setup.sh" >&2
  exit 1
fi
if [ -f "$CLE" ] || [ -f "$PROPS" ]; then
  echo "Une clé de signature existe déjà ($CLE)." >&2
  echo "Je ne l'écrase pas : en changer empêcherait de mettre à jour l'application déjà installée." >&2
  exit 1
fi
if ! command -v keytool >/dev/null 2>&1; then
  echo "keytool introuvable. Installez le JDK, ou utilisez celui d'Android Studio (dossier jbr/bin)." >&2
  exit 1
fi

demander() { # demander "Question" "valeur par défaut"
  local rep
  read -r -p "$1 [$2] : " rep
  rep="${rep:-$2}"
  echo "${rep//,/ }" # une virgule casserait le nom du certificat
}

echo "Identité inscrite dans le certificat (Entrée pour garder la valeur proposée) :"
NOM="$(demander "Nom du titulaire" "Chadrack Londe")"
ORG="$(demander "Organisation / application" "Mtandao")"
VILLE="$(demander "Ville" "Kindu")"
PROV="$(demander "Province" "Maniema")"
PAYS="$(demander "Pays (2 lettres)" "CD")"

if [ -z "${MTANDAO_MDP:-}" ]; then
  while true; do
    read -r -s -p "Choisissez un mot de passe pour la clé (6 caractères minimum) : " MDP; echo
    read -r -s -p "Confirmez le mot de passe : " MDP2; echo
    if [ "${#MDP}" -lt 6 ]; then echo "Trop court, recommencez."; continue; fi
    if [ "$MDP" != "$MDP2" ]; then echo "Les deux mots de passe diffèrent, recommencez."; continue; fi
    break
  done
else
  MDP="$MTANDAO_MDP" # utilisé seulement pour les tests automatiques
fi

# Le mot de passe passe par l'environnement : il n'apparaît pas dans la liste des processus.
export MTANDAO_PW="$MDP"
keytool -genkeypair \
  -keystore "$CLE" -storetype PKCS12 \
  -alias "$ALIAS" -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass:env MTANDAO_PW \
  -dname "CN=$NOM, OU=$ORG, L=$VILLE, ST=$PROV, C=$PAYS" 2>/dev/null

# Dans un fichier .properties, l'antislash est un caractère d'échappement.
MDP_PROPS="${MDP//\\/\\\\}"
umask 077
cat > "$PROPS" <<EOF
storePassword=$MDP_PROPS
keyPassword=$MDP_PROPS
keyAlias=$ALIAS
storeFile=mtandao-release.jks
EOF
chmod 600 "$PROPS" "$CLE"

echo
echo "Clé créée : $CLE"
echo "Empreinte SHA-256 du certificat :"
keytool -list -v -keystore "$CLE" -storepass:env MTANDAO_PW 2>/dev/null | grep -i "SHA256:" | sed 's/^ *//'
cat <<'FIN'

À FAIRE MAINTENANT :
  1. Copiez android/app/mtandao-release.jks ET le mot de passe dans un endroit sûr
     (Drive privé, clé USB). Sans eux, impossible de publier une mise à jour qui
     remplace l'application installée : il faudrait la désinstaller et perdre les données.
  2. N'envoyez jamais ce fichier ni le mot de passe sur GitHub ou par WhatsApp à n'importe qui.

Ensuite, pour fabriquer l'APK signé :   ./build_release.sh
FIN
