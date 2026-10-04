class_name SkyThemeDef
extends Resource
## DECISION (Bontago-mp0.13): the cycle length belongs to the theme resource,
## so every peer receives the same authored duration with the shipped content.
## Bontago-mp0.83 (owner playtest 2026-10-03): the full day/night cycle is 300 s
## (5 min), for every theme; no sky_themes/*.tres overrides it. The F4 Sky tab
## edits it live (60..1800 s) and Skybox keeps the phase continuous across the edit.
@export_range(60.0, 1800.0, 1.0) var cycle_length_seconds: float = 300.0
@export_range(5.0, 85.0, 1.0) var cycle_sun_peak_degrees: float = 65.0
@export_range(0.01, 0.5, 0.01) var cycle_twilight_width: float = 0.2
@export_range(1.0, 10.0, 0.1) var cycle_star_brightness: float = 2.0
@export_range(8.0, 200.0, 1.0) var cycle_star_cells: float = 105.0
@export_range(0.0, 1.0, 0.01) var cycle_star_threshold: float = 0.92
@export_range(0.01, 0.3, 0.01) var cycle_star_radius: float = 0.12
@export_range(0.01, 0.5, 0.01) var cycle_star_horizon_fade: float = 0.22
## Bontago-mp0.122: the moon_v1 disc + halo, opposite the sun. Angular radius of the
## visible disc and halo (degrees), halo strength, disc brightness, and the night mix
## (0..1) at which it is fully visible (it fades in from 0 at dusk, out at dawn).
@export_range(0.5, 12.0, 0.1) var cycle_moon_angular_radius_deg: float = 3.2
@export_range(2.0, 40.0, 0.5) var cycle_moon_halo_radius_deg: float = 14.0
@export_range(0.0, 2.0, 0.05) var cycle_moon_halo_strength: float = 0.6
@export_range(0.2, 3.0, 0.05) var cycle_moon_brightness: float = 1.0
@export_range(0.05, 1.0, 0.01) var cycle_moon_full_night_mix: float = 0.8
## Bontago-59o.18 (docs/SKY_CYCLE_DEFAULT_PLAN.md): Cycle is the default sky and
## the lobby's Sunset / Dawn / Night options become the same cycle locked at a
## fixed phase. Phase 0 = dawn horizon, 0.25 = noon, 0.5 = sunset horizon,
## 0.75 = midnight (Skybox.set_cycle_phase). All five values below are
## shipped content, so every peer derives the same look from the replicated
## sky_theme_mode / sky_theme_resolved with no new wire field.
## Phase a running Cycle match opens at (0.10 = morning, sun ~38 degrees, full day).
@export_range(0.0, 1.0, 0.01) var cycle_start_phase: float = 0.10
## Bontago-1pi.75: a Cycle match opens at a random phase in [min, max] (host-rolled from
## the match seed, MatchConfig.resolve_sky_start_phase). DECISION: 0.0..0.62 spans dawn,
## noon and the sunset into early dusk, avoiding the pitch-black midnight (0.75) as an
## opening; widen max toward 1.0 to allow night starts.
@export_range(0.0, 1.0, 0.01) var cycle_random_start_min: float = 0.0
@export_range(0.0, 1.0, 0.01) var cycle_random_start_max: float = 0.62
## Phase the lobby's "Sunset" option (id "sunset") is locked at: sun low on the setting side.
@export_range(0.0, 1.0, 0.005) var cycle_locked_phase_sunset: float = 0.47
## Phase the lobby's "Dawn" option (id "dawn") is locked at: just after sunrise.
@export_range(0.0, 1.0, 0.005) var cycle_locked_phase_dawn: float = 0.03
## Phase the lobby's "Night" option (id "night") is locked at: midnight.
@export_range(0.0, 1.0, 0.005) var cycle_locked_phase_night: float = 0.75
## Day palette blend phases (a, b, c, d): the dawn palette is used by day and
## fades into the sunset palette on the setting side with
## smoothstep(a, b, phase) * (1 - smoothstep(c, d, phase)). Read by the palette
## blend package (C1b); not a slider row (the F4 panel builds no Vector4 rows).
@export var cycle_dusk_weight_phases: Vector4 = Vector4(0.30, 0.46, 0.90, 0.98)
## Bontago-59o.18 (C1b variation, owner 2026-10-03: "lets add some variation and just
## set a range so it can vary"): the cycle's sky exposure and cloud coverage are not
## fixed at one theme's values (Dawn 0.95 / 0.5, Sunset 0.8 / 0.68); each wanders
## between the min and max below as a smooth, low-frequency function of the match
## seed and the cycle phase (core/SkyVariation.gd), so the host and every client
## show the same sky with no new wire field. A locked Sunset / Dawn / Night sits at
## the value that function has at its locked phase. Storm and overcast scale the
## varying exposure (they never replace it). Off = the theme's own fixed values.
@export var variation_enabled: bool = true
## Sky shader `exposure` range (the overcast weather multiplies whatever it is now).
@export_range(0.0, 2.0, 0.01) var variation_exposure_min: float = 0.8
@export_range(0.0, 2.0, 0.01) var variation_exposure_max: float = 0.95
## Sky shader `cloud_coverage` range: the noise threshold of the overhead cloud layers
## (higher = fewer clouds). Only visible while proc_overhead_clouds_enabled is on.
@export_range(0.0, 1.0, 0.01) var variation_cloud_coverage_min: float = 0.5
@export_range(0.0, 1.0, 0.01) var variation_cloud_coverage_max: float = 0.68
## Sky shader `proc_sea_coverage` range: the same threshold for the cloud floor under
## the horizon (also written to the puff material so the far puffs fade into it).
@export_range(0.0, 1.0, 0.01) var variation_sea_coverage_min: float = 0.3
@export_range(0.0, 1.0, 0.01) var variation_sea_coverage_max: float = 0.48
## Lattice points of the variation per full cycle: the values swing about this many
## times a day (the average swing lasts cycle_length_seconds / this; 3 = 100 s of a
## 300 s day). Fewer is slower and calmer, more is busier; always smooth.
@export_range(2, 12, 1) var variation_knots_per_cycle: int = 3
## Bontago-59o.16: opt-in procedural sky look (docs/SKY_PROCEDURAL_PLAN.md),
## declared first so it is the first row of the F4 Sky tab for the owner's
## painted-vs-procedural comparison. Skybox.apply_theme() writes
## procedural_sea_mix (0 while this is false) and the proc_* parameters.
@export var sky_look_procedural: bool = false
## Optional authored sky shader, also used for environment reflections.
@export var sky_material: Material = null
## Panorama longitude sampling offset, shared by sky background and reflections.
@export var sky_yaw_offset_deg: float = 0.0
## Panorama latitude sampling offset; zero preserves the authored horizon height.
@export var sky_pitch_offset_deg: float = 0.0
## A named sky/ground/fog colour palette applied onto the fallback
## ProceduralSkyMaterial and the shared Environment's fog fields whenever no
## textured six-face set is loaded (game/Skybox.gd's `fallback_active == true`
## -- see Skybox.apply_theme()).
##
## M7 P3 (Bontago-xtq.28) ships exactly one instance,
## config/sky_themes/sunset.tres, tuned against docs/art_mockups/
## 04-sunset-signal.png and 07-sunset-signal-cel-shaded.png. M8 follow-up
## (do not build now, per docs/M7_PLAN.md's P3 package): dawn/storm/night
## instances, plus a theme-selection row in ui/TuningPanel.gd (parallel to its
## existing Skybox six-face-set dropdown, `_build_skybox_row()`) once there is
## more than one instance for the owner to choose between -- a single theme
## needs no picker of its own.

## ProceduralSkyMaterial.sky_top_color / sky_horizon_color -- the upper
## hemisphere's zenith and near-horizon colour.
@export var sky_top_color: Color = Color(0.161, 0.2, 0.333)
@export var sky_horizon_color: Color = Color(0.98, 0.64, 0.38)

## ProceduralSkyMaterial.ground_bottom_color / ground_horizon_color -- the
## lower hemisphere (this map floats above a cloud deck, so "ground" here
## reads as clouds seen from above in shade, not terrain).
@export var ground_bottom_color: Color = Color(0.118, 0.098, 0.137)
@export var ground_horizon_color: Color = Color(0.847, 0.514, 0.333)

## Design range (degrees) a future per-theme sun animation could draw from --
## apply_theme() always writes `y` (the wider/softer glow edge) onto
## ProceduralSkyMaterial.sun_angle_max, since that material only exposes one
## float, not a min/max pair. See Skybox.apply_theme()'s own DECISION.
@export var sun_angle_min_max: Vector2 = Vector2(8.0, 20.0)

## Environment.fog_light_color / fog_density -- the ambient haze tint/
## thickness, also reused by Skybox's FogVolume cloud-deck FogMaterial so the
## depth fog and the volumetric deck read as one coherent colour instead of
## two independently tuned effects.
@export var fog_color: Color = Color(0.93, 0.58, 0.4)
@export var fog_density: float = 0.015

## Environment.fog_sky_affect -- how much the basic depth fog tints the
## rendered sky background itself (0 == sky renders untouched past
## fog_depth_end, 1 == the engine's own default, which fully replaces the sky
## with flat fog_light_color). Bontago-xtq.28's rejected candidate never set
## this, so it silently sat at the engine default of 1.0 and masked the
## ProceduralSkyMaterial's orange-horizon/blue-zenith gradient behind a flat
## haze regardless of fog_density. Kept at 0.0 here so the sunset gradient at
## the horizon stays visible; a future stormier theme could raise it.
@export var fog_sky_affect: float = 0.0

## Bontago-mp0.130 (cosmic-map reference: sky-matched haze, strong sky affect):
## the further Environment fog techniques. fog_aerial_perspective blends the fog
## colour toward the sky colour behind it with distance, so the far cloud sea
## melts into the horizon instead of a flat tint. fog_sun_scatter warms the haze
## toward the sun (COSTS ~1.5 ms GPU at 720p, so every shipped theme keeps it 0). The height pair makes fog denser below fog_height_m (the
## cloud sea under the disc) than around the arena; fog_height_density 0 turns
## it off. All stay clear of the play field: tests pin the keep at the far rim.
@export_range(0.0, 1.0, 0.01) var fog_aerial_perspective: float = 0.0
@export_range(0.0, 1.0, 0.01) var fog_sun_scatter: float = 0.0
@export var fog_height_m: float = 0.0
@export var fog_height_density: float = 0.0
## Ambient haze on the scenery shaders that opt out of Environment fog (the cloud
## sea / puffs): nothing nearer than haze_begin_m, haze_strength at haze_end_m,
## toward fog_color. begin sits beyond 1.2x the field radius so the arena stays crisp.
@export_range(0.0, 1.0, 0.01) var haze_strength: float = 0.0
@export var haze_begin_m: float = 90.0
@export var haze_end_m: float = 520.0

## Environment.volumetric_fog_density/volumetric_fog_albedo -- the global
## ambient volumetric-fog density/tint the render server applies across the
## *entire view frustum*, independent of any FogVolume box placed inside it.
## Bontago-xtq.28 fix round 2 (decisive finding): this field defaults to 0.05
## on a fresh Environment and Skybox.apply_theme()'s previous candidate never
## wrote it, so every shot showed a uniform grey haze over the whole frame
## regardless of where _spawn_fog_volume()'s cloud-deck FogVolume box was
## centred -- a FogVolume only ever *adds* extra density inside its own bounds
## on top of this ambient floor; it cannot subtract it back out elsewhere.
## Kept low here (not 0.0, so the ambient volumetric pass still contributes a
## faint atmospheric depth cue at range) so the cloud-deck FogVolume, not this
## global floor, is what reads as the visible sunset haze band.
@export var volumetric_fog_density: float = 0.003
@export var volumetric_fog_albedo: Color = Color(0.93, 0.58, 0.4)

## Skybox._spawn_fog_volume()'s FogVolume box (the "cloud deck" the disk
## floats above): world-space size and the y-height of its centre. World y ==
## 0 is the floating disk's top surface (see game/Skybox.gd's
## PROBE_GROUND_CLEARANCE_M doc); NetConfig.pos_max_y == 72.0 is the highest a
## stacked block may legally sit. Bontago-xtq.28's rejected candidate centred
## this box at y 40 (spanning y 10..70), which swallowed the entire play
## volume and the gameplay camera in fog. Centring it well below the disk
## instead (top edge at y -10, i.e. at least 10 m of clearance under the
## disk's underside) keeps the whole 0..72 m stacking volume fog-free while
## still reading as a cloud layer the island floats above.
@export var cloud_deck_size_m: Vector3 = Vector3(800.0, 60.0, 800.0)
@export var cloud_deck_height_m: float = -40.0

## Bontago-adt.1 (graphics pass): per-theme light and environment values that
## Skybox.apply_theme() writes onto the scene's DirectionalLight3D (via
## Skybox.light_path) and the shared Environment. Defaults equal the values
## game/Main.tscn shipped with, so a theme that leaves them alone (sunset)
## looks exactly as before.
@export var light_color: Color = Color(1.0, 0.94, 0.85)
@export var light_energy: float = 0.85
## DirectionalLight3D.rotation_degrees; its +Z axis points toward the sun/moon.
@export var light_rotation_deg: Vector3 = Vector3(-45.0, -30.0, 0.0)
## Environment.ambient_light_energy (ambient comes from the sky).
@export var ambient_energy: float = 0.5
## Environment glow_intensity / glow_hdr_threshold: lower threshold makes
## emissive territory, beacons and the moon bloom more.
@export var glow_intensity: float = 0.5
@export var glow_hdr_threshold: float = 1.3
## Whether vfx/SunFlare.gd's screen-space lens flare is drawn under this theme
## (it aims at the painted sunset's sun, so a night theme turns it off).
@export var sun_flare_enabled: bool = true

## Cloud sea below the disc (vfx/CloudSea.gd): 3D toon cumulus clumps built
## from flat-bottomed puffs, drawn with a ShaderMaterial using
## shaders/cloud_puffs.gdshader (its colours, lighting and fades live on that
## material). The clumps scatter over a ring (inner/outer radius from the disc
## axis) with bases between cloud_base_min_m and cloud_base_max_m; no puff top
## rises above cloud_top_max_m (keep it well under the disc's underside and
## the 0..72 m play volume). Each clump is cloud_clump_radius_* wide and
## cloud_clump_height_ratio of that tall, and drifts around the disc at
## cloud_drift_speed_* metres per second (negative reverses). cloud_flat_base
## is how far below a puff's centre (fraction of its radius) its flat base
## sits. GraphicsPreset.cloud_puff_density scales cloud_clump_count. Null
## material or zero clumps means no puffs (the far cloud sea in the sky
## panorama remains).
@export var cloud_puff_material: Material = null
@export var cloud_clump_count: int = 0
@export var cloud_puffs_per_clump: int = 12
@export var cloud_seed: int = 11
@export var cloud_ring_inner_m: float = 80.0
@export var cloud_ring_outer_m: float = 460.0
@export var cloud_base_min_m: float = -75.0
@export var cloud_base_max_m: float = -45.0
@export var cloud_top_max_m: float = -18.0
@export var cloud_clump_radius_min_m: float = 15.0
@export var cloud_clump_radius_max_m: float = 36.0
@export var cloud_clump_height_ratio: float = 0.65
@export var cloud_flat_base: float = 0.15
## Bontago-t8x.2 (owner 2026-10-01: "try moving the puff layer up a bit"): metres
## the sea puff layer and the procedural far ring are raised (bases and tops
## together). vfx/CloudSea.gd then clamps every puff that could reach the disc
## or the play volume back under the disc: the exclusion cylinder is the largest
## field radius (MapDef.RADIUS_LARGE) plus cloud_disc_clearance_ratio of it, and
## inside it no puff top may rise above the disc's underside minus that same
## clearance (disc height from MapDef.disk_height). So a raise can never put a
## cloud through, or in front of, the disc at any tilt or orbit.
@export var cloud_puff_raise_m: float = 0.0
## Clearance around the disc, as a fraction of the largest field radius (see
## cloud_puff_raise_m). 0.25 of the 60 m large field is 15 m.
@export var cloud_disc_clearance_ratio: float = 0.25
@export var cloud_drift_speed_min_mps: float = 0.8
@export var cloud_drift_speed_max_mps: float = 1.8

## Cloud banks (Bontago-470.5): a second, sparser set of big cumulus clumps far
## out past the disc edge, standing higher than the sea (tops up to
## cloud_bank_top_max_m) so a camera looking outward sees them on the horizon.
## Their ring starts far beyond the largest disc, so they never cover the play
## area; drawn by the same MultiMesh as the sea and scaled by the same
## GraphicsPreset density. cloud_bank_count 0 means none.
## cloud_radial_bias crowds the sea's clumps toward its inner (near) edge
## (1 = even over the ring's area, higher = denser near the disc).
@export var cloud_radial_bias: float = 1.0
@export var cloud_bank_count: int = 0
@export var cloud_bank_ring_inner_m: float = 260.0
@export var cloud_bank_ring_outer_m: float = 520.0
@export var cloud_bank_base_min_m: float = -30.0
@export var cloud_bank_base_max_m: float = -5.0
@export var cloud_bank_top_max_m: float = 45.0
@export var cloud_bank_radius_min_m: float = 30.0
@export var cloud_bank_radius_max_m: float = 60.0

## Distant bird flocks (vfx/DistantBirds.gd, Bontago-470.5): a ShaderMaterial
## using shaders/distant_birds.gdshader. Flocks are a random occurrence, not a
## permanent fixture: up to bird_flock_count flocks may be in flight at once
## (each slot waits a random bird_gap_min_s..bird_gap_max_s between flights;
## bird_first_delay_* is the wait before the first), a flock is
## bird_flock_size_min..max birds (bird_single_chance: a lone bird instead),
## and each flight is a straight-ish path that enters from the far
## bird_path_radius_m ring, passes the disc axis at bird_distance_min..max_m
## (its closest approach; keep this well past the disc) at bird_altitude_*
## metres, and leaves the far side at bird_speed_min..max_mps. bird_spacing_m is
## the formation spacing, bird_v_chance the odds of a V rather than a loose
## cluster; bird_size_* is the wing half-span (m). bird_seed 0 = different
## flocks every run. Null material or zero slots means no birds.
@export var bird_material: Material = null
@export var bird_flock_count: int = 0
@export var bird_flock_size_min: int = 2
@export var bird_flock_size_max: int = 7
@export var bird_single_chance: float = 0.2
@export var bird_gap_min_s: float = 90.0
@export var bird_gap_max_s: float = 240.0
@export var bird_first_delay_min_s: float = 10.0
@export var bird_first_delay_max_s: float = 60.0
@export var bird_seed: int = 0
@export var bird_path_radius_m: float = 650.0
@export var bird_distance_min_m: float = 150.0
@export var bird_distance_max_m: float = 380.0
@export var bird_altitude_min_m: float = 15.0
@export var bird_altitude_max_m: float = 80.0
@export var bird_climb_max_mps: float = 1.2
@export var bird_speed_min_mps: float = 11.0
@export var bird_speed_max_mps: float = 17.0
@export var bird_size_min_m: float = 2.0
@export var bird_size_max_m: float = 3.2
@export var bird_spacing_m: float = 14.0
@export var bird_v_chance: float = 0.55

## Bontago-adt.3: cosmetic local ambient life (perching birds on sunset,
## fireflies on night) -- see config/AmbientLifeConfig.gd. Null means none.
@export var ambient_life: AmbientLifeConfig = null

## Bontago-59o.16 (procedural sky, docs/SKY_PROCEDURAL_PLAN.md): the proc_*
## parameters below drive the procedural branch of shaders/sunset_clouds.gdshader
## (plus the puff far-fade and night sea) when sky_look_procedural is on.
@export var procedural_sea_mix: float = 1.0
@export var proc_zenith_color: Color = Color(0.161, 0.2, 0.333)
@export var proc_mid_color: Color = Color(0.55, 0.36, 0.5)
@export var proc_horizon_color: Color = Color(0.98, 0.64, 0.38)
@export var proc_gradient_mid_height: float = 0.35
@export var proc_gradient_power: float = 1.5
@export var proc_horizon_glow_color: Color = Color(1.0, 0.62, 0.28)
@export var proc_horizon_glow_width: float = 0.18
@export var proc_sun_glow_strength: float = 1.0
@export var proc_sea_color_near: Color = Color(0.85, 0.5, 0.42)
@export var proc_sea_color_far: Color = Color(0.34, 0.27, 0.47)
@export var proc_sea_horizon_fade: float = 0.12
@export var proc_strata_scale: float = 1.0
## Bontago-59o.19: far puff ring drawn only while sky_look_procedural is on --
## a third set of big cumulus clumps reaching toward the horizon so the cloud sea
## below it is real lit cumulus, not shader noise. proc_far_count 0 = none.
## proc_far_fade_cap (0..1) caps the puffs' distance fade into the sky colour so
## distant clumps keep visible lit/shadow shading.
@export var proc_far_count: int = 0
@export var proc_far_ring_inner_m: float = 650.0
@export var proc_far_ring_outer_m: float = 2600.0
@export var proc_far_radial_bias: float = 1.0
@export var proc_far_base_min_m: float = -160.0
@export var proc_far_base_max_m: float = -90.0
@export var proc_far_top_max_m: float = -20.0
@export var proc_far_radius_min_m: float = 60.0
@export var proc_far_radius_max_m: float = 130.0
@export var proc_far_fade_cap: float = 0.7

## Bontago-t8x.2 (owner: "I'm not a huge fan of the above clouds"): master toggle
## for the procedural look's overhead cloud layers (the card atlas below or the
## noise strata it replaces). Off by default; the layers are kept, not deleted.
## Skybox writes it to the sky shader's proc_overhead_mix.
@export var proc_overhead_clouds_enabled: bool = false

## Bontago-59o.20: authored cloud-card overhead layer (procedural look only).
## proc_cards_enabled swaps the noise overhead layers for the Blender card
## atlas (assets/sky/cloud_cards); density is the chance a grid cell holds a
## card, scale the plane scale (higher = more, smaller cards), opacity the
## overall cloud alpha.
@export var proc_cards_enabled: bool = true
@export var proc_cards_density: float = 0.85
@export var proc_cards_scale: float = 1.5
@export var proc_cards_opacity: float = 0.95


## Locked cycle phase (0..1) for a concrete sky id as MatchConfig resolves it
## ("sunset", "night" or "dawn"), or -1.0 for any other id (including "" = the
## running cycle), so callers can tell "locked" from "running" without a flag.
func locked_phase_for(sky_id: String) -> float:
	# DECISION: literal ids, matching MatchConfig.SKY_THEME_IDS; the enum has
	# non-concrete RANDOM/CYCLE entries, so its indices cannot key this.
	match sky_id:
		"sunset":
			return cycle_locked_phase_sunset
		"dawn":
			return cycle_locked_phase_dawn
		"night":
			return cycle_locked_phase_night
		_:
			return -1.0
