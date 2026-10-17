class_name FogPresentation
extends WeatherPresentation
## Stylised cel fog, presentation only on every peer. There is
## no geometry: the ramped intensity is pushed into the Skybox (which owns the
## Environment, see Skybox.set_weather_fog) as DEPTH fog that only starts
## depth_begin_m from the camera (near blocks keep full colour), plus a cool
## tint and sky wash, and into the disc overlay, which applies the same fog
## itself (its shader opts out of Environment fog). Intensity 0 (or leaving the
## tree: weather stopped, match ended) restores the theme's own fog. The Low
## graphics preset uses a lower maximum opacity.
## Tunables: config/weather/fog.tres (FogTuning).

const TUNING: FogTuning = preload("res://config/weather/fog.tres")


func is_reduced() -> bool:
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
	var opacity: float = TUNING.max_opacity * (TUNING.low_preset_opacity if is_reduced() else 1.0)
	var color: Color = TUNING.fog_color
	for node: Node in tree.get_nodes_in_group(Skybox.OVERCAST_GROUP):
		var skybox: Skybox = node as Skybox
		skybox.set_weather_fog(amount, opacity, TUNING.depth_begin_m, TUNING.depth_end_m,
			TUNING.fog_color, TUNING.fog_tint_strength, TUNING.sky_affect)
		color = skybox.weather_fog_color()
	# Scenery shaders that opt out of Environment fog (cloud puffs, distant
	# birds, fireflies) fade by the same distance rule, so farther means foggier.
	WeatherFogShader.set_state(amount, opacity, TUNING.depth_begin_m, TUNING.depth_end_m, color, tree)
	# The disc opts out of Environment fog; it fogs itself the same way.
	for node: Node in tree.get_nodes_in_group(TerritoryOverlay.WET_GROUP):
		var overlay: TerritoryOverlay = node as TerritoryOverlay
		overlay.set_weather_fog(amount, opacity, TUNING.depth_begin_m, TUNING.depth_end_m, color)
