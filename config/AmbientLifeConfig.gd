class_name AmbientLifeConfig
extends Resource
## Bontago-adt.3: tunables for the purely cosmetic, local-only ambient life
## (perching birds, vfx/PerchingBirds.gd; fireflies, vfx/Fireflies.gd). One
## instance is referenced from each config/SkyThemeDef.gd (`ambient_life`), so
## the effects are theme-gated: sunset ships birds (fireflies_count 0), night
## ships fireflies (perch_bird_count 0). Nothing here is networked and nothing
## touches physics or gameplay; the perching birds only *read* cursors, blocks,
## flags and the camera and stay away from them.

# --- Perching birds ----------------------------------------------------------

## Birds alive at once; 0 disables the effect for this theme.
@export var perch_bird_count: int = 4
## Bird body length (m), picked per bird, then multiplied by perch_bird_scale
## (owner 2026-09-30: the disc birds read too small, so they are drawn ~1.5x
## with proportions unchanged). The default clearances below are sized for
## the scaled bird; raise them with the scale.
@export var perch_bird_length_min_m: float = 0.25
@export var perch_bird_length_max_m: float = 0.35
@export var perch_bird_scale: float = 1.5
## Landing spots keep at least this far (horizontally) from every player's
## cursor / held block and every home beacon.
@export var perch_min_player_distance_m: float = 16.0
## ... from the goal beacon(s).
@export var perch_min_goal_distance_m: float = 9.0
## ... from the camera's ground position.
@export var perch_min_camera_distance_m: float = 14.0
## ... from any block (settled or falling).
@export var perch_min_block_distance_m: float = 6.0
## ... from the disc's edge.
@export var perch_edge_margin_m: float = 3.0
## Random landing-spot candidates tried per attempt before giving up.
@export var perch_spot_tries: int = 24
## Fraction (0..1) of landings that prefer the top of a settled block (a tower)
## over the open disc; falls back to the other when none is available.
@export var perch_tower_fraction: float = 0.4
## A block must have been motionless this long (s) before a bird may perch on it.
@export var perch_tower_min_settle_s: float = 4.0
## The block's top face must be at least this wide (m) on both sides.
@export var perch_tower_min_top_size_m: float = 0.9
## Nothing (no other block) may sit within this height (m) above the top face.
@export var perch_tower_clear_height_m: float = 2.0

## A perched bird flees when the camera comes within this (3D) distance.
@export var flee_camera_radius_m: float = 9.0
## ... any player's cursor / held block comes within this (3D) distance.
@export var flee_cursor_radius_m: float = 8.0
## ... a block impact happens within this distance.
@export var flee_impact_radius_m: float = 14.0
## ... a block is above the bird within this horizontal distance.
@export var flee_overhead_radius_m: float = 4.0
## ... an unsettled (moving or just-landed) block is within this distance.
@export var flee_moving_block_radius_m: float = 5.5
## ... the block it perches on moves more than this (m) or turns.
@export var flee_block_moved_epsilon_m: float = 0.02
## A block counts as unsettled (moving / just landed) until it has been still this long (s).
@export var block_settled_window_s: float = 0.75
## Landing spots keep at least this far from other birds' spots.
@export var perch_min_bird_spacing_m: float = 3.5
## How often (s) the birds re-check their surroundings.
@export var threat_poll_interval_s: float = 0.12

## Time a bird stays perched before leaving on its own (s).
@export var perch_stay_min_s: float = 14.0
@export var perch_stay_max_s: float = 34.0
## Delay before a bird's first appearance and before each replacement (s).
@export var spawn_delay_min_s: float = 2.0
@export var spawn_delay_max_s: float = 14.0
## Idle behaviour: seconds between actions (look/peck/hop) while perched.
@export var idle_action_min_s: float = 0.8
@export var idle_action_max_s: float = 2.6
## Chance (0..1) that an idle action is a hop rather than a look or peck.
@export var idle_hop_chance: float = 0.25
## Length of a hop (m).
@export var idle_hop_distance_m: float = 0.3
## Height of a hop (m).
@export var idle_hop_height_m: float = 0.12

## Approach: radius (m) of the far circle a bird arrives on, its altitude
## range (m), how long it circles (s) before gliding in, and its speed (m/s).
@export var approach_circle_radius_min_m: float = 55.0
@export var approach_circle_radius_max_m: float = 85.0
@export var approach_altitude_min_m: float = 14.0
@export var approach_altitude_max_m: float = 26.0
@export var approach_circle_time_min_s: float = 3.0
@export var approach_circle_time_max_s: float = 8.0
@export var flight_speed_mps: float = 9.0
## Wing beats per second in flight.
@export var flap_rate_hz: float = 9.0
## Escape: speed (m/s), climb angle (degrees), sideways turn rate (deg/s, sign
## random per bird), seconds to reach full speed, and the distance from the disc
## centre (m) at which a departed bird is removed.
@export var flee_speed_mps: float = 13.0
@export var flee_climb_deg: float = 32.0
@export var flee_turn_rate_deg: float = 38.0
@export var flee_accel_time_s: float = 0.7
@export var despawn_distance_m: float = 130.0

## Cel palette. Each bird picks one back colour at random (dark slate tones);
## belly cream, breast rust, wings/tail dark slate, beak/legs amber.
@export var perch_body_colors: PackedColorArray = PackedColorArray([
	Color(0.12, 0.15, 0.24), Color(0.16, 0.13, 0.21), Color(0.11, 0.17, 0.2),
])
@export var perch_belly_color: Color = Color(0.97, 0.86, 0.68)
@export var perch_breast_color: Color = Color(0.85, 0.42, 0.2)
@export var perch_wing_color: Color = Color(0.05, 0.06, 0.11)
@export var perch_beak_color: Color = Color(1.0, 0.72, 0.2)
@export var perch_outline_color: Color = Color(0.07, 0.05, 0.09)

# --- Fireflies ---------------------------------------------------------------

## Motes alive at once; 0 disables the effect for this theme.
@export var fireflies_count: int = 0
## Fraction (0..1) of motes hovering sparsely above the disc's outer band; the
## rest drift around the rim and over the cloud sea just below it.
@export var fireflies_above_disc_fraction: float = 0.07
## Rim band: radial offset from the disc radius (m), negative is inward.
@export var fireflies_rim_offset_min_m: float = -1.0
@export var fireflies_rim_offset_max_m: float = 14.0
## Rim band: height above the disc surface (m), negative is below.
@export var fireflies_rim_height_min_m: float = -12.0
@export var fireflies_rim_height_max_m: float = 4.0
## Above-disc motes: how far inside the rim (m) they may hover and their height.
@export var fireflies_above_inset_m: float = 8.0
@export var fireflies_above_height_min_m: float = 2.0
@export var fireflies_above_height_max_m: float = 9.0
## Drift amplitude (m), drift speed, blink rate (Hz) and mote size (m).
@export var fireflies_drift_radius_m: float = 2.6
@export var fireflies_drift_speed: float = 0.35
@export var fireflies_blink_hz: float = 0.35
@export var fireflies_size_m: float = 0.5
## Emissive colour and HDR strength (above the glow threshold so they bloom).
@export var fireflies_color: Color = Color(0.72, 1.0, 0.28)
@export var fireflies_emission_energy: float = 4.0
## Motes fade out beyond this distance from the camera (m) to stay cheap and calm.
@export var fireflies_fade_far_m: float = 140.0
@export var fireflies_seed: int = 5
