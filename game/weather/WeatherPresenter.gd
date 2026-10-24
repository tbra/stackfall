class_name WeatherPresenter
extends Node3D
## Client/host presentation of the active weather set:
## instances each active weather's presentation scene and feeds it the ramped
## intensity, purely from Events. It owns no physics and no authority; it is
## fed identically on the host and on a client.

var _instances: Dictionary = {}
var _defs: Dictionary = {}
var _scene_cache: Dictionary = {}
## overhead cloud layer (and storm sky) driven by the same
## replicated intensities as the per-weather presentations.
var _ceiling: CloudCeiling = null


func _ready() -> void:
	_ceiling = CloudCeiling.new()
	_ceiling.name = "CloudCeiling"
	_ceiling.skybox_source = _find_skyboxes
	add_child(_ceiling)
	for def: WeatherTuning in WeatherTuning.load_all():
		_defs[def.id] = def
	Events.weather_started.connect(_on_started)
	Events.weather_stopped.connect(_on_stopped)
	Events.weather_intensity_changed.connect(_on_intensity_changed)
	Events.match_scope_reset.connect(clear_now)


func _exit_tree() -> void:
	if Events.match_scope_reset.is_connected(clear_now):
		Events.match_scope_reset.disconnect(clear_now)


## The one place weather crosses from this autoload-built node into the scene
## that owns the sky.
# DECISION: a group lookup, not a node path: this presenter is built under the
# MatchNet autoload while the Skybox lives in Main and is replaced when Main
# reloads, so a held reference would go stale. Children get this as a Callable.
func _find_skyboxes() -> Array[Skybox]:
	var found: Array[Skybox] = []
	var tree: SceneTree = get_tree() if is_inside_tree() else (Engine.get_main_loop() as SceneTree)
	if tree == null:
		return found
	for node: Node in tree.get_nodes_in_group(Skybox.OVERCAST_GROUP):
		found.append(node as Skybox)
	return found


func presentation_for(weather_id: StringName) -> WeatherPresentation:
	var node: Variant = _instances.get(weather_id)
	return node as WeatherPresentation if is_instance_valid(node) else null


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
	var presentation: WeatherPresentation = node as WeatherPresentation
	if presentation != null:
		presentation.skybox_source = _find_skyboxes
	add_child(node)
	_instances[weather_id] = node
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


## Also run by Events.match_scope_reset at every world build and teardown: back to a freshly
## launched presenter. The cloud ceiling snaps clear (no fade into the next match)
## and the shared weather-fog statics return to their launch defaults. Idempotent.
## DECISION: live presentations are left alone. MatchWeather.reset()
## ends the event on every state change that precedes a reset, and weather_stopped
## (_on_stopped) releases it; a weather the authority still runs at a reset (the
## tests/unit/match/test_match_restart.gd rain case) keeps presenting instead of vanishing
## from under a running effect; only its ceiling target comes back with the next
## intensity change.
func clear_now() -> void:
	if _ceiling != null:
		_ceiling.snap_clear()
	WeatherFogShader.reset_to_launch(get_tree() if is_inside_tree() else null, false)
