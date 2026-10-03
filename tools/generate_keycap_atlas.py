"""Render the Godot key catalog as reusable, high-resolution keycap art.

Run: python tools/generate_keycap_atlas.py
Custom layout label: python tools/generate_keycap_atlas.py --label 'Ö' --output path.png
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/ui/input_glyphs/key_atlas"
FONT = ROOT / "assets/ui/fonts/Manrope-Regular.ttf"
CATALOG = OUT / "catalog.json"
SIZE = 128  # Four source pixels per 32px displayed glyph.
INK = (38, 50, 58, 255)
PAPER = (245, 235, 214, 255)
FIELD = (255, 250, 240, 255)

LABELS = {
    "Unknown": "?",
    "Space": "Space", "Exclam": "!", "QuoteDbl": '"',
    "NumberSign": "#", "Dollar": "$", "Percent": "%", "Ampersand": "&",
    "Apostrophe": "'", "ParenLeft": "(", "ParenRight": ")", "Asterisk": "*",
    "Plus": "+", "Comma": ",", "Minus": "-", "Period": ".", "Slash": "/",
    "Colon": ":", "Semicolon": ";", "Less": "<", "Equal": "=", "Greater": ">",
    "Question": "?", "At": "@", "BracketLeft": "[", "BackSlash": "\\",
    "BracketRight": "]", "AsciiCircum": "^", "UnderScore": "_", "QuoteLeft": "`",
    "BraceLeft": "{", "Bar": "|", "BraceRight": "}", "AsciiTilde": "~",
    "Escape": "Esc", "Backtab": "BTab", "Backspace": "Bksp", "Enter": "Enter",
    "Kp Enter": "Num Ent", "Insert": "Ins", "Delete": "Del", "Print": "PrtSc",
    "SysReq": "SysRq", "PageUp": "PgUp", "PageDown": "PgDn",
    "CapsLock": "Caps", "NumLock": "NumL", "ScrollLock": "ScrL",
    "Windows": "Win", "VolumeDown": "Vol-", "VolumeMute": "Mute",
    "VolumeUp": "Vol+", "MediaPlay": "Play", "MediaStop": "Stop",
    "MediaPrevious": "Prev", "MediaNext": "Next", "MediaRecord": "Rec",
    "HomePage": "HomePg", "Favorites": "Faves", "StandBy": "Standby",
    "OpenURL": "URL", "LaunchMail": "Mail", "LaunchMedia": "Media",
    "On-screen keyboard": "OSK", "JIS Eisu": "Eisu", "JIS Kana": "Kana",
    "Kp Multiply": "Num ×", "Kp Divide": "Num ÷", "Kp Subtract": "Num -",
    "Kp Period": "Num .", "Kp Add": "Num +",
}


def visible_label(name: str) -> str:
    if name in LABELS:
        return LABELS[name]
    if name.startswith("Kp "):
        return "Num " + name[3:]
    if name.startswith("Launch") and len(name) == 7:
        return "L" + name[-1]
    return name


def wrapped_label(label: str) -> list[str]:
    if len(label) <= 7:
        return [label]
    if " " in label:
        words = label.split()
        if len(words) == 2:
            return words
    # Long labels are split into two visible lines; full name stays in catalog.
    split = max(3, min(len(label) - 3, len(label) // 2))
    return [label[:split], label[split:]]


def draw_keycap(label: str) -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((9, 9, 119, 119), radius=24, fill=PAPER, outline=INK, width=6)
    draw.line((13, 100, 115, 100), fill=INK, width=6)
    lines = wrapped_label(label)
    for font_size in range(58 if len(lines) == 1 else 43, 21, -1):
        font = ImageFont.truetype(str(FONT), font_size)
        widths = [draw.textbbox((0, 0), line, font=font, stroke_width=0)[2] for line in lines]
        if max(widths) <= 91:
            break
    line_height = font_size * 1.03
    top = 57 - line_height * len(lines) / 2
    for i, line in enumerate(lines):
        box = draw.textbbox((0, 0), line, font=font)
        x = 64 - (box[2] - box[0]) / 2 - box[0]
        y = top + i * line_height - box[1]
        draw.text((x, y), line, font=font, fill=INK, stroke_width=1, stroke_fill=INK)
    return image


def gallery(entries: list[dict], path: Path) -> None:
    tile_w, tile_h, cols = 124, 158, 10
    rows = (len(entries) + cols - 1) // cols
    sheet = Image.new("RGB", (tile_w * cols, tile_h * rows + 52), PAPER[:3])
    draw = ImageDraw.Draw(sheet)
    title_font = ImageFont.truetype(str(FONT), 29)
    caption_font = ImageFont.truetype(str(FONT), 13)
    draw.text((22, 10), path.stem.replace('_', ' ').title(), font=title_font, fill=INK[:3])
    for i, entry in enumerate(entries):
        x, y = (i % cols) * tile_w, 52 + (i // cols) * tile_h
        glyph = Image.open(OUT / entry["file"]).convert("RGBA")
        glyph.thumbnail((96, 96), Image.Resampling.LANCZOS)
        sheet.paste(glyph, (x + 14, y + 4), glyph)
        caption = entry["godot_name"]
        if len(caption) > 17:
            caption = caption[:16] + "…"
        draw.text((x + 5, y + 110), caption, font=caption_font, fill=INK[:3])
        draw.text((x + 5, y + 129), str(entry["code"]), font=caption_font, fill=INK[:3])
    sheet.save(path, optimize=True)


def small_size_qa(entries: list[dict], path: Path) -> None:
    codes = [32, 65, 87, 92, 4194305, 4194308, 4194323,
             4194343, 4194366, 4194381, 4194433, 4194447]
    by_code = {entry["code"]: entry for entry in entries}
    image = Image.new("RGB", (960, 330), PAPER[:3])
    draw = ImageDraw.Draw(image)
    title_font = ImageFont.truetype(str(FONT), 27)
    caption_font = ImageFont.truetype(str(FONT), 16)
    draw.text((22, 12), "Keycaps at 32 and 24 px", font=title_font, fill=INK[:3])
    for i, code in enumerate(codes):
        entry = by_code[code]
        x = 20 + (i % 6) * 156
        y = 60 + (i // 6) * 131
        source = Image.open(OUT / entry["file"]).convert("RGBA")
        for size, ox, bg in ((32, 10, PAPER), (24, 83, INK)):
            draw.rounded_rectangle((x + ox - 8, y - 8, x + ox + size + 8,
                                    y + size + 8), radius=8, fill=bg)
            glyph = source.resize((size, size), Image.Resampling.LANCZOS)
            image.paste(glyph, (x + ox, y), glyph)
        draw.text((x + 1, y + 50), entry["godot_name"][:17], font=caption_font, fill=INK[:3])
    image.save(path, optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--label", help="Render one arbitrary remapped key label")
    parser.add_argument("--output", type=Path, help="Output PNG for --label")
    args = parser.parse_args()
    if args.label is not None:
        if args.output is None:
            parser.error("--output is required with --label")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        draw_keycap(args.label).save(args.output)
        return

    data = json.loads(CATALOG.read_text(encoding="utf-8"))
    entries = data["keys"]
    for entry in entries:
        code = entry["code"]
        name = entry["godot_name"]
        entry["label"] = visible_label(name)
        entry["file"] = f"keycode_{code}.png"
        draw_keycap(entry["label"]).save(OUT / entry["file"], optimize=True)
    CATALOG.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    gallery([e for e in entries if e["code"] < 4194304], ROOT / "docs/art_mockups/keycap_gallery_printable.png")
    gallery([e for e in entries if e["code"] >= 4194304], ROOT / "docs/art_mockups/keycap_gallery_special.png")
    small_size_qa(entries, ROOT / "docs/art_mockups/keycap_small_size_qa.png")
    # A blank keycap lets future runtime code keep all labels dynamic.
    image = draw_keycap("")
    image.save(OUT / "keycap_blank.png", optimize=True)
    print(f"KEYCAP_ATLAS_READY {len(entries)} codes")


if __name__ == "__main__":
    main()
