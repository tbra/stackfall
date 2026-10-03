# Mouse remap prompt candidates

Four standalone 64×64 SVGs cover the remaining named `InputGlyph.gd` mouse inputs: wheel left/right and side buttons MB4/MB5. The mouse shell follows the existing left/right/middle/up/down glyph set. Coral highlights the active wheel tilt or side tab; the direction and tab position remain visible without color.

`docs/art_mockups/mouse_remap_glyphs_v1.svg` and its PNG render compare 48, 32, and 24 px. Regenerate with `python tools/generate_mouse_remap_glyphs.py`.

These are asset candidates. `ui/InputGlyph.gd`, bindings, and game scenes are unchanged. Review their shape and intended size before integration.
