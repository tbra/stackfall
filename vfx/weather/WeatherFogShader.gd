class_name WeatherFogShader
extends RefCounted
## Bontago-470.3: the weather-fog state shared with every scenery shader that
## opts out of Environment fog (cloud puffs, distant birds, fireflies; the disc
## has its own TerritoryOverlay.set_weather_fog). FogPresentation calls
## set_state(); each such node joins GROUP, calls apply() on its material
## whenever it (re)builds one, and again from refresh_weather_fog() when the
## state changes. The shaders fade by camera distance exactly like the disc:
## nothing before wfog_begin, wfog_strength at wfog_end, toward wfog_color;
## strength 0 is off.

const GROUP: StringName = &"weather_fog_shader"

## Launch values (what a fresh process holds): strength 0 = off, the rest only
## matter once a fog presentation sets them.
const DEFAULT_STRENGTH: float = 0.0
const DEFAULT_BEGIN_M: float = 25.0
const DEFAULT_END_M: float = 110.0
const DEFAULT_COLOR: Color = Color(0.72, 0.8, 0.88, 1.0)

static var strength: float = DEFAULT_STRENGTH
static var begin_m: float = DEFAULT_BEGIN_M
static var end_m: float = DEFAULT_END_M
static var color: Color = DEFAULT_COLOR
## Bontago-mp0.130: the theme's own ambient haze for the same shaders (far cloud
## layers melt into the fog colour even with no Fog weather). The weather values
## above blend in over it by the weather's ramped amount, so a fade-out settles
## on the ambient haze, not on nothing.
static var ambient_strength: float = 0.0
static var ambient_begin_m: float = DEFAULT_BEGIN_M
static var ambient_end_m: float = DEFAULT_END_M
static var ambient_color: Color = DEFAULT_COLOR
static var weather_amount: float = 0.0
static var _weather_strength: float = 0.0
static var _weather_begin_m: float = DEFAULT_BEGIN_M
static var _weather_end_m: float = DEFAULT_END_M
static var _weather_color: Color = DEFAULT_COLOR


static func set_state(amount: float, max_strength: float, begin: float, end: float, fog_color: Color, tree: SceneTree) -> void:
	weather_amount = clampf(amount, 0.0, 1.0)
	_weather_strength = clampf(max_strength, 0.0, 1.0)
	_weather_begin_m = begin
	_weather_end_m = end
	_weather_color = fog_color
	_blend(tree)


## Bontago-mp0.130: the theme's ambient haze (Skybox.apply_theme).
static func set_ambient(haze_strength: float, begin: float, end: float, haze_color: Color, tree: SceneTree) -> void:
	ambient_strength = clampf(haze_strength, 0.0, 1.0)
	ambient_begin_m = begin
	ambient_end_m = end
	ambient_color = haze_color
	_blend(tree)


static func _blend(tree: SceneTree) -> void:
	var w: float = weather_amount
	strength = lerpf(ambient_strength, _weather_strength, w)
	begin_m = lerpf(ambient_begin_m, _weather_begin_m, w)
	end_m = lerpf(ambient_end_m, _weather_end_m, w)
	color = ambient_color.lerp(_weather_color, w)
	if tree == null:
		return
	for node: Node in tree.get_nodes_in_group(GROUP):
		if node.has_method(&"refresh_weather_fog"):
			node.call(&"refresh_weather_fog")


## Bontago-1pi.46 (match reset parity): the state as at launch, group refreshed.
## FogPresentation leaves begin / end / color at its tuning values when it fades
## out; they are invisible at strength 0 but a fresh launch has the defaults.
static func reset_to_launch(tree: SceneTree) -> void:
	ambient_strength = DEFAULT_STRENGTH
	ambient_begin_m = DEFAULT_BEGIN_M
	ambient_end_m = DEFAULT_END_M
	ambient_color = DEFAULT_COLOR
	set_state(1.0, DEFAULT_STRENGTH, DEFAULT_BEGIN_M, DEFAULT_END_M, DEFAULT_COLOR, tree)


static func apply(material: ShaderMaterial) -> void:
	if material == null:
		return
	material.set_shader_parameter(&"wfog_strength", strength)
	material.set_shader_parameter(&"wfog_begin", begin_m)
	material.set_shader_parameter(&"wfog_end", end_m)
	material.set_shader_parameter(&"wfog_color", color)
