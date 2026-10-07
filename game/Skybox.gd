class_name Skybox
extends Node3D
## Runtime-loaded six-face placeholder skybox from the original 2003 Bontago
## install (spec 2.10, presentation). The faces are third-party assets and
## never shipped in this public repo (CLAUDE.md); tools/install_original_assets.ps1
## (owned by another package) copies them to
## `res://assets/original/textures/<set>/<face>.jpg` for local testing, and
## load_set() falls back to the existing ProceduralSkyMaterial untouched
## whenever that folder or a face inside it is missing.
##
## DECISION (game/Skybox.gd, Bontago-1en/assets-sky): six unshaded quads on a
## big inverted box, not a `shader_type sky` sampling a Cubemap. The box does
## not follow the camera -- box_half_extent (400 m) is far larger than any
## map's field_radius (60 m max) or the camera's zoom range
## (config/camera_tuning.tres: zoom_max 100 m), so the parallax from orbiting
## within the field is invisible in practice, at zero extra cost.
##
## DECISION (game/Skybox.gd, Bontago-xtq.8, owner 2026-09-23: "it reflects
## whatever light source you've put in but not the skybox we added
## recently"): the box alone was never enough -- the WorldEnvironment's own
## Sky resource is a separate thing the render server samples for reflections
## and ambient light (Main.tscn: ambient_light_source = AMBIENT_SOURCE_SKY),
## and drawing a box in front of the camera does not change what that
## resource shows. load_set() success now ALSO installs a `shader_type sky`
## ShaderMaterial (shaders/cubemap_sky.gdshader) onto `environment.sky.
## sky_material`, sampling the same six face textures with the same
## SkyboxConfig.face_rotations/face_flip_u/face_flip_v correction the box
## uses (shaders/cubemap_sky.gdshader's own doc has the per-face direction
## algebra, derived by inverting Skybox._face_corners()' corner mapping and
## checked against all four UV corners of all six faces). Reflections/ambient
## now show the loaded set's horizon instead of the ProceduralSkyMaterial
## gradient; a missing/failed set restores the original ProceduralSkyMaterial
## on the Sky resource exactly as it restores the box's fallback.
##
## The box mesh itself is deliberately kept rather than dropped now that the
## sky shader exists: the box is the one part of this system whose
## correctness was verified pixel-by-pixel (tools/skybox_seam_probe.gd's
## measured seam error) and is trivially checkable by eye in a single
## screenshot; the sky shader's face-selection math (its sky() function) was
## checked algebraically against all six faces' corners (see
## shaders/cubemap_sky.gdshader) and
## against two live camera yaws (docs/sky-reflection-before.png/-after.png),
## but a shader bug that only shows up at a grazing reflection angle this
## package's screenshots did not happen to catch would otherwise have no
## direct-view fallback to catch it visually during play. Once the sky
## shader has more mileage (e.g. the seam probe or an equivalent check is
## extended to score it the same way it scores the box), dropping the box and
## letting the sky alone draw the background is a safe, mechanical follow-up.
##
## Bontago-xtq.28 (M7 P3, docs/M7_ART_DIRECTION.md's sunset/atmosphere lines):
## two more pieces layer on top of the above, both applied only while
## `fallback_active` (the six-face box/shader are a separate, self-contained
## look and are left untouched by either):
##   - apply_theme() writes `theme`'s (config/SkyThemeDef.gd) sky/ground
##     colours onto `_fallback_sky_material` *in place*, its fog colour/
##     density onto the wired Environment's basic depth fog, and its
##     volumetric_fog_density/volumetric_fog_albedo onto that same
##     Environment's global ambient volumetric-fog fields (fix round 2 --
##     see SkyThemeDef.volumetric_fog_density's own doc for why the ambient
##     floor has to be set too, not just the FogVolume cloud deck below) --
##     called once from _ready(), so a later load_set() fallback restores the
##     themed colours automatically (see _restore_fallback_sky()) rather than
##     the material's own untouched defaults.
##   - a single FogVolume "cloud deck" child (_spawn_fog_volume()) is always
##     created, its `visible` flag alone tracking
##     GraphicsPreset.volumetric_fog_enabled (Settings.graphics_preset_changed,
##     the same read-only-preset pattern Main.gd's own P1 package
##     establishes) -- dropped from view entirely on Low, present on
##     Medium/High, per docs/M7_ART_DIRECTION.md's performance budget.

@export var config: SkyboxConfig = preload("res://config/skybox_config.tres")

## Bontago-xtq.28 (M7 P3): the sky/ground/fog palette applied onto the
## fallback ProceduralSkyMaterial whenever `fallback_active` is true -- see
## apply_theme() below and the class doc's new paragraph on it. Optional (null
## in a fixture that only cares about the box/fallback_active state); the game
## itself never overrides this from `preload`'s default, the same one-field/
## one-instance convention `config`/`visuals` above already use.
@export var theme: SkyThemeDef = preload("res://config/sky_themes/sunset.tres")
## The live Environment resource Main.tscn's WorldEnvironment displays
## (wired there by a plain node-property reference to the same sub-resource,
## not a node path -- CLAUDE.md's "no deep node paths" is about get_node()
## chains, not sharing one Resource two nodes both already own a reference
## to). Optional (null in a fixture test that only cares about the box/
## fallback_active state, e.g. most of tests/unit/test_skybox.gd): every sky-
## material write below is skipped when this or its .sky is unset.
@export var environment: Environment = null
## Bontago-adt.1: the scene's DirectionalLight3D (wired in Main.tscn, same
## NodePath convention as reflection_probe_path); apply_theme() writes the
## theme's light colour/energy/rotation onto it. Empty in fixtures: no-op.
@export var light_path: NodePath = NodePath("")

## Probe cull mask: all 20 render layers minus the disc, the cloud puffs (below the
## disc plane) and rain streaks (formerly DiscMirror.MIRROR_CULL_MASK).
const PROBE_CULL_MASK: int = 0xFFFFF & ~TerritoryOverlay.DISC_LAYER_BIT & ~CloudSea.RENDER_LAYER_BIT & ~RainPresentation.RENDER_LAYER_BIT
const THEME_DIR: String = "res://config/sky_themes"
const DEFAULT_THEME_ID: String = "sunset"
## Bontago-59o.18: SkyboxConfig.theme_name value that means "the day/night cycle"
## (F4's leading Theme entry); not a file under THEME_DIR. _ready() starts the cycle for it.
const CYCLE_THEME_ID: String = "cycle"
## The night palette the cycle fades toward (config/sky_themes/night.tres).
const CYCLE_NIGHT_THEME_ID: String = "night"
## Bontago-59o.18 (C1b): the palette of the cycle's morning and noon (config/sky_themes/
## dawn.tres); SkyPalette fades it into the sunset.tres palette on the setting side.
const CYCLE_DAWN_THEME_ID: String = "dawn"
var _cloud_sea: CloudSea = null
## Bontago-mp0.92: the running cloud wind (calm per-match heading, storm wind, parallax integral).
var _cloud_drift: CloudDriftState = CloudDriftState.new()
## Bontago-mp0.29: the one lighting/weather/cycle state all cloud layers read.
var _cloud_lighting: CloudLighting = CloudLighting.new()
var _birds: DistantBirds = null
## Bontago-adt.3: cosmetic local ambient life, gated by the theme's
## AmbientLifeConfig (perching birds on sunset, fireflies on night) and the
## graphics preset's ambient_life_enabled. field_path / registry_path are wired
## in Main.tscn (same NodePath convention as light_path); empty in fixtures.
@export var field_path: NodePath = NodePath("")
@export var registry_path: NodePath = NodePath("")
var _perching: PerchingBirds = null
var _fireflies: Fireflies = null

## Bontago-xtq.12 (owner: "isn't very reflective, like at all"): Forward+
## never reflects dynamic scene geometry (the placed blocks) without a
## ReflectionProbe or SSR, so the disk's high metallic/low roughness
## (config/TerritoryVisuals.gd) only ever showed the sky's own smooth
## gradient -- reads as a dull tint, not a mirror. NodePath, not a typed Node
## export, matching game/PlayerController.gd's camera_rig_path/ghost_path
## convention elsewhere in this codebase. Wired in Main.tscn to a sibling
## ReflectionProbe over the disc; left empty in every test fixture below
## (most of tests/unit/test_skybox.gd), so configure_reflection_probe() must
## no-op cleanly with nothing wired, the same optionality `environment` above
## already has.
@export var reflection_probe_path: NodePath = NodePath("")
## config/TerritoryVisuals.gd's reflection_probe_* fields; defaulted the same
## way `environment` is optional above, but never actually null in practice
## (every real scene shares config/territory_visuals.tres, same as
## game/Field.gd's own `visuals` export).
@export var visuals: TerritoryVisuals = preload("res://config/territory_visuals.tres")

const SKY_SHADER: Shader = preload("res://shaders/cubemap_sky.gdshader")
## Vertical position of the probe's box center, in meters above the disk
## surface (which sits at world y == 0 -- game/Field.gd positions its
## TerritoryOverlay at `-map_def.disk_height * 0.5`, negligible next to this
## scale). A small local constant, not a TerritoryVisuals field: it is a
## derived placement detail of reflection_probe_height_m right below, not an
## independent tunable a playtester would ever need to move on its own.
const PROBE_GROUND_CLEARANCE_M: float = 4.0

## Bontago-xtq.28 fix round: the cloud deck's box footprint/thickness/height
## are per-theme now (SkyThemeDef.cloud_deck_size_m/cloud_deck_height_m), not
## local constants here -- the previous candidate's centred-at-y40 box (y
## 10..70) enclosed the entire play volume up to NetConfig.pos_max_y (72.0)
## and the gameplay camera itself, which read as a uniform haze with no
## sunset gradient visible. See SkyThemeDef.gd's doc on those two fields for
## the corrected placement (well below the disk, clear of the stacking
## volume).

## The Sky's own material before this node ever touched it (Main.tscn's
## ProceduralSkyMaterial, captured once in _ready()) -- restored whenever
## load_set() falls back, the same moment the box itself is hidden.
var _fallback_sky_material: Material = null
var _cycle_theme: SkyThemeDef = null
var _cycle_day: SkyThemeDef = null
var _cycle_night: SkyThemeDef = null
## Bontago-59o.18 (C1b): `_cycle_day` (sunset.tres) is the cycle's structure and its
## setting-side palette; `_cycle_dawn` (dawn.tres) is its morning/noon palette. Never
## written: SkyPalette.blend() mixes the two into `_cycle_theme` every phase tick.
var _cycle_dawn: SkyThemeDef = null
var _cycle_phase_last: float = -1.0
var _cycle_life_is_night: bool = false
## Bontago-mp0.83: the phase mapping is phase = fposmod(clock / length + offset,
## 1). `_cycle_length_s` is the length it is currently based on and
## `_cycle_phase_offset` is re-based whenever the live length changes (F4), so
## the time of day never jumps. `_cycle_clock_s` is the last shared clock seen.
var _cycle_length_s: float = 1.0
var _cycle_phase_offset: float = 0.0
var _cycle_clock_s: float = 0.0
## Bontago-59o.18: >= 0 freezes the cycle at that phase (the lobby's Sunset / Dawn /
## Night options and F4's Time of day); -1 = running. Derived from replicated
## mode data and shipped SkyThemeDef content, never from the clock.
var _cycle_locked_phase: float = -1.0
## Bontago-59o.18 (C1b variation): the seed of the cycle's exposure / cloud-coverage
## variation (SkyVariation). configure_match_sky() takes it from the replicated
## MatchConfig (the host-rolled sky_variation_seed, else a deterministic rng_seed),
## so every peer draws the same sky and each match its own; a cycle started outside
## a match (F4, boot) keeps the last one.
var _variation_seed: int = SkyVariation.DEFAULT_SEED

## Bontago-1pi.46 (match reset, docs/MATCH_RESET_AUDIT.md G1): what _ready() left
## behind, captured once, so reset_to_launch() can put this long-lived Skybox back
## exactly where a fresh launch starts (the next match's configure_match_sky() then
## sets its own mode). `_launch_theme` is the static theme _ready() applied and
## `_launch_cycle` says whether the launch config ("cycle" theme_name) started the
## cycle; the set fields are SkyboxConfig's textured-set override (F4).
var _launch_captured: bool = false
var _launch_theme: SkyThemeDef = null
var _launch_theme_name: String = ""
var _launch_cycle: bool = false
var _launch_process_mode: Sky.ProcessMode = Sky.PROCESS_MODE_AUTOMATIC
var _launch_set_enabled: bool = false
var _launch_default_set: String = ""


## The host-resolved mode is included in MatchConfig's normal match-start RPC.
## SnapshotSync supplies the shared clock; no peer's wall time enters the sky.
## Bontago-59o.18 (owner decision: Cycle is the default sky): every mode is the
## day/night cycle. CYCLE runs it from SkyThemeDef.cycle_start_phase; Sunset,
## Night, Dawn (and the host's RANDOM roll of those) are the same cycle locked at
## SkyThemeDef.locked_phase_for(id). Nothing here reads a peer-local clock: the
## phase comes from the replicated mode/resolved id (locked) or from
## SnapshotSync's shared clock (running), so host and clients agree.
func configure_match_sky(match_config: MatchConfig) -> void:
	configure_reflection_probe()  # Bontago-1pi.107: the probe box follows the match's disc size
	var locked: float = -1.0
	if not match_config.is_sky_cycle_running():
		var source: SkyThemeDef = load_theme(DEFAULT_THEME_ID)
		if source != null:
			locked = source.locked_phase_for(match_config.locked_sky_id())
	# DECISION (Bontago-59o.18, C1b variation): the replicated match seed drives the sky
	# variation. The host rolls MatchConfig.sky_variation_seed once per match (an
	# unresolved config with no rng_seed shares SkyVariation's default curve).
	_variation_seed = SkyVariation.seed_for(match_config.effective_sky_variation_seed())
	_cloud_drift.reset(_variation_seed)
	# DECISION (Bontago-59o.18): a match opens its sky at shared clock 0:
	# SnapshotSync.begin_match() resets the clock right after this call, and a
	# stale clock read here would make the start phase differ between peers.
	_start_cycle_at(0.0, locked, match_config.sky_start_phase)


## Bontago-1pi.46 (docs/MATCH_RESET_AUDIT.md G1/G2; Events.match_scope_reset runs this
## at every world build and teardown): returns this long-lived Skybox to what a fresh
## launch looks like, so a match never inherits the previous one's sky. That is the
## launch theme and SkyboxConfig.theme_name, the cycle only if the launch config
## started it, no storm / overcast / weather-fog request, hidden textured faces, the
## scene's own Sky process mode and (via apply_theme) the theme's light, fog and
## ambient. The next match's configure_match_sky() then picks its own mode.
## Idempotent and cheap when the sky is already at launch (the build-time call after
## a teardown reset); only a dirty sky pays the cloud / ambient-life rebuild.
## DECISION (Bontago-1pi.46): SkyboxConfig.enabled / default_set (F4's textured-set
## override) revert to their launch values too, like the F4 Theme pick (audit D1).
func reset_to_launch() -> void:
	if not _launch_captured:
		return
	var weather_active: bool = _storm_amount > 0.0 or _overcast_amount > 0.0 \
		or _weather_cloud_overcast > 0.0 or _snow_brighten > 0.0 or _wfog_amount > 0.0
	var at_launch: bool = not _launch_cycle and _cycle_theme == null and theme == _launch_theme \
		and config.theme_name == _launch_theme_name and fallback_active \
		and config.enabled == _launch_set_enabled and config.default_set == _launch_default_set \
		and (environment == null or environment.sky == null or environment.sky.process_mode == _launch_process_mode)
	var stormed: SkyThemeDef = theme if _storm_amount > 0.0 else null
	_clear_weather_state()
	if at_launch and not weather_active:
		return
	if stormed != null and environment != null and environment.sky != null:
		# The storm blend wrote its colours onto the stormed theme's own sky material
		# (a shared resource for a static theme); put that material back before the
		# theme changes, as a storm ending normally would.
		_apply_theme_parameters(stormed)
	_clear_cycle_state()
	theme = _launch_theme
	config.theme_name = _launch_theme_name
	config.enabled = _launch_set_enabled
	config.default_set = _launch_default_set
	if not fallback_active:
		_face_textures.clear()
		fallback_active = true
		_hide_faces()
	_set_sky_process_mode(_launch_process_mode)
	# Re-bases sky material, fog, light, ambient, overcast / weather-fog baselines at
	# amount 0, the cloud sea, birds, perching birds, fireflies and the sun flare.
	apply_theme(theme)
	_prune_overcast_sky_bases()
	if _launch_cycle:
		start_cycle()
	else:
		refresh_reflection_capture()


## The weather requests and the storm blend back to a fresh Skybox's values (amount 0,
## identity scales); apply_theme() / _apply_overcast() then re-derive the visuals.
func _clear_weather_state() -> void:
	_storm_amount = 0.0
	_storm_target = null
	_storm_blend = null
	_storm_blend_base = null
	_overcast_amount = 0.0
	_weather_cloud_overcast = 0.0
	_snow_brighten = 0.0
	_overcast_light_scale = 1.0
	_sun_cloud_scale = 1.0
	_overcast_ambient_scale = 1.0
	_overcast_exposure_scale = 1.0
	_overcast_fog_tint = Color.WHITE
	_overcast_fog_tint_strength = 0.0
	_wfog_amount = 0.0
	_wfog_max_opacity = 0.0
	_wfog_depth_begin_m = 0.0
	_wfog_depth_end_m = 0.0
	_wfog_tint = Color.WHITE
	_wfog_tint_strength = 0.0
	_wfog_sky_affect_add = 0.0
	_wfog_aerial_add = 0.0


## No cycle of any kind (running or locked) and no pending phase state: what a Skybox
## that never started one holds.
func _clear_cycle_state() -> void:
	_cycle_theme = null
	_sun_direction = Vector3.ZERO
	_daylight = 1.0
	_cycle_day = null
	_cycle_night = null
	_cycle_dawn = null
	_cycle_phase_last = -1.0
	_cycle_life_is_night = false
	_cycle_length_s = 1.0
	_cycle_phase_offset = 0.0
	_cycle_clock_s = 0.0
	_cycle_locked_phase = -1.0
	_variation_seed = SkyVariation.DEFAULT_SEED
	_cloud_drift.reset(_variation_seed)


## Drops the baseline-exposure entries of sky materials that are no longer the live
## one (each cycle start duplicates the sky material and would otherwise stay
## referenced here for the rest of the session). Call after the exposure has been
## written back at amount 0.
func _prune_overcast_sky_bases() -> void:
	var active: Material = environment.sky.sky_material if environment != null and environment.sky != null else null
	for key: Variant in _overcast_sky_bases.keys():
		if key != active:
			_overcast_sky_bases.erase(key)


func _process(delta: float) -> void:
	_step_cloud_drift(delta)
	if _cycle_theme == null:
		return
	update_cycle_clock(SnapshotSync.sky_cycle_seconds())


## Advances the cycle to the shared clock `clock_seconds` (SnapshotSync's host
## clock in a match; tests and probes pass their own). A cycle-length edit that
## landed since the last call is folded in first, keeping the phase continuous.
## A locked cycle ignores the clock for its phase (it only remembers it, so an
## unlock continues from the locked phase) and rewrites nothing.
func update_cycle_clock(clock_seconds: float) -> void:
	if _cycle_theme == null:
		return
	_cycle_clock_s = clock_seconds
	_sync_cycle_length()
	set_cycle_phase(cycle_phase_at(clock_seconds))


## The cycle phase (0..1, 0 = dawn, 0.25 = noon) at shared clock `clock_seconds`
## under the length and offset currently in force; the locked phase while locked.
func cycle_phase_at(clock_seconds: float) -> float:
	if _cycle_locked_phase >= 0.0:
		return _cycle_locked_phase
	return fposmod(clock_seconds / _cycle_length_s + _cycle_phase_offset, 1.0)


## Live cycle length (F4 Sky tab, Bontago-mp0.83): applies `seconds` to the
## running cycle and to the day theme the next match copies from. The time of
## day does not move; only its speed changes from now on (a locked cycle keeps
## its phase and runs at the new length once unlocked). Local dev tuning: the
## length is not replicated, shipped content gives every peer the same default.
func set_cycle_length_seconds(seconds: float) -> void:
	if _cycle_theme == null:
		return
	var length: float = maxf(seconds, 1.0)
	_cycle_theme.cycle_length_seconds = length
	if _cycle_day != null:
		_cycle_day.cycle_length_seconds = length
	_sync_cycle_length()


## Seconds per full cycle the running cycle uses; 0 outside CYCLE mode.
func cycle_length_seconds() -> float:
	return _cycle_length_s if _cycle_theme != null else 0.0


## --- Bontago-59o.18 cycle-default API (docs/SKY_CYCLE_DEFAULT_PLAN.md s3) -----

## Starts the day/night cycle now (F4's Theme "cycle" entry, boot theme_name
## "cycle"; configure_match_sky() uses the same builder at match start).
## `lock_phase` >= 0 freezes the sky at that phase (0 dawn, 0.25 noon, 0.5
## sunset, 0.75 midnight); < 0 runs the cycle. `start_phase` >= 0 is the phase a
## running cycle shows at the shared clock now (SkyThemeDef.cycle_start_phase
## when < 0); it is ignored while locked.
func start_cycle(lock_phase: float = -1.0, start_phase: float = -1.0) -> void:
	_start_cycle_at(SnapshotSync.sky_cycle_seconds(), lock_phase, start_phase)


## Locks the active cycle at `phase` (0..1) or, when `phase` < 0, unlocks it
## so it runs again from the locked phase (continuous, no jump). A lock writes
## the sky once and stops the incremental radiance updates; an unlock resumes
## them. No-op while no cycle is active (call start_cycle() first).
func set_locked_phase(phase: float) -> void:
	if _cycle_theme == null:
		return
	if phase < 0.0:
		if _cycle_locked_phase < 0.0:
			return
		var held: float = _cycle_locked_phase
		_cycle_locked_phase = -1.0
		# DECISION: the running phase continues from the held phase at the last
		# shared clock seen, so unlocking never jumps the time of day.
		_cycle_phase_offset = held - _cycle_clock_s / _cycle_length_s
		_set_sky_process_mode(Sky.PROCESS_MODE_INCREMENTAL)
		return
	_cycle_locked_phase = fposmod(phase, 1.0)
	set_cycle_phase(_cycle_locked_phase)
	_set_sky_process_mode(Sky.PROCESS_MODE_QUALITY)
	refresh_reflection_capture()


## The phase the cycle is locked at, or -1.0 while it is running (or not
## active).
func locked_phase() -> float:
	return _cycle_locked_phase if _cycle_theme != null else -1.0


## True while the day/night cycle (running or locked) drives the sky.
func is_cycle_active() -> bool:
	return _cycle_theme != null


## The cycle phase (0..1) last applied to the sky; -1.0 when the cycle is not
## active.
func current_cycle_phase() -> float:
	return _cycle_phase_last if _cycle_theme != null else -1.0


## The seed the cycle's exposure / cloud-coverage variation currently draws from
## (Bontago-59o.18, C1b follow-up): what configure_match_sky() took from the match
## config, or SkyVariation.DEFAULT_SEED outside a match.
func variation_seed() -> int:
	return _variation_seed


## Re-copies the F4-edited source themes into the live cycle duplicate (F4
## edits during a cycle match must not swap in the static material): the day
## source's fields land on the live duplicate (its own materials are kept), the
## sky/puffs/ambient life are rebuilt from it and the current phase is re-applied,
## so a lock or a running clock is untouched. No-op while no cycle is active.
func refresh_cycle_sources() -> void:
	if _cycle_theme == null or _cycle_day == null:
		return
	for property: Dictionary in _cycle_day.get_property_list():
		var usage: int = int(property["usage"])
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0 or (usage & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var property_name: StringName = StringName(property["name"])
		if property_name == &"sky_material" or property_name == &"cloud_puff_material":
			continue
		var value: Variant = _cycle_day.get(property_name)
		if value is Resource:
			value = (value as Resource).duplicate(true)
		_cycle_theme.set(property_name, value)
	_cycle_theme.sky_look_procedural = true
	_cycle_theme.procedural_sea_mix = 1.0
	apply_theme(_cycle_theme)
	# apply_theme() rebuilt the puffs and ambient life from the day config:
	# re-run the cycle writers and the night swap decision for the current phase.
	_reapply_cycle_phase(true)


## Forces the cycle writers to run again for the phase last applied, running or
## locked, even though it has not changed (set_cycle_phase() returns early on an
## unchanged phase). Whatever rebuilds the cloud puffs / ambient life from
## the day-config `theme` (apply_theme(), the graphics-preset handler, so the
## settings menu and the adaptive governor mid-match) resets their cycle palette,
## light direction and ambient life; a running cycle heals on its next frame
## but a locked one never would, so those callers re-apply here.
## `ambient_life_rebuilt` also re-runs the birds / perching / fireflies night swap
## decision (the rebuild reconfigured them from the day config); the storm-end
## restore does not rebuild them and passes false. No-op while no cycle is
## active or before its first phase write.
func _reapply_cycle_phase(ambient_life_rebuilt: bool) -> void:
	if _cycle_theme == null or environment == null or _cycle_phase_last < 0.0:
		return
	var phase: float = _cycle_phase_last
	if ambient_life_rebuilt:
		_cycle_life_is_night = false
	_cycle_phase_last = -1.0
	set_cycle_phase(phase)


## Builds the cycle (the one place that does) as of shared clock `clock_seconds`.
## Duplicates the authored sunset (day structure and palette) resource once; each
## frame afterwards changes only shader uniforms and Environment/light properties.
func _start_cycle_at(clock_seconds: float, lock_phase: float, start_phase: float) -> void:
	_cycle_theme = null
	_cycle_day = load_theme(DEFAULT_THEME_ID)
	_cycle_night = load_theme(CYCLE_NIGHT_THEME_ID)
	if _cycle_day == null or _cycle_night == null:
		return
	# DECISION (Bontago-59o.18, C1b): a build without dawn.tres degrades to the sunset
	# palette all day (the blend then has the same palette at both ends).
	_cycle_dawn = load_theme(CYCLE_DAWN_THEME_ID)
	if _cycle_dawn == null:
		_cycle_dawn = _cycle_day
	# DECISION (Bontago-mp0.13): duplicate the authored resources once. Each
	# frame changes only shader uniforms and Environment/light properties.
	_cycle_theme = _cycle_day.duplicate(true) as SkyThemeDef
	_cycle_theme.sky_material = _cycle_day.sky_material.duplicate() as Material
	_cycle_theme.cloud_puff_material = _cycle_day.cloud_puff_material.duplicate() as Material
	_cycle_theme.sky_look_procedural = true
	_cycle_theme.procedural_sea_mix = 1.0
	theme = _cycle_theme
	apply_theme(theme)
	_cycle_phase_last = -1.0
	# apply_theme() configured the ambient life from the day config.
	_cycle_life_is_night = false
	_cycle_length_s = maxf(_cycle_theme.cycle_length_seconds, 1.0)
	_cycle_locked_phase = fposmod(lock_phase, 1.0) if lock_phase >= 0.0 else -1.0
	var opening: float = start_phase if start_phase >= 0.0 else _cycle_theme.cycle_start_phase
	# DECISION (Bontago-59o.18): the running phase is fposmod(clock / length +
	# offset, 1); the offset puts `opening` at the start clock, so every peer
	# opens identically and the shared clock alone then carries them forward.
	_cycle_phase_offset = opening - clock_seconds / _cycle_length_s
	_cycle_clock_s = clock_seconds
	set_cycle_phase(cycle_phase_at(clock_seconds))
	if _cycle_locked_phase >= 0.0:
		# DECISION (Bontago-59o.18): a locked sky is written once, so the radiance
		# map is built to full quality after that write and then left alone
		# (default matches must not pay incremental sky updates every frame).
		_set_sky_process_mode(Sky.PROCESS_MODE_QUALITY)
		refresh_reflection_capture()
	else:
		_set_sky_process_mode(Sky.PROCESS_MODE_INCREMENTAL)


func _set_sky_process_mode(mode: Sky.ProcessMode) -> void:
	if environment != null and environment.sky != null:
		environment.sky.process_mode = mode


## DECISION (Bontago-mp0.83): when the authored length changes mid-match, the
## offset is chosen so the phase at the last clock equals the old phase (no
## jump in the time of day); only the rate changes afterwards.
func _sync_cycle_length() -> void:
	var length: float = maxf(_cycle_theme.cycle_length_seconds, 1.0)
	if is_equal_approx(length, _cycle_length_s):
		return
	if _cycle_locked_phase >= 0.0:
		# Locked: the phase is fixed and set_locked_phase(-1) re-bases the offset
		# on unlock, so only the length the running cycle will use changes.
		_cycle_length_s = length
		return
	var phase: float = cycle_phase_at(_cycle_clock_s)
	_cycle_length_s = length
	_cycle_phase_offset = phase - _cycle_clock_s / length


## Public phase seam also used by deterministic tests and visual probes.
func set_cycle_phase(phase: float) -> void:
	if _cycle_theme == null or environment == null:
		return
	phase = fposmod(phase, 1.0)
	if is_equal_approx(phase, _cycle_phase_last):
		return
	_cycle_phase_last = phase
	# Bontago-59o.18 (C1b): the day palette first (dawn by day, sunset on the setting
	# side), written onto the live theme and its materials; everything below mixes that
	# toward the night palette, so `_cycle_theme`'s palette fields are day values here.
	SkyPalette.blend(_cycle_theme, _cycle_dawn, _cycle_day,
		SkyPalette.dusk_weight(phase, _cycle_theme.cycle_dusk_weight_phases))
	var daylight: float = smoothstep(-_cycle_theme.cycle_twilight_width, _cycle_theme.cycle_twilight_width, sin(TAU * phase))
	var night: float = 1.0 - daylight
	var sun_base: Vector3 = (_cycle_day.sky_material as ShaderMaterial).get_shader_parameter(&"sun_direction") as Vector3
	var horizontal: Vector3 = Vector3(sun_base.x, 0.0, sun_base.z).normalized()
	var azimuth: float = TAU * phase
	var elevation: float = deg_to_rad(_cycle_theme.cycle_sun_peak_degrees) * sin(azimuth)
	var direction: Vector3 = Vector3(
		horizontal.x * cos(azimuth) - horizontal.z * sin(azimuth), 0.0,
		horizontal.x * sin(azimuth) + horizontal.z * cos(azimuth)) * cos(elevation)
	direction.y = sin(elevation)
	var material: ShaderMaterial = _cycle_theme.sky_material as ShaderMaterial
	material.set_shader_parameter(&"sun_direction", direction)
	_apply_procedural_params(material, _cycle_theme)
	_apply_cycle_variation(material, phase)
	material.set_shader_parameter(&"cycle_night_mix", night)
	material.set_shader_parameter(&"cycle_night_zenith", _cycle_night.sky_top_color)
	material.set_shader_parameter(&"cycle_night_horizon", _cycle_night.sky_horizon_color)
	material.set_shader_parameter(&"cycle_night_below", _cycle_night.ground_bottom_color)
	material.set_shader_parameter(&"cycle_star_brightness", _cycle_theme.cycle_star_brightness)
	material.set_shader_parameter(&"cycle_star_cells", _cycle_theme.cycle_star_cells)
	material.set_shader_parameter(&"cycle_star_threshold", _cycle_theme.cycle_star_threshold)
	material.set_shader_parameter(&"cycle_star_radius", _cycle_theme.cycle_star_radius)
	material.set_shader_parameter(&"cycle_star_horizon_fade", _cycle_theme.cycle_star_horizon_fade)
	_cycle_theme.fog_color = _cycle_theme.fog_color.lerp(_cycle_night.fog_color, night)
	_cycle_theme.fog_density = lerpf(_cycle_theme.fog_density, _cycle_night.fog_density, night)
	_cycle_theme.volumetric_fog_density = lerpf(_cycle_theme.volumetric_fog_density, _cycle_night.volumetric_fog_density, night)
	_cycle_theme.volumetric_fog_albedo = _cycle_theme.volumetric_fog_albedo.lerp(_cycle_night.volumetric_fog_albedo, night)
	_cycle_theme.ambient_energy = lerpf(_cycle_theme.ambient_energy, _cycle_night.ambient_energy, night)
	# Bontago-mp0.127: stronger sun, weaker sky ambient with the sun high (identity at the
	# horizon and at night), so lit vs shadowed faces read clearly by day and soften at dusk.
	_cycle_theme.ambient_energy *= SunContrast.ambient_scale(direction.y, _cycle_theme.cycle_day_ambient_scale,
		_cycle_theme.cycle_sun_contrast_full_sin)
	_sun_direction = direction
	_daylight = daylight
	# DECISION (Bontago-mp0.13): one key light serves sun by day and a dim
	# authored night direction after sunset. Both fade to zero at the horizon.
	var sun_key: float = smoothstep(0.0, 0.2, direction.y)
	var moon_key: float = smoothstep(0.0, 0.2, -direction.y)
	_cycle_theme.light_energy = _cycle_theme.light_energy * sun_key * SunContrast.light_scale(direction.y,
		_cycle_theme.cycle_sun_energy_gain, _cycle_theme.cycle_sun_contrast_full_sin) 		+ _cycle_night.light_energy * 0.2 * moon_key
	if direction.y < 0.0:
		_cycle_theme.light_color = _cycle_night.light_color
	environment.volumetric_fog_density = _cycle_theme.volumetric_fog_density
	environment.volumetric_fog_albedo = _cycle_theme.volumetric_fog_albedo
	var light: DirectionalLight3D = get_node_or_null(light_path) as DirectionalLight3D if not light_path.is_empty() else null
	if light != null:
		light.light_color = _cycle_theme.light_color
		if direction.y >= 0.0:
			light.global_basis = Basis.looking_at(-direction, Vector3.UP)
		else:
			light.rotation_degrees = _cycle_night.light_rotation_deg
	_apply_overcast(_cycle_theme)
	if _fog_volume != null:
		var fog_material: FogMaterial = _fog_volume.material as FogMaterial
		if fog_material != null:
			fog_material.density = _cycle_theme.fog_density
	# DECISION (Bontago-mp0.13): stagger the ambient-life swap so its
	# discrete configure calls happen in the dark, with hysteresis at twilight.
	var life_is_night: bool = night > 0.85 if not _cycle_life_is_night else night > 0.15
	if life_is_night != _cycle_life_is_night:
		_cycle_life_is_night = life_is_night
		var preset: GraphicsPreset = Settings.current_graphics_preset()
		var life_enabled: bool = preset == null or preset.ambient_life_enabled
		if _birds != null:
			_birds.configure(_cycle_day, not life_is_night and (preset == null or preset.birds_enabled))
		if _perching != null:
			_perching.configure(_cycle_night.ambient_life if life_is_night else _cycle_day.ambient_life, life_enabled)
		if _fireflies != null:
			_fireflies.configure(_cycle_night.ambient_life if life_is_night else _cycle_day.ambient_life,
				life_enabled, _disc_radius_for_ambient_life())
	if _cloud_sea != null:
		# The live theme carries the blended day palette (its puff material, sky cloud
		# colours and proc_sea colours), not the sunset source alone.
		_cloud_sea.set_cycle_appearance(_cycle_theme, _cycle_night, night, direction)
	for node: Node in get_tree().get_nodes_in_group(SunFlare.GROUP):
		var flare: SunFlare = node as SunFlare
		if flare != null:
			flare.set_cycle_sun(direction, daylight)
	# Bontago-mp0.19: the rewrites above are un-stormed; compose the storm blend
	# on top so a running cycle never overwrites the storm sky.
	if _storm_amount > 0.0:
		_apply_storm_blend()
	_publish_cloud_lighting()


## Bontago-59o.18 (C1b variation): writes the cycle's sky exposure, cloud coverage and
## cloud-floor (sea) coverage for `phase` onto the live sky material and the cloud
## puffs. The values are SkyVariation's pure function of (match seed, phase) inside the
## SkyThemeDef.variation_* ranges, or, with variation off, the day theme's own fixed
## uniforms. The exposure is recorded as the weather overcast's baseline
## (_overcast_sky_bases), so _apply_overcast() scales it from today's value instead
## of resetting it; the puffs take the same baseline (not the overcast scale: the
## weather dims them through CloudLighting) and the same sea coverage, so their far
## fade targets exactly the sky drawn behind them.
func _apply_cycle_variation(material: ShaderMaterial, phase: float) -> void:
	var exposure: float = NAN
	var cloud_coverage: float = NAN
	var sea_coverage: float = NAN
	if _cycle_theme.variation_enabled:
		exposure = SkyVariation.exposure_at(_cycle_theme, phase, _variation_seed)
		cloud_coverage = SkyVariation.cloud_coverage_at(_cycle_theme, phase, _variation_seed)
		sea_coverage = SkyVariation.sea_coverage_at(_cycle_theme, phase, _variation_seed)
	else:
		var source: ShaderMaterial = _cycle_day.sky_material as ShaderMaterial
		exposure = _fixed_uniform(source, SKY_EXPOSURE_UNIFORM)
		cloud_coverage = _fixed_uniform(source, CLOUD_COVERAGE_UNIFORM)
		sea_coverage = _fixed_uniform(source, SEA_COVERAGE_UNIFORM)
	var puffs: ShaderMaterial = _cloud_sea.puff_material() if _cloud_sea != null else null
	if not is_nan(exposure):
		# set_cycle_phase() runs _apply_overcast() next, which writes baseline x overcast.
		_overcast_sky_bases[material] = exposure
		if puffs != null:
			puffs.set_shader_parameter(SKY_EXPOSURE_UNIFORM, exposure)
	if not is_nan(cloud_coverage):
		material.set_shader_parameter(CLOUD_COVERAGE_UNIFORM, cloud_coverage)
	if not is_nan(sea_coverage):
		material.set_shader_parameter(SEA_COVERAGE_UNIFORM, sea_coverage)
		if puffs != null:
			puffs.set_shader_parameter(SEA_COVERAGE_UNIFORM, sea_coverage)


## The float `uniform` of `material`, or NAN when the shader leaves it unset.
func _fixed_uniform(material: ShaderMaterial, uniform: StringName) -> float:
	if material == null:
		return NAN
	var value: Variant = material.get_shader_parameter(uniform)
	return float(value) if value is float else NAN


## True whenever no textured box is showing (initial state, a missing
## set/face, or config.enabled == false) -- the existing ProceduralSkyMaterial
## is what's visible in every one of those cases. Read by tests and by a
## manual tester checking print() output.
var fallback_active: bool = true

var _face_textures: Dictionary = {}
var _face_meshes: Dictionary = {}

## Bontago-xtq.28: the FogVolume _spawn_fog_volume() created, or null when
## `theme` was unset in _ready() (see that method's own doc).
var _fog_volume: FogVolume = null

## Bontago-xtq.12 step 2 (F4 tuning panel live-apply, same idiom
## game/CameraRig.gd's own TUNING_GROUP doc explains): every Skybox adds
## itself to this group in _ready() so ui/TuningPanel.gd's
## refresh_territory_visuals_live() can push a live SSR/reflection-probe edit
## onto whichever Skybox is actually in the tree, the same way it already
## reaches every live CameraRig/Block, without needing its own reference to
## this node wired first.
const TUNING_GROUP: StringName = &"tuning_skybox"
## Weather overcast (Bontago-22y.5) finds the Skybox through this group.
const OVERCAST_GROUP: StringName = &"weather_skybox"
## Weather overcast, presentation only. DECISION (Skybox.gd): the Skybox OWNS
## every value the overcast touches. set_overcast() only stores the request;
## _apply_overcast() re-derives the light, ambient, sky exposure and fog tint
## from the current theme's baseline, and apply_theme() ends with it, so a live
## theme switch during rain re-bases on the new theme and amount 0 is exactly
## the theme's own values (no stale multipliers). Weather code never writes the
## Environment or the light directly.
var _overcast_amount: float = 0.0
var _weather_cloud_overcast: float = 0.0
## Bontago-mp0.128: snow brightening 0..1 (CloudCeiling); the gain/lift come from ceiling.tres.
var _snow_brighten: float = 0.0
## Bontago-mp0.19 storm sky blend state (see set_storm_sky()).
const MOON_DISC_TEXTURE: Texture2D = preload("res://assets/sky/moon_v1/moon_disc.png")
const MOON_HALO_TEXTURE: Texture2D = preload("res://assets/sky/moon_v1/moon_halo.png")
const CEILING_TUNING: WeatherCeilingTuning = preload("res://config/weather/ceiling.tres")
var _storm_amount: float = 0.0
## Bontago-mp0.129: aurora write cache (see _apply_aurora()). `_aurora_preset_on` is the graphics
## preset's aurora_enabled, kept from graphics_preset_changed instead of looked up every call;
## `_aurora_sky` is the sky material the uniforms were last written to, `_aurora_visibility_written`
## the visibility on it (-1 = nothing written yet) and `_aurora_look_written` its look values.
var _aurora_preset_on: bool = true
var _aurora_sky: ShaderMaterial = null
var _aurora_visibility_written: float = -1.0
var _aurora_look_written: Array = []
var _storm_target: SkyThemeDef = null
var _storm_blend: SkyThemeDef = null
var _storm_blend_base: SkyThemeDef = null
var _overcast_light_scale: float = 1.0
## Bontago-mp0.127: direct-sun scale from clouds covering the sun (vfx/CloudShadows.gd),
## 1 = clear. Part of the one light-energy writer, _apply_overcast().
var _sun_cloud_scale: float = 1.0
## Bontago-mp0.127: the cycle's last unit sun direction (ZERO before any cycle phase) and
## daylight 0..1, read by vfx/CloudShadows.gd.
var _sun_direction: Vector3 = Vector3.ZERO
var _daylight: float = 1.0
var _overcast_ambient_scale: float = 1.0
var _overcast_exposure_scale: float = 1.0
var _overcast_fog_tint: Color = Color.WHITE
var _overcast_fog_tint_strength: float = 0.0
var _overcast_exposure_base: float = -1.0
var _overcast_theme: SkyThemeDef = null
## Sky shaders with an `exposure` uniform (sunset_clouds, night_sky): the real
## dimming lever, since Environment.background_energy_multiplier barely reads on
## them. material -> its baseline exposure, so amount 0 restores exactly.
const SKY_EXPOSURE_UNIFORM: StringName = &"exposure"
## The other sky-shader uniforms the cycle variation drives (_apply_cycle_variation).
const CLOUD_COVERAGE_UNIFORM: StringName = &"cloud_coverage"
const SEA_COVERAGE_UNIFORM: StringName = &"proc_sea_coverage"
var _overcast_sky_bases: Dictionary = {}
## Weather fog (Bontago-470.3), presentation only. DECISION (Skybox.gd): same
## ownership pattern as the overcast above -- set_weather_fog() stores the
## request and _apply_overcast() (which apply_theme() ends with) re-derives the
## Environment's fog (DEPTH mode from a begin distance) and a further fog tint;
## the fog mode/range baseline is the Environment's own, captured lazily. Amount 0 is
## exactly the theme (and the untouched height fog) again, and a live theme
## switch in fog re-bases on the new theme.
var _wfog_amount: float = 0.0
var _wfog_max_opacity: float = 0.0
var _wfog_depth_begin_m: float = 0.0
var _wfog_depth_end_m: float = 0.0
var _wfog_tint: Color = Color.WHITE
var _wfog_tint_strength: float = 0.0
var _wfog_sky_affect_add: float = 0.0
var _wfog_aerial_add: float = 0.0
var _wfog_base_captured: bool = false
var _wfog_base_mode: int = 0
var _wfog_base_begin: float = 0.0
var _wfog_base_end: float = 0.0
var _wfog_base_curve: float = 1.0

## Bontago-xtq.22: the id apply_set()/list_available_sets() use for "no
## textured set -- keep the procedural sky", i.e. the empty string. Matches
## config.default_set's own type (String) so ui/TuningPanel.gd's dropdown can
## carry it as one more item alongside every real set name, with no separate
## sentinel enum/type to keep in sync between the two files.
const PROCEDURAL_SET_ID: String = ""


func _ready() -> void:
	add_to_group(TUNING_GROUP)
	add_to_group(OVERCAST_GROUP)
	if environment != null and environment.sky != null:
		_fallback_sky_material = environment.sky.sky_material
		_launch_process_mode = environment.sky.process_mode
	for face_name: String in config.face_names:
		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		mesh_instance.name = face_name.capitalize()
		mesh_instance.visible = false
		# The box is static and much larger than the play field (see class
		# doc), so there is nothing worth frustum-culling per frame against a
		# camera that is always deep inside it.
		mesh_instance.extra_cull_margin = config.box_half_extent
		add_child(mesh_instance)
		_face_meshes[face_name] = mesh_instance
	configure_reflection_probe()
	configure_ssr()
	# Bontago-adt.1: SkyboxConfig.theme_name picks a non-default theme.
	if config.theme_name != "" and config.theme_name != DEFAULT_THEME_ID and config.theme_name != CYCLE_THEME_ID:
		var chosen: SkyThemeDef = load_theme(config.theme_name)
		if chosen != null:
			theme = chosen
	_launch_theme = theme
	_launch_theme_name = config.theme_name
	_launch_cycle = config.theme_name == CYCLE_THEME_ID
	_launch_set_enabled = config.enabled
	_launch_default_set = config.default_set
	_launch_captured = true
	_cloud_sea = CloudSea.new()
	_cloud_sea.name = "CloudSea"
	_cloud_sea.lighting = _cloud_lighting
	_cloud_sea.upper_tuning = CEILING_TUNING
	add_child(_cloud_sea)
	_birds = DistantBirds.new()
	_birds.name = "DistantBirds"
	add_child(_birds)
	_perching = PerchingBirds.new()
	_perching.name = "PerchingBirds"
	add_child(_perching)
	_fireflies = Fireflies.new()
	_fireflies.name = "Fireflies"
	add_child(_fireflies)
	var field_node: Field = get_node_or_null(field_path) as Field if not field_path.is_empty() else null
	var registry_node: BlockRegistry = get_node_or_null(registry_path) as BlockRegistry if not registry_path.is_empty() else null
	_perching.bind_scene(field_node, registry_node)
	_fireflies.bind_field(field_node)
	var boot_preset: GraphicsPreset = Settings.current_graphics_preset()
	_aurora_preset_on = boot_preset == null or boot_preset.aurora_enabled
	apply_theme(theme)
	_spawn_fog_volume()
	_apply_fog_volume_visibility(boot_preset)
	Settings.graphics_preset_changed.connect(_on_graphics_preset_changed)
	Events.match_scope_reset.connect(reset_to_launch)
	# Bontago-59o.18: F4's persisted "cycle" Theme entry runs the cycle from boot
	# (after the cloud sea, fog volume and ambient life it drives exist).
	if config.theme_name == CYCLE_THEME_ID:
		start_cycle()


func _exit_tree() -> void:
	if Settings.graphics_preset_changed.is_connected(_on_graphics_preset_changed):
		Settings.graphics_preset_changed.disconnect(_on_graphics_preset_changed)
	if Events.match_scope_reset.is_connected(reset_to_launch):
		Events.match_scope_reset.disconnect(reset_to_launch)


## Public re-apply seam ui/TuningPanel.gd calls (via TUNING_GROUP above)
## whenever the owner edits a reflection tunable live in the F4 panel --
## configure_reflection_probe()/configure_ssr() otherwise only ever run once,
## at boot. Also the one place tools/screenshot_xtq11_disk_opaque.gd's
## `--mirror-mode=`/`--reflection-mode=` overrides re-apply their duplicated
## TerritoryVisuals after swapping `visuals` out from under an already-ready
## Skybox.
func refresh_from_visuals() -> void:
	configure_reflection_probe()
	configure_ssr()


## Bontago-xtq.12 step 2 (owner: "the disc isn't very reflective, like at
## all?" -- step 1's ReflectionProbe alone only ever showed a faint, blurred
## sky gradient): Forward+'s screen-space reflections trace the actual
## rendered depth/color buffer per pixel, so a block that is currently on
## screen shows up in the disk's reflection at roughly its true screen
## position -- the probe's own blurred, periodically-snapshotted cubemap
## cannot do that on its own. Written onto the wired Environment directly
## (not the ReflectionProbe node): SSR is a WorldEnvironment-level effect,
## the same as the sky/ambient the class doc's Bontago-xtq.8 DECISION
## explains. A no-op when no `environment` was wired or `visuals` is unset,
## matching configure_reflection_probe()'s own contract.
func configure_ssr() -> void:
	if visuals == null or environment == null:
		return
	environment.ssr_enabled = visuals.ssr_enabled
	environment.ssr_max_steps = visuals.ssr_max_steps
	environment.ssr_fade_in = visuals.ssr_fade_in
	environment.ssr_fade_out = visuals.ssr_fade_out
	environment.ssr_depth_tolerance = visuals.ssr_depth_tolerance


## Bontago-xtq.12: sizes and enables the ReflectionProbe wired via
## reflection_probe_path (Main.tscn), once at boot -- not per-match, unlike
## TerritoryOverlay's own configure() (see reflection_probe_margin_m's
## DECISION comment in config/TerritoryVisuals.gd for why). A no-op when
## nothing is wired (path empty or the node doesn't resolve) or `visuals` is
## unset, so every existing fixture in tests/unit/test_skybox.gd -- none of
## which wire this -- is unaffected.
func configure_reflection_probe() -> void:
	if visuals == null or reflection_probe_path.is_empty():
		return
	var probe: ReflectionProbe = get_node_or_null(reflection_probe_path) as ReflectionProbe
	if probe == null:
		return
	probe.visible = visuals.reflection_probe_enabled
	probe.update_mode = (
		ReflectionProbe.UPDATE_ALWAYS if visuals.reflection_probe_update_always
		else ReflectionProbe.UPDATE_ONCE
	)
	var half_width: float = _largest_disc_radius() + visuals.reflection_probe_margin_m
	var height: float = visuals.reflection_probe_height_m
	probe.size = Vector3(half_width * 2.0, height, half_width * 2.0)
	probe.position = Vector3(0.0, height * 0.5 - PROBE_GROUND_CLEARANCE_M, 0.0)
	# Box-corrected reflections: the disk is a large flat static surface, so
	# aligning reflected rays to the probe's own box (rather than treating it
	# as infinitely far away, ReflectionProbe's default) keeps the mirrored
	# blocks positioned correctly instead of drifting as the camera orbits.
	probe.box_projection = true
	# DECISION: exclude the disc (TerritoryOverlay.DISC_LAYER_BIT) and the cloud/rain
	# layers from the probe so it never captures the disc's own reflection.
	probe.cull_mask = PROBE_CULL_MASK


## Called once per match/scene start (game/Main.gd) with the map's chosen set
## (config/MapDef.gd's skybox_set). `root_override` lets tests point this at a
## temp directory instead of the real asset root. Returns true and shows the
## textured box on success; returns false, prints one info line, and leaves
## the box hidden (so the ProceduralSkyMaterial fallback shows through) on
## any failure -- never a Godot error for the ordinary "assets not installed"
## case, since both existence checks below run before any file is opened.
##
## Face lookup is exact-case (FileAccess.file_exists() against
## config.face_names, which are lowercase): tools/install_original_assets.ps1
## (owned by another package) already lowercases every face file it copies,
## so this never needs to special-case the original install's mixed-case
## source names itself (see tests/unit/test_skybox.gd's DECISION on why that
## is not separately tested here).
func load_set(set_name: String, root_override: String = "") -> bool:
	_face_textures.clear()
	if not config.enabled:
		fallback_active = true
		_hide_faces()
		return false

	var root: String = root_override if root_override != "" else _resolve_asset_root()
	var set_dir: String = root.path_join(set_name)
	if not DirAccess.dir_exists_absolute(set_dir):
		fallback_active = true
		_hide_faces()
		print("Skybox: set '%s' not found at %s -- using procedural sky" % [set_name, set_dir])
		return false

	for face_name: String in config.face_names:
		var file_path: String = set_dir.path_join(face_name + ".jpg")
		if not FileAccess.file_exists(file_path):
			fallback_active = true
			_hide_faces()
			print("Skybox: face '%s' missing for set '%s' at %s -- using procedural sky" % [
				face_name, set_name, file_path,
			])
			return false
		# Load through an absolute filesystem path: Image.load_from_file on a
		# res:// path prints an engine warning about bypassing the import
		# pipeline (GUT counts it as an error) and the editor would import the
		# gitignored jpgs; assets/original carries a .gdignore for the same
		# reason (tools/install_original_assets.ps1 writes it).
		var image: Image = Image.load_from_file(ProjectSettings.globalize_path(file_path))
		if image == null:
			fallback_active = true
			_hide_faces()
			print("Skybox: face '%s' for set '%s' failed to decode -- using procedural sky" % [
				face_name, set_name,
			])
			return false
		_face_textures[face_name] = ImageTexture.create_from_image(image)

	fallback_active = false
	_build_faces()
	return true


## Test/inspection seam: the ImageTexture load_set() produced for one face,
## or null if load_set() has not succeeded for that face (fallback or not yet
## called).
func get_face_texture(face_name: String) -> ImageTexture:
	return _face_textures.get(face_name) as ImageTexture


## Static (Bontago-xtq.22): list_available_sets() below calls this from a
## static context too (building ui/TuningPanel.gd's dropdown does not need a
## live Skybox instance), and the body never read `self` to begin with.
static func _resolve_asset_root() -> String:
	if OS.has_feature("editor"):
		return "res://assets/original/textures"
	return OS.get_executable_path().get_base_dir().path_join("assets/original/textures")


## Bontago-xtq.22 (owner: "add an option to F4 to change the skybox"): every
## subfolder of the resolved asset root (or `root_override`, the same test
## seam load_set() already has), sorted -- the F4 dropdown's own list of real
## sets, built by ui/TuningPanel.gd alongside its fixed "Procedural / none"
## entry. Returns an empty array (never an error) when the root itself does
## not exist -- the ordinary "original assets not installed" case (CLAUDE.md/
## docs/AGENT_WORKFLOW.md: this repo never ships the third-party textures),
## so a CI machine's dropdown just shows the procedural entry alone.
static func list_available_sets(root_override: String = "") -> PackedStringArray:
	var root: String = root_override if root_override != "" else _resolve_asset_root()
	var sets: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return sets
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry != "." and entry != ".." and dir.current_is_dir():
			sets.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	sets.sort()
	return sets


## Bontago-xtq.22 (owner: disc reflectivity is "hard to judge with that
## texture -- add an option to F4 to change the skybox"): the live-switch
## entry point ui/TuningPanel.gd's new Skybox dropdown calls on every Skybox
## in TUNING_GROUP. `set_name == PROCEDURAL_SET_ID` (the dropdown's
## "Procedural / none" item) turns the textured box/sky off by setting
## `config.enabled = false` -- load_set()'s own first check already falls
## back to the existing ProceduralSkyMaterial whenever that flag is off, so
## this needs no separate fallback path of its own. Any other name is
## remembered onto config.default_set (see that field's own DECISION for why
## reusing it, rather than a second field, is enough for the F4 override
## save/load path to pick it up) and re-enables the box before delegating to
## load_set() -- which prints its own one-line fallback notice and leaves the
## box hidden, exactly as an owner-typed unknown name already does today, for
## an unknown/missing set. `root_override` mirrors load_set()'s own test seam
## so tests/unit/test_skybox.gd can drive this against a temp fixture root
## instead of the real (gitignored) asset root.
func apply_set(set_name: String, root_override: String = "") -> bool:
	if set_name == PROCEDURAL_SET_ID:
		config.enabled = false
		return load_set(set_name, root_override)
	config.default_set = set_name
	config.enabled = true
	return load_set(set_name, root_override)


func _hide_faces() -> void:
	for mesh_instance: MeshInstance3D in _face_meshes.values():
		mesh_instance.visible = false
	_restore_fallback_sky()


func _build_faces() -> void:
	for face_name: String in config.face_names:
		var mesh_instance: MeshInstance3D = _face_meshes.get(face_name) as MeshInstance3D
		if mesh_instance == null:
			continue
		mesh_instance.mesh = _build_face_mesh(face_name)
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		# CULL_DISABLED: the box's faces face inward toward the camera, and
		# with this set the triangle winding below does not have to be
		# reasoned about at all -- both sides render regardless.
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.albedo_texture = _face_textures.get(face_name)
		mesh_instance.material_override = material
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_instance.visible = true
	_install_sky_material()


## Bontago-xtq.28: applies `applied_theme`'s sky/ground colours onto
## `_fallback_sky_material` *in place* (so a later load_set() failure's
## _restore_fallback_sky() restores the themed colours, not the material's own
## untouched defaults) and its fog colour/density onto the wired Environment's
## basic depth fog. A no-op when `applied_theme` is unset or no
## `environment`/`environment.sky` was wired, matching every other
## Environment-touching method above's contract.
func apply_theme(applied_theme: SkyThemeDef) -> void:
	if applied_theme == null or environment == null or environment.sky == null:
		return
	# Bontago-59o.18: while the cycle runs, a source theme it was built from
	# (F4's live edit of sunset.tres / night.tres) must reach the live duplicate,
	# never swap its own static sky material in.
	if _cycle_theme != null and (applied_theme == _cycle_day or applied_theme == _cycle_night or applied_theme == _cycle_dawn):
		refresh_cycle_sources()
		return
	_apply_theme_parameters(applied_theme)
	# Bontago-adt.1: the cloud puffs and birds are rebuilt from the applied
	# theme too, so a live F4 edit or theme switch reaches them.
	_apply_ambient_life(Settings.current_graphics_preset(), applied_theme)
	# Bontago-mp0.19: a live theme switch during a storm re-bases the blend.
	if _storm_amount > 0.0 and applied_theme != _storm_blend:
		_apply_storm_blend()
	_publish_cloud_lighting()


## Everything apply_theme() writes except the ambient-life rebuild (birds,
## puffs): sky, fog, light, ambient, overcast, fog volume, sun flare.
func _apply_theme_parameters(applied_theme: SkyThemeDef) -> void:
	if applied_theme.sky_material != null:
		_fallback_sky_material = applied_theme.sky_material
		var panorama: ShaderMaterial = _fallback_sky_material as ShaderMaterial
		if panorama != null:
			panorama.set_shader_parameter("sky_yaw_offset_deg", applied_theme.sky_yaw_offset_deg)
			panorama.set_shader_parameter("sky_pitch_offset_deg", applied_theme.sky_pitch_offset_deg)
			_apply_procedural_params(panorama, applied_theme)
		if fallback_active:
			environment.sky.sky_material = _fallback_sky_material
	var procedural: ProceduralSkyMaterial = _fallback_sky_material as ProceduralSkyMaterial
	if procedural != null:
		procedural.sky_top_color = applied_theme.sky_top_color
		procedural.sky_horizon_color = applied_theme.sky_horizon_color
		procedural.ground_bottom_color = applied_theme.ground_bottom_color
		procedural.ground_horizon_color = applied_theme.ground_horizon_color
		# DECISION (game/Skybox.gd, Bontago-xtq.28): ProceduralSkyMaterial only
		# exposes one sun_angle_max float, not a min/max pair -- write the
		# wider/softer glow edge (sun_angle_min_max.y) since that is the value
		# that actually controls the visible glow size onscreen; .x is kept on
		# SkyThemeDef only as a design range a future per-theme sun animation
		# could draw from (see that field's own doc in config/SkyThemeDef.gd).
		procedural.sun_angle_max = applied_theme.sun_angle_min_max.y
	environment.fog_enabled = true
	environment.fog_light_color = applied_theme.fog_color
	environment.fog_density = applied_theme.fog_density
	# Bontago-xtq.28 fix round: the previous candidate never set this, so it
	# silently sat at the Environment engine default (1.0), which fully
	# replaces the rendered sky background with flat fog_light_color and
	# masked the ProceduralSkyMaterial's sunset gradient regardless of
	# fog_density. See SkyThemeDef.fog_sky_affect's own doc.
	environment.fog_sky_affect = applied_theme.fog_sky_affect
	# Bontago-xtq.28 fix round 2 (decisive finding): Environment.volumetric_fog_
	# density defaults to 0.05 on a fresh Environment and was never written
	# here, so the whole frustum showed a uniform grey haze regardless of
	# _spawn_fog_volume()'s FogVolume placement -- a FogVolume only adds density
	# on top of this ambient global floor, it cannot remove it. See
	# SkyThemeDef.volumetric_fog_density's own doc.
	environment.volumetric_fog_density = applied_theme.volumetric_fog_density
	environment.volumetric_fog_albedo = applied_theme.volumetric_fog_albedo
	_apply_light_and_environment(applied_theme)
	_apply_overcast(applied_theme)
	_sync_fog_volume(applied_theme)
	_apply_sun_flare(applied_theme)


## Bontago-mp0.19 (storm sky, owner decision Bontago-048 option C): blends the
## active theme toward `storm_theme` by `amount` 0..1 through the same writers
## apply_theme() uses (procedural sky uniforms, fog, light, ambient, overcast).
## DECISION: the two themes own different sky materials, so the blend lerps the
## colour/scalar fields onto the ACTIVE theme's material instead of swapping
## materials; the cloud sea and birds are not rebuilt per frame. Amount 0
## restores through the full apply_theme(theme), i.e. the match's own theme.
func set_storm_sky(amount: float, storm_theme: SkyThemeDef) -> void:
	var clamped: float = clampf(amount, 0.0, 1.0)
	if is_equal_approx(clamped, _storm_amount) and storm_theme == _storm_target:
		return
	var was_active: bool = _storm_amount > 0.0
	var previous_target: SkyThemeDef = _storm_target
	_storm_amount = clamped
	_storm_target = storm_theme
	if clamped <= 0.0 or storm_theme == null:
		_storm_amount = 0.0
		if was_active:
			_restore_after_storm(previous_target if storm_theme == null else storm_theme)
		return
	_apply_storm_blend()


## Storm over: re-applies only the blended parameters (sky, fog incl. the fog
## volume, light, ambient, overcast, flare) and the cloud tint, without the
## birds/puff rebuild apply_theme() does. In CYCLE mode the cycle writers are
## re-run for the current phase afterwards.
func _restore_after_storm(storm_theme: SkyThemeDef) -> void:
	if theme == null or environment == null or environment.sky == null:
		return
	_apply_theme_parameters(theme)
	if _cloud_sea != null and storm_theme != null:
		_cloud_sea.apply_storm_tint(theme, storm_theme, 0.0, theme.sky_material)
	_reapply_cycle_phase(false)
	_publish_cloud_lighting()


func storm_sky_amount() -> float:
	return _storm_amount


func _apply_storm_blend() -> void:
	var base: SkyThemeDef = theme
	if base == null or _storm_target == null or environment == null or environment.sky == null:
		return
	var storm: SkyThemeDef = _storm_target
	var t: float = _storm_amount
	if _storm_blend == null or _storm_blend_base != base:
		_storm_blend = base.duplicate(false) as SkyThemeDef
		_storm_blend_base = base
	var b: SkyThemeDef = _storm_blend
	b.sky_top_color = base.sky_top_color.lerp(storm.sky_top_color, t)
	b.sky_horizon_color = base.sky_horizon_color.lerp(storm.sky_horizon_color, t)
	b.ground_bottom_color = base.ground_bottom_color.lerp(storm.ground_bottom_color, t)
	b.ground_horizon_color = base.ground_horizon_color.lerp(storm.ground_horizon_color, t)
	b.fog_color = base.fog_color.lerp(storm.fog_color, t)
	b.fog_density = lerpf(base.fog_density, storm.fog_density, t)
	b.fog_sky_affect = lerpf(base.fog_sky_affect, storm.fog_sky_affect, t)
	b.volumetric_fog_density = lerpf(base.volumetric_fog_density, storm.volumetric_fog_density, t)
	b.volumetric_fog_albedo = base.volumetric_fog_albedo.lerp(storm.volumetric_fog_albedo, t)
	b.light_color = base.light_color.lerp(storm.light_color, t)
	b.light_energy = lerpf(base.light_energy, storm.light_energy, t)
	b.light_rotation_deg = base.light_rotation_deg.lerp(storm.light_rotation_deg, t)
	b.ambient_energy = lerpf(base.ambient_energy, storm.ambient_energy, t)
	b.glow_intensity = lerpf(base.glow_intensity, storm.glow_intensity, t)
	b.sun_flare_enabled = base.sun_flare_enabled and t < CEILING_TUNING.storm_flare_off_amount
	var base_mix: float = base.procedural_sea_mix if base.sky_look_procedural else 0.0
	var storm_mix: float = storm.procedural_sea_mix if storm.sky_look_procedural else 0.0
	b.sky_look_procedural = true
	b.procedural_sea_mix = lerpf(base_mix, storm_mix, t)
	b.proc_zenith_color = base.proc_zenith_color.lerp(storm.proc_zenith_color, t)
	b.proc_mid_color = base.proc_mid_color.lerp(storm.proc_mid_color, t)
	b.proc_horizon_color = base.proc_horizon_color.lerp(storm.proc_horizon_color, t)
	b.proc_gradient_mid_height = lerpf(base.proc_gradient_mid_height, storm.proc_gradient_mid_height, t)
	b.proc_gradient_power = lerpf(base.proc_gradient_power, storm.proc_gradient_power, t)
	b.proc_horizon_glow_color = base.proc_horizon_glow_color.lerp(storm.proc_horizon_glow_color, t)
	b.proc_horizon_glow_width = lerpf(base.proc_horizon_glow_width, storm.proc_horizon_glow_width, t)
	b.proc_sun_glow_strength = lerpf(base.proc_sun_glow_strength, storm.proc_sun_glow_strength, t)
	b.proc_sea_color_near = base.proc_sea_color_near.lerp(storm.proc_sea_color_near, t)
	b.proc_sea_color_far = base.proc_sea_color_far.lerp(storm.proc_sea_color_far, t)
	var panorama: ShaderMaterial = base.sky_material as ShaderMaterial
	if panorama != null:
		_apply_procedural_params(panorama, b)
	var procedural: ProceduralSkyMaterial = base.sky_material as ProceduralSkyMaterial
	if procedural != null:
		procedural.sky_top_color = b.sky_top_color
		procedural.sky_horizon_color = b.sky_horizon_color
		procedural.ground_bottom_color = b.ground_bottom_color
		procedural.ground_horizon_color = b.ground_horizon_color
	environment.fog_light_color = b.fog_color
	environment.fog_density = b.fog_density
	environment.fog_sky_affect = b.fog_sky_affect
	environment.volumetric_fog_density = b.volumetric_fog_density
	environment.volumetric_fog_albedo = b.volumetric_fog_albedo
	# CYCLE mode owns the light direction (sun path): never blend it.
	_apply_light_and_environment(b, _cycle_theme == null or base != _cycle_theme)
	_apply_overcast(b)
	_apply_sun_flare(b)
	if _fog_volume != null:
		var fog_material: FogMaterial = _fog_volume.material as FogMaterial
		if fog_material != null:
			fog_material.density = b.fog_density
	if _cloud_sea != null:
		_cloud_sea.apply_storm_tint(base, storm, t, base.sky_material)
	_publish_cloud_lighting()


## Bontago-59o.16 (procedural sky P1): writes the opt-in procedural-look uniforms
## onto the theme's sky ShaderMaterial. The effective mix is 0 unless
## sky_look_procedural is set, so the default look is unchanged. Shaders that
## lack a uniform ignore the write.
func _apply_procedural_params(material: ShaderMaterial, applied_theme: SkyThemeDef) -> void:
	var mix: float = applied_theme.procedural_sea_mix if applied_theme.sky_look_procedural else 0.0
	material.set_shader_parameter("procedural_sea_mix", mix)
	material.set_shader_parameter("proc_zenith_color", applied_theme.proc_zenith_color)
	material.set_shader_parameter("proc_mid_color", applied_theme.proc_mid_color)
	material.set_shader_parameter("proc_horizon_color", applied_theme.proc_horizon_color)
	material.set_shader_parameter("proc_gradient_mid_height", applied_theme.proc_gradient_mid_height)
	material.set_shader_parameter("proc_gradient_power", applied_theme.proc_gradient_power)
	material.set_shader_parameter("proc_horizon_glow_color", applied_theme.proc_horizon_glow_color)
	material.set_shader_parameter("proc_horizon_glow_width", applied_theme.proc_horizon_glow_width)
	material.set_shader_parameter("proc_sun_glow_strength", applied_theme.proc_sun_glow_strength)
	material.set_shader_parameter("proc_sea_color_near", applied_theme.proc_sea_color_near)
	material.set_shader_parameter("proc_sea_color_far", applied_theme.proc_sea_color_far)
	material.set_shader_parameter("proc_sea_horizon_fade", applied_theme.proc_sea_horizon_fade)
	material.set_shader_parameter("proc_strata_scale", applied_theme.proc_strata_scale)
	material.set_shader_parameter("proc_overhead_mix", 1.0 if applied_theme.proc_overhead_clouds_enabled else 0.0)
	material.set_shader_parameter("proc_cards_mix", 1.0 if applied_theme.proc_cards_enabled else 0.0)
	material.set_shader_parameter("proc_cards_opacity", applied_theme.proc_cards_opacity)
	var layout: Variant = material.get_shader_parameter("proc_cards_layout")
	if layout is Vector4:
		var cards_layout: Vector4 = layout as Vector4
		material.set_shader_parameter("proc_cards_layout", Vector4(
			applied_theme.proc_cards_scale, cards_layout.y, applied_theme.proc_cards_density, cards_layout.w))


## Bontago-xtq.28: creates this Skybox's own FogVolume "cloud deck" child --
## Skybox and Field are sibling nodes under Main.tscn (game/Skybox.gd's
## Bontago-xtq.28 class-doc paragraph), so this is the only owned-file path to
## add it; game/Field.tscn itself is left untouched (DECISION, this method):
## a NodePath from Field to a Skybox-owned node, or vice versa, would need a
## wire in Main.tscn, which this package does not own. Always created (so
## _on_graphics_preset_changed() below only ever has to flip `visible`, never
## construct/destroy) with `theme`'s fog colour/density shared onto its
## FogMaterial, so the depth fog apply_theme() sets above and this volumetric
## deck read as one coherent colour instead of two independently tuned
## effects. A no-op (no node created, get_fog_volume() stays null) when
## `theme` is unset.
func _spawn_fog_volume() -> void:
	if theme == null:
		return
	var fog_volume: FogVolume = FogVolume.new()
	fog_volume.name = "CloudDeck"
	fog_volume.size = theme.cloud_deck_size_m
	fog_volume.position = Vector3(0.0, theme.cloud_deck_height_m, 0.0)
	var fog_material: FogMaterial = FogMaterial.new()
	fog_material.density = theme.fog_density
	fog_material.albedo = theme.fog_color
	fog_volume.material = fog_material
	add_child(fog_volume)
	_fog_volume = fog_volume


## autoload/Settings.gd's graphics_preset_changed handler, connected in
## _ready() and disconnected in _exit_tree() above.
func _on_graphics_preset_changed(preset: GraphicsPreset) -> void:
	# Bontago-mp0.129: the aurora reads this cached flag, never the Settings lookup.
	_aurora_preset_on = preset == null or preset.aurora_enabled
	_apply_fog_volume_visibility(preset)
	_apply_ambient_life(preset, theme)
	# Bontago-59o.18: the rebuild above is day-configured (puff palette, light
	# direction, birds, perching, fireflies); put the cycle's current phase back on
	# top. A locked Night / Dawn / Sunset match never self-heals otherwise.
	_reapply_cycle_phase(true)
	_publish_cloud_lighting()


## Bontago-adt.1: loads res://config/sky_themes/<id>.tres, or null if missing.
static func load_theme(theme_id: String) -> SkyThemeDef:
	var path: String = "%s/%s.tres" % [THEME_DIR, theme_id]
	if not ResourceLoader.exists(path):
		return null
	return load(path) as SkyThemeDef


## Bontago-adt.1: live theme switch (sky, light, environment, cloud sea, birds,
## cloud-deck fog volume, sun flare, reflection probe re-capture).
func set_theme_by_id(theme_id: String) -> bool:
	# Bontago-59o.18: "cycle" is not a theme file; it (re)starts the running cycle
	# and is remembered like any theme pick (re-applied by _ready()).
	if theme_id == CYCLE_THEME_ID:
		start_cycle()
		if not is_cycle_active():
			return false
		config.theme_name = theme_id
		refresh_reflection_capture()
		return true
	var chosen: SkyThemeDef = load_theme(theme_id)
	if chosen == null:
		return false
	theme = chosen
	_cycle_theme = null
	_cycle_locked_phase = -1.0
	_cycle_phase_last = -1.0
	_set_sky_process_mode(Sky.PROCESS_MODE_QUALITY)
	config.theme_name = theme_id
	apply_theme(theme)
	refresh_reflection_capture()
	return true


## Theme ids (file basenames) under THEME_DIR whose resource is a SkyThemeDef
## (skips the noise textures), sorted. Future themes appear automatically.
static func list_available_themes() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(THEME_DIR)
	if dir == null:
		return ids
	for file_name: String in dir.get_files():
		var clean: String = file_name.trim_suffix(".remap")
		if not clean.ends_with(".tres"):
			continue
		var theme_id: String = clean.get_basename()
		if load_theme(theme_id) != null and not ids.has(theme_id):
			ids.append(theme_id)
	ids.sort()
	return ids


## Forces the ReflectionProbe to re-capture the (new) sky: an UPDATE_ONCE probe
## only renders when it becomes visible, so toggle it after re-configuring.
func refresh_reflection_capture() -> void:
	configure_reflection_probe()
	if reflection_probe_path.is_empty():
		return
	var probe: ReflectionProbe = get_node_or_null(reflection_probe_path) as ReflectionProbe
	if probe != null and probe.visible:
		probe.visible = false
		probe.visible = true


## Resyncs the CloudDeck FogVolume's size/position/material to `applied_theme`
## (it was only ever built once in _ready() from the boot theme).
func _sync_fog_volume(applied_theme: SkyThemeDef) -> void:
	if _fog_volume == null:
		return
	_fog_volume.size = applied_theme.cloud_deck_size_m
	_fog_volume.position = Vector3(0.0, applied_theme.cloud_deck_height_m, 0.0)
	var fog_material: FogMaterial = _fog_volume.material as FogMaterial
	if fog_material != null:
		fog_material.density = applied_theme.fog_density
		fog_material.albedo = applied_theme.fog_color


## Pushes the theme's sun_flare_enabled onto every SunFlare in the tree.
func _apply_sun_flare(applied_theme: SkyThemeDef) -> void:
	if not is_inside_tree():
		return
	for node: Node in get_tree().get_nodes_in_group(SunFlare.GROUP):
		var flare: SunFlare = node as SunFlare
		if flare != null:
			flare.set_theme_enabled(applied_theme.sun_flare_enabled)
			flare.set_weather_scale(_cloud_lighting.sun_scale)


## Bontago-adt.1: cloud puffs and birds follow the graphics preset (Low:
## sparse puffs, no birds). A null preset means full quality. The puffs copy
## the theme's sky material uniforms so their far fade matches the sky.
func _apply_ambient_life(preset: GraphicsPreset, applied_theme: SkyThemeDef) -> void:
	var density: float = preset.cloud_puff_density if preset != null else 1.0
	var birds: bool = preset == null or preset.birds_enabled
	if _cloud_sea != null:
		var sky_material: Material = applied_theme.sky_material if applied_theme != null else null
		var subdivisions: int = preset.cloud_puff_subdivisions if preset != null else CloudSea.PUFF_SUBDIVISIONS
		_cloud_sea.upper_low = preset != null and not preset.ambient_life_enabled
		_cloud_sea.disc_radius_m = _largest_disc_radius()
		_cloud_sea.configure(applied_theme, density, sky_material, subdivisions)
		# Bontago-mp0.19: configure() resets the puff palette; keep the storm tint.
		if _storm_amount > 0.0 and _storm_target != null and applied_theme != null and applied_theme == theme:
			_cloud_sea.apply_storm_tint(applied_theme, _storm_target, _storm_amount, applied_theme.sky_material)
	if _birds != null:
		_birds.configure(applied_theme, birds)
	# Bontago-adt.3: perching birds / fireflies, rebuilt (never duplicated) on
	# every theme apply, live switch and preset change.
	var life: AmbientLifeConfig = applied_theme.ambient_life if applied_theme != null else null
	var life_enabled: bool = preset == null or preset.ambient_life_enabled
	if _perching != null:
		_perching.configure(life, life_enabled)
	if _fireflies != null:
		_fireflies.configure(life, life_enabled, _disc_radius_for_ambient_life())


## Bontago-adt.1: writes the theme's light and glow/ambient values onto the
## wired DirectionalLight3D and Environment.
func _apply_light_and_environment(applied_theme: SkyThemeDef, write_rotation: bool = true) -> void:
	environment.ambient_light_energy = applied_theme.ambient_energy
	environment.glow_intensity = applied_theme.glow_intensity
	environment.glow_hdr_threshold = applied_theme.glow_hdr_threshold
	if light_path.is_empty():
		return
	var light: DirectionalLight3D = get_node_or_null(light_path) as DirectionalLight3D
	if light == null:
		return
	light.light_color = applied_theme.light_color
	light.light_energy = applied_theme.light_energy
	if write_rotation:
		light.rotation_degrees = applied_theme.light_rotation_deg


## Bontago-mp0.29: the shared cloud lighting (never null; layers connect to
## its `changed` signal and read it).
func cloud_lighting() -> CloudLighting:
	return _cloud_lighting


## Gathers the inputs the cloud layers share from what this Skybox has already
## resolved (theme / cycle / storm palette on the puff material, the key light,
## overcast, storm) and publishes them once. The sea below the disc draws from
## the same sky cloud_* colours (they are mixed/tinted by the same writers); the
## puffs and the weather ceiling take the published palette and weather grade.
func _publish_cloud_lighting() -> void:
	var puff: ShaderMaterial = _cloud_sea.puff_material() if _cloud_sea != null else null
	if puff == null and theme != null:
		puff = theme.cloud_puff_material as ShaderMaterial
	var sky: ShaderMaterial = theme.sky_material as ShaderMaterial if theme != null else null
	var night: float = 0.0
	if sky != null and _cycle_theme != null:
		var mixed: Variant = sky.get_shader_parameter(&"cycle_night_mix")
		night = float(mixed) if mixed is float else 0.0
	# Bontago-mp0.129: the aurora follows the same night / weather / preset inputs, and does
	# not need the puff material, so it is written before the puff-less early return.
	_apply_aurora(night)
	if puff == null:
		return
	var direction: Vector3 = _cloud_lighting.light_direction
	var raw_direction: Variant = puff.get_shader_parameter(&"light_direction")
	if raw_direction is Vector3:
		direction = (raw_direction as Vector3).normalized()
	var light_color: Color = (_cycle_theme if _cycle_theme != null else theme).light_color if theme != null else Color.WHITE
	if _storm_amount > 0.0 and _storm_blend != null:
		light_color = _storm_blend.light_color
	var cloud_overcast: float = cloud_overcast_amount()
	var weather: float = maxf(cloud_overcast, _storm_amount)
	var dim: float = CloudLighting.combined_dim(CEILING_TUNING.cloud_overcast_dim, CEILING_TUNING.storm_darkness_add,
		cloud_overcast, _storm_amount, night, CEILING_TUNING.night_dim_relief, CEILING_TUNING.max_combined_dim)
	# Bontago-mp0.128: snow lifts the clouds (a negative dim brightens), not at night.
	dim -= CEILING_TUNING.snow_cloud_brighten * _snow_brighten * (1.0 - clampf(night, 0.0, 1.0))
	var changed: bool = _cloud_lighting.publish(
		_puff_color(puff, &"shadow_color", _cloud_lighting.shadow_color),
		_puff_color(puff, &"mid_color", _cloud_lighting.mid_color),
		_puff_color(puff, &"lit_color", _cloud_lighting.lit_color),
		_puff_color(puff, &"rim_color", _cloud_lighting.rim_color),
		direction, light_color, night, cloud_overcast, _storm_amount, dim,
		CEILING_TUNING.cloud_overcast_desaturate * weather)
	_apply_moon(night)
	var sun_effects: float = CloudLighting.sun_effect_scale(night, CEILING_TUNING.sun_night_fade_end, cloud_overcast,
		CEILING_TUNING.sun_overcast_attenuation, _storm_amount, CEILING_TUNING.sun_storm_attenuation)
	var floor_changed: bool = _cloud_lighting.publish_floor(
		CloudLighting.floor_for_tone(CEILING_TUNING.puff_floor_tint, CEILING_TUNING.puff_min_brightness, 1.0),
		CEILING_TUNING.puff_floor_shadow_ratio, CEILING_TUNING.puff_floor_mid_ratio, sun_effects)
	if changed or floor_changed:
		if _cloud_sea != null:
			_cloud_sea.apply_lighting(_cloud_lighting)
		_apply_sun_effect_scale(sun_effects)


## Bontago-mp0.122: writes the moon_v1 disc/halo uniforms on the live cycle sky. The moon
## sits opposite the sun, fades in with the night mix and is hidden by overcast/storm
## exactly as far as the sun's own weather keep (CloudLighting.sun_weather_keep).
func _apply_moon(night: float) -> void:
	if _cycle_theme == null:
		return
	var sky: ShaderMaterial = _cycle_theme.sky_material as ShaderMaterial
	if sky == null:
		return
	var sun: Variant = sky.get_shader_parameter(&"sun_direction")
	if sun is Vector3:
		sky.set_shader_parameter(&"moon_direction", -(sun as Vector3).normalized())
	var full: float = maxf(_cycle_theme.cycle_moon_full_night_mix, 0.0001)
	var keep: float = CloudLighting.sun_weather_keep(cloud_overcast_amount(), CEILING_TUNING.sun_overcast_attenuation,
		_storm_amount, CEILING_TUNING.sun_storm_attenuation)
	sky.set_shader_parameter(&"moon_disc_tex", MOON_DISC_TEXTURE)
	sky.set_shader_parameter(&"moon_halo_tex", MOON_HALO_TEXTURE)
	sky.set_shader_parameter(&"moon_visibility", smoothstep(0.0, full, night) * keep)
	sky.set_shader_parameter(&"moon_angular_radius_deg", _cycle_theme.cycle_moon_angular_radius_deg)
	sky.set_shader_parameter(&"moon_halo_radius_deg", _cycle_theme.cycle_moon_halo_radius_deg)
	sky.set_shader_parameter(&"moon_halo_strength", _cycle_theme.cycle_moon_halo_strength)
	sky.set_shader_parameter(&"moon_brightness", _cycle_theme.cycle_moon_brightness)


## Bontago-mp0.129 (owner playtest: "at night lets add an aurora borealis effect to the sky"):
## writes the aurora uniforms on the live sky material (the cycle's sunset_clouds, or a static
## theme's own sky such as night_sky). `night` is the cycle's night mix 0..1 (0 outside the
## cycle). The shaders only read `aurora_visibility`, so the day / night / weather / preset
## decision lives here, exactly as for the moon: the cycle fades it in over the theme's
## aurora_start_night_mix .. aurora_full_night_mix (SkyThemeDef.aurora_night_strength, edges
## ordered), a static theme shows it at full strength only when SkyThemeDef.aurora_always_on,
## the weather's sun keep (overcast, storm) scales it, and it is 0 whenever the theme or the
## graphics preset (Low, `_aurora_preset_on`) switches it off.
## This runs on every cycle phase tick, so it is cheap while the aurora is hidden (the whole
## day): no Settings lookup, and nothing is written to the material until the visibility
## changes. The look uniforms are written only while visible and only when they differ from
## what is already on that material (a new sky material is written afresh).
func _apply_aurora(night: float) -> void:
	var active: SkyThemeDef = _cycle_theme if _cycle_theme != null else theme
	var sky: ShaderMaterial = active.sky_material as ShaderMaterial if active != null else null
	if sky == null:
		return
	if sky != _aurora_sky:
		_aurora_sky = sky
		_aurora_visibility_written = -1.0
		_aurora_look_written = []
	var strength: float = 0.0
	if active.aurora_enabled and _aurora_preset_on:
		if _cycle_theme != null:
			strength = active.aurora_night_strength(night)
		elif active.aurora_always_on:
			strength = 1.0
	var visibility: float = 0.0
	if strength > 0.0:
		visibility = strength * CloudLighting.sun_weather_keep(cloud_overcast_amount(),
			CEILING_TUNING.sun_overcast_attenuation, _storm_amount, CEILING_TUNING.sun_storm_attenuation)
	if visibility != _aurora_visibility_written:
		_aurora_visibility_written = visibility
		sky.set_shader_parameter(&"aurora_visibility", visibility)
	if visibility <= 0.0:
		return
	var look: Array = [active.aurora_intensity, active.aurora_color_low, active.aurora_color_mid,
		active.aurora_color_top, active.aurora_speed, active.aurora_base_height, active.aurora_curtain_height]
	if look == _aurora_look_written:
		return
	_aurora_look_written = look
	sky.set_shader_parameter(&"aurora_intensity", active.aurora_intensity)
	sky.set_shader_parameter(&"aurora_color_low", active.aurora_color_low)
	sky.set_shader_parameter(&"aurora_color_mid", active.aurora_color_mid)
	sky.set_shader_parameter(&"aurora_color_top", active.aurora_color_top)
	sky.set_shader_parameter(&"aurora_speed", active.aurora_speed)
	sky.set_shader_parameter(&"aurora_base_height", active.aurora_base_height)
	sky.set_shader_parameter(&"aurora_curtain_height", active.aurora_curtain_height)


## Bontago-mp0.34: scales the sky shader's god rays / sun glow and the screen
## flare by the weather + night sun scale (host and client compute it the same).
func _apply_sun_effect_scale(sun_effects: float) -> void:
	var active: SkyThemeDef = _cycle_theme if _cycle_theme != null else theme
	var sky: ShaderMaterial = active.sky_material as ShaderMaterial if active != null else null
	if sky != null:
		sky.set_shader_parameter(&"sun_effect_scale", sun_effects)
	if not is_inside_tree():
		return
	for node: Node in get_tree().get_nodes_in_group(SunFlare.GROUP):
		var flare: SunFlare = node as SunFlare
		if flare != null:
			flare.set_weather_scale(sun_effects)


static func _puff_color(material: ShaderMaterial, parameter: StringName, fallback: Color) -> Color:
	var value: Variant = material.get_shader_parameter(parameter)
	return value as Color if value is Color else fallback


func get_cloud_sea() -> CloudSea:
	return _cloud_sea


func get_birds() -> DistantBirds:
	return _birds


func get_perching_birds() -> PerchingBirds:
	return _perching


func get_fireflies() -> Fireflies:
	return _fireflies


## Bontago-1pi.107: the radius the cloud sea, its exclusion cylinder and the
## reflection probe must cover -- the bound Field's (disc-size scaled) radius,
## never below the largest shipped map.
func _largest_disc_radius() -> float:
	if not field_path.is_empty():
		var field_node: Field = get_node_or_null(field_path) as Field
		if field_node != null and field_node.map_definition() != null:
			return maxf(field_node.map_definition().field_radius, MapDef.RADIUS_LARGE)
	return MapDef.RADIUS_LARGE


## Disc radius (m) the fireflies ring around: the bound Field's map, else the
## default map's radius.
func _disc_radius_for_ambient_life() -> float:
	if not field_path.is_empty():
		var field_node: Field = get_node_or_null(field_path) as Field
		if field_node != null:
			return field_node.map_definition().field_radius
	return MapDef.RADIUS_MEDIUM


## Bontago-xtq.28: the FogVolume's only gating -- `visible` alone, never
## created/destroyed (see _spawn_fog_volume()'s own doc on why). Matches
## docs/M7_ART_DIRECTION.md's performance budget: dropped from view entirely
## on Low (config/graphics_presets/low.tres: volumetric_fog_enabled == false),
## present on Medium/High. A no-op when no FogVolume exists yet (`theme` was
## unset in _ready()) or `preset` is unset.
func _apply_fog_volume_visibility(preset: GraphicsPreset) -> void:
	if _fog_volume == null or preset == null:
		return
	_fog_volume.visible = preset.volumetric_fog_enabled


## Test/inspection seam: the FogVolume _spawn_fog_volume() created, or null if
## `theme` was unset in _ready().
func get_fog_volume() -> FogVolume:
	return _fog_volume


## Restores the Environment's Sky to whatever material it carried before this
## node ever touched it (Main.tscn's ProceduralSkyMaterial) -- a no-op when no
## `environment` was wired (most of tests/unit/test_skybox.gd) or _ready()
## never captured one (environment.sky was null at the time).
func _restore_fallback_sky() -> void:
	if environment == null or environment.sky == null or _fallback_sky_material == null:
		return
	environment.sky.sky_material = _fallback_sky_material


## Bontago-xtq.8: installs shaders/cubemap_sky.gdshader onto the Environment's
## Sky, with the same six face textures and the same SkyboxConfig.
## face_rotations/face_flip_u/face_flip_v the box's own quads use -- see the
## class doc and the shader's doc for why the two are the same convention
## read two different ways. A no-op when no `environment` was wired.
func _install_sky_material() -> void:
	if environment == null or environment.sky == null:
		return
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = SKY_SHADER
	for index: int in range(config.face_names.size()):
		var face_name: String = config.face_names[index]
		var rotation: int = config.face_rotations[index] if index < config.face_rotations.size() else 0
		var flip_u: bool = index < config.face_flip_u.size() and config.face_flip_u[index] != 0
		var flip_v: bool = index < config.face_flip_v.size() and config.face_flip_v[index] != 0
		material.set_shader_parameter(face_name + "_tex", _face_textures.get(face_name))
		material.set_shader_parameter(face_name + "_rotation", rotation)
		material.set_shader_parameter(face_name + "_flip_u", flip_u)
		material.set_shader_parameter(face_name + "_flip_v", flip_v)
	environment.sky.sky_material = material
	# DECISION (game/Skybox.gd): PROCESS_MODE_QUALITY, not the default
	# AUTOMATIC/INCREMENTAL. Reflections/ambient are read from the sky's own
	# radiance/irradiance maps, not the background pixels directly --
	# INCREMENTAL mode (meant for a sky that keeps changing, e.g. a day/night
	# cycle) spreads that recompute over many frames, so a freshly-loaded set
	# would keep showing the *previous* sky's (or the fallback gradient's)
	# stale reflection for a visible stretch of play. QUALITY recomputes fully
	# on the next frame instead; this skybox only ever changes at
	# load_set() (once per match/map), so the one-frame cost is negligible.
	environment.sky.process_mode = Sky.PROCESS_MODE_QUALITY


## One quad per face of a box_half_extent-sided cube, in Skybox-local space
## (this node sits at the world origin -- see class doc on why it does not
## follow the camera). Built directly rather than from BoxMesh/QuadMesh so
## each face's UV orientation is an explicit, checkable base mapping (see
## _face_corners()) with a per-face correction on top of it
## (config.face_rotations/face_flip_u/face_flip_v, applied by
## _apply_face_transform() below) -- the base mapping alone ("front" unrotated
## with back/left/right as the 90-degree turns around it, top/bottom attached
## to front's edges unrotated) turned out NOT to match the original install's
## own per-face orientation for any of the six files; every face needs its
## correction. See tools/skybox_seam_probe.gd, which found that correction
## numerically, for why and the measured seam error.
func _build_face_mesh(face_name: String) -> ArrayMesh:
	var corners: Dictionary = _face_corners(StringName(face_name), config.box_half_extent)
	if corners.is_empty():
		return null

	var index: int = config.face_names.find(face_name)
	var rotation: int = config.face_rotations[index] if index >= 0 and index < config.face_rotations.size() else 0
	var flip_u: bool = index >= 0 and index < config.face_flip_u.size() and config.face_flip_u[index] != 0
	var flip_v: bool = index >= 0 and index < config.face_flip_v.size() and config.face_flip_v[index] != 0

	var positions: PackedVector3Array = PackedVector3Array([
		corners["p00"], corners["p10"], corners["p01"], corners["p11"],
	])
	var uvs: PackedVector2Array = PackedVector2Array([
		_apply_face_transform(0.0, 0.0, flip_u, flip_v, rotation),
		_apply_face_transform(1.0, 0.0, flip_u, flip_v, rotation),
		_apply_face_transform(0.0, 1.0, flip_u, flip_v, rotation),
		_apply_face_transform(1.0, 1.0, flip_u, flip_v, rotation),
	])
	var indices: PackedInt32Array = PackedInt32Array([0, 2, 1, 1, 2, 3])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Applies (in order) an optional horizontal flip, an optional vertical
## flip, then `rotation` quarter turns (each turn: (u,v) -> (v, 1-u)) to a
## face's base UV coordinate. Shared, as a static method, with
## tools/skybox_seam_probe.gd so the probe's search space and Skybox's actual
## render are provably the same transform -- the probe's printed table is
## meaningless otherwise. rotation is taken mod 4 (any int is accepted so a
## config value never has to be pre-clamped).
static func _apply_face_transform(u: float, v: float, flip_u: bool, flip_v: bool, rotation: int) -> Vector2:
	var uu: float = 1.0 - u if flip_u else u
	var vv: float = 1.0 - v if flip_v else v
	var turns: int = ((rotation % 4) + 4) % 4
	for _i: int in range(turns):
		var next_u: float = vv
		var next_v: float = 1.0 - uu
		uu = next_u
		vv = next_v
	return Vector2(uu, vv)


## p00/p10/p01/p11 are this face's UV (0,0)/(1,0)/(0,1)/(1,1) corners in
## world space (h = box_half_extent), before any face_rotations/flip
## correction is applied (that happens in _build_face_mesh() above via
## _apply_face_transform()). See the class/method doc above for the
## convention these follow. Static (and called that way by the seam probe
## too) since it is a pure function of face + h, with no instance state.
static func _face_corners(face: StringName, h: float) -> Dictionary:
	match face:
		&"front":
			return {
				"p00": Vector3(-h, h, -h), "p10": Vector3(h, h, -h),
				"p01": Vector3(-h, -h, -h), "p11": Vector3(h, -h, -h),
			}
		&"back":
			return {
				"p00": Vector3(h, h, h), "p10": Vector3(-h, h, h),
				"p01": Vector3(h, -h, h), "p11": Vector3(-h, -h, h),
			}
		&"right":
			return {
				"p00": Vector3(h, h, -h), "p10": Vector3(h, h, h),
				"p01": Vector3(h, -h, -h), "p11": Vector3(h, -h, h),
			}
		&"left":
			return {
				"p00": Vector3(-h, h, h), "p10": Vector3(-h, h, -h),
				"p01": Vector3(-h, -h, h), "p11": Vector3(-h, -h, -h),
			}
		&"top":
			return {
				"p00": Vector3(-h, h, h), "p10": Vector3(h, h, h),
				"p01": Vector3(-h, h, -h), "p11": Vector3(h, h, -h),
			}
		&"bottom":
			return {
				"p00": Vector3(-h, -h, -h), "p10": Vector3(h, -h, -h),
				"p01": Vector3(-h, -h, h), "p11": Vector3(h, -h, h),
			}
		_:
			return {}


## Weather overcast (Bontago-22y.5): `amount` 0..1 scales the theme's light and
## ambient energy, the sky exposure and tints the fog toward `fog_tint`. The
## *_scale values are the factors reached at amount 1. Amount 0 restores the
## theme exactly.
func set_overcast(amount: float, light_scale: float, ambient_scale: float, exposure_scale: float, fog_tint: Color, fog_tint_strength: float) -> void:
	_overcast_amount = clampf(amount, 0.0, 1.0)
	_overcast_light_scale = light_scale
	_overcast_ambient_scale = ambient_scale
	_overcast_exposure_scale = exposure_scale
	_overcast_fog_tint = fog_tint
	_overcast_fog_tint_strength = fog_tint_strength
	_apply_overcast(_overcast_theme if _overcast_theme != null else theme)
	_publish_cloud_lighting()


func overcast_amount() -> float:
	return _overcast_amount


## Bontago-mp0.29: the overcast every weather (rain, snow, storm; CloudCeiling) asks
## of the cloud layers. Grades the shared CloudLighting only; the light, ambient
## and fog overcast above stay RainPresentation's.
func set_weather_cloud_overcast(amount: float) -> void:
	var clamped: float = clampf(amount, 0.0, 1.0)
	if clamped == _weather_cloud_overcast:
		return
	_weather_cloud_overcast = clamped
	_publish_cloud_lighting()


## Bontago-mp0.128: snow brightens the sky (background exposure) and the clouds
## (negative weather dim) by `amount` 0..1; 0 restores exactly.
func set_snow_brighten(amount: float) -> void:
	var clamped: float = clampf(amount, 0.0, 1.0)
	if clamped == _snow_brighten:
		return
	_snow_brighten = clamped
	if theme != null and environment != null:
		_apply_overcast(_overcast_theme if _overcast_theme != null else theme)
	_publish_cloud_lighting()


func snow_brighten_amount() -> float:
	return _snow_brighten


## The overcast the cloud layers are graded by (strongest of the sources).
func cloud_overcast_amount() -> float:
	return maxf(_overcast_amount, _weather_cloud_overcast)


## Weather fog (Bontago-470.3): `amount` 0..1 switches the Environment to DEPTH
## fog that starts `depth_begin_m` from the camera (so nearby blocks keep their
## full colour) and reaches `max_opacity * amount` at `depth_end_m`, tints the
## fog toward `tint` and lets it wash the sky/horizon by `sky_affect_add` more.
## Amount 0 restores the theme (and its own fog mode) exactly.
func set_weather_fog(amount: float, max_opacity: float, depth_begin_m: float, depth_end_m: float, tint: Color, tint_strength: float, sky_affect_add: float = 0.0, aerial_add: float = 0.0) -> void:
	_wfog_amount = clampf(amount, 0.0, 1.0)
	_wfog_max_opacity = max_opacity
	_wfog_depth_begin_m = depth_begin_m
	_wfog_depth_end_m = depth_end_m
	_wfog_tint = tint
	_wfog_tint_strength = tint_strength
	_wfog_sky_affect_add = sky_affect_add
	_wfog_aerial_add = aerial_add
	_apply_overcast(_overcast_theme if _overcast_theme != null else theme)


## The fog colour currently in the Environment (the disc's own fog uses it).
func weather_fog_color() -> Color:
	return environment.fog_light_color if environment != null else _wfog_tint


func weather_fog_amount() -> float:
	return _wfog_amount


func _apply_overcast(applied_theme: SkyThemeDef) -> void:
	if applied_theme == null or environment == null:
		return
	_overcast_theme = applied_theme
	if _overcast_exposure_base < 0.0:
		_overcast_exposure_base = environment.background_energy_multiplier
	var amount: float = _overcast_amount
	environment.ambient_light_energy = applied_theme.ambient_energy * lerpf(1.0, _overcast_ambient_scale, amount)
	environment.background_energy_multiplier = _overcast_exposure_base * lerpf(1.0, _overcast_exposure_scale, amount) 		* lerpf(1.0, CEILING_TUNING.snow_sky_exposure_gain, _snow_brighten)
	_apply_sky_exposure(amount)
	var tint: float = _overcast_fog_tint_strength * amount
	var fog_color: Color = applied_theme.fog_color.lerp(_overcast_fog_tint, tint)
	fog_color = fog_color.lerp(_wfog_tint, _wfog_tint_strength * _wfog_amount)
	environment.fog_light_color = fog_color
	_apply_weather_fog(applied_theme)
	var fog_material: FogMaterial = _fog_volume.material as FogMaterial if _fog_volume != null else null
	if fog_material != null:
		fog_material.albedo = fog_color
	if light_path.is_empty():
		return
	var light: DirectionalLight3D = get_node_or_null(light_path) as DirectionalLight3D
	if light != null:
		light.light_energy = applied_theme.light_energy * lerpf(1.0, _overcast_light_scale, amount) * _sun_cloud_scale


## Bontago-mp0.127: the sun scale clouds cover it by (1 = clear). Rewrites only the light.
func set_sun_cloud_scale(scale: float) -> void:
	scale = clampf(scale, 0.0, 1.0)
	if is_equal_approx(scale, _sun_cloud_scale):
		return
	_sun_cloud_scale = scale
	if _overcast_theme != null:
		_apply_overcast(_overcast_theme)


func sun_cloud_scale() -> float:
	return _sun_cloud_scale


## Unit direction toward the sun (ZERO until a cycle phase was applied) and daylight 0..1.
func sun_direction() -> Vector3:
	return _sun_direction


func daylight() -> float:
	return _daylight


## Mean cloud drift speed (m/s) of the live theme at the current wind strength (calm 1x,
## storm_speed_mult at full storm), the speed the cloud shadows follow.
func cloud_drift_speed_mps() -> float:
	var live: SkyThemeDef = _cycle_theme if _cycle_theme != null else theme
	if live == null:
		return 0.0
	return absf(live.cloud_drift_speed_min_mps + live.cloud_drift_speed_max_mps) * 0.5 * _cloud_drift.speed_mult


## Bontago-mp0.92: the one cloud wind (puffs, sun occlusion and CloudShadows all read it).
func cloud_drift() -> CloudDriftState:
	return _cloud_drift


## Unit ground wind (x, z) the clouds currently drift along.
func cloud_wind_dir() -> Vector2:
	return _cloud_drift.heading


## The storm's live wind heading (StormPresentation pushes it); the clouds ease onto it as the
## storm blend rises and back to the calm heading as it falls.
func set_cloud_storm_wind(direction: Vector2) -> void:
	_cloud_drift.set_storm_wind(direction)


## Advances the shared cloud wind by `delta` and hands its integral to the puffs (also the test seam).
func _step_cloud_drift(delta: float) -> void:
	_cloud_drift.step(delta, _storm_amount)
	if _cloud_sea != null:
		_cloud_sea.set_drift_offset(_cloud_drift.offset)


## Bontago-mp0.130: aerial perspective, sun scatter and height fog from the theme.
func _apply_fog_extras(applied_theme: SkyThemeDef) -> void:
	if is_inside_tree():
		WeatherFogShader.set_ambient(applied_theme.haze_strength, applied_theme.haze_begin_m,
			applied_theme.haze_end_m, environment.fog_light_color, get_tree())
	environment.fog_aerial_perspective = clampf(applied_theme.fog_aerial_perspective + _wfog_aerial_add * _wfog_amount, 0.0, 1.0)
	environment.fog_sun_scatter = applied_theme.fog_sun_scatter
	environment.fog_height = applied_theme.fog_height_m
	environment.fog_height_density = applied_theme.fog_height_density


func _apply_weather_fog(applied_theme: SkyThemeDef) -> void:
	_apply_fog_extras(applied_theme)
	if not _wfog_base_captured:
		_wfog_base_captured = true
		_wfog_base_mode = environment.fog_mode
		_wfog_base_begin = environment.fog_depth_begin
		_wfog_base_end = environment.fog_depth_end
		_wfog_base_curve = environment.fog_depth_curve
	var amount: float = _wfog_amount
	environment.fog_sky_affect = clampf(applied_theme.fog_sky_affect + _wfog_sky_affect_add * amount, 0.0, 1.0)
	if amount <= 0.0:
		environment.fog_mode = _wfog_base_mode as Environment.FogMode
		environment.fog_depth_begin = _wfog_base_begin
		environment.fog_depth_end = _wfog_base_end
		environment.fog_depth_curve = _wfog_base_curve
		environment.fog_density = applied_theme.fog_density
		return
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_depth_begin = _wfog_depth_begin_m
	environment.fog_depth_end = _wfog_depth_end_m
	environment.fog_depth_curve = 1.0
	# In DEPTH mode fog_density is the maximum opacity reached at fog_depth_end.
	environment.fog_density = clampf(_wfog_max_opacity * amount, 0.0, 1.0)


func _apply_sky_exposure(amount: float) -> void:
	var active: ShaderMaterial = null
	if environment.sky != null:
		active = environment.sky.sky_material as ShaderMaterial
	if active != null and not _overcast_sky_bases.has(active) and active.get_shader_parameter(SKY_EXPOSURE_UNIFORM) is float:
		_overcast_sky_bases[active] = float(active.get_shader_parameter(SKY_EXPOSURE_UNIFORM))
	for key: Variant in _overcast_sky_bases.keys():
		var material: ShaderMaterial = key as ShaderMaterial
		var base: float = float(_overcast_sky_bases[key])
		material.set_shader_parameter(SKY_EXPOSURE_UNIFORM, base * lerpf(1.0, _overcast_exposure_scale, amount) if material == active else base)
