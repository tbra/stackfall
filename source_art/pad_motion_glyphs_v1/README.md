# Isolated native SVG review helper

Copy project.godot.review into TEMP as project.godot and copy rasterize.gd beside
it. Arguments: absolute assets/ui/input_glyphs directory,then a TEMP output folder
named codex_pad_motion_rasters. The helper draws12SVGs at24/32/48px and exits.
Use tools/generate_pad_motion_glyphs.py --review afterwards. Keeping the project
filename as .review avoids a nested project during game imports.
