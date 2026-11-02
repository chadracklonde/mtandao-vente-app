#!/usr/bin/env bash
# Prépare le projet Android de Mtandao (à lancer une seule fois, après le clonage).
# Prérequis : Flutter installé (flutter doctor) et Android SDK.
set -euo pipefail

if [ ! -d android ]; then
  echo "→ Création du projet Android (identifiant : cd.mtandao)…"
  # flutter create ne doit pas écraser nos fichiers : on les met de côté puis on les remet.
  tmp="$(mktemp -d)"
  cp -r lib test pubspec.yaml analysis_options.yaml assets "$tmp"/
  flutter create --org cd --project-name mtandao --platforms=android .
  rm -rf lib test
  cp -r "$tmp"/lib "$tmp"/test .
  cp "$tmp"/pubspec.yaml "$tmp"/analysis_options.yaml .
  cp -r "$tmp"/assets/. assets/
  rm -rf "$tmp"
fi

echo "→ Nom affiché sous l'icône : Mtandao"
manifest="android/app/src/main/AndroidManifest.xml"
sed -i 's/android:label="[^"]*"/android:label="Mtandao"/' "$manifest"

echo "→ Empreinte digitale / visage (autorisation + activité compatible)…"
if ! grep -q "USE_BIOMETRIC" "$manifest"; then
  sed -i 's#<application#<uses-permission android:name="android.permission.USE_BIOMETRIC"/>\n    <application#' "$manifest"
fi
find android/app/src/main -name 'MainActivity.*' -exec sed -i 's/\bFlutterActivity\b/FlutterFragmentActivity/g' {} +

echo "→ Sauvegarde Google Drive (autorisation Internet)…"
if ! grep -q "android.permission.INTERNET" "$manifest"; then
  sed -i 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <application#' "$manifest"
fi

echo "→ Signature de l'APK (clé personnelle, voir README)…"
python3 tool/configurer_signature.py

echo "→ Dépendances…"
flutter pub get

echo "→ Icônes de l'application…"
dart run flutter_launcher_icons

echo
echo "Terminé. Pour tester sur un téléphone branché :   flutter run"
echo
echo "Pour signer l'application avec VOTRE clé, puis fabriquer l'APK :"
echo "   ./tool/creer_cle_signature.sh     (une seule fois)"
echo "   ./build_release.sh"
