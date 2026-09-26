class_name HUDVisualTuning
extends Resource
## Tunables for M7 P5 (docs/M7_PLAN.md, "P5 -- HUD minimap + reskin"): the
## minimap's camera framing/refresh cadence and the layered-pastel/coral
## panel palette used to restyle ui/HUD.tscn (docs/M7_ART_DIRECTION.md's HUD
## styling section). CLAUDE.md: "No magic numbers... every tunable value
## belongs in a Resource under res://config/".
##
## This is presentation only, same split TerritoryVisuals.gd documents for
## the disk: nothing here changes a rule. HUD.gd's own layout geometry
## (offset_left/offset_top pixel positions in ui/HUD.tscn) stays inline,
## following that scene's own pre-M7 DECISION that pure screen-space drawing
## geometry is not worth resourcing -- only the minimap's world-space camera
## framing and the reskin's *colors* (the part the mockups actually specify)
## live here.
##
## Loaded once as config/hud_visual_tuning.tres.

## -- Minimap (docs/M7_ART_DIRECTION.md Q4: "(a) live orthographic SubViewport
## camera ... recommended") -----------------------------------------------
## Square pixel size of the minimap's SubViewport/TextureRect in the HUD
## corner.
@export var minimap_size_px: int = 160
## Extra meters of orthographic half-extent beyond MapDef.field_radius, so
## the disk's own rim (and anything just past it, e.g. a home flag) is never
## clipped at the minimap's edge.
@export var minimap_zoom_margin_m: float = 6.0
## How often the minimap's SubViewport re-renders, in Hz. ui/Minimap.gd gates
## SubViewport.render_target_update_mode behind a Timer at this cadence
## instead of UPDATE_ALWAYS (docs/M7_ART_DIRECTION.md: "small continuous
## render cost" is the accepted tradeoff of option (a), but every frame is
## more than a corner-of-the-screen top-down view needs to read as live).
@export var minimap_refresh_hz: float = 8.0
## Height, in meters above the field's own surface, the minimap's orthogonal
## camera sits at, looking straight down. Only needs to clear the tallest
## plausible stack; the orthogonal projection's own `size` (not distance)
## is what actually controls framing.
##
## Bontago-xtq.30 (owner: minimap "shows as a uniform grey radial blur -- no
## disk outline, no territory colour"). ROOT CAUSE (confirmed by reading
## game/Main.tscn's WorldEnvironment + config/graphics_presets/medium.tres,
## the Settings.DEFAULT_PRESET_ID the acceptance screenshot boots with):
## ui/Minimap.gd's SubViewport shares the main scene's own World3D
## (`own_world_3d = false`, same pattern as game/DiscMirror.gd) precisely so
## it renders the live disk/blocks -- but that means the minimap camera also
## inherited the SHARED Environment, whose volumetric_fog_enabled M7 P1 turns
## on for every preset from "medium" up (game/Main.gd's
## _apply_graphics_preset()). At the old 120 m height the top-down ray to the
## field crosses the entire fog volume, washing the whole minimap to a flat
## grey with no disk silhouette. ui/Minimap.gd now gives the minimap camera
## its OWN Camera3D.environment (fog/volumetric fog/glow/SSR/SSAO all off,
## solid minimap_backdrop_color background) so the shared world's
## post-processing can never reach it, regardless of preset -- this is the
## primary fix. Lowering the height only tightens the margin now that
## nothing is fogging it: config/NetConfig.gd's own pos_max_y (72.0 m) is the
## documented hard ceiling nothing in the match can rise above (spec's wire
## band via GhostTuning.hover_ceiling_margin), so 80 m (72 + an 8 m margin)
## clears every legal block/ghost position with room to spare, instead of
## the old value's much larger, no-longer-needed allowance.
@export var minimap_camera_height_m: float = 80.0
## Near/far clip planes for the minimap camera, in meters from the camera
## itself. Far must clear minimap_camera_height_m plus room for a tall stack
## above the disk (see minimap_camera_height_m's own DECISION comment above
## for why both shrank together).
@export var minimap_near_clip_m: float = 1.0
@export var minimap_far_clip_m: float = 40.0

## -- HUD panel palette (docs/art_mockups/10-main-menu-layered-pastel.png,
## docs/art_mockups/08-cel-shaded-home-beacons.png) -------------------------
## Cream/parchment panel fill behind HUD readouts (turn label, timer,
## shares list). Alpha < 1 keeps the sunset field readable behind it.
@export var panel_background_color: Color = Color(0.965, 0.925, 0.867, 0.85)
## Coral border/accent stroke around a panel (mockup 10's "Host" button
## outline), also used for the minimap's own frame ring.
@export var panel_border_color: Color = Color(0.886, 0.412, 0.322, 1.0)
## Dark slate ink for HUD label text over the cream panels.
@export var panel_text_color: Color = Color(0.169, 0.227, 0.271, 1.0)
## Corner rounding, in pixels, applied to every reskinned HUD panel's
## StyleBoxFlat.
@export var panel_corner_radius_px: float = 12.0
## Border stroke width, in pixels, for every reskinned HUD panel.
@export var panel_border_width_px: float = 2.0
## Amber ring around the minimap, echoing the disk's own gold rim (mockup 08).
@export var minimap_frame_color: Color = Color(0.867, 0.667, 0.318, 1.0)
## Dark slate void behind the minimap's rendered disk, matching the disk's
## own base tone so an out-of-frame area (before a match starts) doesn't
## flash white.
@export var minimap_backdrop_color: Color = Color(0.129, 0.153, 0.188, 1.0)
