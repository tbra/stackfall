# Cel impact dust and chips v1

Original Codex vector art for Bontago-mp0.109. Two1024x1024 RGBA atlases contain
16frames each in a4x4 grid of256px cells. Rounded cel dust lobes expand away
from one contact point; small neutral chips rotate outward and disappear early.
The burst thins to a faint tail, then ends in a completely clear final frame.
No downloaded images, existing sprites or third-party art were used.

- `impact_hard.png`: normal compact burst for block/block or block/disc contact.
- `impact_soft.png`: same timing and pivot,55% linear art scale, fewer chips.
- `manifest.json`: row-major regions, pivot, timing, terminal frame and seed.

## Integration

Play once at30fps:16frames, approximately0.533s. Frame15 is transparent; retire
the effect after it. Keep the flipbook on a consistent fixed quad; cell content
expands within it. Contact pivot is(128,156) in each256px cell, UV(.5,.609375).
Offset the quad so that pivot lies at the impact point; a center pivot would
make the dust appear below the contact. Align the puff's rise with the chosen
presentation up/impact normal and billboard consistently for a moving camera.

The palette is neutral cool dust/chips for both surfaces. It can receive a
restrained material tint; avoid tinting it so dark that it vanishes on the disc.
Use straight alpha and linear filtering, not additive blending. Maintain depth
occlusion with the blocks and disc. Cells have at least12px transparent padding;
disable mipmaps or build per-cell mip gutters to avoid neighboring-frame bleed.

Choose one variant per confirmed impact strength. Both use the same quad size;
soft art is already smaller, so do not automatically apply another55% shrink.
Hook presentation to the existing replicated-impact path during integration,
preserve authoritative impact thresholds/rate limits and Low preset behavior.
This package changes no physics, networking, particle code or gameplay state.

## Reproduce

`python tools/generate_impact_puff.py` regenerates32frame SVGs,2atlas SVGs and
manifest. Copy `source_art/impact_puff_v1/project.godot.review` to a temporary
folder as `project.godot`, alongside `rasterize.gd`, then:

```powershell
godot --headless --path $helper --script "$helper/rasterize.gd" -- "$checkout/source_art/impact_puff_v1" "$helper/png"
python tools/generate_impact_puff.py --review-native "$helper/png"
```

Python3.8+ and Pillow are needed for review. Source uses seeded original geometry.
The helper never boots the game. Keep its `.review` suffix inside this repo.

## Evidence and limits

`docs/art_mockups/impact_puff_v1/contact_sheet.png` shows all32frames.
`motion.gif` compares both variants over real bright sky and dark disc crops
from `loading_arena_v2/round_dawn.png`, at full cell size for close inspection.
It repeats only for review, with a pause after the clear frame. GIF timing uses
30/30/40ms ticks to approximate30fps within its10ms time resolution.
`motion_peak.png` gives a still from the burst. These are static background
composites; live contact placement, density, motion and camera acceptance remain
with Claude's integration review.

Native Godot4.7.2 generated34rasters with clean exit0. Three bounded headless
runs were used: initial check caught a duplicate empty terminal tail; correction
passed native generation and revealed subpixel edge-AA rounding in8pixels;
final source revision softened the dust silhouette after visual review. All
final checks pass: exact atlas dimensions,16distinct frames per variant,
12px+padding, terminal alpha clear, soft occupied area below40% of normal,
frame14 alpha mass below3% of peak, source regeneration, Python syntax and XML.
Native atlas/individual rasters may differ by at most1alpha level and2levels
of premultiplied RGB in at most64pixels per cell; this accommodates harmless
subpixel raster rounding. No full suite or game window was run.
