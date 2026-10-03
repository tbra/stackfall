"""Generate standalone Stackfall menu-action art and an SVG review sheet."""

from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/ui/icons/menu_art"
SHEET = ROOT / "docs/art_mockups/menu_icons_art_v1.svg"

INK = "#26323A"
PAPER = "#F5EBD6"
FIELD = "#FFFAF0"
CORAL = "#EB6B5C"
TEAL = "#75CBD1"
BRASS = "#E8B85D"

# Deliberately broad silhouettes and 2px ink contours for 24px display.
ART = {
    "play": f'<path d="M10 6.5 26 16 10 25.5Z" fill="{CORAL}" stroke="{INK}" stroke-width="2.2" stroke-linejoin="round"/><path d="M11 8.5 18 12.7" stroke="{PAPER}" stroke-width="2" stroke-linecap="round"/>',
    "host": f'<path d="M5 13 16 5 27 13v13H5Z" fill="{PAPER}" stroke="{INK}" stroke-width="2.2" stroke-linejoin="round"/><path d="M12 26v-9h8v9" fill="{CORAL}" stroke="{INK}" stroke-width="2" stroke-linejoin="round"/><path d="M8 13h16" stroke="{INK}" stroke-width="2"/>',
    "join": f'<path d="M5 7h14v18H5Z" fill="{PAPER}" stroke="{INK}" stroke-width="2.2" stroke-linejoin="round"/><path d="M16 12 21 16 16 20M11 16h10" fill="none" stroke="{CORAL}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/><path d="M23 7h4v18h-4" fill="none" stroke="{INK}" stroke-width="2.2" stroke-linecap="round"/>',
    "settings": f'<path d="M5 9h22M5 16h22M5 23h22" stroke="{INK}" stroke-width="2.3" stroke-linecap="round"/><circle cx="12" cy="9" r="3.5" fill="{TEAL}" stroke="{INK}" stroke-width="2"/><circle cx="21" cy="16" r="3.5" fill="{CORAL}" stroke="{INK}" stroke-width="2"/><circle cx="14" cy="23" r="3.5" fill="{BRASS}" stroke="{INK}" stroke-width="2"/>',
    "back": f'<path d="M15 6 5 16l10 10" fill="none" stroke="{INK}" stroke-width="3.4" stroke-linecap="round" stroke-linejoin="round"/><path d="M6 16h21" stroke="{CORAL}" stroke-width="3.4" stroke-linecap="round"/>',
    "quit": f'<path d="M13 6H6v20h7M19 6h7v20h-7" fill="none" stroke="{INK}" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/><path d="M16 7v12" stroke="{CORAL}" stroke-width="3.4" stroke-linecap="round"/><path d="M10 18a7 7 0 1 0 12 0" fill="none" stroke="{CORAL}" stroke-width="3" stroke-linecap="round"/>',
}

def icon_svg(name: str, art: str) -> str:
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" '
            f'role="img" aria-label="{name.title()} menu action">'
            f'<title>{name.title()} menu action</title>{art}</svg>\n')

def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    SHEET.parent.mkdir(parents=True, exist_ok=True)
    for name, art in ART.items():
        svg = icon_svg(name, art)
        ET.fromstring(svg)
        (OUT / f"{name}_art.svg").write_text(svg, encoding="utf-8")

    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="1120" height="450" viewBox="0 0 1120 450">',
             f'<rect width="1120" height="450" fill="{PAPER}"/>',
             f'<text x="44" y="58" font-family="Arial,sans-serif" font-size="32" font-weight="700" fill="{INK}">Menu action icon candidates</text>',
             f'<text x="44" y="86" font-family="Arial,sans-serif" font-size="16" fill="{INK}">Live icons remain unchanged. Compare at 48, 32 and 24 px; dark tiles use a paper badge.</text>']
    for i, (name, art) in enumerate(ART.items()):
        x = 44 + i * 174
        parts += [f'<rect x="{x}" y="122" width="150" height="272" rx="16" fill="{FIELD}" stroke="#C7AD85" stroke-width="2"/>',
                  f'<text x="{x+75}" y="156" text-anchor="middle" font-family="Arial,sans-serif" font-size="17" font-weight="700" fill="{INK}">{name.title()}</text>']
        for size, y in ((48, 176), (32, 253), (24, 316)):
            bg_x = x + 75 - size/2 - 7
            bg_y = y - 7
            parts.append(f'<rect x="{bg_x:g}" y="{bg_y:g}" width="{size+14}" height="{size+14}" rx="10" fill="{INK if size == 24 else PAPER}"/>')
            if size == 24:
                parts.append(f'<rect x="{x+75-size/2-2:g}" y="{y-2}" width="{size+4}" height="{size+4}" rx="6" fill="{PAPER}"/>')
            parts.append(f'<svg x="{x+75-size/2:g}" y="{y}" width="{size}" height="{size}" viewBox="0 0 32 32">{art}</svg>')
    parts.append('</svg>\n')
    svg = ''.join(parts)
    ET.fromstring(svg)
    SHEET.write_text(svg, encoding="utf-8")

if __name__ == "__main__":
    main()
