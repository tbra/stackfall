# Remappable keyboard glyph assets

This package extends the first keycap set in two ways:

- Fourteen hand-drawn vector shortcut keys: W/A/S/D/F/Q/R/G/C/X/Y/Z/1/2.
- An atlas of **214 displayable Godot 4.7.2 keycodes plus `KEY_UNKNOWN`** exposed by `OS.get_keycode_string` for printable ASCII and the engine's named special-key range. Each code has a transparent 128×128 PNG mapped by `key_atlas/catalog.json`. The catalog includes punctuation, both letter cases, function keys F1–F35, modifiers, navigation, keypad, media, launch keys, and a `?` fallback. `KEY_NONE` and `KEY_SPECIAL` are sentinels rather than bindable keys.

Every atlas keycap uses the bundled Manrope font, paper face, ink outline, and lower lip. Four source pixels per 32px prompt and mipmapped imports keep edges crisp. `docs/art_mockups/keycap_gallery_printable.png`, `keycap_gallery_special.png`, and `keycap_small_size_qa.png` are for review.

Remapping can also produce international or future key labels outside the finite Godot catalog. `key_atlas/keycap_blank.svg` and `keycap_blank.png` are label-free source art so a UI renderer can place the actual key name at runtime. `python tools/generate_keycap_atlas.py --label 'Ö' --output path.png` renders a custom label when the bundled font supports it. The full key name remains in the catalog for accessibility even when the visible keycap uses a short form.

To regenerate the standard atlas: `godot --headless --path . --script tools/scan_godot_key_catalog.gd`, then `python tools/generate_keycap_atlas.py`. The 14 vector shortcuts come from `python tools/generate_bound_key_glyphs.py`.

These are candidate assets only. `ui/InputGlyph.gd`, bindings, menus, and game scenes are unchanged. Runtime use of these assets, including arbitrary remaps, requires Claude's separate integration and review.
