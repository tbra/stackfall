"""Build one labelled contact-sheet PNG from many screenshots (Bontago-fca.8).

    python tools/contact_sheet.py a.png b.png dir/ "shots/*.png" [-o out.png]
        [--max-width 1280] [--columns N]
    python tools/contact_sheet.py --self-test

Workers view the sheet, not each full-size PNG. Existing *_sheet.png inputs are skipped.
"""
import argparse
import glob
import math
import os
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFont

DEFAULT_MAX_WIDTH = 1280
GAP = 6
LABEL_H = 16
BACKGROUND = (26, 26, 26)
LABEL_COLOUR = (230, 230, 230)


def collect(inputs):
    paths = []
    for item in inputs:
        if os.path.isdir(item):
            found = sorted(glob.glob(os.path.join(item, "*.png")))
        elif any(c in item for c in "*?["):
            found = sorted(glob.glob(item))
        else:
            found = [item]
        paths.extend(p for p in found if not p.endswith("_sheet.png"))
    return paths


def build(paths, max_width=DEFAULT_MAX_WIDTH, columns=0):
    if not paths:
        raise ValueError("no input images")
    cols = columns or min(len(paths), math.ceil(math.sqrt(len(paths))))
    cols = max(1, min(cols, len(paths)))
    rows = math.ceil(len(paths) / cols)
    cell_w = max(1, (max_width - GAP * (cols + 1)) // cols)
    cells = []
    for p in paths:
        im = Image.open(p).convert("RGB")
        h = max(1, round(im.height * min(1.0, cell_w / im.width)))
        w = min(im.width, cell_w)
        cells.append((os.path.basename(p), im.resize((w, h), Image.LANCZOS)))
    row_h = max(c[1].height for c in cells) + LABEL_H
    sheet = Image.new("RGB", (cols * cell_w + GAP * (cols + 1), rows * row_h + GAP * (rows + 1)), BACKGROUND)
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()
    for i, (name, im) in enumerate(cells):
        x = GAP + (i % cols) * (cell_w + GAP)
        y = GAP + (i // cols) * (row_h + GAP)
        draw.text((x, y), name[: max(1, cell_w // 6)], fill=LABEL_COLOUR, font=font)
        sheet.paste(im, (x, y + LABEL_H))
    return sheet


def self_test():
    with tempfile.TemporaryDirectory() as d:
        paths = []
        for i, colour in enumerate([(200, 40, 40), (40, 200, 40), (40, 40, 200), (200, 200, 40)]):
            p = os.path.join(d, "shot_%d.png" % i)
            Image.new("RGB", (1920, 1080), colour).save(p)
            paths.append(p)
        sheet = build(collect([d]), 1280)
        assert sheet.width <= 1280, sheet.size
        assert sheet.height < 1080 * 2, sheet.size
        out = os.path.join(d, "x_sheet.png")
        sheet.save(out)
        assert len(collect([d])) == 4  # sheet excluded
        assert len(collect([os.path.join(d, "shot_*.png")])) == 4
    print("self-test ok", sheet.size)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("inputs", nargs="*")
    ap.add_argument("-o", "--output", default="")
    ap.add_argument("--max-width", type=int, default=DEFAULT_MAX_WIDTH)
    ap.add_argument("--columns", type=int, default=0)
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        self_test()
        return 0
    paths = collect(args.inputs)
    if not paths:
        print("no PNG inputs found", file=sys.stderr)
        return 1
    sheet = build(paths, args.max_width, args.columns)
    out = args.output or os.path.join(os.path.dirname(os.path.abspath(paths[0])), "contact_sheet.png")
    sheet.save(out)
    print("%s %dx%d (%d images)" % (out, sheet.width, sheet.height, len(paths)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
