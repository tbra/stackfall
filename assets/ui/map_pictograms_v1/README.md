# Arena shape pictograms

Five vector silhouette icons in MatchConfig.MapVariant order: Round, Oval,
Ring, Twin and Cross. A neutral cream fill and dark rounded contour match
Codex's gift/weather pictogram sets. Geometry identifies the shape without color.

`atlas.svg` is 256x128, with 64x64 regions recorded in `regions.json`.
The final three cells are transparent. Use an AtlasTexture with its region from
that manifest and filter clipping enabled. Labels remain normal UI text; these
icons do not replace map names or indicate arena size. Scale through the shared
UI rule and keep the SVG source; avoid separate per-screen scale factors.

This is art only: no Lobby or live UI wiring. Twin depicts the joined lobes;
Ring has a genuinely transparent center. The silhouettes illustrate selected
map geometry, not the current game's round visual fallback for some variants.

## Reproduce

Run `python tools/generate_map_pictograms.py`. Then use the isolated headless
Godot helper in `source_art/map_pictograms_v1`: copy `project.godot.review`
to a temporary folder as `project.godot`, copy `rasterize.gd` beside it, then run
that temporary project with `-s rasterize.gd --` followed
by the absolute atlas path and a temporary raster output directory named
`codex_map_pictogram_rasters`. Run the Python generator with `--review` to inspect
native 24/32/48px rasterizations on light, dark and grayscale backgrounds.

The review verifies exact enum coverage, native dimensions, outer alpha padding,
three empty cells, distinct icons and the transparent Ring center. Validation
and handoff are recorded in Bontago-mp0.110. Review image is generated only after
native rasterization succeeds.
