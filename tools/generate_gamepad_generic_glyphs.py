"""Generate Guide, Misc, and generic remappable gamepad button art."""

from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/ui/input_glyphs"
SHEET = ROOT / "docs/art_mockups/gamepad_generic_glyphs_v1.svg"
INK, PAPER, FIELD = "#26323A", "#F5EBD6", "#FFFAF0"
CORAL, TEAL, BRASS = "#EB6B5C", "#75CBD1", "#E8B85D"

ART = {
    "gamepad_guide": ("Gamepad Guide button",
        f'<circle cx="32" cy="32" r="27" fill="{PAPER}" stroke="{INK}" stroke-width="3"/><circle cx="32" cy="32" r="20" fill="none" stroke="{INK}" stroke-width="2"/><path d="M32 16 36 28 48 32 36 36 32 48 28 36 16 32 28 28Z" fill="{BRASS}" stroke="{INK}" stroke-width="2" stroke-linejoin="round"/>'),
    "gamepad_misc": ("Gamepad Misc button",
        f'<rect x="6" y="15" width="52" height="34" rx="15" fill="{PAPER}" stroke="{INK}" stroke-width="3"/><path d="M10 42h44" stroke="{INK}" stroke-width="2" stroke-linecap="round"/><circle cx="22" cy="31" r="3.5" fill="{INK}"/><circle cx="32" cy="31" r="3.5" fill="{CORAL}" stroke="{INK}" stroke-width="1"/><circle cx="42" cy="31" r="3.5" fill="{INK}"/>'),
    "gamepad_button_blank": ("Blank gamepad button for dynamic label",
        f'<rect x="6" y="15" width="52" height="34" rx="15" fill="{PAPER}" stroke="{INK}" stroke-width="3"/><path d="M10 42h44" stroke="{INK}" stroke-width="2" stroke-linecap="round"/>'),
}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    SHEET.parent.mkdir(parents=True, exist_ok=True)
    for name, (title, art) in ART.items():
        svg = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" role="img" aria-labelledby="t"><title id="t">{title}</title>{art}</svg>\n'
        ET.fromstring(svg)
        (OUT / f"{name}.svg").write_text(svg, encoding="utf-8")

    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="900" height="390" viewBox="0 0 900 390">',
             f'<rect width="900" height="390" fill="{PAPER}"/>',
             f'<text x="40" y="53" font-family="Arial,sans-serif" font-size="29" font-weight="700" fill="{INK}">Additional gamepad button art</text>',
             f'<text x="40" y="80" font-family="Arial,sans-serif" font-size="16" fill="{INK}">Guide, Misc and a shell for platform-specific remaps · 48, 32, 24 px</text>']
    titles = ("Guide", "Misc", "Blank button")
    for i, ((name, (title, art)), label) in enumerate(zip(ART.items(), titles)):
        x = 40 + i * 282
        parts += [f'<rect x="{x}" y="112" width="262" height="244" rx="16" fill="{FIELD}" stroke="#C7AD85" stroke-width="2"/>',
                  f'<text x="{x+131}" y="146" text-anchor="middle" font-family="Arial,sans-serif" font-size="18" font-weight="700" fill="{INK}">{label}</text>']
        for size, cx, dark in ((48, 55, False), (32, 131, False), (24, 211, True)):
            y = 213
            parts.append(f'<rect x="{x+cx-size/2-10:g}" y="{y-size/2-10:g}" width="{size+20}" height="{size+20}" rx="10" fill="{INK if dark else PAPER}"/>')
            parts.append(f'<svg x="{x+cx-size/2:g}" y="{y-size/2:g}" width="{size}" height="{size}" viewBox="0 0 64 64">{art}</svg>')
            parts.append(f'<text x="{x+cx}" y="294" text-anchor="middle" font-family="Arial,sans-serif" font-size="14" fill="{INK}">{size} px</text>')
    parts.append('</svg>\n')
    svg = ''.join(parts)
    ET.fromstring(svg)
    SHEET.write_text(svg, encoding="utf-8")


if __name__ == "__main__":
    main()
