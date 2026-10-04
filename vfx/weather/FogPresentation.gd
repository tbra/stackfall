class_name FogPresentation
extends WeatherPresentation
## Bontago-470.3: stylised cel fog, presentation only on every peer. There is
## no geometry: the ramped intensity is pushed into the Skybox (which owns the
## Environment, see Skybox.set_weather_fog) as DEPTH fog that only starts
## depth_begin_m from the camera (near blocks keep full colour), plus a cool
## tint and sky wash, and into the disc overlay, which applies the same fog
## itself (its shader opts out of Environment fog). Intensity 0 (or leaving the
## tree: weather stopped, match ended) restores the theme's own fog. The Low
## graphics preset uses a lower maximum opacity.
## Tunables: config/weather/fog.tres (FogTuning).

const TUNING: FogTuning = preload("res://config/weather/fog.tres")

var _tuning: FogTuning = TUNING
var _reduced_override: int = -1


## Test seam: `reduced` 1 = Low variant, 0 = full, default -1 = ask Settings.
func configure(tuning: FogTuning, reduced: int = -1) -> void:
	_tuning = tuning
	_reduced_override = reduced


func is_reduced() -> bool:
	if _reduced_override >= 0:
		return _reduced_override == 1
	if Engine.get_main_loop() == null:
		return false
	var preset: GraphicsPreset = Settings.current_graphics_preset()
	return preset != null and not preset.ambient_life_enabled


func set_intensity(value: float) -> void:
	super.set_intensity(value)
	_apply_fog(value)


func _exit_tree() -> void:
	_apply_fog(0.0)


func _apply_fog(amount: float) -> void:
	if not is_inside_tree() and amount > 0.0:
		return
	var tree: SceneTree = get_tree() if is_inside_tree() else (Engine.get_main_loop() as SceneTree)
	if tree == null:
		return
	var opacity: float = _tuning.max_opacity * (_tuning.low_preset_opacity if is_reduced() else 1.0)
	var color: Color = _tuning.fog_color
	for node: Node in tree.get_nodes_in_group(Skybox.OVERCAST_GROUP):
		var skybox: Skybox = node as Skybox
		skybox.set_weather_fog(amount, opacity, _tuning.depth_begin_m, _tuning.depth_end_m,
			_tuning.fog_color, _tuning.fog_tint_strength, _tuning.sky_affect, _tuning.aerial_perspective_add)
		color = skybox.weather_fog_color()
	# Scenery shaders that opt out of Environment fog (cloud puffs, distant
	# birds, fireflies) fade by the same distance rule, so farther means foggier.
	WeatherFogShader.set_state(amount, opacity, _tuning.depth_begin_m, _tuning.depth_end_m, color, tree)
	# The disc opts out of Environment fog; it fogs itself the same way.
	for node: Node in tree.get_nodes_in_group(TerritoryOverlay.WET_GROUP):
		(node as TerritoryOverlay).set_weather_fog(amount, opacity, _tuning.depth_begin_m, _tuning.depth_end_m, color)
