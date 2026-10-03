"""Generate standalone HUD pictograms and their visual review sheet."""

from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/ui/hud/status_icons"
SHEET = ROOT / "docs/art_mockups/hud_status_icons_v1.svg"

INK = "#26323A"
PAPER = "#F5EBD6"
FIELD = "#FFFAF0"
CORAL = "#EB6B5C"
TEAL = "#75CBD1"
BRASS = "#E8B85D"

ART = {
    "timer": f'<circle cx="16" cy="17" r="10" fill="{PAPER}" stroke="{INK}" stroke-width="2.4"/><path d="M16 8v9l5 3" fill="none" stroke="{CORAL}" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/><path d="M12 4h8" stroke="{INK}" stroke-width="2.4" stroke-linecap="round"/>',
    "height": f'<path d="M5 26h22" stroke="{INK}" stroke-width="2.4" stroke-linecap="round"/><path d="M9 24V17h5v7M14 24V12h5v12M19 24V7h5v17" fill="{TEAL}" stroke="{INK}" stroke-width="2" stroke-linejoin="round"/><path d="M5 13 9 9m-4 4 4 4M6 13h7" fill="none" stroke="{CORAL}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>',
    "territory": f'<path d="M5 9 13 5l7 4 7-3v17l-7 4-7-4-8 4Z" fill="{PAPER}" stroke="{INK}" stroke-width="2.2" stroke-linejoin="round"/><path d="M13 5v18M20 9v18" stroke="{INK}" stroke-width="1.8"/><path d="M6 12 12 9v11l-6 3Z" fill="{TEAL}"/><path d="M21 12 26 10v11l-5 3Z" fill="{CORAL}"/>',
    "gift": f'<path d="M5 14h22v13H5Z" fill="{PAPER}" stroke="{INK}" stroke-width="2.2" stroke-linejoin="round"/><path d="M4 11h24v5H4Z" fill="{BRASS}" stroke="{INK}" stroke-width="2.2" stroke-linejoin="round"/><path d="M16 11v16" stroke="{CORAL}" stroke-width="3"/><path d="M16 11C7 10 8 4 12 4c3 0 4 4 4 7Zm0 0c9-1 8-7 4-7-3 0-4 4-4 7Z" fill="{TEAL}" stroke="{INK}" stroke-width="1.8" stroke-linejoin="round"/>',
    "locked": f'<rect x="7" y="14" width="18" height="13" rx="2" fill="{CORAL}" stroke="{INK}" stroke-width="2.4"/><path d="M11 14V9a5 5 0 0 1 10 0v5" fill="none" stroke="{INK}" stroke-width="2.6" stroke-linecap="round"/><circle cx="16" cy="20" r="2" fill="{PAPER}"/><path d="M16 22v2" stroke="{PAPER}" stroke-width="2"/>',
}

def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    SHEET.parent.mkdir(parents=True, exist_ok=True)
    for name, art in ART.items():
        svg = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" role="img" aria-label="{name.title()} HUD status"><title>{name.title()} HUD status</title>{art}</svg>\n'
        ET.fromstring(svg)
        (OUT / f"{name}_art.svg").write_text(svg, encoding="utf-8")

    chunks = [f'<svg xmlns="http://www.w3.org/2000/svg" width="1040" height="428" viewBox="0 0 1040 428">',
              f'<rect width="1040" height="428" fill="{PAPER}"/>',
              f'<text x="40" y="55" fill="{INK}" font-family="Arial,sans-serif" font-weight="700" font-size="30">HUD status pictograms</text>',
              f'<text x="40" y="82" fill="{INK}" font-family="Arial,sans-serif" font-size="16">Source icons only · 48 / 32 / 24 px · retain text labels and numeric readouts</text>']
    for i, (name, art) in enumerate(ART.items()):
        x = 40 + i * 200
        chunks.extend([f'<rect x="{x}" y="113" width="180" height="270" rx="16" fill="{FIELD}" stroke="#C7AD85" stroke-width="2"/>',
                       f'<text x="{x+90}" y="147" text-anchor="middle" fill="{INK}" font-family="Arial,sans-serif" font-weight="700" font-size="18">{name.title()}</text>'])
        for size, y in ((48, 172), (32, 251), (24, 316)):
            chunks.append(f'<rect x="{x+90-size/2-7:g}" y="{y-7}" width="{size+14}" height="{size+14}" rx="10" fill="{PAPER}"/>')
            chunks.append(f'<svg x="{x+90-size/2:g}" y="{y}" width="{size}" height="{size}" viewBox="0 0 32 32">{art}</svg>')
    chunks.append('</svg>\n')
    svg = ''.join(chunks)
    ET.fromstring(svg)
    SHEET.write_text(svg, encoding="utf-8")

if __name__ == "__main__":
    main()
