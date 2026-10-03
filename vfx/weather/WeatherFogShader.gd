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


## Bontago-1pi.46 (match reset parity): the state as at launch, group refreshed.
## FogPresentation leaves begin / end / color at its tuning values when it fades
## out; they are invisible at strength 0 but a fresh launch has the defaults.
static func reset_to_launch(tree: SceneTree) -> void:
	set_state(1.0, DEFAULT_STRENGTH, DEFAULT_BEGIN_M, DEFAULT_END_M, DEFAULT_COLOR, tree)


static func apply(material: ShaderMaterial) -> void:
	if material == null:
		return
	material.set_shader_parameter(&"wfog_strength", strength)
	material.set_shader_parameter(&"wfog_begin", begin_m)
	material.set_shader_parameter(&"wfog_end", end_m)
	material.set_shader_parameter(&"wfog_color", color)
