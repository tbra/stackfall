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

## -- Crystal cel shading (Bontago-mp0.3.1, owner feedback on docs/art_mockups/
## 08-cel-shaded-home-beacons.png: "Same for the beacons" -- the faceted
## crystal now draws with shaders/beacon_crystal.gdshader, the same toon-band
## + shadow-tint + hard specular technique as shaders/block_cell_grid.gdshader,
## kept as its own tunable set here (rather than reusing BlockVisualTuning)
## since HomeFlag/BeaconVisualTuning own the beacon end to end and every
## HomeFlag/GoalFlag already builds its own dedicated material instance, never
## a shared/cached one. -----------------------------------------------------
## How many discrete lit/shadow bands the crystal's toon diffuse ramp is
## quantized into.
@export var crystal_toon_band_count: int = 3
## Minimum normalized shading factor on the crystal's own darkest facet, so it
## never reads near-black even facing away from the DirectionalLight.
@export var crystal_shadow_floor: float = 0.45
## Cool ambient/sky tint blended into the crystal's darkest facets.
@export var crystal_shadow_tint: Color = Color(0.72, 0.78, 0.97)
## Shading factor on the crystal's brightest facet, pushed above 1.0 so the
## lit side reads punchier than a flat repaint of its own colour.
@export var crystal_highlight_boost: float = 1.2
@export var crystal_specular_strength: float = 0.8
## Blinn-Phong exponent before toon-quantizing; higher is a smaller, sharper
## facet highlight dot.
@export var crystal_specular_sharpness: float = 32.0
## Width of the smoothstep used to turn the specular falloff into a hard edge.
@export var crystal_specular_softness: float = 0.08

## -- Pulsating glow (owner feedback: "pulsating glow from the beacons") ------
## HomeFlag._process()/_apply_pulse() drive both the ring's own scale and the
## ring/crystal emission energy from a single sine wave over this period, so
## every beacon on the disk pulses in lockstep rather than drifting out of
## phase against each other.
## Seconds for one full pulse cycle; 0 or less disables the pulse (steady glow).
@export var pulse_period_s: float = 2.4
## Fractional swing in the ring's own uniform XZ scale at the peak of the
## pulse (0.05 = the ring's radius grows/shrinks by +-5%).
@export var pulse_scale_amplitude: float = 0.05
## Fractional swing in ring_emission/crystal_emission at the peak of the pulse
## (0.35 = the emission energy swings by +-35% of its base value).
@export var pulse_emission_amplitude: float = 0.35

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

## Bontago-adt.2: Global multiplier on the beacon ring and crystal emission (raise/lower for night themes). Peaks stay near the 1.3 glow threshold at 1.0.
@export var emission_scale: float = 1.0

## Bontago-adt.2: Fraction of the crystal emission shown face-on (the dimmer core); the silhouette edges glow at full strength.
@export var crystal_core_glow: float = 0.55

## Bontago-adt.2: Extra white-hot emission on the crystal facet silhouettes (fresnel edge).
@export var crystal_edge_glow: float = 0.6

## Bontago-adt.2: How much white is mixed into the crystal edge glow (0 = pure beacon color).
@export var crystal_edge_white_mix: float = 0.55

## Bontago-adt.2: Fresnel exponent of the crystal edge glow; higher confines it to the very edge.
@export var crystal_edge_power: float = 2.2

## Bontago-adt.2: Metallic value of the beacon socket base (polished graphite).
@export var socket_metallic: float = 0.8

## Bontago-adt.2: Roughness of the beacon socket base.
@export var socket_roughness: float = 0.3

## -- Goal claim display (Bontago-470.7: goal beacons must clearly show who has
## claimed them). Neutral goals keep the look above; a claimed goal takes its
## controller's colour with boosted emission and a tall light beam; a contested
## goal flickers between the contesting colours with a striped beam.
## Emission multiplier on a claimed goal's ring and crystal (times emission_scale).
@export var claimed_emission_boost: float = 1.5
## Emission multiplier on a contested goal's ring and crystal.
@export var contested_emission_boost: float = 1.3
## Height of the claim beam in meters (tall enough to read across the map).
@export var claim_beam_height: float = 40.0
## Radius of the claim beam in meters at GoalFlag scale.
@export var claim_beam_radius: float = 0.45
## Peak additive brightness of the claim beam at its base (fades to 0 at the top).
@export var claim_beam_alpha: float = 0.7
## Moving bands along the beam (a shape cue that does not rely on hue alone).
@export var claim_beam_band_count: float = 8.0
## Band scroll speed in beam heights per second (positive rises).
@export var claim_beam_scroll_speed: float = 0.35
## How dark the gaps between beam bands are (0 = fully dark gaps, 1 = no bands).
@export var claim_beam_band_floor: float = 0.2
## Seconds the claim-change flash and burst take to fade.
@export var claim_flash_duration_s: float = 1.2
## Extra emission multiplier at the instant a claim changes (decays to 0).
@export var claim_flash_boost: float = 3.0
## Extra ring scale fraction at the instant a claim changes (decays to 0).
@export var claim_flash_ring_scale: float = 0.6
## Sparks in the burst on a claim change.
@export var claim_burst_count: int = 28
## Initial speed of burst sparks in m/s.
@export var claim_burst_speed: float = 7.0
## Size of a burst spark in meters.
@export var claim_burst_size: float = 0.35
## Flicker rate in Hz between the contesting colours of a contested goal.
@export var contested_flicker_hz: float = 3.0
## Used as the second flicker colour when fewer than two contesting teams are found nearby.
@export var contested_color: Color = Color(1.0, 1.0, 1.0)
## Radius in meters around a contested goal to look for the contesting teams' colours.
@export var contested_probe_radius: float = 3.5
## Number of probe points on that ring.
@export var contested_probe_samples: int = 16

## -- Claim-radius ring (Bontago-1pi.18.6, QoL experiment 4). Drawn on the ground
## around each goal beacon ONLY while the "bigger goal claim radius" toggle is on
## (see GoalFlag.set_claim_ring()); with the toggle off nothing is built.
## Tint of the ring (alpha is claim_ring_alpha); neutral so it reads as "the area
## where claiming counts" without implying a team.
@export var claim_ring_color: Color = Color(1.0, 0.95, 0.8)
## Opacity of the claim-radius ring, kept low so it stays a subtle ground cue.
@export var claim_ring_alpha: float = 0.2
## Width of the ring band in meters, centred on the claim radius.
@export var claim_ring_width: float = 0.25
## Height above the ground the ring floats at, so it never z-fights the disc.
@export var claim_ring_lift: float = 0.05
## Segments in the ring's full circle (built once per match).
@export var claim_ring_segments: int = 96
