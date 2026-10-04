# Lobby icon candidates

Fourteen original SVGs on a 24 x 24 grid, with 2-unit rounded strokes and white
source colour. No fonts, filters, embedded images or external artwork. Reproduce
with `python tools/generate_lobby_icons.py`. `catalog.json` lists all meanings.

Included: GAME, ROUND, GIFTS and EXPERIMENTS section symbols; add/remove bot;
teams; easy/normal/hard difficulty (one/two/three bars); random team (dice);
colour swap; and advanced disclosure chevrons (expanded down, collapsed right).
The difficulty symbols supplement their labels rather than replacing the names.

The white source preserves the existing tint contract in
`ui/theme/MenuStyleFactory.gd`: `apply_ink()` gives a Button's icon the same ink
as its label across draw states. Header TextureRects need their parent's theme
ink applied through the existing UI path. Do not bake a palette into these SVGs.
Keep the project's shared UI scaling rule when integrating them.

## Native review

`docs/art_mockups/lobby_icons_v1/review.png` compares 16/24/32 px over light, dark
and grayscale backgrounds. All 42 native Godot rasters passed dimensions,
transparent outer padding, unique alpha silhouettes and white-only visible RGB.
XML/catalog coverage, generator syntax and diff checks also pass. The sheet was
visually inspected, including 16 px bot controls and disclosure arrows.

The isolated native run returned 0 with no errors or warnings. Log:
Windows TEMP/codex-lobby-icons-native.log. No game window or test suite ran.
These are asset candidates; actual Lobby layout, focus/navigation, live resizing
and multi-resolution UI acceptance remain integration work for Claude.

## Reproduce the review

Copy `source_art/lobby_icons_v1/project.godot.review` into a temporary directory
as `project.godot`, and copy `rasterize.gd` beside it. Run that temporary project
headlessly with `-s rasterize.gd -- <absolute lobby_v1 directory> <TEMP folder
named codex_lobby_icon_rasters>`. Then run
`python tools/generate_lobby_icons.py --review`.
The .review filename avoids a nested Godot project in the game checkout.
