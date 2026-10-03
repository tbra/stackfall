"""Generate mouse horizontal-wheel and side-button source glyphs."""

from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/ui/input_glyphs"
SHEET = ROOT / "docs/art_mockups/mouse_remap_glyphs_v1.svg"
INK, PAPER, FIELD, CORAL = "#26323A", "#F5EBD6", "#FFFAF0", "#EB6B5C"

SHELL = f'<path d="M13 28a19 19 0 0 1 38 0v13a19 19 0 0 1-38 0Z" fill="{PAPER}" stroke="{INK}" stroke-width="3"/><path d="M13 28h38M32 9v19" fill="none" stroke="{INK}" stroke-width="3"/><path d="M24 52q8 5 16 0" fill="none" stroke="{INK}" stroke-width="2" stroke-linecap="round"/>'
WHEEL = f'<rect x="28" y="14" width="8" height="17" rx="4" fill="{FIELD}" stroke="{INK}" stroke-width="2"/>'


def wheel(direction: str) -> str:
    arrow = ('M28 37H18m6-6-6 6 6 6' if direction == 'left'
             else 'M36 37h10m-6-6 6 6-6 6')
    active = ('M28 18h4v8h-4Z' if direction == 'left'
              else 'M32 18h4v8h-4Z')
    return SHELL + WHEEL + f'<path d="{active}" fill="{CORAL}"/><path d="{arrow}" fill="none" stroke="{CORAL}" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/>'


def side(which: int) -> str:
    tabs = []
    for index, y in ((4, 31), (5, 41)):
        tabs.append(f'<rect x="7" y="{y}" width="13" height="8" rx="3" fill="{CORAL if which == index else FIELD}" stroke="{INK}" stroke-width="2"/>')
    return SHELL + ''.join(tabs)


ART = {
    "mouse_wheel_left": ("Mouse wheel left", wheel('left')),
    "mouse_wheel_right": ("Mouse wheel right", wheel('right')),
    "mouse_button_4": ("Mouse side button 4", side(4)),
    "mouse_button_5": ("Mouse side button 5", side(5)),
}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    SHEET.parent.mkdir(parents=True, exist_ok=True)
    for filename, (title, art) in ART.items():
        svg = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" role="img" aria-labelledby="t"><title id="t">{title}</title>{art}</svg>\n'
        ET.fromstring(svg)
        (OUT / f"{filename}.svg").write_text(svg, encoding="utf-8")

    chunks = [f'<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="395" viewBox="0 0 1000 395">',
              f'<rect width="1000" height="395" fill="{PAPER}"/>',
              f'<text x="38" y="52" fill="{INK}" font-family="Arial,sans-serif" font-weight="700" font-size="30">Remaining mouse prompt candidates</text>',
              f'<text x="38" y="80" fill="{INK}" font-family="Arial,sans-serif" font-size="16">Wheel left/right and side buttons 4/5 · 48, 32 and 24 px</text>']
    for i, (filename, (title, art)) in enumerate(ART.items()):
        x = 38 + i * 240
        chunks += [f'<rect x="{x}" y="111" width="224" height="250" rx="15" fill="{FIELD}" stroke="#C7AD85" stroke-width="2"/>',
                   f'<text x="{x+112}" y="143" text-anchor="middle" fill="{INK}" font-family="Arial,sans-serif" font-size="16" font-weight="700">{title}</text>']
        for size, cx, dark in ((48, 52, False), (32, 119, False), (24, 182, True)):
            y = 209
            chunks.append(f'<rect x="{x+cx-size/2-8:g}" y="{y-size/2-8:g}" width="{size+16}" height="{size+16}" rx="9" fill="{INK if dark else PAPER}"/>')
            chunks.append(f'<svg x="{x+cx-size/2:g}" y="{y-size/2:g}" width="{size}" height="{size}" viewBox="0 0 64 64">{art}</svg>')
            chunks.append(f'<text x="{x+cx}" y="292" text-anchor="middle" font-family="Arial,sans-serif" font-size="14" fill="{INK}">{size} px</text>')
    chunks.append('</svg>\n')
    svg = ''.join(chunks)
    ET.fromstring(svg)
    SHEET.write_text(svg, encoding="utf-8")


if __name__ == "__main__":
    main()
