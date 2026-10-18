class_name SkyReflections
extends RefCounted
## Reflection probe sizing/retrigger, the probe interval stepping, SSR/SSAO on the Environment
## and the radiance tick cadence. Every dependency is injected through bind() and the call
## parameters: no node paths, groups or autoload reach-ins.

## Probe cull mask: everything but the disc and the cloud/rain layers, so the probe never
## captures the disc's own reflection.
const PROBE_CULL_MASK: int = 0xFFFFF & ~TerritoryOverlay.DISC_LAYER_BIT & ~CloudSea.RENDER_LAYER_BIT & ~RainPresentation.RENDER_LAYER_BIT
## The probe box sits this far below the disc plane (m).
const PROBE_GROUND_CLEARANCE_M: float = 4.0
## Nudge (m) that re-renders an UPDATE_ONCE probe in place.
const PROBE_RETRIGGER_NUDGE_M: float = 0.001
## Lowest radiance rate accepted; guards the division.
const MIN_RADIANCE_HZ: float = 0.001

## Bench hook: while true, step() never reports a radiance tick (the accumulator still runs).
var frozen: bool = false

var _environment: Environment = null
var _probe: ReflectionProbe = null
var _registry: BlockRegistry = null
var _visuals: TerritoryVisuals = null
var _radiance: SkyRadianceConfig = null

var _probe_mode: int = GraphicsPreset.ReflectionProbeMode.ALWAYS
var _probe_interval_s: float = 0.5
var _probe_elapsed_s: float = 0.0
var _probe_seen_revision: int = -1
var _probe_nudged: bool = false
var _radiance_accum_s: float = 0.0
var _disc_radius_m: float = MapDef.RADIUS_LARGE
var _preset: GraphicsPreset = null


func bind(environment: Environment, probe: ReflectionProbe, registry: BlockRegistry,
		visuals: TerritoryVisuals, radiance: SkyRadianceConfig) -> void:
	_environment = environment
	_probe = probe
	_registry = registry
	_visuals = visuals
	_radiance = radiance


## The probe strategy in force: OFF when the scene-level switch is off, ALWAYS when the dev
## override forces it, else the preset's choice (INTERVAL when no preset is known).
static func effective_probe_mode(tuning: TerritoryVisuals, preset: GraphicsPreset) -> int:
	if tuning == null or not tuning.reflection_probe_enabled:
		return GraphicsPreset.ReflectionProbeMode.OFF
	if tuning.reflection_probe_update_always:
		return GraphicsPreset.ReflectionProbeMode.ALWAYS
	if preset == null:
		return GraphicsPreset.ReflectionProbeMode.INTERVAL
	return preset.reflection_probe_mode


## Sizes and enables the probe for a disc of `disc_radius_m` under `preset`. No-op when no
## probe or visuals were bound.
func configure_probe(disc_radius_m: float, preset: GraphicsPreset) -> void:
	_disc_radius_m = disc_radius_m
	_preset = preset
	if _visuals == null or _probe == null:
		return
	_probe_mode = effective_probe_mode(_visuals, preset)
	_probe_interval_s = preset.reflection_probe_interval_s if preset != null else _probe_interval_s
	_probe.visible = _probe_mode != GraphicsPreset.ReflectionProbeMode.OFF
	_probe.update_mode = (
		ReflectionProbe.UPDATE_ALWAYS if _probe_mode == GraphicsPreset.ReflectionProbeMode.ALWAYS
		else ReflectionProbe.UPDATE_ONCE
	)
	_probe_nudged = false
	_probe_elapsed_s = 0.0
	var half_width: float = disc_radius_m + _visuals.reflection_probe_margin_m
	var height: float = _visuals.reflection_probe_height_m
	_probe.size = Vector3(half_width * 2.0, height, half_width * 2.0)
	_probe.position = Vector3(0.0, height * 0.5 - PROBE_GROUND_CLEARANCE_M, 0.0)
	# Box-corrected reflections keep the mirrored blocks in place as the camera orbits.
	_probe.box_projection = true
	_probe.cull_mask = PROBE_CULL_MASK


## The only SSR/SSAO writer. SSR needs the dev switch (`visuals.ssr_enabled`) AND the preset;
## SSAO follows `visuals` only. DECISION: the dev switch is a real kill switch; shipped visuals
## have it on, so the result equals the preset value. A null preset leaves it to `visuals`.
func configure_ssr(preset: GraphicsPreset) -> void:
	if _visuals == null or _environment == null:
		return
	_environment.ssr_enabled = _visuals.ssr_enabled and (preset == null or preset.ssr_enabled)
	_environment.ssr_max_steps = _visuals.ssr_max_steps
	_environment.ssr_fade_in = _visuals.ssr_fade_in
	_environment.ssr_fade_out = _visuals.ssr_fade_out
	_environment.ssr_depth_tolerance = _visuals.ssr_depth_tolerance
	_environment.ssao_enabled = _visuals.ssao_enabled
	_environment.ssao_radius = _visuals.ssao_radius
	_environment.ssao_intensity = _visuals.ssao_intensity
	_environment.ssao_power = _visuals.ssao_power
	_environment.ssao_detail = _visuals.ssao_detail
	_environment.ssao_horizon = _visuals.ssao_horizon
	_environment.ssao_sharpness = _visuals.ssao_sharpness
	_environment.ssao_light_affect = _visuals.ssao_light_affect
	_environment.ssao_ao_channel_affect = _visuals.ssao_ao_channel_affect


## REALTIME sky radiance while the cycle runs, QUALITY while locked. No-op without a sky.
func set_running(running: bool) -> void:
	if _environment == null or _environment.sky == null:
		return
	_environment.sky.process_mode = Sky.PROCESS_MODE_REALTIME if running else Sky.PROCESS_MODE_QUALITY


## Advances the probe interval (INTERVAL mode re-renders once when the block layout changed)
## and the radiance accumulator; true when a radiance tick is due (never while `frozen`).
func step(delta: float) -> bool:
	_step_probe_interval(delta)
	if _radiance == null:
		return false
	_radiance_accum_s += delta
	var interval: float = 1.0 / maxf(_radiance.radiance_hz, MIN_RADIANCE_HZ)
	if _radiance_accum_s < interval:
		return false
	_radiance_accum_s = minf(_radiance_accum_s - interval, interval)
	return not frozen


## Re-configures the probe (last disc radius and preset) and toggles it so an UPDATE_ONCE probe
## re-captures the (new) sky.
func refresh_capture() -> void:
	configure_probe(_disc_radius_m, _preset)
	if _probe != null and _probe.visible:
		_probe.visible = false
		_probe.visible = true


## Re-renders the (UPDATE_ONCE) probe in place by nudging it; see PROBE_RETRIGGER_NUDGE_M.
func retrigger_probe() -> void:
	if _probe == null or not _probe.visible or _probe.update_mode != ReflectionProbe.UPDATE_ONCE:
		return
	_probe_nudged = not _probe_nudged
	_probe.position.y += PROBE_RETRIGGER_NUDGE_M if _probe_nudged else -PROBE_RETRIGGER_NUDGE_M


func _step_probe_interval(delta: float) -> void:
	if _probe_mode != GraphicsPreset.ReflectionProbeMode.INTERVAL or _registry == null:
		return
	_probe_elapsed_s += delta
	if _probe_elapsed_s < _probe_interval_s:
		return
	_probe_elapsed_s = 0.0
	var revision: int = _registry.territory_revision()
	if revision == _probe_seen_revision:
		return
	_probe_seen_revision = revision
	retrigger_probe()
