"""Generate self-contained SVG keycaps for currently bound shortcut keys."""

from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/ui/input_glyphs"
SHEET = ROOT / "docs/art_mockups/bound_key_glyphs_v1.svg"

INK = "#26323A"
PAPER = "#F5EBD6"
CORAL = "#EB6B5C"

# Hand-drawn centerlines, avoiding font substitutions in SVG import.
PATHS = {
    "w": "M17 18 23 45 32 30 41 45 47 18",
    "a": "M18 45 32 17 46 45 M23 36H41",
    "s": "M44 21Q39 16 31 17Q20 17 20 25Q20 31 32 32Q45 33 45 39Q45 47 32 47Q23 47 18 42",
    "d": "M20 18V46H29Q46 46 46 32Q46 18 29 18Z",
    "f": "M21 46V18H45 M21 31H40",
    "q": "M32 17Q18 17 18 32Q18 47 32 47Q46 47 46 32Q46 17 32 17Z M37 40 48 50",
    "r": "M20 46V18H33Q45 18 45 27Q45 35 33 35H20 M32 35 46 46",
    "g": "M45 22Q40 17 32 17Q18 17 18 32Q18 47 32 47Q45 47 45 34H34",
    "c": "M45 22Q40 17 32 17Q18 17 18 32Q18 47 32 47Q40 47 45 42",
    "x": "M19 18 45 46 M45 18 19 46",
    "y": "M18 18 32 33 46 18 M32 33V46",
    "z": "M19 18H45L19 46H45",
    "1": "M25 24 34 18V46 M25 46H44",
    "2": "M20 24Q22 17 33 17Q45 17 45 26Q45 33 19 46H46",
}


def artwork(label: str) -> str:
    return (f'<rect x="5" y="5" width="54" height="54" rx="12" fill="{PAPER}" stroke="{INK}" stroke-width="3"/>'
            f'<path d="M7 49h50" stroke="{INK}" stroke-width="3" stroke-linecap="round"/>'
            f'<path d="{PATHS[label]}" fill="none" stroke="{INK}" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>')


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    SHEET.parent.mkdir(parents=True, exist_ok=True)
    for label in PATHS:
        art = artwork(label)
        svg = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" role="img" aria-labelledby="t"><title id="t">{label.upper()} key</title>{art}</svg>\n'
        ET.fromstring(svg)
        (OUT / f"key_{label}.svg").write_text(svg, encoding="utf-8")

    chunks = [f'<svg xmlns="http://www.w3.org/2000/svg" width="1120" height="570" viewBox="0 0 1120 570">',
              f'<rect width="1120" height="570" fill="{PAPER}"/>',
              f'<text x="36" y="52" fill="{INK}" font-family="Arial,sans-serif" font-weight="700" font-size="30">Bound keyboard glyph candidates</text>',
              f'<text x="36" y="78" fill="{INK}" font-family="Arial,sans-serif" font-size="16">Gameplay and lobby shortcut keys · 32 and 24 px · vector paths, no font dependency</text>']
    for i, label in enumerate(PATHS):
        col, row = i % 7, i // 7
        x, y = 36 + 156 * col, 104 + 226 * row
        chunks += [f'<rect x="{x}" y="{y}" width="140" height="202" rx="15" fill="#FFFAF0" stroke="#C7AD85" stroke-width="2"/>',
                   f'<text x="{x+70}" y="{y+31}" text-anchor="middle" font-family="Arial,sans-serif" font-size="17" font-weight="700" fill="{INK}">{label.upper()}</text>']
        for size, oy in ((32, 49), (24, 114)):
            chunks.append(f'<rect x="{x+70-size/2-5:g}" y="{y+oy-5}" width="{size+10}" height="{size+10}" rx="8" fill="{PAPER}"/>')
            chunks.append(f'<svg x="{x+70-size/2:g}" y="{y+oy}" width="{size}" height="{size}" viewBox="0 0 64 64">{artwork(label)}</svg>')
    chunks.append('</svg>\n')
    sheet = ''.join(chunks)
    ET.fromstring(sheet)
    SHEET.write_text(sheet, encoding="utf-8")


if __name__ == "__main__":
    main()
