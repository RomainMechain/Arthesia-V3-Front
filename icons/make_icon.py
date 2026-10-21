"""Icône d'Arthesia : la Tour sous une rune des Architectes, violet mystique.

Écrit trois SVG (512 × 512) dans Arthesia-V3-Front/icons/ :
- icon.svg : l'icône complète (icône du projet, lanceur Android classique) ;
- icon_background.svg / icon_foreground.svg : les deux couches de l'icône
  adaptative Android. Le premier plan est réduit pour tenir dans la zone
  sûre (66 % centraux) que tous les masques de lanceur conservent.
"""
import math
from pathlib import Path

OUT = Path(__file__).resolve().parent
OUT.mkdir(exist_ok=True)

DEFS = """
  <defs>
    <radialGradient id="sky" cx="50%" cy="34%" r="75%">
      <stop offset="0" stop-color="#4a1f7a"/>
      <stop offset="0.45" stop-color="#2a0f4d"/>
      <stop offset="1" stop-color="#0c0519"/>
    </radialGradient>
    <radialGradient id="halo" cx="50%" cy="50%" r="50%">
      <stop offset="0" stop-color="#7ff6ff" stop-opacity="0.85"/>
      <stop offset="0.35" stop-color="#38c8f0" stop-opacity="0.35"/>
      <stop offset="1" stop-color="#38c8f0" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="aura" cx="50%" cy="50%" r="50%">
      <stop offset="0" stop-color="#b06cff" stop-opacity="0.45"/>
      <stop offset="1" stop-color="#b06cff" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="stone" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#8f6cc4"/>
      <stop offset="0.28" stop-color="#5a3a8c"/>
      <stop offset="0.7" stop-color="#2e1952"/>
      <stop offset="1" stop-color="#160a2b"/>
    </linearGradient>
    <linearGradient id="ledge" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#c7a8ff"/>
      <stop offset="0.35" stop-color="#7a55b5"/>
      <stop offset="1" stop-color="#241240"/>
    </linearGradient>
    <linearGradient id="window" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#d9fcff"/>
      <stop offset="1" stop-color="#3fd0f5"/>
    </linearGradient>
    <linearGradient id="beam" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#7ff6ff" stop-opacity="0"/>
      <stop offset="0.6" stop-color="#7ff6ff" stop-opacity="0.22"/>
      <stop offset="1" stop-color="#7ff6ff" stop-opacity="0.5"/>
    </linearGradient>
    <linearGradient id="mist" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#6b3fa8" stop-opacity="0"/>
      <stop offset="0.5" stop-color="#4b2680" stop-opacity="0.85"/>
      <stop offset="1" stop-color="#1a0b33" stop-opacity="1"/>
    </linearGradient>
    <radialGradient id="cloud" cx="50%" cy="50%" r="50%">
      <stop offset="0" stop-color="#3a1b66" stop-opacity="1"/>
      <stop offset="0.55" stop-color="#2c1350" stop-opacity="0.9"/>
      <stop offset="1" stop-color="#2c1350" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="cloud_light" cx="50%" cy="50%" r="50%">
      <stop offset="0" stop-color="#8a5cc7" stop-opacity="0.55"/>
      <stop offset="1" stop-color="#8a5cc7" stop-opacity="0"/>
    </radialGradient>
  </defs>"""


def stars() -> str:
    points = [(70, 90, 1.6), (120, 60, 1.1), (420, 80, 1.8), (455, 150, 1.1), (90, 200, 1.2), (400, 220, 1.0),
              (60, 300, 1.4), (445, 290, 1.5), (150, 140, 0.9), (360, 50, 1.2), (470, 360, 1.0), (40, 400, 1.1)]
    return "\n".join(f'    <circle cx="{x}" cy="{y}" r="{r}" fill="#e6d4ff" opacity="0.75"/>' for x, y, r in points)


def background() -> str:
    return f"""  <rect width="512" height="512" fill="url(#sky)"/>
  <circle cx="256" cy="150" r="230" fill="url(#aura)"/>
{stars()}"""


def rune_ring(cx: float, cy: float, r: float) -> str:
    """Cercle de rune : anneau, encoches régulières et trois glyphes."""
    parts = [f'<circle cx="{cx}" cy="{cy}" r="{r * 2.1}" fill="url(#halo)"/>',
             f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="#9ff8ff" stroke-width="5"/>',
             f'<circle cx="{cx}" cy="{cy}" r="{r - 11}" fill="none" stroke="#5fe0ff" stroke-width="2" opacity="0.8"/>']
    for i in range(12):
        a = math.radians(i * 30)
        x1, y1 = cx + math.cos(a) * (r - 11), cy + math.sin(a) * (r - 11)
        x2, y2 = cx + math.cos(a) * (r + (9 if i % 3 == 0 else 4)), cy + math.sin(a) * (r + (9 if i % 3 == 0 else 4))
        parts.append(f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="#bffbff" stroke-width="{3 if i % 3 == 0 else 2}" stroke-linecap="round"/>')
    # Glyphes : un losange au sommet, deux traits brisés sur les flancs.
    parts.append(f'<path d="M {cx} {cy - r - 22} l 9 13 l -9 13 l -9 -13 z" fill="#e8feff"/>')
    for side in (-1, 1):
        x = cx + side * (r + 3)
        parts.append(f'<path d="M {x} {cy - 14} l {side * 10} 8 l {-side * 10} 8 l {side * 10} 8" fill="none" stroke="#bffbff" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>')
    return "\n    ".join(parts)


def tower() -> str:
    tiers = [  # (bas, haut, demi-largeur en bas, demi-largeur en haut)
        (446, 352, 64, 58),
        (342, 262, 49, 44),
        (252, 188, 36, 32),
    ]
    cx = 256
    parts = [
        # Rayon de lumière qui monte de la tour vers la rune.
        '<path d="M 236 190 L 276 190 L 300 30 L 212 30 Z" fill="url(#beam)"/>',
    ]
    for index, (bottom, top, half_bottom, half_top) in enumerate(tiers):
        parts.append(f'<path d="M {cx - half_bottom} {bottom} L {cx + half_bottom} {bottom} L {cx + half_top} {top} L {cx - half_top} {top} Z" fill="url(#stone)"/>')
        # Corniche en saillie au sommet de chaque niveau.
        parts.append(f'<rect x="{cx - half_top - 7}" y="{top - 10}" width="{(half_top + 7) * 2}" height="10" rx="2" fill="url(#ledge)"/>')
        # Créneaux sur la corniche.
        step = (half_top + 7) * 2 / 5
        for i in range(5):
            if i % 2 == 0:
                parts.append(f'<rect x="{cx - half_top - 7 + i * step:.1f}" y="{top - 17}" width="{step:.1f}" height="8" fill="url(#ledge)"/>')
        # Fenêtres éclairées (une ou deux par niveau).
        window_y = (bottom + top) / 2 - 6
        offsets = [0] if index == 2 else [-18, 18]
        for dx in offsets:
            w, h = (12, 24) if index < 2 else (10, 20)
            x = cx + dx - w / 2
            parts.append(f'<circle cx="{cx + dx}" cy="{window_y + h / 2}" r="{h * 0.9}" fill="url(#halo)" opacity="0.6"/>')
            parts.append(f'<path d="M {x} {window_y + h} L {x} {window_y + w / 2} A {w / 2} {w / 2} 0 0 1 {x + w} {window_y + w / 2} L {x + w} {window_y + h} Z" fill="url(#window)"/>')
    # Arête lumineuse côté gauche : la lumière de la rune éclaire la tour.
    parts.append('<path d="M 192 446 L 198 352 M 207 342 L 212 262 M 220 252 L 224 188" stroke="#d6c2ff" stroke-width="2.5" opacity="0.7"/>')
    # Flèche du sommet.
    parts.append('<path d="M 230 178 L 282 178 L 256 104 Z" fill="url(#stone)"/>')
    parts.append('<path d="M 230 178 L 256 104 L 250 178 Z" fill="#a688d8" opacity="0.55"/>')
    return "\n    ".join(parts)


def mist() -> str:
    # Nappe de brume : le pied de la tour s'y perd, ses bords s'estompent.
    return """<ellipse cx="256" cy="458" rx="240" ry="72" fill="url(#cloud)"/>
    <ellipse cx="200" cy="446" rx="120" ry="34" fill="url(#cloud_light)"/>
    <ellipse cx="320" cy="452" rx="130" ry="36" fill="url(#cloud_light)"/>"""


def foreground() -> str:
    return f"""    {rune_ring(256, 104, 58)}
    {tower()}
    {mist()}"""


def svg(body: str) -> str:
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">{DEFS}\n{body}\n</svg>\n'


# Icône complète : le premier plan un peu réduit pour respirer sur le fond.
(OUT / "icon.svg").write_text(svg(background() + f'\n  <g transform="translate(256 262) scale(0.9) translate(-256 -262)">\n{foreground()}\n  </g>'), encoding="utf-8")
(OUT / "icon_background.svg").write_text(svg(background()), encoding="utf-8")
# Premier plan adaptatif : contenu (y 40 → 470) ramené dans la zone sûre centrale.
(OUT / "icon_foreground.svg").write_text(svg(f'  <g transform="translate(256 262) scale(0.72) translate(-256 -255)">\n{foreground()}\n  </g>'), encoding="utf-8")
print("ok")
