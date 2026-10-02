# Gamepad glyph variants

This second vector asset batch complements the first eight glyphs in Bontago-mp0.37. It adds X, Y, RB, LT, RT, D-pad down/left/right, and left/right stick. `tools/generate_gamepad_glyphs.py` writes the ten standalone sources deterministically.

All files are 64×64 SVGs with a dark 3 px silhouette and no fonts or filters. The D-pad uses a highlighted arm; face buttons retain both letter and color. The shoulder and trigger caps keep their labels as paths, so import does not depend on local fonts. These files are for future UI art integration; `ui/InputGlyph.gd` remains untouched.

Review the sources at 24 and 32 px on light and dark backgrounds. Some platform-specific controls (Start/Back, touchpad, paddles) and keyboard/mouse variants remain for later packages.

Review (Claude, 2026-10-02): RB, LT and RT were redrawn with filled letterforms inside y 20-38 to match `gamepad_lb.svg`; the first version used stroked letters that touched the y=43 lip. `docs/art_mockups/gamepad_glyphs_v2.png` predates that fix.
