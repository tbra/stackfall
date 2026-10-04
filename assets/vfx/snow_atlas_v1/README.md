# Cel snow sprite atlas v1

Original Codex vector art for Bontago-mp0.106: 8 six-spoke crystals and 8 irregular
faceted snow clumps. No downloaded images or third-party samples were used.
The white/cool-blue palette follows SnowTuning's cel snow tones; a translucent
outer rim and slate border preserve the silhouette on bright skies.

`snow_atlas.png` is 512x512 RGBA, 4x4 cells of128x128, with top-left row-major
indices0..15. `manifest.json` gives exact pixel regions and UV rectangles.
Each cell has at least14px transparent padding. Preserve straight alpha and
linear filtering. Avoid sampling adjacent cells when using mipmaps: disable
mipmaps for small particles or build per-cell mip gutters during integration.

Treat cells as random static variants, not a16-frame animation. Use UV=(localUV
+ cell)/4 or an equivalent AtlasTexture region. Full-color art already includes
cel shading and border; avoid applying the existing procedural circular flake
mask or a second outline. Preserve the current camera-facing billboards,
angular size limits, ramp density, Low preset count, wind and gameplay snow.
This package does not alter the weather shader or presentation code.

## Reproduce

Run `python tools/generate_snow_atlas.py` for the17SVG sources and manifest.
Copy `source_art/snow_atlas_v1/project.godot.review` to a temporary directory as
`project.godot`, alongside `rasterize.gd`. Then run the tiny native helper:

```powershell
godot --headless --path $helper --script "$helper/rasterize.gd" -- "$checkout/source_art/snow_atlas_v1" "$helper/png"
python tools/generate_snow_atlas.py --review-native "$helper/png"
```

Python3.8+ and Pillow are needed for review. The helper never boots the game.
`project.godot.review` is intentionally named to avoid nested Godot projects.

## Evidence and limits

`docs/art_mockups/snow_atlas_v1/review.png` shows all16tiles and native8/16/32px
samples, plus32/16px compositing on real dawn sky and dark disc crops from
`assets/ui/loading_arena_v2/round_dawn.png`. The background crops are enlarged
for review; the sprites are at the labeled screen sizes. These are contact-sheet
composites, not a live snowfall capture. Live density, motion and camera acceptance
remain with Claude's integration review.

Verification checks exact512px RGBA atlas size,16nonempty unique tiles,
14px+padding, exact matching atlas/individual native rasters, and alpha-safe
8/16/32/128px raster bounds. Native Godot4.7.2 helper exited0 without errors.
No full suite or game window was run.
