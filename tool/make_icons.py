#!/usr/bin/env python3
"""Génère le logo Mtandao (concept A : ticket à encoches + arcs Wi-Fi).

Produit :
  assets/logo.png                    logo dans l'app (fond transparent, bleu)
  assets/icon/icon.png               icône classique (fond bleu, symbole blanc)
  assets/icon/icon_foreground.png    premier plan de l'icône adaptative (transparent)

Usage : python3 tool/make_icons.py   (nécessite Pillow)
"""
import math
import os

from PIL import Image, ImageDraw

BLEU = (10, 143, 208, 255)  # #0A8FD0
BLANC = (255, 255, 255, 255)

SS = 4  # sur-échantillonnage pour des bords lisses
BASE = 100.0  # le dessin est défini dans un repère 100 x 100


def symbole_masque(taille):
    """Masque (L) du symbole, dans un carré `taille` x `taille`."""
    n = taille * SS
    k = n / BASE
    m = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(m)

    def cercle(cx, cy, r, v):
        d.ellipse([(cx - r) * k, (cy - r) * k, (cx + r) * k, (cy + r) * k], fill=v)

    # --- arcs Wi-Fi (au-dessus du ticket)
    cx, cy = 50.0, 41.0
    epaisseur = 6.2
    for rayon in (15.0, 26.0, 37.0):
        d.arc(
            [(cx - rayon) * k, (cy - rayon) * k, (cx + rayon) * k, (cy + rayon) * k],
            start=228, end=312, fill=255, width=int(epaisseur * k),
        )
        # bouts arrondis
        for ang in (228, 312):
            a = math.radians(ang)
            r_mid = rayon - epaisseur / 2
            cercle(cx + r_mid * math.cos(a), cy + r_mid * math.sin(a), epaisseur / 2, 255)
    cercle(cx, cy, 4.8, 255)  # point du signal

    # --- ticket
    x0, y0, x1, y1 = 12.0, 54.0, 88.0, 94.0
    d.rounded_rectangle([x0 * k, y0 * k, x1 * k, y1 * k], radius=7 * k, fill=255)

    # encoches latérales (demi-cercles évidés au milieu des côtés)
    ym = (y0 + y1) / 2
    cercle(x0, ym, 6.5, 0)
    cercle(x1, ym, 6.5, 0)

    # ligne de perforation en pointillés
    px = 64.0
    y = y0 + 5
    while y < y1 - 4:
        d.rounded_rectangle([(px - 1.1) * k, y * k, (px + 1.1) * k, (y + 3.6) * k],
                            radius=1.0 * k, fill=0)
        y += 6.2

    # lignes de « texte » (le code) sur la partie gauche
    d.rounded_rectangle([22 * k, 66 * k, 54 * k, 71 * k], radius=2.5 * k, fill=0)
    d.rounded_rectangle([22 * k, 77 * k, 44 * k, 82 * k], radius=2.5 * k, fill=0)
    # petit carré sur la souche (type QR)
    d.rounded_rectangle([71 * k, 67 * k, 80 * k, 76 * k], radius=1.5 * k, fill=0)

    return m.resize((taille, taille), Image.LANCZOS)


def composer(taille_toile, part_symbole, couleur, fond=None):
    """Place le symbole centré sur une toile, occupant `part_symbole` de sa taille."""
    toile = Image.new("RGBA", (taille_toile, taille_toile), fond or (0, 0, 0, 0))
    t = int(taille_toile * part_symbole)
    masque = symbole_masque(t)
    # recentre sur la boîte réelle du dessin (de y=4 à y=94 environ)
    pastille = Image.new("RGBA", (t, t), couleur)
    pastille.putalpha(masque)
    bbox = masque.getbbox()
    cx_b = (bbox[0] + bbox[2]) / 2
    cy_b = (bbox[1] + bbox[3]) / 2
    ox = int(taille_toile / 2 - cx_b - (t - t) / 2)
    oy = int(taille_toile / 2 - cy_b)
    toile.alpha_composite(pastille, (max(ox, 0), max(oy, 0)))
    return toile


def main():
    racine = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    os.makedirs(os.path.join(racine, "assets", "icon"), exist_ok=True)

    # logo dans l'app : bleu sur transparent
    composer(512, 0.94, BLEU).save(os.path.join(racine, "assets", "logo.png"))

    # icône classique : symbole blanc sur fond bleu
    composer(1024, 0.66, BLANC, fond=BLEU).save(
        os.path.join(racine, "assets", "icon", "icon.png"))

    # icône adaptative : premier plan blanc dans la zone sûre (~61 %)
    composer(1024, 0.58, BLANC).save(
        os.path.join(racine, "assets", "icon", "icon_foreground.png"))
    print("Icônes générées dans assets/")


if __name__ == "__main__":
    main()
