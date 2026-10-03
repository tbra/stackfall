"""Generate Start and Back gamepad prompt SVGs and review sheet."""

from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/ui/input_glyphs"
SHEET = ROOT / "docs/art_mockups/gamepad_menu_glyphs_v1.svg"
INK, PAPER, FIELD = "#26323A", "#F5EBD6", "#FFFAF0"
CORAL, TEAL = "#EB6B5C", "#75CBD1"

SHELL = f'<rect x="5" y="13" width="54" height="39" rx="16" fill="{PAPER}" stroke="{INK}" stroke-width="3"/><path d="M9 42h46" stroke="{INK}" stroke-width="3" stroke-linecap="round"/>'
ART = {
    "start": SHELL + f'<path d="M23 23h18M23 30h18M23 37h18" stroke="{INK}" stroke-width="4" stroke-linecap="round"/><circle cx="45" cy="30" r="2" fill="{CORAL}"/>',
    "back": SHELL + f'<rect x="25" y="22" width="18" height="15" rx="2" fill="{TEAL}" stroke="{INK}" stroke-width="2.5"/><path d="M20 30h17v13H20Z" fill="{FIELD}" stroke="{INK}" stroke-width="2.5" stroke-linejoin="round"/>',
}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    SHEET.parent.mkdir(parents=True, exist_ok=True)
    for name, art in ART.items():
        svg = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" role="img" aria-labelledby="t"><title id="t">Gamepad {name.title()} button</title>{art}</svg>\n'
        ET.fromstring(svg)
        (OUT / f"gamepad_{name}.svg").write_text(svg, encoding="utf-8")

    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="800" height="380" viewBox="0 0 800 380">',
             f'<rect width="800" height="380" fill="{PAPER}"/>',
             f'<text x="40" y="51" font-family="Arial,sans-serif" font-size="30" font-weight="700" fill="{INK}">Gamepad Start / Back candidates</text>',
             f'<text x="40" y="78" font-family="Arial,sans-serif" font-size="16" fill="{INK}">Standalone source glyphs · 48, 32, 24 px · light and dark surfaces</text>']
    for i, (name, art) in enumerate(ART.items()):
        x = 40 + i * 375
        parts += [f'<rect x="{x}" y="112" width="350" height="234" rx="16" fill="{FIELD}" stroke="#C7AD85" stroke-width="2"/>',
                  f'<text x="{x+175}" y="148" text-anchor="middle" font-family="Arial,sans-serif" font-size="20" font-weight="700" fill="{INK}">{name.title()}</text>']
        for size, cx, dark in ((48, 84, False), (32, 175, False), (24, 270, True)):
            y = 206
            parts.append(f'<rect x="{x+cx-size/2-12:g}" y="{y-size/2-12:g}" width="{size+24}" height="{size+24}" rx="12" fill="{INK if dark else PAPER}"/>')
            parts.append(f'<svg x="{x+cx-size/2:g}" y="{y-size/2:g}" width="{size}" height="{size}" viewBox="0 0 64 64">{art}</svg>')
            parts.append(f'<text x="{x+cx}" y="286" text-anchor="middle" font-family="Arial,sans-serif" font-size="15" fill="{INK}">{size} px</text>')
    parts.append('</svg>\n')
    svg = ''.join(parts)
    ET.fromstring(svg)
    SHEET.write_text(svg, encoding="utf-8")


if __name__ == "__main__":
    main()
