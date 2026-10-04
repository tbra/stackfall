# HUD feedback pictograms v1

Four original32x32 SVGs extending the existing HUD status art family:
ink#26323A, paper#F5EBD6, teal#75CBD1, coral#EB6B5C and brass#E8B85D.
They supplement existing `height_art`, `territory_art`, `timer_art`, gift and
locked icons. They do not replace them or change live HUD code.

| File | Current game meaning | Pair with |
| --- | --- | --- |
| held_block_height.svg | Height of the held block above the surface | Block height number in `set_tower_and_block_height` |
| goal_capture.svg | A team is capturing the circular goal | Actual capture ring and team identity |
| placement_rejected.svg | Placement did not happen | Actual rejection reason from `show_reject` |
| placement_relocated.svg | Placement happened at an automatic valid point in own territory | Existing relocation message from `show_relocated` |

The held-block icon has a single floating cube and vertical measurement arrow;
it is distinct from the existing tallest-tower pictogram. Capture uses a round
goal and inward arrows, preserving the minimap's circle/diamond distinction.
Rejected uses a cross badge; relocated uses a travel arrow and destination.
These cues differ in shape as well as hue. No static fraction is encoded by
the capture icon; runtime progress must remain an actual changing indicator.

Keep labels, units, team information and reasons. These dark-ink icons belong
on the existing paper/field panel surfaces. Do not place them directly over an
unbacked dark sky or monochrome-tint the entire art. Prefer24–32px at1080p;
16px samples are supporting small-size checks and should retain accompanying
text. Preserve aspect ratio and linear SVG raster filtering when resizing.

## Provenance and reproduction

Original Codex SVG paths; no external artwork or embedded font. The generator
`python tools/generate_hud_feedback_icons.py` recreates all four sources and
`catalog.json`, including their intended semantics.

Copy `source_art/hud_feedback_icons_v1/project.godot.review` to a temporary
helper directory as `project.godot`, alongside `rasterize.gd`, then:

```powershell
godot --headless --path $helper --script "$helper/rasterize.gd" -- "$checkout/assets/ui/hud/feedback_icons_v1" "$helper/png"
python tools/generate_hud_feedback_icons.py --review-native "$helper/png"
```

Review uses Python3.8+ and Pillow. Keep the project's `.review` suffix inside
the game repository to avoid a nested-project warning.

## Evidence and limits

`docs/art_mockups/hud_feedback_icons_v1/review.png` compares native16/24/32/48px
rasters on paper and field cards in a dark surround, plus grayscale. The colors
come from the existing design-system tokens. This is a source-art review page,
not a runtime HUD screenshot or claim about actual HUD layout/contrast.

One isolated Godot4.7.2 headless helper exited0 cleanly, within a90s deadline.
Exact raster dimensions, nonempty alpha, transparent outer edges, and four
unique silhouettes passed. Deterministic regeneration, SVG XML and Python
syntax were checked. No game window or full suite was run. Claude reviews the
candidate and chooses placement before any live HUD wiring.
