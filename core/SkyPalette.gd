class_name SkyPalette
extends RefCounted
## Bontago-59o.18 (C1b, docs/SKY_CYCLE_DEFAULT_PLAN.md s2 "Day palette"): the day half
## of the sky cycle is not one palette. Morning and noon use the dawn.tres palette
## and it fades into the sunset.tres palette on the setting side, by the dusk weight
## below (a smoothstep window per SkyThemeDef.cycle_dusk_weight_phases). Pure rules,
## no scene tree: game/Skybox.gd calls these in set_cycle_phase() before it mixes the
## result toward the night palette.

## SkyThemeDef colour fields the day palette owns. Light direction is not here: the
## cycle owns the sun path. Exposure and cloud coverage are not here either: they are
## structure (and the weather overcast scales the exposure from its own baseline).
const THEME_COLORS: Array[StringName] = [
	&"sky_top_color", &"sky_horizon_color", &"ground_bottom_color", &"ground_horizon_color",
	&"fog_color", &"volumetric_fog_albedo", &"light_color",
	&"proc_zenith_color", &"proc_mid_color", &"proc_horizon_color", &"proc_horizon_glow_color",
	&"proc_sea_color_near", &"proc_sea_color_far",
]
## SkyThemeDef scalar fields tuned together with those colours (light, fog, glow).
const THEME_SCALARS: Array[StringName] = [
	&"fog_density", &"volumetric_fog_density", &"light_energy", &"ambient_energy",
	&"proc_horizon_glow_width", &"proc_sun_glow_strength",
]
## Colour uniforms of the theme's sky ShaderMaterial (sun disc / halo / rays and the
## cloud cel colours the overhead cards and the sea draw with).
const SKY_UNIFORM_COLORS: Array[StringName] = [
	&"sun_core_color", &"sun_halo_color", &"sun_ray_color",
	&"cloud_shadow_color", &"cloud_mid_color", &"cloud_lit_color", &"cloud_rim_color",
]
## Colour uniforms of the theme's cloud puff ShaderMaterial (the four cel tones).
const PUFF_UNIFORM_COLORS: Array[StringName] = [&"shadow_color", &"mid_color", &"lit_color", &"rim_color"]


## 0 = the dawn palette, 1 = the sunset palette, for a cycle `phase` (0..1, 0 dawn,
## 0.25 noon, 0.5 sunset, 0.75 midnight). `window` = (a, b, c, d) =
## SkyThemeDef.cycle_dusk_weight_phases: smoothstep(a, b, phase) * (1 - smoothstep(c, d, phase)).
## Zero through the morning and noon, ramps up on the setting side, holds 1 through
## the night, and returns to 0 before the next dawn. Continuous across the 1 -> 0 wrap.
static func dusk_weight(phase: float, window: Vector4) -> float:
	var wrapped: float = fposmod(phase, 1.0)
	return _window_step(window.x, window.y, wrapped) * (1.0 - _window_step(window.z, window.w, wrapped))


## Writes into `into` the palette `a` fades to `b` by `t` (clamped 0..1; t 0 is exactly
## `a`'s values and t 1 exactly `b`'s): THEME_COLORS / THEME_SCALARS on the theme and
## SKY_UNIFORM_COLORS / PUFF_UNIFORM_COLORS on its sky and puff ShaderMaterials. `into`
## keeps everything else (structure, light direction, night uniforms). A material is
## skipped when `into` or a source lacks it or its uniform, so a theme without a puff
## material (or an unset uniform) is harmless. `into`'s materials are written in place,
## so `into` must own its materials (never share a source theme's: that would edit the
## shipped resource).
static func blend(into: SkyThemeDef, a: SkyThemeDef, b: SkyThemeDef, t: float) -> void:
	if into == null or a == null or b == null:
		return
	var weight: float = clampf(t, 0.0, 1.0)
	for field: StringName in THEME_COLORS:
		into.set(field, mix_color(a.get(field) as Color, b.get(field) as Color, weight))
	for field: StringName in THEME_SCALARS:
		into.set(field, mix_scalar(float(a.get(field)), float(b.get(field)), weight))
	_blend_uniforms(into.sky_material, a.sky_material, b.sky_material, SKY_UNIFORM_COLORS, weight)
	_blend_uniforms(into.cloud_puff_material, a.cloud_puff_material, b.cloud_puff_material, PUFF_UNIFORM_COLORS, weight)


## `a` at weight 0 and `b` at weight 1 exactly (a plain lerp can miss `b` by a float
## rounding step), the linear mix between.
static func mix_color(a: Color, b: Color, weight: float) -> Color:
	if weight <= 0.0:
		return a
	if weight >= 1.0:
		return b
	return a.lerp(b, weight)


static func mix_scalar(a: float, b: float, weight: float) -> float:
	if weight <= 0.0:
		return a
	if weight >= 1.0:
		return b
	return lerpf(a, b, weight)


## smoothstep(from, to, x) that stays a clean 0/1 step when the window is empty or
## reversed (a mis-authored Vector4 must not produce NaN).
static func _window_step(from: float, to: float, x: float) -> float:
	if to <= from:
		return 1.0 if x >= from else 0.0
	return smoothstep(from, to, x)


static func _blend_uniforms(into: Material, a: Material, b: Material, names: Array[StringName], weight: float) -> void:
	var target: ShaderMaterial = into as ShaderMaterial
	var from: ShaderMaterial = a as ShaderMaterial
	var to: ShaderMaterial = b as ShaderMaterial
	if target == null or from == null or to == null:
		return
	for uniform: StringName in names:
		var from_value: Variant = from.get_shader_parameter(uniform)
		var to_value: Variant = to.get_shader_parameter(uniform)
		if from_value is Color and to_value is Color:
			target.set_shader_parameter(uniform, mix_color(from_value as Color, to_value as Color, weight))
