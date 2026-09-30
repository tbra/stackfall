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

static var strength: float = 0.0
static var begin_m: float = 25.0
static var end_m: float = 110.0
static var color: Color = Color(0.72, 0.8, 0.88, 1.0)


static func set_state(amount: float, max_strength: float, begin: float, end: float, fog_color: Color, tree: SceneTree) -> void:
	strength = clampf(max_strength * amount, 0.0, 1.0)
	begin_m = begin
	end_m = end
	color = fog_color
	if tree == null:
		return
	for node: Node in tree.get_nodes_in_group(GROUP):
		if node.has_method(&"refresh_weather_fog"):
			node.call(&"refresh_weather_fog")


static func apply(material: ShaderMaterial) -> void:
	if material == null:
		return
	material.set_shader_parameter(&"wfog_strength", strength)
	material.set_shader_parameter(&"wfog_begin", begin_m)
	material.set_shader_parameter(&"wfog_end", end_m)
	material.set_shader_parameter(&"wfog_color", color)
