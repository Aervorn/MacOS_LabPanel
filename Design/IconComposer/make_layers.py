"""Calques de l'icône de LabPanel pour Icon Composer (macOS 26).

Une fenêtre à onglets (l'onglet du milieu est ouvert) qui montre une baie de trois serveurs,
voyants allumés. Tous les calques sont sur le même canevas de 1024 × 1024 : ils se superposent
sans réglage. Écrit les SVG ici, copie dans LabPanel/AppIcon.icon/Assets ceux qu'utilise l'icône,
et assemble Design/LabPanel-icon.svg (icône complète, pour le README).

    python3 Design/IconComposer/make_layers.py
"""
import shutil
from pathlib import Path

HERE = Path(__file__).parent
ICON_ASSETS = HERE.parent.parent / "LabPanel" / "AppIcon.icon" / "Assets"
HEAD = '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\n'

# Fenêtre
WX, WY, WW, WH = 172, 196, 680, 632
# Onglets
TAB_W, TAB_H, TAB_GAP, TAB_Y = 172, 58, 22, 232
TABS_X = 512 - (3 * TAB_W + 2 * TAB_GAP) // 2
# Serveurs
UX, UW, UH, UGAP, UY = 244, 536, 118, 26, 372
LEDS = [("#22C55E", "#22C55E"), ("#22C55E", "#F59E0B"), ("#22C55E", "#38BDF8")]

LAYERS = {}

# Fond : référence seulement (dans l'icône, c'est le dégradé de fond d'Icon Composer)
LAYERS["1-fond.svg"] = HEAD + """  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#312E81"/><stop offset="0.55" stop-color="#2563EB"/><stop offset="1" stop-color="#06B6D4"/>
    </linearGradient>
  </defs>
  <rect width="1024" height="1024" fill="url(#bg)"/>
</svg>
"""

# Fenêtre claire, avec le filet sous les onglets
LAYERS["2-fenetre.svg"] = HEAD + f"""  <defs>
    <linearGradient id="win" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#E8EEF7"/>
    </linearGradient>
  </defs>
  <rect x="{WX}" y="{WY}" width="{WW}" height="{WH}" rx="76" fill="url(#win)"/>
  <rect x="{WX + 40}" y="{TAB_Y + TAB_H + 22}" width="{WW - 80}" height="6" rx="3" fill="#CBD5E1"/>
</svg>
"""

# Onglets : celui du milieu ouvert, en orange ; une pastille blanche fait office d'icône
tabs = HEAD + """  <defs>
    <linearGradient id="tabOn" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#FDBA74"/><stop offset="1" stop-color="#F97316"/>
    </linearGradient>
  </defs>
"""
for i in range(3):
    x = TABS_X + i * (TAB_W + TAB_GAP)
    fill = "url(#tabOn)" if i == 1 else "#C7D2E3"
    tabs += f'  <rect x="{x}" y="{TAB_Y}" width="{TAB_W}" height="{TAB_H}" rx="{TAB_H / 2}" fill="{fill}"/>\n'
    dot = "#FFFFFF" if i == 1 else "#EEF2F8"
    tabs += f'  <circle cx="{x + 32}" cy="{TAB_Y + TAB_H / 2}" r="13" fill="{dot}"/>\n'
    bar = "#FFFFFF" if i == 1 else "#EEF2F8"
    tabs += f'  <rect x="{x + 58}" y="{TAB_Y + TAB_H / 2 - 6}" width="{TAB_W - 90}" height="12" rx="6" fill="{bar}" fill-opacity="0.9"/>\n'
tabs += "</svg>\n"
LAYERS["3-onglets.svg"] = tabs

# Baie de trois serveurs, avec leurs grilles d'aération
units = HEAD + """  <defs>
    <linearGradient id="unit" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#334155"/><stop offset="1" stop-color="#1E293B"/>
    </linearGradient>
  </defs>
"""
for i in range(3):
    y = UY + i * (UH + UGAP)
    cy = y + UH / 2
    units += f'  <rect x="{UX}" y="{y}" width="{UW}" height="{UH}" rx="24" fill="url(#unit)"/>\n'
    units += f'  <rect x="{UX + 168}" y="{cy - 6}" width="96" height="12" rx="6" fill="#64748B"/>\n'
    for k, dy in enumerate((-24, 0, 24)):
        units += f'  <rect x="{UX + 300}" y="{cy + dy - 5}" width="196" height="10" rx="5" fill="#475569"/>\n'
units += "</svg>\n"
LAYERS["4-serveurs.svg"] = units

# Voyants
leds = HEAD
for i, colors in enumerate(LEDS):
    cy = UY + i * (UH + UGAP) + UH / 2
    for j, color in enumerate(colors):
        cx = UX + 54 + j * 56
        leds += f'  <circle cx="{cx}" cy="{cy}" r="24" fill="{color}" fill-opacity="0.28"/>\n'
        leds += f'  <circle cx="{cx}" cy="{cy}" r="15" fill="{color}"/>\n'
leds += "</svg>\n"
LAYERS["5-voyants.svg"] = leds


def composite():
    """Icône complète en un seul SVG (README) : calques superposés, coins arrondis comme sur macOS."""
    def inner(svg):
        body = svg.split("\n", 1)[1]
        return body.rsplit("</svg>", 1)[0]
    names = ("1-fond.svg", "2-fenetre.svg", "3-onglets.svg", "4-serveurs.svg", "5-voyants.svg")
    shadow = ('  <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">'
              '<feDropShadow dx="0" dy="18" stdDeviation="22" flood-color="#0B1030" flood-opacity="0.35"/></filter>\n')
    parts = [inner(LAYERS[names[0]]), '  <g filter="url(#shadow)">\n']
    parts += [inner(LAYERS[name]) for name in names[1:]]
    parts.append("  </g>\n")
    return (HEAD + '  <defs><clipPath id="squircle"><rect width="1024" height="1024" rx="229"/></clipPath>\n' + shadow + '  </defs>\n'
            + '  <g clip-path="url(#squircle)">\n' + "".join(parts) + "  </g>\n</svg>\n")


if __name__ == "__main__":
    (HERE.parent / "LabPanel-icon.svg").write_text(composite(), encoding="utf-8")
    ICON_ASSETS.mkdir(parents=True, exist_ok=True)
    for name, svg in LAYERS.items():
        (HERE / name).write_text(svg, encoding="utf-8")
        if name != "1-fond.svg":
            shutil.copy(HERE / name, ICON_ASSETS / name)
