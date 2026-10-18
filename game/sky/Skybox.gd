class_name Skybox
extends Node3D
## Sky presentation facade (spec 1.10). Pure wiring: it owns no sky maths and no writer logic.
##   - `sky_def` (SkyCycleDef) is the one description of the sky; SkyEvaluator turns it into
##     SkyFrames in three cached stages (A tick, B storm, C weather), each behind a dirty flag.
##   - SkyCycleClock owns the phase; SkyWeatherState holds the presenters' requests.
##   - SkyDomeWriter, SkyEnvironmentWriter, CloudSea.apply_frame and SkyAmbientLife write the
##     result; SkyReflections owns the probe, SSR and the radiance cadence.
## Weather setters only store state and set a dirty bit. `_process` runs after the presenters
## (process_priority) and calls flush_weather() once per frame; every accessor that reads
## written state flushes on demand. Stage A (keyframes) runs only at a radiance tick, a lock,
## a cycle start, a preset change or a definition refresh, so a locked sky with no weather
## writes nothing to the sky material after its first frame.
##
## Transitional shims (removed with the F4 and test migration): `theme`, `apply_theme`,
## `refresh_cycle_sources`, `set_theme_by_id`, `load_theme` and `list_available_themes` keep the
## old SkyThemeDef-based F4 panel and tests working; they re-derive `sky_def` from the live
## theme resources through SkyThemeMigration.

@export var config: SkyboxConfig = preload("res://config/sky/skybox_config.tres")
## The sky description. Defaults to the shipped cycle; an F4 edit goes through refresh_sky_def().
@export var sky_def: SkyCycleDef = preload("res://config/sky/sky_cycle.tres")
## Transitional: the SkyThemeDef the old API exposed. After a cycle starts it is a shallow copy
## of the sunset theme pointing at the live sky material (see _publish_theme_shim).
@export var theme: SkyThemeDef = preload("res://config/sky/themes/sunset.tres")
## The live Environment Main.tscn's WorldEnvironment displays; null in fixtures that only care
## about the cycle state (every Environment/sky write is then skipped).
@export var environment: Environment = null
## The scene's DirectionalLight3D; empty in fixtures.
@export var light_path: NodePath = NodePath(""):
	set(value):
		light_path = value
		_rebind_light()
## Field and block registry for the ambient life, wired in Main.tscn; empty in fixtures.
@export var field_path: NodePath = NodePath("")
@export var registry_path: NodePath = NodePath("")
## ReflectionProbe over the disc, wired in Main.tscn; empty in fixtures.
@export var reflection_probe_path: NodePath = NodePath("")
@export var visuals: TerritoryVisuals = preload("res://config/territory/territory_visuals.tres")

## Probe cull mask (the disc, cloud puffs and rain streaks excluded).
const PROBE_CULL_MASK: int = SkyReflections.PROBE_CULL_MASK
const THEME_DIR: String = "res://config/sky/themes"
const DEFAULT_THEME_ID: String = "sunset"
## SkyboxConfig.theme_name value that means "the running day/night cycle".
const CYCLE_THEME_ID: String = "cycle"
const CYCLE_NIGHT_THEME_ID: String = "night"
const CYCLE_DAWN_THEME_ID: String = "dawn"
const SKY_TIME_GLOBAL: StringName = SkyDomeWriter.SKY_TIME_GLOBAL
const SKY_SUN_DIR_GLOBAL: StringName = SkyDomeWriter.SKY_SUN_DIR_GLOBAL
const SKY_MOON_DIR_GLOBAL: StringName = SkyDomeWriter.SKY_MOON_DIR_GLOBAL
## F4 tuning-panel live-apply group and the weather presenters' lookup group.
const TUNING_GROUP: StringName = &"tuning_skybox"
const OVERCAST_GROUP: StringName = &"weather_skybox"
const CEILING_TUNING: WeatherCeilingTuning = preload("res://config/weather/ceiling.tres")
## DECISION: an ordering constant, not a tunable. Processing last (after the presenters at the
## default priority) lets the once-per-frame flush show this frame's weather requests.
const PROCESS_PRIORITY: int = 100
const SECONDS_PER_MSEC: float = 0.001

var radiance_config: SkyRadianceConfig = preload("res://config/sky/sky_radiance_config.tres")
## Counts disc writes and keeps the last sun direction written (tests / probes).
var disc_publish_count: int = 0
var last_disc_sun_direction: Vector3 = Vector3.ZERO
## Test-visible evaluation counters: stage A, B and C runs and sky-material uniform writes.
var tick_runs: int = 0
var storm_runs: int = 0
var weather_runs: int = 0
var sky_material_writes: int = 0

var _clock: SkyCycleClock = SkyCycleClock.new()
var _weather: SkyWeatherState = SkyWeatherState.new()
var _tick_frame: SkyFrame = SkyFrame.new()
var _storm_frame: SkyFrame = SkyFrame.new()
var _out_frame: SkyFrame = SkyFrame.new()
var _has_tick: bool = false
var _tick_fresh: bool = false
var _dirty_b: bool = false
var _dirty_c: bool = false
var _cycle_phase_last: float = -1.0
var _cycle_clock_s: float = 0.0
var _sun_direction: Vector3 = Vector3.ZERO
var _daylight: float = 1.0
var _variation_seed: int = SkyVariation.DEFAULT_SEED
var _aurora_preset_on: bool = true
var _preset: GraphicsPreset = null
var _flare_stormed: bool = false
var _env_bound: bool = false
var _storm_exposure_scale: float = 1.0

var _dome: SkyDomeWriter = SkyDomeWriter.new()
## The day theme whose static look (view offsets, overhead/cards layers) the dome material carries.
var _look_theme: SkyThemeDef = null
var _env_writer: SkyEnvironmentWriter = SkyEnvironmentWriter.new()
var _reflections: SkyReflections = SkyReflections.new()
var _life: SkyAmbientLife = SkyAmbientLife.new()
var _cloud_sea: CloudSea = null
var _fog_volume: FogVolume = null
var _cloud_drift: CloudDriftState = CloudDriftState.new()
var _cloud_lighting: CloudLighting = CloudLighting.new()
## Mirror of SkyAmbientLife.is_night(); cleared whenever the ambient life is reconfigured.
var _cycle_life_is_night: bool = false
var _sky_clock_s: float = float(Time.get_ticks_msec()) * SECONDS_PER_MSEC
var _pinned_sky_time_s: float = -1.0
var _pinned_cloud_drift_s: float = -1.0
var _overlay_cache: Dictionary[SkyThemeDef, SkyOverlayDef] = {}

var _launch_captured: bool = false
var _launch_lock_phase: float = -1.0
var _launch_theme_name: String = ""
var _launch_cycle: bool = false


func _init() -> void:
	process_priority = PROCESS_PRIORITY


func _ready() -> void:
	add_to_group(TUNING_GROUP)
	add_to_group(OVERCAST_GROUP)
	_weather.tuning = CEILING_TUNING
	# DECISION: a per-Skybox copy (sub-resources stay shared and are never written), so a live
	# cycle-length edit never leaks into the shipped resource other Skyboxes and tests read.
	if sky_def != null:
		sky_def = sky_def.duplicate() as SkyCycleDef
	_preset = Settings.current_graphics_preset()
	_aurora_preset_on = _preset == null or _preset.aurora_enabled
	var field_node: Field = get_node_or_null(field_path) as Field if not field_path.is_empty() else null
	var registry_node: BlockRegistry = get_node_or_null(registry_path) as BlockRegistry if not registry_path.is_empty() else null
	var probe: ReflectionProbe = get_node_or_null(reflection_probe_path) as ReflectionProbe if not reflection_probe_path.is_empty() else null
	var light: DirectionalLight3D = get_node_or_null(light_path) as DirectionalLight3D if not light_path.is_empty() else null
	_reflections.bind(environment, probe, registry_node, visuals, radiance_config)
	_reflections.configure_probe(_largest_disc_radius(), _preset)
	# DECISION: boot writes the dev-visuals SSR value only (null preset), as today: the preset's
	# SSR choice then arrives through apply_graphics_preset (Main), so the shipped result is the same.
	_reflections.configure_ssr(null)
	if sky_def == null:
		return
	_env_writer.bind(environment, light)
	_env_bound = true
	_env_writer.set_deck_visible(_preset)
	_fog_volume = _env_writer.spawn_deck(self, sky_def)
	_cloud_sea = CloudSea.new()
	_cloud_sea.name = "CloudSea"
	_cloud_sea.lighting = _cloud_lighting
	_cloud_sea.upper_tuning = CEILING_TUNING
	add_child(_cloud_sea)
	_life.build(self, field_node, registry_node)
	_launch_theme_name = config.theme_name
	_launch_cycle = config.theme_name == CYCLE_THEME_ID
	_launch_lock_phase = _launch_lock_for(config.theme_name)
	_launch_captured = true
	Settings.graphics_preset_changed.connect(_on_graphics_preset_changed)
	Events.match_scope_reset.connect(reset_to_launch)
	# Boot (and every teardown) is the cycle locked at SkyboxConfig.theme_name, or running for "cycle".
	_start_cycle_at(_shared_clock_s(), _launch_lock_phase, -1.0)


func _exit_tree() -> void:
	if Settings.graphics_preset_changed.is_connected(_on_graphics_preset_changed):
		Settings.graphics_preset_changed.disconnect(_on_graphics_preset_changed)
	if Events.match_scope_reset.is_connected(reset_to_launch):
		Events.match_scope_reset.disconnect(reset_to_launch)


func _process(delta: float) -> void:
	var radiance_due: bool = _reflections.step(delta)
	_step_cloud_drift(delta)
	if _pinned_sky_time_s >= 0.0:
		_sky_clock_s = _pinned_sky_time_s
	else:
		_sky_clock_s += delta
	_publish_globals(true)
	# The sky material is written at radiance_hz (a write re-renders the radiance octmap); the
	# phase comes from the exact shared clock at each write so host and client agree. A locked
	# sky is never ticked.
	if radiance_due and _clock.is_active() and _clock.locked_phase() < 0.0:
		_advance_cycle(_shared_clock_s())
	flush_weather()


## The one place the shared match clock is read. DECISION: kept as the facade's existing
## MatchContext read (the clock source needs a Main.tscn wire to inject, which this package
## does not own).
func _shared_clock_s() -> float:
	return MatchContext.current().shared_clock_seconds()


## Writes the shader globals every frame: the sky clock and the exact (not tick-stepped) sun and
## moon disc directions. A global lives in the shared buffer, so there is no material dirty.
func _publish_globals(count_frame: bool) -> void:
	var direction: Vector3 = last_disc_sun_direction
	if _clock.is_active() and sky_def != null:
		direction = SkyEvaluator.sun_direction(sky_def, _clock.phase_at(_shared_clock_s()))
		if count_frame:
			disc_publish_count += 1
		last_disc_sun_direction = direction
	var wrap: float = radiance_config.time_wrap_seconds
	_dome.publish_globals(direction, fposmod(_sky_clock_s, wrap))


# --- match / launch ---------------------------------------------------------------------------

## The host-resolved mode is in MatchConfig's match-start RPC; SnapshotSync supplies the shared
## clock. CYCLE runs the cycle from `sky_start_phase`; Sunset, Night, Dawn (and the host's RANDOM
## roll of those) are the same cycle locked at sky_def.locked_phase_for(id).
func configure_match_sky(match_config: MatchConfig) -> void:
	refresh_reflection_capture_config()
	var locked: float = -1.0
	if not match_config.is_sky_cycle_running():
		locked = sky_def.locked_phase_for(match_config.locked_sky_id())
	# DECISION: the replicated match seed drives the sky variation (host rolls it once per match).
	_variation_seed = SkyVariation.seed_for(match_config.effective_sky_variation_seed())
	_cloud_drift.reset(_variation_seed)
	# DECISION: a match opens its sky at shared clock 0 (SnapshotSync.begin_match() resets the
	# clock right after this call), so the start phase never depends on a stale clock.
	_start_cycle_at(0.0, locked, match_config.sky_start_phase)


## Events.match_scope_reset: returns this long-lived Skybox to a fresh launch (the cycle locked at
## the launch sky id, or running for "cycle"), with no storm, overcast or weather-fog request.
## Idempotent and cheap when the sky is already at launch.
func reset_to_launch() -> void:
	if not _launch_captured:
		return
	var weather_active: bool = _weather.any_active()
	var at_launch: bool = not _launch_cycle and _clock.is_active() and _clock.locked_phase() == _launch_lock_phase \
		and config.theme_name == _launch_theme_name and _variation_seed == SkyVariation.DEFAULT_SEED
	_clear_weather_state()
	if at_launch and not weather_active:
		return
	_variation_seed = SkyVariation.DEFAULT_SEED
	_cloud_drift.reset(_variation_seed)
	config.theme_name = _launch_theme_name
	_start_cycle_at(_shared_clock_s(), _launch_lock_phase, -1.0)


func _clear_weather_state() -> void:
	_weather.clear()
	_dirty_b = true
	_dirty_c = true


func _launch_lock_for(sky_id: String) -> float:
	if sky_id == CYCLE_THEME_ID or sky_def == null:
		return -1.0
	var phase: float = sky_def.locked_phase_for(sky_id)
	return phase if phase >= 0.0 else sky_def.locked_phase_for(DEFAULT_THEME_ID)


## Starts the cycle now (F4 "cycle", boot). `lock_phase` >= 0 freezes it at that phase; a
## running cycle shows `start_phase` (sky_def.cycle_start_phase when < 0) at the clock now.
func start_cycle(lock_phase: float = -1.0, start_phase: float = -1.0) -> void:
	_start_cycle_at(_shared_clock_s(), lock_phase, start_phase)


func _start_cycle_at(clock_seconds: float, lock_phase: float, start_phase: float) -> void:
	if sky_def == null:
		return
	# A fresh sky material per cycle start (as the old duplicate was): nothing a previous match
	# wrote (aurora look, stale uniforms) survives into the next one.
	if sky_def.sky_material != null:
		_dome.bind(environment.sky if environment != null else null, sky_def.sky_material)
	var opening: float = start_phase if start_phase >= 0.0 else sky_def.cycle_start_phase
	_clock.start(clock_seconds, sky_def.cycle_length_seconds, lock_phase, opening)
	_cycle_clock_s = clock_seconds
	_rebuild_ambient(true)
	_push_flare_reset()
	_publish_theme_shim()
	_tick_to(_clock.phase_at(clock_seconds), true)
	flush_weather()
	if _clock.locked_phase() >= 0.0:
		# A locked sky is written once, then its radiance is built to full quality and left alone.
		_reflections.set_running(false)
		refresh_reflection_capture()
	else:
		# DECISION: REALTIME, not INCREMENTAL: one octmap render + cheap fast filter per refresh.
		_reflections.set_running(true)


## Locks the cycle at `phase` (0..1) or, for `phase` < 0, unlocks it so it runs on from the
## locked phase. No-op before a cycle exists.
func set_locked_phase(phase: float) -> void:
	if not _clock.is_active():
		return
	if phase < 0.0:
		if _clock.locked_phase() < 0.0:
			return
		_clock.set_locked(-1.0)
		_reflections.set_running(true)
		return
	_clock.set_locked(phase)
	_tick_to(_clock.locked_phase())
	flush_weather()
	_reflections.set_running(false)
	refresh_reflection_capture()


func locked_phase() -> float:
	return _clock.locked_phase()


func is_cycle_active() -> bool:
	return _clock.is_active()


## The cycle phase last evaluated; -1 when no cycle is active.
func current_cycle_phase() -> float:
	return _cycle_phase_last if _clock.is_active() else -1.0


func variation_seed() -> int:
	return _variation_seed


func cycle_phase_at(clock_seconds: float) -> float:
	return _clock.phase_at(clock_seconds)


func cycle_length_seconds() -> float:
	return _clock.length_s()


## Advances the cycle to the shared clock and writes the result now (tests and probes).
func update_cycle_clock(clock_seconds: float) -> void:
	if not _clock.is_active():
		return
	_advance_cycle(clock_seconds)
	flush_weather()


func _advance_cycle(clock_seconds: float) -> void:
	_cycle_clock_s = clock_seconds
	_tick_to(_clock.advance(clock_seconds, sky_def.cycle_length_seconds))


## Public phase seam (deterministic tests and visual probes): evaluates stage A at `phase`.
func set_cycle_phase(phase: float) -> void:
	if not _clock.is_active():
		return
	if _tick_to(phase):
		flush_weather()


## F4 cycle length: applies to the running cycle and to the definition the next match uses. The
## time of day does not move; only its speed changes.
func set_cycle_length_seconds(seconds: float) -> void:
	if not _clock.is_active():
		return
	var length: float = maxf(seconds, SkyCycleClock.MIN_LENGTH_S)
	sky_def.cycle_length_seconds = length
	_clock.advance(_cycle_clock_s, length)


## Bench hook: while true the running cycle never reports a radiance tick.
func set_cycle_writes_frozen(frozen: bool) -> void:
	_reflections.frozen = frozen


## Capture-only hook (tools/shot_targets.gd): freezes the `sky_time` global and the cloud drift
## offset so two shots of one state are identical. A negative value leaves that clock running.
func set_capture_pin(sky_time_s: float, cloud_drift_s: float) -> void:
	_pinned_sky_time_s = sky_time_s
	_pinned_cloud_drift_s = cloud_drift_s
	if sky_time_s >= 0.0 or cloud_drift_s >= 0.0:
		# A pinned capture uses the fixed default seed so two shots of one state agree.
		_variation_seed = SkyVariation.DEFAULT_SEED
		_cloud_drift.reset(_variation_seed)


# --- evaluation -------------------------------------------------------------------------------

func _overcast_exposure_now() -> float:
	return lerpf(1.0, _weather.overcast_exposure_scale, _weather.overcast_amount)


## Stage A at `phase`. Unless `force`, an unchanged phase is a no-op. True when it ran.
func _tick_to(phase: float, force: bool = false) -> bool:
	phase = fposmod(phase, 1.0)
	if not force and _has_tick and is_equal_approx(phase, _cycle_phase_last):
		return false
	_cycle_phase_last = phase
	SkyEvaluator.evaluate_tick(sky_def, phase, _variation_seed, _clock.night_index(), _aurora_preset_on, _tick_frame)
	tick_runs += 1
	_has_tick = true
	_tick_fresh = true
	_dirty_b = true
	_storm_exposure_scale = _overcast_exposure_now()
	_sun_direction = _tick_frame.sun_direction
	_daylight = _tick_frame.daylight
	return true


## Runs the dirty stages (B, then C) and the writers, at most once each. No-op until a stage A
## frame exists. `_process` calls it once per frame; tests and accessors call it on demand.
func flush_weather() -> void:
	if not _has_tick:
		return
	var tick_ran: bool = _tick_fresh
	var storm_ran: bool = false
	if _dirty_b:
		SkyEvaluator.apply_storm(_tick_frame, _weather.storm_amount, _weather.storm_overlay,
			CEILING_TUNING.storm_flare_off_amount, _storm_frame)
		_dirty_b = false
		_dirty_c = true
		storm_runs += 1
		storm_ran = true
	if not _dirty_c:
		return
	SkyEvaluator.apply_weather(_storm_frame, _weather, _out_frame)
	if _out_frame.storm_amount > 0.0:
		SkyEvaluator.puff_snapshot(sky_def, _out_frame, _out_frame)
	if _out_frame.storm_amount > 0.0:
		# DECISION (parity, quirk Q1 ordering): under a storm the puffs' exposure is the sky exposure
		# when the storm blend last ran (a storm request or a tick), scaled by the overcast in force
		# at THAT call, so a same-frame overcast change reaches the puffs one request later.
		_out_frame.puff_exposure = _tick_frame.exposure * _storm_exposure_scale
	_dirty_c = false
	_tick_fresh = false
	weather_runs += 1
	_write_frame(tick_ran, storm_ran)


func _write_frame(tick_ran: bool, storm_ran: bool) -> void:
	if tick_ran:
		_publish_globals(false)
	_dome.stage(_out_frame)
	sky_material_writes += _dome.flush()
	_env_writer.apply(_out_frame, get_tree() if is_inside_tree() else null)
	if _cloud_sea != null and (tick_ran or storm_ran or _out_frame.storm_amount > 0.0):
		_cloud_sea.apply_frame(_out_frame)
	_publish_cloud_lighting(_out_frame)
	if storm_ran and not tick_ran:
		# A storm request moved the sky between ticks: an UPDATE_ONCE probe would keep the sky it
		# captured earlier (the disc reflects it), so re-capture it now.
		_reflections.retrigger_probe()
	_push_flares(tick_ran, storm_ran)
	if tick_ran:
		_life.update_night(sky_def, _out_frame.night, _preset, _disc_radius_for_ambient_life())
		_cycle_life_is_night = _life.is_night()


## Light wired after _ready (a fixture sets light_path late): rebind the writer and rewrite.
func _rebind_light() -> void:
	if not _env_bound:
		return
	var light: DirectionalLight3D = null
	if not light_path.is_empty() and is_inside_tree():
		light = get_node_or_null(light_path) as DirectionalLight3D
	_env_writer.bind(environment, light)
	if _has_tick:
		_dirty_c = true
		flush_weather()


## The cloud inputs the layers share, published once from the evaluated frame.
func _publish_cloud_lighting(frame: SkyFrame) -> void:
	var changed: bool = _cloud_lighting.publish(frame.puff_shadow_color, frame.puff_mid_color,
		frame.puff_lit_color, frame.puff_rim_color, frame.puff_light_direction, frame.lighting_light_color,
		frame.night, frame.cloud_overcast, frame.storm_amount, frame.weather_dim, frame.weather_desaturate)
	var floor_changed: bool = _cloud_lighting.publish_floor(frame.floor_color, frame.floor_shadow_ratio,
		frame.floor_mid_ratio, frame.sun_effects)
	if (changed or floor_changed) and _cloud_sea != null:
		_cloud_sea.apply_lighting(_cloud_lighting)


func _each_flare(action: Callable) -> void:
	if not is_inside_tree():
		return
	# DECISION: the existing SunFlare group lookup stays (a node path needs a Main.tscn wire);
	# it runs only when a stage reran, never per quiet frame.
	for node: Node in get_tree().get_nodes_in_group(SunFlare.GROUP):
		var flare: SunFlare = node as SunFlare
		if flare != null:
			action.call(flare)


func _push_flare_reset() -> void:
	var weather_scale: float = _cloud_lighting.sun_scale
	_flare_stormed = false
	_each_flare(func(flare: SunFlare) -> void:
		flare.set_theme_enabled(true)
		flare.set_weather_scale(weather_scale))


func _push_flares(tick_ran: bool, storm_ran: bool) -> void:
	var frame: SkyFrame = _out_frame
	var stormed: bool = frame.storm_amount > 0.0
	var restore: bool = _flare_stormed and not stormed
	_flare_stormed = stormed
	_each_flare(func(flare: SunFlare) -> void:
		if restore:
			flare.set_theme_enabled(true)
		if tick_ran or restore:
			flare.set_cycle_sun(frame.sun_direction, frame.daylight)
		if stormed and (storm_ran or tick_ran):
			flare.set_theme_enabled(frame.flare_enabled)
		flare.set_weather_scale(frame.flare_weather_scale))


# --- accessors --------------------------------------------------------------------------------

## The evaluated output frame (tests / probes).
func current_frame() -> SkyFrame:
	flush_weather()
	return _out_frame


## The weather requests currently held (tests / fingerprint).
func weather_state() -> SkyWeatherState:
	return _weather


func sun_direction() -> Vector3:
	flush_weather()
	return _sun_direction


func daylight() -> float:
	flush_weather()
	return _daylight


func cloud_overcast_amount() -> float:
	return _weather.cloud_overcast_amount()


## The fog colour currently in the Environment (the disc's own fog uses it).
func weather_fog_color() -> Color:
	flush_weather()
	return _env_writer.weather_fog_color() if environment != null else _weather.wfog_tint


func cloud_drift_speed_mps() -> float:
	if sky_def == null:
		return 0.0
	return absf(sky_def.cloud_drift_speed_min_mps + sky_def.cloud_drift_speed_max_mps) * 0.5 * _cloud_drift.speed_mult


func cloud_wind_dir() -> Vector2:
	return _cloud_drift.heading


func set_cloud_storm_wind(direction: Vector2) -> void:
	_cloud_drift.set_storm_wind(direction)


func _step_cloud_drift(delta: float) -> void:
	if _pinned_cloud_drift_s >= 0.0:
		_cloud_drift.offset = _cloud_drift.heading * _cloud_drift.speed_mult * _pinned_cloud_drift_s
	else:
		_cloud_drift.step(delta, _weather.storm_amount)
	if _cloud_sea != null:
		_cloud_sea.set_drift_offset(_cloud_drift.offset)


# --- weather requests (state + dirty bit only) --------------------------------------------------

## Storm blend `amount` 0..1 toward `storm_theme`'s look (converted to an overlay, cached per
## theme instance until the next bridge refresh). Transitional signature until the overlay API.
func set_storm_sky(amount: float, storm_theme: SkyThemeDef) -> void:
	var clamped: float = clampf(amount, 0.0, 1.0)
	var overlay: SkyOverlayDef = _overlay_for(storm_theme)
	if is_equal_approx(clamped, _weather.storm_amount) and overlay == _weather.storm_overlay:
		return
	_weather.storm_amount = clamped if overlay != null else 0.0
	_weather.storm_overlay = overlay
	_storm_exposure_scale = _overcast_exposure_now()
	_dirty_b = true


func _overlay_for(storm_theme: SkyThemeDef) -> SkyOverlayDef:
	if storm_theme == null:
		return null
	if not _overlay_cache.has(storm_theme):
		_overlay_cache[storm_theme] = SkyThemeMigration.overlay_from_theme(storm_theme)
	return _overlay_cache[storm_theme]


## Weather overcast: `amount` 0..1 scales light and ambient energy and the sky exposure and tints
## the fog toward `fog_tint`; the *_scale values are the factors reached at amount 1.
func set_overcast(amount: float, light_scale: float, ambient_scale: float, exposure_scale: float, fog_tint: Color, fog_tint_strength: float) -> void:
	var clamped: float = clampf(amount, 0.0, 1.0)
	if clamped == _weather.overcast_amount and light_scale == _weather.overcast_light_scale \
			and ambient_scale == _weather.overcast_ambient_scale and exposure_scale == _weather.overcast_exposure_scale \
			and fog_tint == _weather.overcast_fog_tint and fog_tint_strength == _weather.overcast_fog_tint_strength:
		return
	_weather.overcast_amount = clamped
	_weather.overcast_light_scale = light_scale
	_weather.overcast_ambient_scale = ambient_scale
	_weather.overcast_exposure_scale = exposure_scale
	_weather.overcast_fog_tint = fog_tint
	_weather.overcast_fog_tint_strength = fog_tint_strength
	_dirty_c = true


## The overcast every weather asks of the cloud layers only (CloudCeiling).
func set_weather_cloud_overcast(amount: float) -> void:
	var clamped: float = clampf(amount, 0.0, 1.0)
	if clamped == _weather.weather_cloud_overcast:
		return
	_weather.weather_cloud_overcast = clamped
	_dirty_c = true


## Snow brightens the sky and the clouds by `amount` 0..1; 0 restores exactly.
func set_snow_brighten(amount: float) -> void:
	var clamped: float = clampf(amount, 0.0, 1.0)
	if clamped == _weather.snow_brighten:
		return
	_weather.snow_brighten = clamped
	_dirty_c = true


## Weather fog: `amount` 0..1 switches to DEPTH fog starting `depth_begin_m` from the camera and
## reaching `max_opacity * amount` at `depth_end_m`, tinted toward `tint`.
func set_weather_fog(amount: float, max_opacity: float, depth_begin_m: float, depth_end_m: float, tint: Color, tint_strength: float, sky_affect_add: float = 0.0) -> void:
	var clamped: float = clampf(amount, 0.0, 1.0)
	if clamped == _weather.wfog_amount and max_opacity == _weather.wfog_max_opacity \
			and depth_begin_m == _weather.wfog_depth_begin_m and depth_end_m == _weather.wfog_depth_end_m \
			and tint == _weather.wfog_tint and tint_strength == _weather.wfog_tint_strength \
			and sky_affect_add == _weather.wfog_sky_affect_add:
		return
	_weather.wfog_amount = clamped
	_weather.wfog_max_opacity = max_opacity
	_weather.wfog_depth_begin_m = depth_begin_m
	_weather.wfog_depth_end_m = depth_end_m
	_weather.wfog_tint = tint
	_weather.wfog_tint_strength = tint_strength
	_weather.wfog_sky_affect_add = sky_affect_add
	_dirty_c = true


## The sun scale clouds cover it by (1 = clear); only the light energy changes.
func set_sun_cloud_scale(scale: float) -> void:
	scale = clampf(scale, 0.0, 1.0)
	if is_equal_approx(scale, _weather.sun_cloud_scale):
		return
	_weather.sun_cloud_scale = scale
	_dirty_c = true


# --- ambient life and clouds ------------------------------------------------------------------

## Rebuilds the cloud sea and the ambient life from `sky_def` (never duplicating them). The puffs
## copy their far-fade snapshot (quirk Q3) from the evening key at cycle start, else from the
## live frame. Clears the night flag with the ambient life's own reset.
func _rebuild_ambient(from_cycle_start: bool) -> void:
	var preset: GraphicsPreset = _preset
	if _cloud_sea != null:
		var density: float = preset.cloud_puff_density if preset != null else 1.0
		var subdivisions: int = preset.cloud_puff_subdivisions if preset != null else CloudSea.PUFF_SUBDIVISIONS
		var billboard_m: float = preset.cloud_billboard_distance_m if preset != null else 0.0
		_cloud_sea.upper_low = preset != null and not preset.ambient_life_enabled
		_cloud_sea.disc_radius_m = _largest_disc_radius()
		var source: SkyFrame = _out_frame if (_has_tick and not from_cycle_start) else SkyEvaluator.evening_frame(sky_def)
		var snapshot: SkyFrame = SkyFrame.new()
		SkyEvaluator.puff_snapshot(sky_def, source, snapshot)
		_cloud_sea.configure_cycle(sky_def, snapshot, density, subdivisions, billboard_m)
	_life.configure(sky_def, preset, _disc_radius_for_ambient_life())
	_cycle_life_is_night = false


func _on_graphics_preset_changed(preset: GraphicsPreset) -> void:
	_preset = preset
	_aurora_preset_on = preset == null or preset.aurora_enabled
	_env_writer.set_deck_visible(preset)
	_reflections.configure_probe(_largest_disc_radius(), preset)
	_rebuild_ambient(false)
	# The rebuild reset the puff palette and ambient life; put the current phase back on top.
	if _has_tick:
		_tick_to(_cycle_phase_last, true)
		flush_weather()


## The single entry Main calls when a graphics preset is applied: probe, SSR/SSAO, glow,
## volumetric fog and the deck visibility, each with one owner.
func apply_graphics_preset(preset: GraphicsPreset) -> void:
	_reflections.configure_probe(_largest_disc_radius(), preset)
	_reflections.configure_ssr(preset)
	_env_writer.apply_preset(preset)


## Public re-apply seam the F4 panel calls after a reflection tunable edit.
func refresh_from_visuals() -> void:
	_reflections.configure_probe(_largest_disc_radius(), _preset)
	_reflections.configure_ssr(_preset)


static func effective_probe_mode(tuning: TerritoryVisuals, preset: GraphicsPreset) -> int:
	return SkyReflections.effective_probe_mode(tuning, preset)


func refresh_reflection_capture_config() -> void:
	_reflections.configure_probe(_largest_disc_radius(), _preset)


## Forces the ReflectionProbe to re-capture the (new) sky.
func refresh_reflection_capture() -> void:
	_reflections.configure_probe(_largest_disc_radius(), _preset)
	_reflections.refresh_capture()


## Re-renders the (UPDATE_ONCE) probe in place.
func retrigger_reflection_probe() -> void:
	_reflections.retrigger_probe()


func _largest_disc_radius() -> float:
	if not field_path.is_empty():
		var field_node: Field = get_node_or_null(field_path) as Field
		if field_node != null and field_node.map_definition() != null:
			return maxf(field_node.map_definition().field_radius, MapDef.RADIUS_LARGE)
	return MapDef.RADIUS_LARGE


func _disc_radius_for_ambient_life() -> float:
	if not field_path.is_empty():
		var field_node: Field = get_node_or_null(field_path) as Field
		if field_node != null and field_node.map_definition() != null:
			return field_node.map_definition().field_radius
	return MapDef.RADIUS_MEDIUM


# --- F4 definition refresh and the transitional theme bridge ------------------------------------

## A live edit of `sky_def`: re-evaluates the current phase now and rebuilds the clouds and ambient
## life from it. A lock or a running clock is untouched.
func refresh_sky_def() -> void:
	_overlay_cache.clear()
	_env_writer.sync_deck(sky_def)
	# The puffs' far-fade snapshot restarts from the evening key, as the old rebuild did.
	_rebuild_ambient(true)
	if _has_tick:
		_tick_to(_cycle_phase_last, true)
		flush_weather()


## Transitional bridge (until the F4 panel edits SkyCycleDef): re-derives `sky_def` from the live
## SkyThemeDef resources the panel edits, then refreshes.
func refresh_cycle_sources() -> void:
	_derive_def_from_themes(null)
	refresh_sky_def()


## Transitional: a theme edit or switch re-derives the definition and refreshes. A theme outside
## the shipped sunset/dawn/night trio stands in for the whole day.
func apply_theme(applied_theme: SkyThemeDef) -> void:
	if applied_theme == null:
		return
	_derive_def_from_themes(applied_theme)
	refresh_sky_def()


func _derive_def_from_themes(applied: SkyThemeDef) -> void:
	var sunset: SkyThemeDef = load_theme(DEFAULT_THEME_ID)
	var dawn: SkyThemeDef = load_theme(CYCLE_DAWN_THEME_ID)
	var night: SkyThemeDef = load_theme(CYCLE_NIGHT_THEME_ID)
	if applied != null and applied != sunset and applied != dawn and applied != night:
		sunset = applied
		dawn = applied
	if sunset == null:
		return
	sky_def = SkyThemeMigration.cycle_from_themes(sunset, dawn, night)
	_look_theme = sunset


func _publish_theme_shim() -> void:
	var source: SkyThemeDef = load_theme(DEFAULT_THEME_ID)
	if source == null:
		return
	var shim: SkyThemeDef = source.duplicate(false) as SkyThemeDef
	shim.sky_material = _dome.material()
	shim.sky_look_procedural = true
	shim.procedural_sea_mix = 1.0
	theme = shim


## Loads res://config/sky/themes/<id>.tres, or null if missing (transitional shim).
static func load_theme(theme_id: String) -> SkyThemeDef:
	var path: String = "%s/%s.tres" % [THEME_DIR, theme_id]
	if not ResourceLoader.exists(path):
		return null
	return load(path) as SkyThemeDef


## F4 / probe sky switch: "cycle" runs the cycle, a locked id (sunset, dawn, night) locks it at
## sky_def.locked_phase_for(id). False for an unknown id.
func set_theme_by_id(theme_id: String) -> bool:
	if theme_id == CYCLE_THEME_ID:
		start_cycle()
		config.theme_name = theme_id
		return true
	var phase: float = sky_def.locked_phase_for(theme_id)
	if phase < 0.0:
		return false
	config.theme_name = theme_id
	if _clock.is_active():
		set_locked_phase(phase)
	else:
		start_cycle(phase)
	return true


## Theme ids (file basenames) under THEME_DIR whose resource is a SkyThemeDef, sorted.
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
