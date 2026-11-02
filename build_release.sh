#!/usr/bin/env bash
# Fabrique l'APK signé de Mtandao (ou le bundle pour le Play Store avec : ./build_release.sh aab).
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f android/key.properties ]; then
  echo "Clé de signature absente. Lancez d'abord :  ./tool/creer_cle_signature.sh" >&2
  exit 1
fi
python3 tool/configurer_signature.py >/dev/null  # sans danger si déjà fait

if [ "${1:-apk}" = "aab" ]; then
  flutter build appbundle --release
  echo
  echo "Bundle signé : build/app/outputs/bundle/release/app-release.aab"
  exit 0
fi

# Sauvegarde Google Drive : identifiant (public) du client OAuth « Web » (voir le README).
DEFINES=()
if [ -n "${GOOGLE_SERVER_CLIENT_ID:-}" ]; then
  DEFINES+=("--dart-define=GOOGLE_SERVER_CLIENT_ID=${GOOGLE_SERVER_CLIENT_ID}")
fi

flutter build apk --release ${DEFINES[@]+"${DEFINES[@]}"}
APK="build/app/outputs/flutter-apk/app-release.apk"
echo
echo "APK signé : $APK"

# Vérification de la signature, si l'outil d'Android est disponible.
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
APKSIGNER="$(ls "$SDK"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1 || true)"
if [ -n "$APKSIGNER" ]; then
  echo "Vérification de la signature :"
  "$APKSIGNER" verify --print-certs "$APK" | grep -E "Signer #1 certificate (DN|SHA-256)" || true
else
  echo "(apksigner introuvable : vérification ignorée.)"
fi
echo
echo "Pensez à augmenter le numéro après le « + » de version dans pubspec.yaml à chaque mise à jour"
echo "(1.0.0+1 devient 1.0.1+2), sinon Android refusera d'installer la nouvelle version par-dessus."
