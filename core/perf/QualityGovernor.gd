class_name QualityGovernor
extends RefCounted
## Bontago-1pi.11.37: pure rules of the opt-in adaptive quality governor (no scene
## tree). A level 0..max_level() counts how many expensive visuals are shed, cheapest
## visual loss first:
##   1 particle budget, 2 weather density, 3 disc mirror,
##   4 shadow distance + cascades, 5 volumetric fog, 6 3D render scale (optional).
## evaluate() is fed one low-rate sample (mean frame ms, awake block count) and moves
## the level one step at a time: down after a sustained stress, back up only after a
## longer sustained recovery below a stricter band (hysteresis). apply() builds the
## effective preset on a duplicate; the stored preset is never written.

const LEVEL_PARTICLES: int = 1
const LEVEL_WEATHER: int = 2
const LEVEL_MIRROR: int = 3
const LEVEL_SHADOWS: int = 4
const LEVEL_FOG: int = 5
const LEVEL_RENDER_SCALE: int = 6

var config: QualityGovernorConfig = null
var level: int = 0
var _stress_s: float = 0.0
var _calm_s: float = 0.0


func _init(governor_config: QualityGovernorConfig = null) -> void:
	config = governor_config if governor_config != null else QualityGovernorConfig.new()


func max_level() -> int:
	return LEVEL_RENDER_SCALE if config.render_scale_step_enabled else LEVEL_FOG


func reset() -> void:
	level = 0
	_stress_s = 0.0
	_calm_s = 0.0


func is_stressed(frame_ms: float, awake: int) -> bool:
	return frame_ms > config.target_frame_ms or awake >= config.awake_high


func is_calm(frame_ms: float, awake: int) -> bool:
	return frame_ms < config.target_frame_ms * config.recover_frame_ratio and awake <= config.awake_settled


## One sample covering `dt_s` seconds. Returns true when `level` changed. A sample in
## the band between stressed and calm holds the level and restarts both timers.
func evaluate(frame_ms: float, awake: int, dt_s: float) -> bool:
	if is_stressed(frame_ms, awake):
		_calm_s = 0.0
		_stress_s += dt_s
		if _stress_s >= config.shed_delay_s and level < max_level():
			level += 1
			_stress_s = 0.0
			return true
	elif is_calm(frame_ms, awake):
		_stress_s = 0.0
		_calm_s += dt_s
		if _calm_s >= config.restore_delay_s and level > 0:
			level -= 1
			_calm_s = 0.0
			return true
	else:
		_stress_s = 0.0
		_calm_s = 0.0
	return false


## `base` untouched; at level 0 it is returned as is, otherwise a duplicate with the
## first `at_level` steps applied.
static func apply(base: GraphicsPreset, at_level: int, cfg: QualityGovernorConfig) -> GraphicsPreset:
	if base == null or at_level <= 0 or cfg == null:
		return base
	var out: GraphicsPreset = base.duplicate() as GraphicsPreset
	if at_level >= LEVEL_PARTICLES:
		out.particle_budget_scale = minf(out.particle_budget_scale, cfg.shed_particle_budget_scale)
	if at_level >= LEVEL_WEATHER:
		out.weather_density_scale = minf(out.weather_density_scale, cfg.shed_weather_density_scale)
	if at_level >= LEVEL_MIRROR:
		out.mirror_enabled = false
	if at_level >= LEVEL_SHADOWS:
		out.sun_shadow_mode = mini(out.sun_shadow_mode, cfg.shed_shadow_mode)
		out.sun_shadow_max_distance = minf(out.sun_shadow_max_distance, cfg.shed_shadow_max_distance_m)
	if at_level >= LEVEL_FOG:
		out.volumetric_fog_enabled = false
	if at_level >= LEVEL_RENDER_SCALE and cfg.render_scale_step_enabled:
		out.render_scale_3d = minf(out.render_scale_3d, cfg.shed_render_scale)
	return out
