> **SUPERSEDED (2026-10-10, Bontago-hfa.2):** the pastel "layered" design system below is replaced by the Stackfall Arcade system. See `docs/UI_RESKIN_PLAN.md` and `docs/ui_reskin/` (tokens.json, components.md); the runtime tokens live in `config/arcade_visual_tuning.tres`. Kept for history only.

# Stackfall asset design system — candidate v1

This is the visual contract for **new art assets**. It records the current UI theme and gives future glyph, HUD, sound, and model assets one consistent direction. It does not change game behavior or replace the live Godot theme. See [the specimen sheet](art_mockups/stackfall_design_system_v1.svg) for the visual reference.

## Character

Stackfall is a playful tabletop contest above a huge sky. The interface should feel like painted game pieces: warm paper surfaces, dark precise ink, coral actions, and small flashes of brass. Silhouettes should read quickly while the camera, weather, and background move. Keep the playful shape language; avoid photoreal chrome, horror texture on the core UI, and tiny ornamental detail.

The cosmic horror map can bend the **environment** toward violet, deep teal, and black. Keep critical prompts, status, and player identity legible with the core UI tokens.

## Color tokens

The first six rows are derived from `ui/theme/stackfall_theme.tres` on main at `4c9ea44`. Hex values are rounded from Godot's float colors. New art can use the three accent colors below; they are proposals, not live theme values.

| Token | Hex | Use |
| --- | --- | --- |
| `ink` | `#26323A` | Main type, outlines, dark glyphs |
| `paper` | `#F5EBD6` | Main panel surface |
| `field` | `#FFFAF0` | Inputs and inner cards |
| `border` | `#C7AD85` | Quiet edges, dividers |
| `coral` | `#EB6B5C` | Primary action, active selection |
| `coral_hover` | `#F28C7A` | Hover artwork |
| `sky_teal` | `#75CBD1` | Secondary information, cool light |
| `brass` | `#E8B85D` | Gift reward, focus sparkle |
| `deep_violet` | `#51445F` | Rare special art, cosmic map cue |

Use `ink` on `paper` or `field` for ordinary text. White lettering belongs on coral or other saturated fills only when contrast holds at final size. Never encode player, gift, or weather state with hue alone: pair it with shape, label, or pattern. Reserve brass for a moment of attention so every element does not compete for it.

## Type and spacing

- **Family:** Manrope, from `assets/ui/fonts/Manrope-Regular.ttf`. Use the existing theme's weight variations; do not introduce a second UI family.
- **Type scale at 1080p:** caption 11, body 14, control 14–16, card title 24, hero title 44 px. These track the current theme and menu usage. Prefer fewer sizes in one view.
- **Safe minimum:** 11 px captions only for supporting information. Gameplay decisions and control prompts need at least 14 px at 1080p.
- **Spacing unit:** 4 px. Use 8 inside compact glyphs, 12–16 between peer controls, 20 in panels, 24–32 between groups.
- **Alignment:** text left aligned within a panel; values and controls share a visible baseline. Avoid floating captions with no associated control.
- **Sentence case** for labels. Short all-caps is reserved for tiny category stamps and engraved 3D markings.

## Shape and linework

The live theme uses 18 px panel corners, 16 px button corners, 10 px fields, and 2 px panel borders. New UI art should sit naturally against those radii. Use a confident outline in `ink` or a darker local material color, usually 2–3 px at a 32 px icon size. Round line caps and joins. One broad highlight and one underside shadow are enough to make a small icon feel like an object. Avoid hairline strokes, soft blur, and multiple thin concentric rings.

For a pictogram, draw its silhouette first. Check at 24, 32, and 48 px. At 24 px, remove internal detail before increasing stroke density. Optical alignment matters more than mathematical centering: arrows, sound waves, and asymmetrical gifts may need a 1 px visual nudge.

## Input glyphs

The game currently draws key, mouse, and controller prompts in `ui/InputGlyph.gd`. Standalone art should use the same grammar so future replacements can be made without retraining players.

| Family | Container | State cue | Required labels |
| --- | --- | --- | --- |
| Keyboard | Soft rectangular keycap with dark lower lip | Filled face and ink legend | Esc, Enter, Space, Tab, arrows, letters as needed |
| Mouse | One recognizable mouse shell with a split upper face | Coral fill on the active button or wheel | Left, right, middle, wheel up/down, movement |
| Gamepad face | Round button with thick rim | A green, B coral/red, X blue, Y gold; letter remains visible | A/B/X/Y and platform-neutral action text nearby |
| D-pad | Four-arm cross | Coral active arm plus dark outline | Up/down/left/right |
| Shoulder/trigger | Wide shallow cap | Ink label; trigger has a deeper profile | LB/RB/LT/RT or platform equivalent |
| Stick | Circular well and short stem | Direction arrow or click dot | Left/right, directions, L3/R3 |

Keep glyph height near the current 32 px control glyph. A glyph's outline must survive downscaling without a fuzzy raster edge. Source vectors should have a `viewBox`, no filters, and explicit paths. Give every SVG a plain-language accessible name in its metadata or adjacent usage data. Do not bake an instruction such as “Press A” into a glyph: the prompt text must remain localizable and device aware.

## HUD and UI assets

- **Information layers:** one primary action/state per card; score and time in stable positions; momentary feedback in an accent layer. Do not let a decoration compete with held gift or placement feedback.
- **Cards:** paper face, 2 px border, quiet lower shadow. Compact cards can reduce corner radius to 10 px, but keep the same edge and fill language.
- **Meters:** one continuous fill with a hard readable end; four-pixel ticks only when they convey discrete steps. Include a numeric or text fallback for critical status.
- **Gift cards:** silhouette at a shared apparent scale, warm highlight at the active edge, simple category mark. Icons should remain distinct in grayscale.
- **States:** normal, hover/focus, pressed, disabled, warning, and success need named art or a defined tint treatment. Focus needs a visible 3 px ink outline, matching the theme.
- **Layout:** protect a 16 px outer margin at 720p. Validate designs at 1280×720 and ultrawide; never solve a crowded view with smaller type alone.

## 3D asset language

- **Proportions:** use the ordinary block as the size ruler. A held gift should fit inside roughly one block's silhouette unless its function needs an unmistakable extension.
- **Primary read:** identify an asset from shape alone at the normal camera distance. Use one dominant mass and at most two supporting forms.
- **Surface:** broad cel-lit planes, controlled roughness, and a small number of material regions. Put detail in silhouette, bevel, or one emblem before adding texture noise.
- **Edges:** bevel enough to catch a highlight; avoid razor-sharp toy pieces and fully rounded blobs. Outlines or dark undersides should stay stable when the object spins.
- **Color:** map the same family colors onto materials. Coral marks action/danger, teal marks motion/cool, brass marks reward, violet is rare or cosmic. Keep value contrast clear against bright sky and dark storm.
- **Delivery:** export source plus Godot-ready `.glb` or `.tscn`, keep pivots at useful placement centers, and include a neutral-light turntable image. This is a delivery rule for future models; this package contains no model.

## Sound identity

Sound assets should match the shape language: short, tactile attacks with a small melodic or airy tail. A block placement can have a low wooden/ceramic body; menu motion uses a lighter click; gifts add a three-note glint; weather stays diffuse and does not mask placement. Keep distinct events distinct by timing and register, not simply by loudness. Deliver dry source WAV and game-ready file, trim silence, avoid clipping, and document the intended trigger and loop behavior. Audition against music and at low playback level before integration.

## Asset review checklist

1. Show the asset at intended in-game size and against both paper and a sky/storm background.
2. Check silhouette and text at 1280×720. Check icon edges at 24, 32, and 48 px.
3. Confirm contrast and shape cues in grayscale. Check that no critical state relies only on color.
4. For 3D, inspect from the normal camera and as a rotating thumbnail. For sound, listen in context at low level.
5. Record source file, export file, dimensions or duration, and intended usage in the handoff.

## Relationship to current files

`ui/theme/stackfall_theme.tres` remains the live UI source. `ui/InputGlyph.gd` remains the live input glyph implementation. `config/menu_visual_tuning.tres` and the HUD tuning resources still control runtime layout. This candidate defines the shared art direction for later asset packages; adopting a token in the game requires a separate implementation and review.
