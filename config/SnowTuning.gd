class_name SnowTuning
extends WeatherTuning
## Snow's tunables (Bontago-22y.6), loaded as config/weather/snow.tres. The
## base WeatherTuning fields drive the framework's schedule and ramp; the
## fields below drive accumulation (host physics), its replication and the
## visuals every peer draws.
##
## Model: snow builds up in discrete levels on "patches". A patch is one
## upward-facing, uncovered cell top of a settled block, or one disc drift.
## Each patch is one rounded, tilted, slightly lumpy dome (seeded per patch,
## so host and clients agree without sending geometry) whose height is
## level / depth_levels * max_depth_m and whose footprint grows from
## cap_fill_light to cap_fill_heavy. The host gives each dome one convex
## collider built from the same grid points every peer draws.
##
## On top of the colliding drifts the disc gets a visual-only cover (no height,
## drawn by the disc shader) that spreads from a frosting to soft drifts
## with the cover level. It has no collider and no height, so it cannot mislead.
##
## Melting is the event's ramp-out: while intensity falls, every patch is
## capped at ceil(depth_levels * intensity / peak) levels, so all snow is gone
## when the event ends. ramp_out_s is therefore the melt duration.

## Float slack when rounding a melt fraction to a level. Numerics, not tuning.
const MELT_ROUNDING: float = 0.0001

@export_group("Accumulation")
## Deepest a patch's dome gets at its peak (metres, at the top level).
@export var max_depth_m: float = 0.14
## Number of discrete depth steps; colliders change only per step.
@export_range(1, 8, 1) var depth_levels: int = 4
## Seconds of full-intensity snowfall per level (scaled down by intensity).
@export var seconds_per_level: float = 7.0
## A block patch's edge as a fraction of cube_size.
@export var block_patch_fill: float = 0.96
## A disc drift's edge in map cells.
@export var disc_patch_cells: float = 2.2
## A block only collects snow while one of its local axes points within this
## many degrees of world up; tipping further clears its snow.
@export var max_up_tilt_deg: float = 25.0
## Free space kept above a patch's next level: anything within it (another
## block resting or hovering there) stops that patch growing.
@export var cover_clearance_m: float = 0.06

@export_group("Dome shape")
## Grid segments per dome edge (collider points = (segments + 1)^2).
@export_range(2, 10, 1) var cap_segments: int = 8
## Footprint edge fraction at the first level (dusting) and the top level.
@export_range(0.1, 1.0, 0.01) var cap_fill_light: float = 0.78
@export_range(0.1, 1.0, 0.01) var cap_fill_heavy: float = 1.0
## Footprint roundness: 2 = round, higher = squarer with rounded corners.
@export var cap_squareness: float = 4.0
## Disc drift footprint roundness (2 = round: drifts, not squares).
@export var disc_cap_squareness: float = 2.0
## Profile: 1 = cone-ish, 2 = soft dome, higher = flatter plateau.
@export var cap_roundness: float = 2.2
## Largest tilt of a dome (fraction of its height across half its width);
## what makes a block set on snow rest crooked.
@export_range(0.0, 0.9, 0.01) var cap_tilt_max: float = 0.35
## Lumpiness (fraction of height) and its spatial frequency (radians/half edge).
@export_range(0.0, 0.5, 0.01) var cap_bump_amp: float = 0.12
@export var cap_bump_freq: float = 3.0
## Smallest peak height (metres); keeps a level-1 hull non-degenerate.
@export var cap_min_height_m: float = 0.02
## Collision margin (convex radius) of a snow collider: small, so the rounded
## hull edge stays within a few mm of the drawn rim.
@export var collider_margin_m: float = 0.004
## Width (metres) of the soft shoulder along a block snow layer's outer rim;
## sides shared with a snowy neighbour cell have none (one continuous layer).
@export var cap_rim_width_m: float = 0.12
## Base lift above the surface (metres), to avoid z-fighting with the face.
@export var cap_lift_m: float = 0.002
## Touching snowy tops of different blocks at the same height draw as one
## surface (no rim at the shared edge); visual only, colliders stay per block.
@export var cross_merge_enabled: bool = true
## Tops count as the same height within this many metres.
@export var cross_merge_height_tol_m: float = 0.03
## Largest gap (metres) between two blocks' top faces that still merges.
@export var cross_merge_gap_m: float = 0.08
## Fraction of a cell two faces must overlap sideways to merge.
@export_range(0.0, 1.0, 0.01) var cross_merge_overlap: float = 0.5
## Block owners re-examined for moved neighbours per frame.
@export var cross_merge_checks_per_frame: int = 2

@export_group("Disc cover")
## Visual-only snow layer drawn by the disc's own shader (no collider):
## depth is an even base amount (cover_amount_light -> cover_amount_heavy as
## the cover level rises, so it builds up gradually) plus a gentle low-
## frequency variation (cover_variation across the noise range, noise at
## cover_noise_scale per metre) and the drift biases below: deeper near block
## bases, plate seams and the rim. No threshold, so no separate blobs.
@export var cover_noise_scale: float = 0.2
@export_range(0.0, 1.0, 0.01) var cover_amount_light: float = 0.12
@export_range(0.0, 1.0, 0.01) var cover_amount_heavy: float = 0.32
@export_range(0.0, 2.0, 0.01) var cover_variation: float = 1.9
## Disc snow lightens the surface but never replaces it: at least this share of
## the bare disc (territory colour, plate and rivet detail) always shows.
@export_range(0.0, 1.0, 0.01) var cover_territory_min: float = 0.45
## Drifts run this many times longer along the wind than across it.
@export_range(1.0, 12.0, 0.1) var cover_wind_stretch: float = 4.0
## Wind direction of the streaks on the disc (degrees).
@export_range(0.0, 360.0, 1.0) var cover_wind_angle_deg: float = 25.0
@export_range(0.0, 1.0, 0.01) var cover_strength_light: float = 0.35
@export_range(0.0, 1.0, 0.01) var cover_strength_heavy: float = 1.0
## Snow gathers first along plate seams, near the rim (outer fraction of
## the radius) and around block bases (within cover_base_radius_cells).
@export var cover_seam_bias: float = 0.0
## Seam band width as a fraction of a plate.
@export var cover_seam_width: float = 0.04
@export_range(0.0, 1.0, 0.01) var cover_rim_start: float = 0.8
@export var cover_rim_bias: float = 0.2
@export var cover_base_bias: float = 0.35
@export var cover_base_radius_cells: float = 2.5
## Blocks stamped into the block-base drift map per frame (rebuilt once per
## level change, over several frames).
@export var cover_drift_blocks_per_frame: int = 24
## Height (metres) over which a disc drift dome fades in from its rim, so
## it blends into the cover instead of showing a circle outline.
@export var disc_drift_rim_fade_m: float = 0.08
## Colliding disc drifts start growing only once the visual cover has
## reached this level (light snow is a frosting with no mounds).
@export var disc_drift_min_cover: int = 2

@export_group("Budget")
## Snowy cell tops per block.
@export var max_patches_per_block: int = 4
## Snowy block patches in the whole match (one collider each).
@export var max_block_patches: int = 160
## Colliding disc drifts in the whole match (one collider each).
@export var max_disc_patches: int = 90
## Disc drifts keep this far from home and goal flags (metres).
@export var disc_flag_clear_radius_m: float = 2.5
## Coverage checks (one shape query each) per physics frame.
@export var patch_checks_per_frame: int = 12
## Dome meshes/hulls computed per frame (host and client); a block or disc
## region swaps to its new snow in one commit once all its domes are ready.
@export var rebuild_patches_per_frame: int = 3
## Live blocks examined for new snowy tops per physics frame.
@export var discover_blocks_per_frame: int = 16
## Disc drifts are grouped into square regions this many cells wide (one
## mesh and one static body per region).
@export var disc_region_cells: int = 16
## Hold a sleeping block frozen while its snow shapes change: Jolt wakes a
## body whose shape changes and the whole resting pile with it; a frozen
## (static) body wakes nothing.
@export var freeze_during_rebuild: bool = true
## Host: fewest seconds between two replicated snow states.
@export var send_min_interval_s: float = 0.25

@export_group("Presentation")
## Falling flakes at full intensity (the Low graphics preset uses the second).
@export var flake_amount: int = 1600
@export var flake_amount_low: int = 450
## Half extent of the camera-centred box flakes spawn in (metres).
@export var flake_box_half_extent: Vector3 = Vector3(24.0, 1.0, 24.0)
## Spawn box height above the camera (metres).
@export var flake_height_above_camera_m: float = 12.0
@export var flake_fall_speed: float = 1.8
@export var flake_lifetime_s: float = 9.0
@export var flake_size_m: float = 0.1
## Turbulence strength (sideways wander).
@export var flake_drift: float = 0.35
## Flake size and fall speed vary by +/- this fraction.
@export_range(0.0, 0.9, 0.01) var flake_jitter: float = 0.35
@export var flake_color: Color = Color(0.96, 0.98, 1.0, 0.9)
## Cel-styled snow colours: lit, shaded band, cool rim.
## Off-white, never pure white: with the three light bands it stays below
## the glow threshold under the brightest sky theme.
@export var snow_color: Color = Color(0.8, 0.82, 0.9, 1.0)
## Direct-light gain of snow on the disc (its lighting replaces the metal's
## damped response); keeps the lit band under the glow threshold.
@export var cover_light_gain: float = 0.7
## Cel tone steps inside a disc drift, by snow depth 0..1: shadow tone below
## the first, pale lavender up to the second, lit off-white above; each step
## is cover_tone_width wide. The outer cover_edge_soft of depth fades softly.
@export_range(0.0, 1.0, 0.01) var cover_tone_mid_at: float = 0.35
@export_range(0.0, 1.0, 0.01) var cover_tone_lit_at: float = 0.7
@export_range(0.0, 0.2, 0.005) var cover_tone_width: float = 0.03
@export_range(0.01, 1.0, 0.01) var cover_edge_soft: float = 0.3
@export var cover_tone_mid_color: Color = Color(0.74, 0.76, 0.9, 1.0)
@export var cover_tone_shade_color: Color = Color(0.6, 0.63, 0.82, 1.0)
## Ambient (sky) light kept on disc snow, as a fraction of the disc's own.
@export_range(0.0, 1.0, 0.01) var cover_ambient_factor: float = 0.6
@export var snow_mid_color: Color = Color(0.8, 0.82, 0.93, 1.0)
@export var snow_shade_color: Color = Color(0.55, 0.58, 0.82, 1.0)
@export var snow_rim_color: Color = Color(0.8, 0.9, 1.0, 1.0)
@export_range(0.0, 2.0, 0.01) var snow_rim_strength: float = 0.2


## Height of a patch's level-`level` dome peak (metres, before shape factors).
func level_height(level: int) -> float:
	if depth_levels <= 0:
		return 0.0
	return max_depth_m * float(clampi(level, 0, depth_levels)) / float(depth_levels)


## Seconds between two growth passes at `current_intensity` (INF when calm).
func level_interval(current_intensity: float) -> float:
	if current_intensity <= 0.0:
		return INF
	return seconds_per_level / current_intensity


## Highest level allowed while melting: the ramp-out's remaining fraction of
## the peak the event reached, rounded up so the last level goes only at 0.
func melt_cap(current_intensity: float, peak: float) -> int:
	if peak <= 0.0 or current_intensity <= 0.0:
		return 0
	var fraction: float = clampf(current_intensity / peak, 0.0, 1.0)
	return clampi(ceili(float(depth_levels) * fraction - MELT_ROUNDING), 0, depth_levels)
