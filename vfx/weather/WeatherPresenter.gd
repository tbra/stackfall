class_name WeatherPresenter
extends Node3D
## Client/host presentation of the active weather set (Bontago-22y.10):
## instances each active weather's presentation scene and feeds it the ramped
## intensity, purely from Events. It owns no physics and no authority; it is
## fed identically on the host and on a client.

var _instances: Dictionary = {}
var _defs: Dictionary = {}
var _scene_cache: Dictionary = {}
## Bontago-mp0.19: overhead cloud layer (and storm sky) driven by the same
## replicated intensities as the per-weather presentations.
var _ceiling: CloudCeiling = null


func _ready() -> void:
	_ceiling = CloudCeiling.new()
	_ceiling.name = "CloudCeiling"
	add_child(_ceiling)
	for def: WeatherTuning in WeatherTuning.load_all():
		_defs[def.id] = def
	Events.weather_started.connect(_on_started)
	Events.weather_stopped.connect(_on_stopped)
	Events.weather_intensity_changed.connect(_on_intensity_changed)


## Test seam: replace the registry the presenter resolves scenes from.
func set_defs(defs: Array[WeatherTuning]) -> void:
	_defs.clear()
	for def: WeatherTuning in defs:
		_defs[def.id] = def


func presentation_for(weather_id: StringName) -> WeatherPresentation:
	var node: Variant = _instances.get(weather_id)
	return node as WeatherPresentation if is_instance_valid(node) else null


func cloud_ceiling() -> CloudCeiling:
	return _ceiling


func active_count() -> int:
	return _instances.size()


func _on_started(weather_id: StringName) -> void:
	if _ceiling != null:
		_ceiling.set_weather_intensity(weather_id, 0.0)
	if _instances.has(weather_id):
		return
	var def: WeatherTuning = _defs.get(weather_id) as WeatherTuning
	if def == null or def.presentation_scene == "":
		return
	var scene: PackedScene = _scene_cache.get(def.presentation_scene) as PackedScene
	if scene == null:
		scene = load(def.presentation_scene) as PackedScene
		_scene_cache[def.presentation_scene] = scene
	if scene == null:
		return
	var node: Node = scene.instantiate()
	add_child(node)
	_instances[weather_id] = node
	var presentation: WeatherPresentation = node as WeatherPresentation
	if presentation != null:
		presentation.set_intensity(0.0)


func _on_stopped(weather_id: StringName) -> void:
	if _ceiling != null:
		_ceiling.set_weather_intensity(weather_id, 0.0)
	var node: Variant = _instances.get(weather_id)
	_instances.erase(weather_id)
	if is_instance_valid(node):
		(node as Node).queue_free()


func _on_intensity_changed(weather_id: StringName, intensity: float) -> void:
	if _ceiling != null:
		_ceiling.set_weather_intensity(weather_id, intensity)
	var presentation: WeatherPresentation = presentation_for(weather_id)
	if presentation != null:
		presentation.set_intensity(intensity)
