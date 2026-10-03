# Additional gamepad button glyphs

`gamepad_guide.svg` and `gamepad_misc.svg` cover two named `InputGlyph.gd` button states outside the earlier face/shoulder/stick/Start/Back set. `gamepad_button_blank.svg` supplies the same ink-and-paper button shell without a baked label, so a future prompt renderer can overlay the actual remapped button name (including `BtnN` fallback or platform-specific labels).

`docs/art_mockups/gamepad_generic_glyphs_v1.svg` and its PNG render compare the art at 48, 32, and 24 px. Regenerate with `python tools/generate_gamepad_generic_glyphs.py`.

These are candidate assets only. The gamepad input renderer and bindings are unchanged. Guide/Misc symbols vary by platform; Claude should use platform text alongside these neutral pictograms when needed.
