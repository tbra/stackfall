class_name TerritoryVisuals
extends Resource
## Every tunable number the territory overlay, its shader and the flags use
## (spec 2.10, 3.3). CLAUDE.md: "No magic numbers... every tunable value
## belongs in a Resource under res://config/".
##
## These are presentation numbers only: nothing here may change a rule.
## TerritoryTuning holds the rule numbers, MapDef the geometry, and this
## resource how the result looks. M2 asks only for a readable soft tint, an
## outline, a shimmer and a hole; the full look of spec 2.10 is M7.
##
## Loaded once as config/territory_visuals.tres.

## -- Disk surface -----------------------------------------------------------
## The disk's own color where no team owns the ground.
@export var disk_base_color: Color = Color(0.68, 0.70, 0.74)
## Bontago-xtq.4 (owner, 2026-09-22: "a bit transparent and reflective"):
## retuned from 0.1 toward a glass-like metallic response; drives the
## shader's SPECULAR-visible reflection of ProceduralSky.
##
## DECISION (config/TerritoryVisuals.gd, Bontago-xtq.6, owner 2026-09-23:
## "the bottom reflects what's on top... also it reflects whatever light
## source you've put in"): brought back down from 0.6 -- combined with
## disk_roughness's old 0.1, the disk read as a near-mirror (shaders/
## territory.gdshader's METALLIC/ROUGHNESS write, cull_disabled on both the
## top and underside), which is what made a resting block look reflected in
## the surface under it and the DirectionalLight3D's specular highlight read
## as a hot mirror spot. Interim fix per the owner's note ("we'll work more
## on the design in m7"); not art direction.
@export var disk_metallic: float = 0.2
## Retuned from 0.45 toward glass-smooth (Bontago-xtq.4); low roughness is
## what makes the sky's reflection actually visible rather than a diffuse
## blur.
##
## DECISION (config/TerritoryVisuals.gd, Bontago-xtq.6): raised back toward
## matte alongside disk_metallic above, for the same mirror-reflection
## complaint. Still glossier than a fully diffuse surface (1.0), so the disk
## keeps some sky highlight without doubling as a mirror for the blocks
## resting on it.
@export var disk_roughness: float = 0.45
## Radial segments of the disk mesh. High enough that the rim reads as a
## circle rather than a polygon at the camera distances spec 2.5 allows.
@export var disk_mesh_segments: int = 96

## -- Glass translucency (Bontago-xtq.4) --------------------------------------
## Base opacity of the disk everywhere; 1.0 is fully opaque, 0.0 fully clear.
## Rises toward 1 via tint_opacity_boost wherever a territory tint, the
## animated rim/outline, a contested/goal shimmer, or a hole's rim glow is
## drawn, so ownership stays readable through the glass.
@export var glass_alpha: float = 0.75
## How much extra opacity a drawn tint/rim/shimmer/goal indicator adds on top
## of glass_alpha (added then clamped to 1, so a full-strength indicator
## always reads fully opaque regardless of how translucent the bare glass is).
@export var tint_opacity_boost: float = 0.25

## -- Territory tint (spec 2.10: "a soft tint in their color") ---------------
## Half-width of the smoothstep applied to the bilinear owner edge, in owner
## units (the texture's R channel counts teams, so 1.0 is one whole team
## step). Larger is blurrier.
@export var edge_softness: float = 0.4
## How much of the owner color is mixed over the disk at full coverage.
@export var tint_alpha: float = 0.55

## -- Animated outline (spec 2.10: "with an animated outline") ---------------
## Half-width of the outline band around a territory edge, same units as
## edge_softness.
@export var outline_width: float = 0.16
## Pulses per second along the outline.
@export var outline_speed: float = 1.6
## Emission strength of the outline at the peak of its pulse.
@export var outline_strength: float = 1.4
## How much of the pulse is animated; the rest is a constant outline.
@export var outline_pulse_depth: float = 0.45

## -- Contested cells (spec 2.10: "Contested areas shimmer") -----------------
@export var contested_color: Color = Color(1.0, 0.95, 0.75)
## Shimmer cycles per second.
@export var contested_shimmer_rate: float = 5.0
## Spatial frequency of the shimmer's travelling bands, in cycles across the
## whole disk.
@export var contested_shimmer_scale: float = 24.0
@export var contested_shimmer_strength: float = 0.4

## -- Holes (spec 2.10: "Hole edges glow", 3.3: the shader discards holes) ---
@export var hole_rim_color: Color = Color(1.0, 0.45, 0.12)
## Width of the glowing rim just outside a hole, in hole-mask units.
@export var hole_rim_width: float = 0.35
@export var hole_rim_glow: float = 2.5

## -- Flags (spec 2.2, 2.3) --------------------------------------------------
@export var flag_pole_height: float = 3.2
@export var flag_pole_radius: float = 0.09
@export var flag_pole_color: Color = Color(0.85, 0.86, 0.88)
## Width and height of the banner at the top of the pole.
@export var flag_banner_size: Vector2 = Vector2(1.6, 0.9)
## How much the goal flag's banner is scaled up from a home flag's.
@export var goal_flag_scale: float = 1.35
@export var goal_flag_color: Color = Color(0.95, 0.93, 0.85)
## Emission strength of a flag's banner, so owners read at a glance.
@export var flag_emission: float = 0.6

## -- Goal capture ring (spec 2.3: "A radial progress ring appears on each
## goal flag while someone is capturing it") --------------------------------
## Outer radius of the ring lying on the disk around a goal flag.
@export var capture_ring_radius: float = 2.2
@export var capture_ring_thickness: float = 0.45
## Height above the disk surface, so the ring never z-fights the disk.
@export var capture_ring_lift: float = 0.06
## Segments in the full circle; the drawn arc uses a proportional share.
@export var capture_ring_segments: int = 64
@export var capture_ring_emission: float = 1.8

## -- Analytic circle rendering (Bontago-cmc.5, owner requirement: "should
## look smooth... some kind of metaballs system") ----------------------------
## game/TerritoryOverlay.gd now feeds the shader the home-anchored circle
## list itself (disk-local x/z/radius/team, one texel per circle) alongside
## the cell raster, so the territory border is the analytic union of real
## circles instead of a smoothstepped, bilinearly-upscaled 1 m cell grid —
## the grid can only ever look like a blurred grid, never a curve
## (game/TerritoryOverlay.gd's class doc explains why). These fields are
## deliberately separate from edge_softness/outline_* above: those still
## drive the *raster fallback* path (shaders/territory.gdshader's
## `circles_valid == false` branch, taken when the circle list overflows
## max_shader_circles), which has no continuous distance field to feather —
## only the bilinear owner ramp — so it cannot share this path's meaning of
## "meters from the analytic boundary".
##
## Half-width, in meters, of the smoothstep applied to a team's analytic
## coverage value (radius - distance to the nearest/union-blended circle of
## that team). Larger reads blurrier.
@export var rim_soft_width: float = 0.25
## Half-width, in meters, of the bright rim band drawn just inside a
## territory's analytic edge (docs/ORIGINAL_BONTAGO_NOTES.md: "a bright
## border around the rim of the shaded area").
@export var rim_width: float = 0.35
## Emission strength of the rim at the peak of its pulse.
@export var rim_strength: float = 1.4
## How much of the rim's pulse is animated; the rest is a constant glow.
@export var rim_pulse_depth: float = 0.45
## Pulses per second along the rim.
@export var rim_speed: float = 1.6
## Smooth-min/-max blend radius, in meters, used when two overlapping
## same-team circles are combined into one team coverage value — the
## "metaballs" look the owner asked for. 0 disables blending (a plain union,
## still smooth-edged, just with a visible seam angle where two circles of
## different radii meet).
@export var metaball_blend: float = 0.3
## Circles the shader actually loops per pixel before falling back to the
## raster path for that frame (docs, "Bounded cost"). Defaults to
## TerritoryTuning.max_circles; lower this on weaker GPUs without touching
## the solver's own cap.
@export var max_shader_circles: int = 400
