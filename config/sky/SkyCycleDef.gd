class_name SkyCycleDef
extends Resource
## The one day/night cycle of the sky (plain data): structure, the day keyframes, the night
## layer and the cloud and bird layouts. Day, Dawn and Night are this cycle locked at a phase
## (phase 0 dawn horizon, 0.25 noon, 0.5 sunset horizon, 0.75 midnight). Evaluated by
## core/sky/SkyEvaluator.gd; the shipped values come from the themes it replaces.


# Clock
## Seconds for one full day/night cycle; every peer reads the same authored value.
@export_range(60.0, 1800.0, 1.0) var cycle_length_seconds: float = 300.0
## Phase a running cycle match opens at (0 dawn, 0.25 noon, 0.5 sunset, 0.75 midnight).
@export_range(0.0, 1.0, 0.01) var cycle_start_phase: float = 0.10
## Lowest phase of the host-rolled random opening phase.
@export_range(0.0, 1.0, 0.01) var cycle_random_start_min: float = 0.0
## Highest phase of the random opening phase (0.62 avoids opening at midnight).
@export_range(0.0, 1.0, 0.01) var cycle_random_start_max: float = 0.62
## Phase the lobby Sunset sky is locked at.
@export_range(0.0, 1.0, 0.005) var cycle_locked_phase_sunset: float = 0.47
## Phase the lobby Dawn sky is locked at.
@export_range(0.0, 1.0, 0.005) var cycle_locked_phase_dawn: float = 0.03
## Phase the lobby Night sky is locked at.
@export_range(0.0, 1.0, 0.005) var cycle_locked_phase_night: float = 0.75

# Sun and light
## Sun elevation at noon, degrees.
@export_range(5.0, 85.0, 1.0) var cycle_sun_peak_degrees: float = 65.0
## Half-width of the sine-of-elevation twilight smoothstep that mixes in the night.
@export_range(0.01, 0.5, 0.01) var cycle_twilight_width: float = 0.2
## Direct sun energy multiplier at full sun contrast.
@export_range(1.0, 3.0, 0.05) var cycle_sun_energy_gain: float = 1.7
## Sky ambient multiplier at full sun contrast.
@export_range(0.2, 1.0, 0.01) var cycle_day_ambient_scale: float = 0.7
## Sine of the sun elevation at which the full contrast factor applies.
@export_range(0.1, 1.0, 0.01) var cycle_sun_contrast_full_sin: float = 0.6
## Azimuth reference the sun path rotates from (the sky material sun_direction of the shipped look).
@export var sun_base_direction: Vector3 = Vector3(0.963087, 0.069011, -0.260192)
## Sine of the sun elevation over which the key light fades in/out at the horizon.
@export_range(0.01, 1.0, 0.01) var light_key_ramp_sin: float = 0.2

# Ambient-life swap
## Night mix above which the ambient life switches to its night set.
@export_range(0.0, 1.0, 0.01) var life_night_on_mix: float = 0.85
## Night mix below which the ambient life switches back to its day set.
@export_range(0.0, 1.0, 0.01) var life_night_off_mix: float = 0.15

# Stars
## Star brightness.
@export_range(1.0, 10.0, 0.1) var cycle_star_brightness: float = 2.0
## Star grid density.
@export_range(8.0, 200.0, 1.0) var cycle_star_cells: float = 105.0
## Star cell hash threshold (higher is fewer stars).
@export_range(0.0, 1.0, 0.01) var cycle_star_threshold: float = 0.92
## Star radius within its cell.
@export_range(0.01, 0.3, 0.01) var cycle_star_radius: float = 0.12
## Fade of stars near the horizon.
@export_range(0.01, 0.5, 0.01) var cycle_star_horizon_fade: float = 0.22

# Moon
## Moon disc angular radius, degrees.
@export_range(0.5, 12.0, 0.1) var cycle_moon_angular_radius_deg: float = 3.2
## Moon halo angular radius, degrees.
@export_range(2.0, 40.0, 0.5) var cycle_moon_halo_radius_deg: float = 14.0
## Moon halo strength.
@export_range(0.0, 2.0, 0.05) var cycle_moon_halo_strength: float = 0.6
## Moon disc brightness.
@export_range(0.2, 3.0, 0.05) var cycle_moon_brightness: float = 1.0
## Night mix at which the moon is fully visible.
@export_range(0.05, 1.0, 0.01) var cycle_moon_full_night_mix: float = 0.8

# Aurora
## Whether the aurora can show at night.
@export var aurora_enabled: bool = true
## Aurora brightness.
@export_range(0.0, 3.0, 0.05) var aurora_intensity: float = 0.45
## Aurora curtain lower colour.
@export var aurora_color_low: Color = Color(0.12, 1.0, 0.42)
## Aurora curtain middle colour.
@export var aurora_color_mid: Color = Color(0.08, 0.75, 0.8)
## Aurora curtain upper colour.
@export var aurora_color_top: Color = Color(0.55, 0.3, 0.95)
## Aurora drift and ripple speed.
@export_range(0.0, 4.0, 0.05) var aurora_speed: float = 1.0
## Sine of the elevation of the aurora's lower edge.
@export_range(0.0, 0.6, 0.01) var aurora_base_height: float = 0.1
## Height of the curtains above the lower edge, in sine of elevation.
@export_range(0.05, 1.0, 0.01) var aurora_curtain_height: float = 0.4
## Night mix at which the aurora starts to fade in.
@export_range(0.0, 1.0, 0.01) var aurora_start_night_mix: float = 0.5
## Night mix at which the aurora is fully visible.
@export_range(0.05, 1.0, 0.01) var aurora_full_night_mix: float = 0.95
## Chance a night shows the aurora, rolled once per night from the match seed.
@export_range(0.0, 1.0, 0.01) var aurora_night_chance: float = 0.1

# Variation
## Whether sky exposure and sea coverage wander with the match seed and phase.
@export var variation_enabled: bool = true
## Lowest sky exposure of the variation.
@export_range(0.0, 2.0, 0.01) var variation_exposure_min: float = 0.8
## Highest sky exposure of the variation.
@export_range(0.0, 2.0, 0.01) var variation_exposure_max: float = 0.95
## Lowest cloud-sea coverage threshold of the variation.
@export_range(0.0, 1.0, 0.01) var variation_sea_coverage_min: float = 0.3
## Highest cloud-sea coverage threshold of the variation.
@export_range(0.0, 1.0, 0.01) var variation_sea_coverage_max: float = 0.48
## Lattice points of the variation per full cycle.
@export_range(2, 12, 1) var variation_knots_per_cycle: int = 3

# Fog and glow structure
## How much the depth fog tints the sky background.
@export_range(0.0, 1.0, 0.01) var fog_sky_affect: float = 0.0
## Blend of the fog colour toward the sky colour with distance.
@export_range(0.0, 1.0, 0.01) var fog_aerial_perspective: float = 0.0
## Warms the haze toward the sun (GPU cost, keep 0).
@export_range(0.0, 1.0, 0.01) var fog_sun_scatter: float = 0.0
## Height below which the height fog is denser, metres.
@export_range(-500.0, 500.0, 1.0) var fog_height_m: float = 0.0
## Density of the height fog (0 turns it off).
@export_range(0.0, 1.0, 0.001) var fog_height_density: float = 0.0
## Ambient haze on the scenery shaders at haze_end_m.
@export_range(0.0, 1.0, 0.01) var haze_strength: float = 0.0
## Distance where the ambient haze starts.
@export_range(0.0, 2000.0, 1.0) var haze_begin_m: float = 90.0
## Distance where the ambient haze reaches haze_strength.
@export_range(0.0, 4000.0, 1.0) var haze_end_m: float = 520.0
## Size of the cloud-deck FogVolume, metres.
@export var cloud_deck_size_m: Vector3 = Vector3(800.0, 60.0, 800.0)
## Height of the cloud-deck FogVolume centre, metres.
@export_range(-500.0, 100.0, 1.0) var cloud_deck_height_m: float = -40.0
## Environment glow intensity.
@export_range(0.0, 8.0, 0.01) var glow_intensity: float = 0.5
## Environment glow HDR threshold.
@export_range(0.0, 8.0, 0.01) var glow_hdr_threshold: float = 1.3

# Sky structure the storm overlay also targets
## Height of the sky gradient mid stop.
@export_range(0.0, 1.0, 0.01) var proc_gradient_mid_height: float = 0.35
## Sky gradient curve exponent.
@export_range(0.1, 8.0, 0.05) var proc_gradient_power: float = 1.5
## Fade of the cloud sea into the horizon.
@export_range(0.0, 1.0, 0.01) var proc_sea_horizon_fade: float = 0.12

# Materials
## Day keyframes: key 0 is the base palette (morning), later keys mix in by their phase window (evening).
@export var day_keyframes: Array[SkyKeyframe] = []
## The night layer mixed over the day palette by sun elevation.
@export var night: SkyNightKeyframe = null
## The one sky shader material.
@export var sky_material: ShaderMaterial = null
## The one cloud puff material.
@export var cloud_puff_material: ShaderMaterial = null
## Distant bird flock material; null means no birds.
@export var bird_material: Material = null
## Day ambient life (perching birds); null for none.
@export var ambient_life: AmbientLifeConfig = null

# Clouds: sea
## Number of sea cloud clumps (scaled by the graphics preset).
@export_range(0, 400, 1) var cloud_clump_count: int = 0
## Puffs per clump.
@export_range(1, 64, 1) var cloud_puffs_per_clump: int = 12
## Seed of the cloud placement.
@export_range(0, 2147483647, 1) var cloud_seed: int = 11
## Inner radius of the sea clump ring, metres.
@export_range(0.0, 3000.0, 1.0) var cloud_ring_inner_m: float = 80.0
## Outer radius of the sea clump ring, metres.
@export_range(0.0, 3000.0, 1.0) var cloud_ring_outer_m: float = 460.0
## Lowest sea clump base height, metres.
@export_range(-500.0, 500.0, 1.0) var cloud_base_min_m: float = -75.0
## Highest sea clump base height, metres.
@export_range(-500.0, 500.0, 1.0) var cloud_base_max_m: float = -45.0
## Highest point any sea puff may reach, metres.
@export_range(-500.0, 500.0, 1.0) var cloud_top_max_m: float = -18.0
## Smallest sea clump radius, metres.
@export_range(1.0, 300.0, 0.5) var cloud_clump_radius_min_m: float = 15.0
## Largest sea clump radius, metres.
@export_range(1.0, 300.0, 0.5) var cloud_clump_radius_max_m: float = 36.0
## Clump height as a fraction of its radius.
@export_range(0.1, 3.0, 0.01) var cloud_clump_height_ratio: float = 0.65
## How far below a puff centre its flat base sits, as a fraction of its radius.
@export_range(0.0, 1.0, 0.01) var cloud_flat_base: float = 0.15
## Metres the sea and far puff layers are raised.
@export_range(-100.0, 200.0, 0.5) var cloud_puff_raise_m: float = 0.0
## Clearance around the disc as a fraction of the largest field radius.
@export_range(0.0, 2.0, 0.01) var cloud_disc_clearance_ratio: float = 0.25
## Slowest clump drift speed, metres per second.
@export_range(-20.0, 20.0, 0.05) var cloud_drift_speed_min_mps: float = 0.8
## Fastest clump drift speed, metres per second.
@export_range(-20.0, 20.0, 0.05) var cloud_drift_speed_max_mps: float = 1.8
## Crowds the sea clumps toward the inner edge (1 is even).
@export_range(0.1, 8.0, 0.05) var cloud_radial_bias: float = 1.0

# Clouds: banks
## Number of far cloud banks.
@export_range(0, 200, 1) var cloud_bank_count: int = 0
## Inner radius of the bank ring, metres.
@export_range(0.0, 4000.0, 1.0) var cloud_bank_ring_inner_m: float = 260.0
## Outer radius of the bank ring, metres.
@export_range(0.0, 4000.0, 1.0) var cloud_bank_ring_outer_m: float = 520.0
## Lowest bank base height, metres.
@export_range(-500.0, 500.0, 1.0) var cloud_bank_base_min_m: float = -30.0
## Highest bank base height, metres.
@export_range(-500.0, 500.0, 1.0) var cloud_bank_base_max_m: float = -5.0
## Highest point of any bank puff, metres.
@export_range(-500.0, 500.0, 1.0) var cloud_bank_top_max_m: float = 45.0
## Smallest bank radius, metres.
@export_range(1.0, 400.0, 0.5) var cloud_bank_radius_min_m: float = 30.0
## Largest bank radius, metres.
@export_range(1.0, 400.0, 0.5) var cloud_bank_radius_max_m: float = 60.0

# Clouds: far ring
## Number of far-ring cloud clumps toward the horizon.
@export_range(0, 400, 1) var proc_far_count: int = 0
## Inner radius of the far ring, metres.
@export_range(0.0, 6000.0, 1.0) var proc_far_ring_inner_m: float = 650.0
## Outer radius of the far ring, metres.
@export_range(0.0, 6000.0, 1.0) var proc_far_ring_outer_m: float = 2600.0
## Crowds the far clumps toward the inner edge.
@export_range(0.1, 8.0, 0.05) var proc_far_radial_bias: float = 1.0
## Lowest far clump base height, metres.
@export_range(-1000.0, 1000.0, 1.0) var proc_far_base_min_m: float = -160.0
## Highest far clump base height, metres.
@export_range(-1000.0, 1000.0, 1.0) var proc_far_base_max_m: float = -90.0
## Highest point of any far puff, metres.
@export_range(-1000.0, 1000.0, 1.0) var proc_far_top_max_m: float = -20.0
## Smallest far clump radius, metres.
@export_range(1.0, 600.0, 0.5) var proc_far_radius_min_m: float = 60.0
## Largest far clump radius, metres.
@export_range(1.0, 600.0, 0.5) var proc_far_radius_max_m: float = 130.0
## Cap on the far puffs' distance fade into the sky colour.
@export_range(0.0, 1.0, 0.01) var proc_far_fade_cap: float = 0.7

# Birds
## Flocks that may be in flight at once (0 means no birds).
@export_range(0, 16, 1) var bird_flock_count: int = 0
## Smallest flock.
@export_range(1, 64, 1) var bird_flock_size_min: int = 2
## Largest flock.
@export_range(1, 64, 1) var bird_flock_size_max: int = 7
## Chance a flight is a lone bird.
@export_range(0.0, 1.0, 0.01) var bird_single_chance: float = 0.2
## Shortest wait between flights of one slot, seconds.
@export_range(0.0, 3600.0, 1.0) var bird_gap_min_s: float = 90.0
## Longest wait between flights of one slot, seconds.
@export_range(0.0, 3600.0, 1.0) var bird_gap_max_s: float = 240.0
## Shortest wait before a slot's first flight, seconds.
@export_range(0.0, 3600.0, 1.0) var bird_first_delay_min_s: float = 10.0
## Longest wait before a slot's first flight, seconds.
@export_range(0.0, 3600.0, 1.0) var bird_first_delay_max_s: float = 60.0
## Bird flight seed (0 is different flocks every run).
@export_range(0, 2147483647, 1) var bird_seed: int = 0
## Radius of the ring flights enter and leave from, metres.
@export_range(0.0, 4000.0, 1.0) var bird_path_radius_m: float = 650.0
## Closest approach to the disc axis, minimum, metres.
@export_range(0.0, 4000.0, 1.0) var bird_distance_min_m: float = 150.0
## Closest approach to the disc axis, maximum, metres.
@export_range(0.0, 4000.0, 1.0) var bird_distance_max_m: float = 380.0
## Lowest flight altitude, metres.
@export_range(-500.0, 1000.0, 1.0) var bird_altitude_min_m: float = 15.0
## Highest flight altitude, metres.
@export_range(-500.0, 1000.0, 1.0) var bird_altitude_max_m: float = 80.0
## Largest climb or descent rate, metres per second.
@export_range(0.0, 20.0, 0.05) var bird_climb_max_mps: float = 1.2
## Slowest flight speed, metres per second.
@export_range(0.0, 100.0, 0.5) var bird_speed_min_mps: float = 11.0
## Fastest flight speed, metres per second.
@export_range(0.0, 100.0, 0.5) var bird_speed_max_mps: float = 17.0
## Smallest bird wing half-span, metres.
@export_range(0.1, 20.0, 0.1) var bird_size_min_m: float = 2.0
## Largest bird wing half-span, metres.
@export_range(0.1, 20.0, 0.1) var bird_size_max_m: float = 3.2
## Formation spacing, metres.
@export_range(0.0, 200.0, 0.5) var bird_spacing_m: float = 14.0
## Chance a flock flies in a V rather than a loose cluster.
@export_range(0.0, 1.0, 0.01) var bird_v_chance: float = 0.55


## Locked cycle phase (0..1) for a concrete sky id as MatchConfig resolves it
## ("sunset", "night" or "dawn"), or -1.0 for any other id (including "" = the running
## cycle), so callers can tell "locked" from "running" without a flag.
func locked_phase_for(sky_id: String) -> float:
	match sky_id:
		MatchConfig.SKY_ID_SUNSET:
			return cycle_locked_phase_sunset
		MatchConfig.SKY_ID_DAWN:
			return cycle_locked_phase_dawn
		MatchConfig.SKY_ID_NIGHT:
			return cycle_locked_phase_night
		_:
			return -1.0


## How much of the aurora the cycle shows at night mix `night_mix` (0 none, 1 full): a
## smoothstep across the start..full edges, ordered first so a reversed edit still fades in.
func aurora_night_strength(night_mix: float) -> float:
	var low: float = minf(aurora_start_night_mix, aurora_full_night_mix)
	var high: float = maxf(aurora_start_night_mix, aurora_full_night_mix)
	return smoothstep(low, high, night_mix)


## The key whose raw values seed the cloud-puff snapshot at cycle start (the evening key,
## the last day keyframe), or null with no keys.
func evening_keyframe() -> SkyKeyframe:
	if day_keyframes.is_empty():
		return null
	return day_keyframes[day_keyframes.size() - 1]
