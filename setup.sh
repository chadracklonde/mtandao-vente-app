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

echo "→ Dépendances…"
flutter pub get

echo "→ Icônes de l'application…"
dart run flutter_launcher_icons

echo
echo "Terminé. Pour tester sur un téléphone branché :   flutter run"
echo "Pour fabriquer l'APK à installer :                 flutter build apk --release"
echo "(l'APK se trouve dans build/app/outputs/flutter-apk/app-release.apk)"
