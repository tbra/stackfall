"""Build one labelled contact-sheet PNG from many screenshots (Bontago-fca.8).

    python tools/contact_sheet.py a.png b.png dir/ "shots/*.png" [-o out.png]
        [--max-width 1280] [--columns N]
    python tools/contact_sheet.py --self-test

Workers view the sheet, not each full-size PNG. Existing *_sheet.png inputs are skipped.
A sheet is never larger than 2600x3000 px: when the shots do not fit it is paginated into
<name>_p1.png, <name>_p2.png ... (the single file name is kept when one page suffices) and every
page path is printed.
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
MAX_SHEET_W = 2600  # hard cap on any written sheet (px)
MAX_SHEET_H = 3000


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


def build_pages(paths, max_width=DEFAULT_MAX_WIDTH, columns=0):
    """List of sheet images, each at most MAX_SHEET_W x MAX_SHEET_H; one page when everything fits."""
    if not paths:
        raise ValueError("no input images")
    max_width = max(1, min(max_width, MAX_SHEET_W))
    cols = columns or min(len(paths), math.ceil(math.sqrt(len(paths))))
    cols = max(1, min(cols, len(paths)))
    cell_w = max(1, (max_width - GAP * (cols + 1)) // cols)
    max_cell_h = max(1, MAX_SHEET_H - GAP * 2 - LABEL_H)
    cells = []
    for p in paths:
        im = Image.open(p).convert("RGB")
        scale = min(1.0, cell_w / im.width, max_cell_h / im.height)
        size = (max(1, round(im.width * scale)), max(1, round(im.height * scale)))
        cells.append((os.path.basename(p), im.resize(size, Image.LANCZOS) if size != im.size else im))
    row_h = max(c[1].height for c in cells) + LABEL_H
    rows_per_page = max(1, (MAX_SHEET_H - GAP) // (row_h + GAP))
    per_page = rows_per_page * cols
    font = ImageFont.load_default()
    pages = []
    for start in range(0, len(cells), per_page):
        chunk = cells[start:start + per_page]
        rows = math.ceil(len(chunk) / cols)
        used_cols = min(cols, len(chunk))
        sheet = Image.new("RGB", (used_cols * cell_w + GAP * (used_cols + 1),
                                  rows * row_h + GAP * (rows + 1)), BACKGROUND)
        draw = ImageDraw.Draw(sheet)
        for i, (name, im) in enumerate(chunk):
            x = GAP + (i % cols) * (cell_w + GAP)
            y = GAP + (i // cols) * (row_h + GAP)
            draw.text((x, y), name[: max(1, cell_w // 6)], fill=LABEL_COLOUR, font=font)
            sheet.paste(im, (x, y + LABEL_H))
        pages.append(sheet)
    return pages


def page_paths(out, count):
    """out.png when one page, else out_p1.png, out_p2.png ..."""
    if count <= 1:
        return [out]
    root, ext = os.path.splitext(out)
    return ["%s_p%d%s" % (root, i + 1, ext or ".png") for i in range(count)]


def build(paths, max_width=DEFAULT_MAX_WIDTH, columns=0):
    """First page of build_pages (the whole sheet whenever it fits the cap)."""
    return build_pages(paths, max_width, columns)[0]


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
        many = []
        for i in range(30):
            p = os.path.join(d, "many_%02d.png" % i)
            Image.new("RGB", (1920, 1080), (i * 8, 80, 80)).save(p)
            many.append(p)
        pages = build_pages(many, 5000, 2)
        assert len(pages) > 1, len(pages)
        assert all(pg.width <= MAX_SHEET_W and pg.height <= MAX_SHEET_H for pg in pages), [pg.size for pg in pages]
        assert page_paths("a.png", 1) == ["a.png"] and page_paths("a.png", 2)[1] == "a_p2.png"
        tall = os.path.join(d, "tall.png")
        Image.new("RGB", (100, 9000)).save(tall)
        assert build_pages([tall])[0].height <= MAX_SHEET_H
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
    pages = build_pages(paths, args.max_width, args.columns)
    out = args.output or os.path.join(os.path.dirname(os.path.abspath(paths[0])), "contact_sheet.png")
    for path, sheet in zip(page_paths(out, len(pages)), pages):
        sheet.save(path)
        print("%s %dx%d (%d images total)" % (path, sheet.width, sheet.height, len(paths)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
