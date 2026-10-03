# Compact gift pictograms

Candidate vector art for all fourteen `config/specials` gift IDs. These are
original compact symbols using the design system's ink, paper, coral, teal and
brass palette. Each gift has its own silhouette. No live HUD wiring is included.

## Atlas use

`atlas.svg` is a transparent 256 × 256 image containing a 4 × 4 grid of 64 × 64
cells. `regions.json` maps exact gift IDs to `[x, y, width, height]` rectangles.
The final two cells are empty. Create an `AtlasTexture` using the imported atlas
and the corresponding `Rect2`, and display it at 24, 32 or 48 pixels. Keep the
atlas at its default import scale; scale region coordinates by the same factor
if you change that scale. Disable mipmaps for small HUD use and avoid sampling
outside each cell. Shapes have padding, but atlas-wide mipmaps can mix cells.

`review.png` shows the native Godot SVG raster at all three sizes on paper and
ink panels. Dark outlines merge with the ink panel; colored and paper shapes
remain visible. Visual acceptance and the final HUD background belong to review.

## Reproduce

From this checkout, run:

```powershell
python tools/generate_gift_pictograms.py
$rasterOutput = Join-Path $env:TEMP 'codex_gift_pictogram_rasters'
godot --headless --path source_art/gift_pictograms_v1 --script rasterize.gd -- "$PWD/assets/ui/gift_pictograms_v1/atlas.svg" $rasterOutput
python tools/generate_gift_pictograms.py --review
```

The isolated raster project is ignored by the game asset importer. The generator
checks exact gift registry coverage; the native raster script checks dimensions
and conversion errors. Review assembly checks actual raster alpha bounds: all fourteen
symbols have a transparent outer border at each size, and the final two cells
are empty. No engine window or full game suite is required.
