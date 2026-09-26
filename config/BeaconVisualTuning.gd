class_name BeaconVisualTuning
extends Resource
## Sizes, colors and emission strengths for the procedural "beacon" that
## replaces the M2 pole-and-banner placeholder on both HomeFlag and GoalFlag
## (M7 P8, Bontago-xtq.33; docs/M7_ART_DIRECTION.md Q6: "procedural home
## beacons (socket + luminous ring + faceted crystal) replace the pennants; a
## neutral variant for the goal flag").
##
## Every beacon is three MeshInstance3D pieces built from primitives/an
## ArrayMesh in HomeFlag._build() -- no imported art assets, no shader (P2
## owns toon shading; these stay plain StandardMaterial3D):
## - Socket: a low cylinder, always socket_color regardless of owner.
## - Ring: a flat annulus lying on top of the socket, tinted the owner's
##   color (or neutral_color on a GoalFlag) and lit up via emission.
## - Crystal: a faceted bipyramid ("cut gem") on top of the ring, same tint.
##
## GoalFlag.banner_scale() returns goal_scale_factor so its ring and crystal
## are larger than a HomeFlag's, matching HomeFlag's own "the socket stays a
## constant base for every flag" contract (see HomeFlag._build()'s comment) --
## only the socket ever stays a fixed size.
##
## Exposed on the F4 TuningPanel "Beacons" tab with ranges/descriptions in
## config/tuning_panel_hints.tres (Bontago-xtq.34/xtq.36; the original xtq.33
## package left the wiring to a follow-up).
##
## Loaded once as config/beacon_visual_tuning.tres.
##
## DECISION (Bontago-xtq.41, owner playtest: "the beacons are way too small"):
## socket/ring/crystal dimensions scaled up 2.5x from the xtq.33/34 launch
## defaults (socket_radius 0.4->1.0, socket_height 0.25->0.625,
## ring_outer_radius 0.55->1.375, ring_thickness 0.12->0.3, crystal_radius
## 0.22->0.55, crystal_height 0.75->1.875) so a HomeFlag's crystal reads as
## roughly two 1m block cells tall and its ring as wider than one, matching
## docs/art_mockups/08-cel-shaded-home-beacons.png at the real follow-camera
## distance (config/camera_tuning.tres' follow_distance 9.0) rather than only
## at the far overview framing earlier screenshots used. goal_scale_factor is
## unchanged (1.35) -- it already keeps the goal variant proportionately
## larger (goal crystal ~2.53m), so no change was needed there. The socket
## still stays a constant base across every flag (only scaled up in absolute
## terms, not made proportional to banner_scale()) -- no per-flag rule
## changed, only BeaconVisualTuning's own numbers. Checked HomeFlag.tscn/
## GoalFlag.tscn and HomeFlag._build(): the beacon is three plain
## MeshInstance3D pieces with no CollisionShape/StaticBody/Area3D anywhere,
## so this size change carries no physics footprint and cannot affect block
## placement (core/rules/PlacementRules.gd never reads flag geometry either).

## -- Socket (the low base every beacon shares) -------------------------------
@export var socket_radius: float = 1.0
@export var socket_height: float = 0.625
## Always this color, home or goal -- only the ring and crystal above it
## carry an owner's (or the goal's neutral) color, matching the reference
## mockup's dark, uniform beacon bases (docs/art_mockups/
## 08-cel-shaded-home-beacons.png).
@export var socket_color: Color = Color(0.16, 0.16, 0.18)

## -- Ring (the luminous halo lying flat on the socket) -----------------------
## Outer radius of a HomeFlag's ring; GoalFlag's is this * goal_scale_factor.
@export var ring_outer_radius: float = 1.375
## Ring width (outer minus inner radius) at HomeFlag scale.
@export var ring_thickness: float = 0.3
## Height above the top of the socket the ring sits at, so it never z-fights
## the socket's own cap (mirrors TerritoryVisuals.capture_ring_lift's role).
@export var ring_lift: float = 0.03
## Segments in the ring's full circle.
@export var ring_segments: int = 48
@export var ring_emission: float = 1.4

## -- Crystal (the faceted gem on top) ----------------------------------------
## Waist radius of a HomeFlag's crystal; GoalFlag's is this * goal_scale_factor.
@export var crystal_radius: float = 0.55
## Apex-to-apex height of a HomeFlag's crystal; GoalFlag's is this *
## goal_scale_factor. The crystal is a bipyramid (two low-poly cones base to
## base) so it reads as a cut gem, not a smooth cone.
@export var crystal_height: float = 1.875
## Sides of the bipyramid's waist ring. Each face gets its own flat normal
## (HomeFlag._add_facet()), so a low count reads as deliberately faceted
## rather than as an under-tessellated cone.
@export var crystal_facets: int = 6
@export var crystal_emission: float = 1.1

## -- Goal variant -------------------------------------------------------------
## How much larger a GoalFlag's ring and crystal are than a HomeFlag's;
## GoalFlag.banner_scale() returns this (spec keeps that method name -- see
## HomeFlag.banner_scale()'s own doc). Same default TerritoryVisuals.
## goal_flag_scale used to carry for the old banner, kept for continuity.
@export var goal_scale_factor: float = 1.35
## GoalFlag's own ring/crystal tint, independent of any owner's color -- spec
## 2.2/2.3's goal flag has no team. Same default color
## TerritoryVisuals.goal_flag_color already uses for its own, unrelated
## fallback purposes (Field.gd._color_for_index(), TerritoryOverlay.gd.
## set_slot_colors()), kept in sync for visual coherence even though the two
## exports are intentionally independent (this package doesn't own
## TerritoryVisuals.gd).
@export var neutral_color: Color = Color(0.95, 0.93, 0.85)
