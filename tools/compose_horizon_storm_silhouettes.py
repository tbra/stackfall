"""Build the owner comparison sheet for three storm-cell silhouette options."""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parents[1]
REVIEW = ROOT / "docs/art_mockups/horizon_storm_cell_v1"
OPTIONS = (
    ("storm_silhouette_1.png", "1  Broad anvil", "Wide shelf with rounded inner towers"),
    ("storm_silhouette_2.png", "2  Centered towers", "Even, layered cumulus profile"),
    ("storm_silhouette_3.png", "3  Offset towers", "Asymmetric twin-tower profile"),
)
THUMBNAIL = (640, 360)
CROP_BOX = (200, 110, 1400, 785)
HEADER_HEIGHT = 78
GUTTER = 20
PAD = 20


def main() -> None:
    images: list[Image.Image] = []
    for filename, _title, _subtitle in OPTIONS:
        image = Image.open(REVIEW / filename).convert("RGB")
        if image.size != (1600, 900):
            raise ValueError(f"{filename} must be 1600x900, got {image.size}")
        focused = image.crop(CROP_BOX)
        images.append(ImageOps.fit(focused, THUMBNAIL, method=Image.Resampling.LANCZOS))

    width = PAD * 2 + len(OPTIONS) * THUMBNAIL[0] + (len(OPTIONS) - 1) * GUTTER
    height = PAD * 2 + THUMBNAIL[1] + HEADER_HEIGHT
    sheet = Image.new("RGB", (width, height), "#18212f")
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default(size=21)
    small_font = ImageFont.load_default(size=16)

    for index, ((image_name, title, subtitle), image) in enumerate(zip(OPTIONS, images)):
        left = PAD + index * (THUMBNAIL[0] + GUTTER)
        top = PAD
        sheet.paste(image, (left, top))
        draw.text((left + 2, top + THUMBNAIL[1] + 10), title, fill="#f4efe5", font=font)
        draw.text((left + 2, top + THUMBNAIL[1] + 44), subtitle, fill="#b9c5d3", font=small_font)

    output = REVIEW / "silhouette_options.png"
    sheet.save(output, optimize=True)
    print(f"Wrote {output} size={sheet.size}; source options={len(OPTIONS)}")


if __name__ == "__main__":
    main()
