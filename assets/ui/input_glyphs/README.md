# Stackfall input glyph source assets

These SVGs are standalone source art for the device prompt family defined in `docs/ART_DESIGN_SYSTEM.md` (candidate in `codex/assets-design-system`). They do not change the live `ui/InputGlyph.gd` rendering path.

All glyphs use a 64×64 viewBox, 3 px dark outline, no filters, and a title for accessible previews. The intended rendered height is about 32 px at 1080p. The colored gamepad face button remains lettered; the D-pad uses an additional shape cue. `key_e.svg` is the initial letter key specimen; future bindings need their own legend exports from this template.

Current set: E, up arrow, mouse left, mouse wheel, gamepad A, gamepad B, D-pad up, and left shoulder. Add right, X/Y, triggers, sticks, and other key legends as separate source variants when the production prompt inventory is finalized.

Review at 24, 32, and 48 px over both paper and a dark sky. Source colors are not meant for automatic theme tinting. No external artwork or fonts are embedded.

## Stick motion and default combo specimens

`gamepad_motion_catalog.json` lists eight directional stick glyphs,L3/R3 clicks,
and two combo examples. See `GAMEPAD_MOTION_GLYPHS.md` for dimensions,provenance,
reproduction and review. Composite examples describe default bindings only;
remapped prompts must compose the current binding glyphs at runtime.
