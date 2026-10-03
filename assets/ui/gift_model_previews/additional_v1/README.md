# Additional gift model preview candidates

Seven transparent 384×384 PNGs for black hole, cat, freeze, glue, magnet, paintball and Stackfall, rendered from their `*_v1.glb` models at frame 1. The camera, lighting and 80% framing target match the original gift candidate pack in Bontago-mp0.78. The contact sheet includes light-background insets for alpha-edge review.

Rebuild with Blender 4.5: `blender -b --python tools/render_additional_gift_model_icons.py`. Generate the sheet with system Python and Pillow: `python tools/render_additional_gift_model_icons.py --sheet`.

Review at actual HUD size before adopting alongside the corresponding held models. Blender materials differ from the game's toon shader; the pack can also guide framing for a Godot rerender. The live HUD preview folder is unchanged by this package.
