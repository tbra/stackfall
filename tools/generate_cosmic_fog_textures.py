"""Make deterministic, wrap-safe alpha textures for distant cosmic fog layers."""

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/maps/cosmic_horror/fog_textures"
PREVIEW = ROOT / "docs/art_mockups/cosmic_fog_texture_preview.png"
SIZE = 512


def periodic_field(seed: int, scale: float) -> np.ndarray:
    rng = np.random.default_rng(seed)
    white = rng.standard_normal((SIZE, SIZE))
    axis = np.fft.fftfreq(SIZE) * SIZE
    ky, kx = np.meshgrid(axis, axis, indexing="ij")
    frequency = np.sqrt(kx * kx + ky * ky)
    envelope = np.where(frequency == 0, 0.0, np.power(1.0 + frequency / scale, -2.4))
    field = np.fft.ifft2(np.fft.fft2(white) * envelope).real
    field -= field.mean()
    field /= field.std()
    return field


def softstep(values: np.ndarray) -> np.ndarray:
    values = np.clip(values, 0.0, 1.0)
    return values * values * (3.0 - 2.0 * values)


def write_texture(name: str, seed: int, density: float, opacity: float, shift: int = 0) -> Image.Image:
    broad = periodic_field(seed, 1.4)
    detail = periodic_field(seed + 913, 5.0)
    field = broad * 0.82 + detail * 0.18
    low = np.quantile(field, density)
    high = np.quantile(field, 0.97)
    alpha = softstep((field - low) / (high - low)) * opacity
    alpha = np.roll(alpha, shift, axis=1)
    bytes_alpha = np.uint8(np.rint(alpha * 255))
    # Duplicate first row/column so ordinary repeat sampling has no visible seam.
    bytes_alpha[-1, :] = bytes_alpha[0, :]
    bytes_alpha[:, -1] = bytes_alpha[:, 0]
    rgba = np.empty((SIZE, SIZE, 4), dtype=np.uint8)
    rgba[:, :, :3] = (206, 220, 227)
    rgba[:, :, 3] = bytes_alpha
    image = Image.fromarray(rgba, "RGBA")
    image.save(OUT / f"{name}.png")
    return image


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    textures = [
        ("fog_veil", write_texture("fog_veil", 1803, 0.25, 0.40)),
        ("fog_wisps", write_texture("fog_wisps", 2718, 0.58, 0.62)),
        ("fog_wisps_offset", write_texture("fog_wisps_offset", 2718, 0.58, 0.62, SIZE // 3)),
    ]
    sheet = Image.new("RGB", (SIZE * 3, SIZE + 42), (33, 50, 64))
    for index, (name, layer) in enumerate(textures):
        tile = Image.new("RGBA", (SIZE, SIZE), (33, 50, 64, 255))
        tile.alpha_composite(layer)
        sheet.paste(tile.convert("RGB"), (index * SIZE, 0))
    draw = ImageDraw.Draw(sheet)
    for index, (name, _) in enumerate(textures):
        draw.text((index * SIZE + 14, SIZE + 12), name.replace("_", " ").upper(), fill=(245, 235, 214))
    sheet.save(PREVIEW)
    print(f"Wrote {len(textures)} 512x512 RGBA tiles and {PREVIEW.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
