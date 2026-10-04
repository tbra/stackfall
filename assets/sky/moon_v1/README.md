# Cel moon disc and halo v1

Original Codex vector art for Bontago-mp0.107. Both textures are 1024x1024 RGBA
with transparent padding. The full moon uses broad cool cel bands, restrained
maria and a few simple crater rims. Its palette follows the cool moon colors in
`shaders/night_sky.gdshader`, with modest contrast suitable for the procedural
night sky. No downloaded images or third-party art were used.

- `moon_disc.png`: center (512,512), radius400px,112px padding.
- `moon_halo.png`: same center, radius480px,32px padding, smooth blue alpha falloff.
- `manifest.json`: geometry, palette, seed and static preview placement.

## Integration

This is a full-disc asset; phases are optional and may be added with a runtime
mask. Align the disc with the chosen sky moon direction and the night key light.
Draw behind the clouds and foreground, only during the night contribution.
Use an unlit sky path and straight-alpha blending so the baked light bands do
not receive another directional shade. Start with white tint and no extra bloom.
The halo is a separate low-opacity layer: alpha composite it behind the disc,
or use its alpha as intensity for an additive sky glow. Do not add its constant
RGB without multiplying by alpha.

The visible disc diameter is800/1024 of its texture quad. Compute the intended
angular size from that visible radius when integrating. The static preview uses
a96px disc quad and432px halo quad, centered at(960,145) on1280x720; these are
illustrative choices. The old shader's3.2-degree radius and22-degree glow are
reference tuning, not exact settings proven by this screen-space composite.
Preserve existing cloud occlusion, cycle time, weather blending and networking.
No sky shader, theme, moon direction or game code is changed in this package.

## Reproduce

Run `python tools/generate_moon_assets.py` for SVG sources and manifest. Copy
`source_art/moon_v1/project.godot.review` to a temporary directory as
`project.godot`, alongside `rasterize.gd`, then:

```powershell
godot --headless --path $helper --script "$helper/rasterize.gd" -- "$checkout/source_art/moon_v1" "$helper/png"
python tools/generate_moon_assets.py --review-native "$helper/png"
```

Review requires Python3.8+ and Pillow. The helper stays separate from the game.
Its `.review` suffix prevents a nested-project warning when staged into the repo.

## Evidence and limits

`docs/art_mockups/moon_v1/review.png` shows both textures, native64/128px samples,
and a static composite over the actual rendered `loading_arena_v2/round_night.png`.
`night_composite.png` is the standalone1280x720 art proposal. The composite does
not simulate cloud occlusion or prove moving-camera sky behavior.

The isolated Godot4.7.2 helper exited0 cleanly. Exact1024px RGBA dimensions,
transparent edge padding, opaque disc center, nonempty64/128px rasters, and
monotonic halo alpha along all four cardinal radii passed. Review hashes are in
`verification.json`. No full suite or game window was run. Live sky placement,
phase handling and visual acceptance remain with Claude's integration review.
