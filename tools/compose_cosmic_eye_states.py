"""Make a compact visual comparison of the three transparent eye overlays."""

from pathlib import Path
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
PREVIEW = ROOT / "docs/art_mockups/cosmic_horizon_silhouette_preview.png"
ASSETS = ROOT / "assets/maps/cosmic_horror"
OUT = ROOT / "docs/art_mockups/cosmic_horizon_eye_states.png"


def main() -> None:
    backdrop = Image.open(PREVIEW).convert("RGBA")
    result = Image.new("RGB", (2400, 332), "#17152C")
    draw = ImageDraw.Draw(result)
    for index, state in enumerate(("dim", "watch", "flare")):
        eye = Image.open(ASSETS / f"horizon_eye_{state}.png").convert("RGBA")
        if eye.size != (1600, 520):
            raise ValueError(f"Wrong overlay size: {state}: {eye.size}")
        panel = backdrop.copy()
        panel.alpha_composite(eye, (0, 40))
        panel = panel.resize((800, 300), Image.Resampling.LANCZOS)
        result.paste(panel.convert("RGB"), (800 * index, 0))
        draw.text((800 * index + 24, 307), state.upper(), fill="#F5EBD6")
    result.save(OUT)
    print(f"Composed {OUT.relative_to(ROOT)} ({result.width}x{result.height})")


if __name__ == "__main__":
    main()
