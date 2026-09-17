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
@export var disk_metallic: float = 0.1
@export var disk_roughness: float = 0.45
## Radial segments of the disk mesh. High enough that the rim reads as a
## circle rather than a polygon at the camera distances spec 2.5 allows.
@export var disk_mesh_segments: int = 96

## -- Territory tint (spec 2.10: "a soft tint in their color") ---------------
## Half-width of the smoothstep applied to the bilinear owner edge, in owner
## units (the texture's R channel counts teams, so 1.0 is one whole team
## step). Larger is blurrier.
@export var edge_softness: float = 0.25
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
@export var contested_shimmer_strength: float = 0.5

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
