class_name CloudCeiling
extends Node
## Bontago-mp0.19 / mp0.29: drives the overcast puff layer above the disc while
## it rains, snows or storms (the disc floats above a cloud sea, so precipitation
## needs clouds overhead). The layer itself is the cloud sea's own puff field
## (vfx/CloudSea.gd: same mesh, shader, noise and CloudLighting), duplicated high
## above the disc and always present; this node only fades the shared overcast
## (its lighting) with the replicated weather intensities WeatherPresenter feeds in, so every peer renders the same, and
## publishes the shared overcast and the storm sky blend (Skybox.set_storm_sky).
## Tunables: config/weather/ceiling.tres (WeatherCeilingTuning).

const TUNING: WeatherCeilingTuning = preload("res://config/weather/ceiling.tres")

var tuning: WeatherCeilingTuning = TUNING
var _targets: Dictionary = {}
var _amount: float = 0.0
var _storm_amount: float = 0.0
## Shared overcast (rain/snow/storm each at their own tuned amount), faded like
## the puff layer and published to every Skybox so all cloud layers grade together.
var _overcast: float = 0.0
var _pushed_overcast: float = -1.0
var _brighten: float = 0.0
var _pushed_brighten: float = -1.0
var _storm_theme: SkyThemeDef = null
## Cached Skybox lookups (refreshed whenever the storm value changes).
var _skyboxes: Array[Skybox] = []
var _pushed_storm: float = -1.0


func _ready() -> void:
	Events.match_scope_reset.connect(snap_clear)


func _exit_tree() -> void:
	if Events.match_scope_reset.is_connected(snap_clear):
		Events.match_scope_reset.disconnect(snap_clear)
	_amount = 0.0
	_overcast = 0.0
	_brighten = 0.0
	_push_storm(0.0)


## Bontago-1pi.46 (docs/MATCH_RESET_AUDIT.md G2; Events.match_scope_reset runs this at
## every world build and teardown): drops every active weather request and the
## fades in flight, and pushes "clear" to the skyboxes now. Without it a match that
## starts right after a storm / rain one (Replay, quick re-host, sandbox) opens
## overcast and storm-tinted and fades out over `fade_out_s`. Idempotent.
func snap_clear() -> void:
	_targets.clear()
	_amount = 0.0
	_storm_amount = 0.0
	_overcast = 0.0
	_brighten = 0.0
	_pushed_brighten = -1.0
	# Forget what was pushed so _push_storm() cannot treat "0 again" as settled and
	# skip a skybox that was dirtied meanwhile; it also refreshes the group lookup.
	_pushed_storm = -1.0
	_pushed_overcast = -1.0
	_skyboxes.clear()
	_push_storm(0.0)


## Weather `weather_id` now has `intensity` (0 on stop).
func set_weather_intensity(weather_id: StringName, intensity: float) -> void:
	if not tuning.weather_ids.has(weather_id):
		return
	if intensity <= 0.0:
		_targets.erase(weather_id)
	else:
		_targets[weather_id] = clampf(intensity, 0.0, 1.0)


func target_amount() -> float:
	var best: float = 0.0
	for value: Variant in _targets.values():
		best = maxf(best, float(value))
	return best


func target_storm() -> float:
	var best: float = 0.0
	for weather_id: Variant in _targets.keys():
		best = maxf(best, tuning.sky_blend_for(weather_id as StringName, float(_targets[weather_id])))
	return best


## Snow brightening target (0..1): the snow intensity, unless a rain or storm sky is up.
func target_brighten() -> float:
	return float(_targets.get(&"snow", 0.0)) * (1.0 - clampf(target_storm(), 0.0, 1.0))


## Overcast the active weathers drive right now (the strongest one wins).
func target_overcast() -> float:
	var best: float = 0.0
	for weather_id: Variant in _targets.keys():
		best = maxf(best, tuning.overcast_for(weather_id as StringName, float(_targets[weather_id])))
	return best


func brighten() -> float:
	return _brighten


func overcast() -> float:
	return _overcast


## Weather intensity fade (0..1): 0 in clear weather. Drives precipitation, not cloud presence.
func amount() -> float:
	return _amount


func storm_amount() -> float:
	return _storm_amount


## Advances the fades by `delta` (also the test seam).
func step(delta: float) -> void:
	var target: float = target_amount()
	var fade_s: float = tuning.fade_in_s if target > _amount else tuning.fade_out_s
	_amount = move_toward(_amount, target, delta / maxf(fade_s, 0.001))
	var storm_target: float = target_storm()
	var storm_s: float = tuning.fade_in_s if storm_target > _storm_amount else tuning.fade_out_s
	_storm_amount = move_toward(_storm_amount, storm_target, delta / maxf(storm_s, 0.001))
	var overcast_target: float = target_overcast()
	var overcast_s: float = tuning.fade_in_s if overcast_target > _overcast else tuning.fade_out_s
	_overcast = move_toward(_overcast, overcast_target, delta / maxf(overcast_s, 0.001))
	var bright_target: float = target_brighten()
	var bright_s: float = tuning.fade_in_s if bright_target > _brighten else tuning.fade_out_s
	_brighten = move_toward(_brighten, bright_target, delta / maxf(bright_s, 0.001))
	_push_storm(_storm_amount)


func _process(delta: float) -> void:
	# Idle early-out: nothing to fade or push.
	if _amount <= 0.0 and _storm_amount <= 0.0 and _overcast <= 0.0 and _brighten <= 0.0 and _targets.is_empty():
		return
	step(delta)


func _push_storm(value: float) -> void:
	var settled: bool = is_equal_approx(value, _pushed_storm) and _overcast == _pushed_overcast \
			and _brighten == _pushed_brighten
	if settled and not _skyboxes.is_empty():
		return
	var tree: SceneTree = get_tree() if is_inside_tree() else (Engine.get_main_loop() as SceneTree)
	if tree == null:
		return
	if value > 0.0 and _storm_theme == null:
		_storm_theme = Skybox.load_theme(tuning.storm_theme_id)
	if _skyboxes.is_empty() or not is_equal_approx(value, _pushed_storm):
		_skyboxes.clear()
		for node: Node in tree.get_nodes_in_group(Skybox.OVERCAST_GROUP):
			_skyboxes.append(node as Skybox)
	_pushed_storm = value
	var cloud_changed: bool = _overcast != _pushed_overcast
	_pushed_overcast = _overcast
	var bright_changed: bool = _brighten != _pushed_brighten
	_pushed_brighten = _brighten
	for skybox: Skybox in _skyboxes:
		if is_instance_valid(skybox):
			skybox.set_storm_sky(value, _storm_theme)
			if cloud_changed:
				skybox.set_weather_cloud_overcast(_overcast)
			if bright_changed:
				skybox.set_snow_brighten(_brighten)
