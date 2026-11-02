#!/usr/bin/env python3
"""Configure Gradle pour signer l'APK de release avec android/key.properties.

À lancer après la création du projet Android (setup.sh le fait). Sans danger si
relancé : ne modifie rien si la configuration est déjà en place.

Gère les deux formats de fichier Gradle : build.gradle.kts (récent) et build.gradle.
"""
import os
import re
import sys

RACINE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
KTS = os.path.join(RACINE, "android", "app", "build.gradle.kts")
GROOVY = os.path.join(RACINE, "android", "app", "build.gradle")

# ----------------------------------------------------------------- Kotlin DSL

KTS_IMPORTS = "import java.io.FileInputStream\nimport java.util.Properties\n\n"

KTS_CHARGEMENT = """val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

"""

KTS_SIGNING = """    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

"""

KTS_CHOIX = (
    'signingConfig = if (keystorePropertiesFile.exists()) '
    'signingConfigs.getByName("release") else signingConfigs.getByName("debug")'
)

# ----------------------------------------------------------------- Groovy DSL

GROOVY_CHARGEMENT = """def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

"""

GROOVY_SIGNING = """    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
        }
    }

"""

GROOVY_CHOIX = (
    "signingConfig keystorePropertiesFile.exists() ? signingConfigs.release : signingConfigs.debug"
)


def patcher(texte, kotlin):
    if "keystoreProperties" in texte:
        return texte, False

    ancre = re.search(r"^android\s*\{[ \t]*\n", texte, re.MULTILINE)
    choix = re.search(
        r'signingConfig\s*=?\s*signingConfigs[.\w()"]*',
        texte,
    )
    if not ancre or not choix:
        raise ValueError("structure inattendue")

    # 1) remplacer le choix de signature (avant d'insérer, pour garder les positions)
    remplacement = KTS_CHOIX if kotlin else GROOVY_CHOIX
    texte = texte[: choix.start()] + remplacement + texte[choix.end():]

    # 2) bloc signingConfigs juste après « android { »
    ancre = re.search(r"^android\s*\{[ \t]*\n", texte, re.MULTILINE)
    texte = texte[: ancre.end()] + (KTS_SIGNING if kotlin else GROOVY_SIGNING) + texte[ancre.end():]

    # 3) lecture de key.properties avant « android { »
    ancre = re.search(r"^android\s*\{[ \t]*\n", texte, re.MULTILINE)
    chargement = KTS_CHARGEMENT if kotlin else GROOVY_CHARGEMENT
    texte = texte[: ancre.start()] + chargement + texte[ancre.start():]

    # 4) imports en tête (Kotlin seulement)
    if kotlin:
        texte = KTS_IMPORTS + texte
    return texte, True


def main():
    if os.path.exists(KTS):
        chemin, kotlin = KTS, True
    elif os.path.exists(GROOVY):
        chemin, kotlin = GROOVY, False
    else:
        print("Projet Android introuvable. Lancez d'abord ./setup.sh", file=sys.stderr)
        return 1

    with open(chemin, encoding="utf-8") as f:
        original = f.read()
    try:
        nouveau, change = patcher(original, kotlin)
    except ValueError:
        print(
            f"Je n'ai pas reconnu la structure de {os.path.relpath(chemin, RACINE)}.\n"
            "Ajoutez la signature à la main : https://docs.flutter.dev/deployment/android#sign-the-app",
            file=sys.stderr,
        )
        return 2

    if change:
        with open(chemin, "w", encoding="utf-8") as f:
            f.write(nouveau)
        print(f"Signature de release configurée dans {os.path.relpath(chemin, RACINE)}.")
    else:
        print("Signature de release déjà configurée.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
