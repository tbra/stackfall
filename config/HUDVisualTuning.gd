class_name HUDVisualTuning
extends Resource
## Tunables for M7 P5 (docs/M7_PLAN.md, "P5 -- HUD minimap + reskin") and its
## Bontago-mp0.3.3 restyle: the minimap's framing/refresh cadence and the
## layered-pastel/coral -> mockup-08 palette used to restyle ui/HUD.tscn
## (docs/M7_ART_DIRECTION.md's HUD styling section). CLAUDE.md: "No magic
## numbers... every tunable value belongs in a Resource under res://config/".
##
## This is presentation only, same split TerritoryVisuals.gd documents for
## the disk: nothing here changes a rule. HUD.gd's own layout geometry
## (offset_left/offset_top pixel positions in ui/HUD.tscn) stays inline,
## following that scene's own pre-M7 DECISION that pure screen-space drawing
## geometry is not worth resourcing -- only the minimap's world-space
## framing and the reskin's *colors* (the part the mockups actually specify)
## live here.
##
## Loaded once as config/hud_visual_tuning.tres.

## -- Minimap (Bontago-mp0.3.3, owner: minimap "reflecting the sky depending
## on the camera angle" -- see ui/Minimap.gd's own class doc DECISION for the
## fix: a 2D draw straight from the live TerritoryRaster, camera-relative, no
## SubViewport/Camera3D at all, so there is no camera angle for it to depend
## on) -----------------------------------------------------------------------
## Square pixel size of the minimap's rendered image/Control in the HUD
## corner.
@export var minimap_size_px: int = 160
## Extra meters of half-extent beyond MapDef.field_radius the minimap frames,
## so the disk's own rim (and anything just past it, e.g. a home flag) is
## never clipped at the minimap's edge.
@export var minimap_zoom_margin_m: float = 6.0
## How often the minimap's image is rebuilt from the live TerritoryRaster, in
## Hz. Throttled the same way the old SubViewport was (a corner-of-the-screen
## top-down readout does not need every-frame freshness), just driving a CPU
## image rebuild now instead of a render pass.
@export var minimap_refresh_hz: float = 8.0
## Radius, in HUD pixels, of the small diamond beacon glyph the minimap
## draws at each slot's home-flag position (docs/art_mockups/
## 08-cel-shaded-home-beacons.png).
@export var minimap_beacon_radius_px: float = 4.0
## Goal beacon glyph (filled circle, distinct from the home diamonds).
@export var minimap_goal_radius_px: float = 5.0
@export var minimap_goal_neutral_color: Color = Color(0.85, 0.85, 0.85)
@export var minimap_goal_contested_color: Color = Color(1.0, 0.55, 0.15)
@export var minimap_goal_capture_width_px: float = 2.0
@export var minimap_gift_radius_px: float = 5.0
@export var minimap_gift_falling_color: Color = Color(1.0, 0.91, 0.35)
@export var minimap_gift_landed_color: Color = Color(1.0, 0.69, 0.27)
@export var minimap_gift_outline_color: Color = Color(0.08, 0.09, 0.12, 0.95)
## Border stroke width, in pixels, of the minimap's own frame ring --
## a thin rim (owner review 2026-09-26: "thin light-grey rim (~2px)", not a
## thick gold ring).
@export var minimap_frame_border_width_px: float = 2.0

## -- HUD panel palette (docs/art_mockups/10-main-menu-layered-pastel.png,
## docs/art_mockups/08-cel-shaded-home-beacons.png) -------------------------
## Dark translucent panel fill behind the compact status readouts (turn/
## height/locked/special text) and the next-shape card. Alpha < 1 keeps the
## sunset field readable behind it.
@export var panel_background_color: Color = Color(0.07, 0.10, 0.14, 0.78)
## Corner rounding, in pixels, applied to every reskinned HUD panel's
## StyleBoxFlat.
@export var panel_corner_radius_px: float = 16.0
## Border stroke width, in pixels, for every reskinned HUD panel.
@export var panel_border_width_px: float = 2.0
## Thin light-grey rim color framing the minimap (owner review 2026-09-26:
## replaces the earlier thick amber ring).
@export var minimap_frame_color: Color = Color(0.85, 0.87, 0.90, 0.85)
## Dark, semi-translucent void behind the minimap's rendered disk, matching
## the disk's own base tone. Used both as the minimap panel's backdrop
## (before a match starts) and as the in-disk "unowned" fill once one is
## running, so an unclaimed cell reads as bare floor rather than a hole in
## the image. Alpha < 1 (owner review 2026-09-26: "dark translucent disc").
@export var minimap_backdrop_color: Color = Color(0.129, 0.153, 0.188, 0.82)
## Thin light stroke drawn at the disk's own field-radius edge (inside the
## zoom-margin padded frame), so the playable disc's true boundary reads
## clearly against the darker unowned floor around it.
@export var minimap_disc_outline_color: Color = Color(0.85, 0.87, 0.90, 0.55)
## How much brighter/more saturated a team's territory fill is drawn on the
## minimap than its own base color (HSV value/saturation multipliers), so
## even a small owned patch reads clearly at minimap scale (owner review
## 2026-09-26: "brighter/more saturated fill... so even small shares read").
@export var minimap_territory_saturation_boost: float = 1.2
@export var minimap_territory_value_boost: float = 1.15

## -- Top-left per-player rows (mockup 08: two-tone diamond glyph + slim
## share bar, no boxy panel) --------------------------------------------------
## Side length, in pixels, of the small faceted diamond glyph drawn beside
## each player's territory-share bar (owner review 2026-09-26: "~20 px tall").
@export var hud_row_glyph_size_px: float = 20.0
## Bontago-1pi.81 (ui/SlotDiamond.gd, the one colour diamond used by the HUD, lobby seats and
## round score table): how much lighter the lit (left) half is than the slot colour,
@export var hud_diamond_lit_amount: float = 0.25
## how much darker the shaded (right) half is,
@export var hud_diamond_shade_amount: float = 0.25
## and the stroke around the diamond.
@export var hud_diamond_outline_color: Color = Color(0.0, 0.0, 0.0, 0.55)
@export var hud_diamond_outline_width_px: float = 1.5
## Dark translucent track color behind each player's territory-share bar
## (the team-colored fill is drawn on top of this, per slot).
@export var hud_share_bar_track_color: Color = Color(0.05, 0.06, 0.09, 0.55)
## Subtle light sheen drawn across the top of every share bar's track, for
## the same soft-highlight read the mockup's bars have.
@export var hud_share_bar_highlight_color: Color = Color(1.0, 1.0, 1.0, 0.18)
## Thin light inner border stroke around each share bar's track (owner
## review 2026-09-26: "thin light inner border").
@export var hud_share_bar_border_color: Color = Color(1.0, 1.0, 1.0, 0.22)

## Bontago-1pi.23: subdued, low-contrast dark-glass cards with light ink, so
## the persistent HUD never competes with the 3D scene (owner: the bright
## backgrounds behind previews and stats were distracting).
@export var surface_color: Color = Color(0.04, 0.06, 0.09, 0.42)
@export var surface_border_color: Color = Color(1.0, 1.0, 1.0, 0.12)
@export var ink_color: Color = Color(0.96, 0.95, 0.90)
@export var muted_ink_color: Color = Color(0.80, 0.82, 0.84, 0.90)
@export var inner_surface_color: Color = Color(1.0, 1.0, 1.0, 0.05)
@export var card_padding_px: float = 16.0
@export var share_bar_width_px: float = 200.0
## Width in pixels of the player-name column beside each share bar; longer
## names are ellipsized (Bontago-1pi.68).
@export var hud_row_name_width_px: float = 110.0
@export var share_bar_height_px: float = 14.0
## Fraction of a share bar's height covered by the lighter highlight band on its fill.
@export var share_bar_highlight_ratio: float = 0.35

## Bontago-mp0.27: pre-match 3-2-1 label. "Go" stays this long after PLAYING starts.
@export var countdown_font_size: int = 120
## Countdown label outline width = countdown_font_size / this.
@export var countdown_outline_divisor: int = 6
@export var countdown_go_text: String = "Go!"
@export var countdown_go_hold_s: float = 0.8
@export var countdown_outline_color: Color = Color(0.05, 0.07, 0.10, 0.85)

## Bontago-mp0.145: the ONE style every transient HUD message (claim toast,
## reject/relocated message, winner banner) shares: a dark-glass pill in the
## HUD card family, light ink, a readable text outline, and a border that
## carries the accent (the player's colour for a player message, the reject
## accent below for a refusal).
@export var toast_fill_color: Color = Color(0.05, 0.07, 0.10, 0.82)
@export var toast_border_width_px: float = 3.0
@export var toast_corner_radius_px: float = 18.0
@export var toast_padding_x_px: float = 16.0
@export var toast_padding_y_px: float = 6.0
@export var toast_font_size: int = 16
@export var toast_outline_size_px: int = 4
## Border accent of a refusal ("Rejected: ...") message; distinct from the
## relocated message's bluish auto-drop-flash accent and a player colour.
@export var toast_reject_accent_color: Color = Color(0.95, 0.42, 0.36)
