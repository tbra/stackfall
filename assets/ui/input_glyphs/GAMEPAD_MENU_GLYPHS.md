# Gamepad Start and Back candidates

These two 64×64 standalone SVGs fill the Start/Back source-art gap named in `GAMEPAD_VARIANTS.md`. Start uses three menu bars and a coral dot; Back uses two overlapping view cards. Both share the warm paper button shell, ink outline, and lower lip of the existing LB/RB family. Their meaning remains readable by shape without color.

Start is currently bound to pause; Back is a named generic button in `ui/InputGlyph.gd`. No game or input code has changed. `docs/art_mockups/gamepad_menu_glyphs_v1.svg` and its PNG render compare 48, 32 and 24 px. Regenerate with `python tools/generate_gamepad_menu_glyphs.py`.

Review with platform-specific labels before using on PlayStation or Nintendo controllers.
