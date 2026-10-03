extends GutTest
## Bontago-59o.18 (C1b): core/SkyPalette.gd, the dawn -> sunset day palette blend of the
## sky cycle (docs/SKY_CYCLE_DEFAULT_PLAN.md s2). Pure rules; the Skybox wiring
## (morning = dawn palette, sunset lock = sunset palette) is in test_sky_themes.gd.

const DEFAULT_WINDOW: Vector4 = Vector4(0.30, 0.46, 0.90, 0.98)
const CYCLE_SHADER: String = "res://shaders/sunset_clouds.gdshader"


func _themed(seed_value: float) -> SkyThemeDef:
	# A theme whose every blended field is a distinct value derived from seed_value.
	var theme: SkyThemeDef = SkyThemeDef.new()
	for field: StringName in SkyPalette.THEME_COLORS:
		theme.set(field, Color(seed_value, seed_value * 0.5, 1.0 - seed_value, 1.0))
	for field: StringName in SkyPalette.THEME_SCALARS:
		theme.set(field, seed_value * 2.0 + 0.25)
	var sky: ShaderMaterial = ShaderMaterial.new()
	for uniform: StringName in SkyPalette.SKY_UNIFORM_COLORS:
		sky.set_shader_parameter(uniform, Color(seed_value, 0.2, 0.4, 1.0))
	sky.set_shader_parameter(&"exposure", seed_value + 1.0)
	theme.sky_material = sky
	var puffs: ShaderMaterial = ShaderMaterial.new()
	for uniform: StringName in SkyPalette.PUFF_UNIFORM_COLORS:
		puffs.set_shader_parameter(uniform, Color(0.1, seed_value, 0.7, 1.0))
	puffs.set_shader_parameter(&"exposure", seed_value + 1.0)
	theme.cloud_puff_material = puffs
	return theme


func _color_param(material: Material, uniform: StringName) -> Color:
	return (material as ShaderMaterial).get_shader_parameter(uniform) as Color


# --- dusk_weight -----------------------------------------------------------

func test_dusk_weight_is_zero_by_day_and_one_from_sunset_through_the_night() -> void:
	# The window is a Vector4 (32-bit components), so the literal edge phases are
	# compared with a tolerance; the window's own edge values are exact.
	for phase: float in [0.0, 0.03, 0.10, 0.25, 0.30]:
		assert_almost_eq(SkyPalette.dusk_weight(phase, DEFAULT_WINDOW), 0.0, 0.000001, "morning/noon phase %s is the dawn palette" % phase)
	for phase: float in [0.46, 0.47, 0.5, 0.75, 0.90]:
		assert_almost_eq(SkyPalette.dusk_weight(phase, DEFAULT_WINDOW), 1.0, 0.000001, "phase %s is the sunset palette" % phase)
	for phase: float in [0.98, 0.99, 1.0]:
		assert_almost_eq(SkyPalette.dusk_weight(phase, DEFAULT_WINDOW), 0.0, 0.000001, "phase %s is back to the dawn palette" % phase)
	assert_eq(SkyPalette.dusk_weight(DEFAULT_WINDOW.x, DEFAULT_WINDOW), 0.0, "exactly dawn at the window start")
	assert_eq(SkyPalette.dusk_weight(DEFAULT_WINDOW.y, DEFAULT_WINDOW), 1.0, "exactly sunset at the rise end")
	assert_eq(SkyPalette.dusk_weight(DEFAULT_WINDOW.z, DEFAULT_WINDOW), 1.0, "still sunset at the fall start")
	assert_eq(SkyPalette.dusk_weight(DEFAULT_WINDOW.w, DEFAULT_WINDOW), 0.0, "exactly dawn again at the fall end")
	assert_eq(SkyPalette.dusk_weight(0.47, DEFAULT_WINDOW), 1.0, "the Sunset lock phase is exactly the sunset palette")
	assert_eq(SkyPalette.dusk_weight(0.03, DEFAULT_WINDOW), 0.0, "the Dawn lock phase is exactly the dawn palette")


func test_dusk_weight_rises_smoothly_on_the_setting_side_and_falls_before_dawn() -> void:
	var previous: float = 0.0
	var phase: float = DEFAULT_WINDOW.x
	while phase <= DEFAULT_WINDOW.y:
		var weight: float = SkyPalette.dusk_weight(phase, DEFAULT_WINDOW)
		assert_gte(weight, previous - 0.000001, "non-decreasing through the rise at %s" % phase)
		previous = weight
		phase += 0.005
	assert_almost_eq(SkyPalette.dusk_weight((DEFAULT_WINDOW.x + DEFAULT_WINDOW.y) * 0.5, DEFAULT_WINDOW), 0.5, 0.0001,
		"a smoothstep is 0.5 at the middle of its window")
	assert_between(SkyPalette.dusk_weight(0.34, DEFAULT_WINDOW), 0.01, 0.49, "eased in, not linear-hard")
	previous = 1.0
	phase = DEFAULT_WINDOW.z
	while phase <= DEFAULT_WINDOW.w:
		var weight: float = SkyPalette.dusk_weight(phase, DEFAULT_WINDOW)
		assert_lte(weight, previous + 0.000001, "non-increasing through the fall at %s" % phase)
		previous = weight
		phase += 0.005
	assert_almost_eq(SkyPalette.dusk_weight((DEFAULT_WINDOW.z + DEFAULT_WINDOW.w) * 0.5, DEFAULT_WINDOW), 0.5, 0.0001)


func test_dusk_weight_stays_in_0_1_and_is_continuous_over_the_whole_cycle_and_its_wrap() -> void:
	var previous: float = SkyPalette.dusk_weight(0.0, DEFAULT_WINDOW)
	for step: int in range(1, 1001):
		var weight: float = SkyPalette.dusk_weight(float(step) / 1000.0, DEFAULT_WINDOW)
		assert_between(weight, 0.0, 1.0)
		assert_lt(absf(weight - previous), 0.06, "no jump between phase steps at %s" % (float(step) / 1000.0))
		previous = weight
	assert_eq(SkyPalette.dusk_weight(1.0, DEFAULT_WINDOW), SkyPalette.dusk_weight(0.0, DEFAULT_WINDOW), "the 1 -> 0 wrap is seamless")


func test_dusk_weight_wraps_phases_outside_0_1() -> void:
	assert_almost_eq(SkyPalette.dusk_weight(1.25, DEFAULT_WINDOW), SkyPalette.dusk_weight(0.25, DEFAULT_WINDOW), 0.000001)
	assert_almost_eq(SkyPalette.dusk_weight(-0.25, DEFAULT_WINDOW), SkyPalette.dusk_weight(0.75, DEFAULT_WINDOW), 0.000001)
	assert_almost_eq(SkyPalette.dusk_weight(2.4, DEFAULT_WINDOW), SkyPalette.dusk_weight(0.4, DEFAULT_WINDOW), 0.000001)


func test_dusk_weight_follows_a_retuned_window_and_survives_a_degenerate_one() -> void:
	var late: Vector4 = Vector4(0.4, 0.5, 0.6, 0.7)
	assert_eq(SkyPalette.dusk_weight(0.39, late), 0.0)
	assert_eq(SkyPalette.dusk_weight(0.55, late), 1.0)
	assert_eq(SkyPalette.dusk_weight(0.75, late), 0.0)
	assert_almost_eq(SkyPalette.dusk_weight(0.45, late), 0.5, 0.0001)
	# An empty or reversed window is a clean step, never NaN.
	for degenerate: Vector4 in [Vector4(0.5, 0.5, 0.9, 0.9), Vector4(0.6, 0.4, 0.95, 0.9), Vector4.ZERO]:
		for phase: float in [0.0, 0.3, 0.5, 0.7, 0.95, 1.0]:
			var weight: float = SkyPalette.dusk_weight(phase, degenerate)
			assert_false(is_nan(weight), "%s at %s" % [degenerate, phase])
			assert_between(weight, 0.0, 1.0)
	assert_eq(SkyPalette.dusk_weight(0.4, Vector4(0.5, 0.5, 0.9, 0.9)), 0.0)
	assert_eq(SkyPalette.dusk_weight(0.7, Vector4(0.5, 0.5, 0.9, 0.9)), 1.0, "an empty rise is a step at its edge")


func test_shipped_default_window_puts_the_palettes_where_the_options_are() -> void:
	var theme: SkyThemeDef = SkyThemeDef.new()
	assert_eq(theme.cycle_dusk_weight_phases, DEFAULT_WINDOW)
	assert_eq(SkyPalette.dusk_weight(theme.cycle_locked_phase_dawn, theme.cycle_dusk_weight_phases), 0.0, "locked Dawn is the dawn palette")
	assert_eq(SkyPalette.dusk_weight(theme.cycle_start_phase, theme.cycle_dusk_weight_phases), 0.0, "a Cycle match opens in the dawn palette")
	assert_eq(SkyPalette.dusk_weight(0.25, theme.cycle_dusk_weight_phases), 0.0, "noon is the dawn palette")
	assert_eq(SkyPalette.dusk_weight(theme.cycle_locked_phase_sunset, theme.cycle_dusk_weight_phases), 1.0, "locked Sunset is the sunset palette")
	assert_eq(SkyPalette.dusk_weight(theme.cycle_locked_phase_night, theme.cycle_dusk_weight_phases), 1.0, "midnight carries the sunset palette (it is mixed away)")


# --- blend -----------------------------------------------------------------

func test_blend_endpoints_are_exactly_the_two_palettes() -> void:
	var a: SkyThemeDef = _themed(0.2)
	var b: SkyThemeDef = _themed(0.9)
	var into: SkyThemeDef = _themed(0.5)
	SkyPalette.blend(into, a, b, 0.0)
	_assert_palette(into, a, "t = 0")
	SkyPalette.blend(into, a, b, 1.0)
	_assert_palette(into, b, "t = 1")
	SkyPalette.blend(into, a, b, -3.0)
	_assert_palette(into, a, "t below 0 clamps")
	SkyPalette.blend(into, a, b, 7.0)
	_assert_palette(into, b, "t above 1 clamps")


func _assert_palette(actual: SkyThemeDef, expected: SkyThemeDef, label: String) -> void:
	for field: StringName in SkyPalette.THEME_COLORS:
		assert_eq(actual.get(field), expected.get(field), "%s: %s" % [label, field])
	for field: StringName in SkyPalette.THEME_SCALARS:
		assert_eq(actual.get(field), expected.get(field), "%s: %s" % [label, field])
	for uniform: StringName in SkyPalette.SKY_UNIFORM_COLORS:
		assert_eq(_color_param(actual.sky_material, uniform), _color_param(expected.sky_material, uniform), "%s: sky %s" % [label, uniform])
	for uniform: StringName in SkyPalette.PUFF_UNIFORM_COLORS:
		assert_eq(_color_param(actual.cloud_puff_material, uniform), _color_param(expected.cloud_puff_material, uniform), "%s: puff %s" % [label, uniform])


func test_blend_midpoint_is_the_linear_mix_of_every_field() -> void:
	var a: SkyThemeDef = _themed(0.2)
	var b: SkyThemeDef = _themed(0.8)
	var into: SkyThemeDef = _themed(0.5)
	SkyPalette.blend(into, a, b, 0.25)
	for field: StringName in SkyPalette.THEME_COLORS:
		var expected: Color = (a.get(field) as Color).lerp(b.get(field) as Color, 0.25)
		assert_true((into.get(field) as Color).is_equal_approx(expected), "colour %s" % field)
	for field: StringName in SkyPalette.THEME_SCALARS:
		assert_almost_eq(float(into.get(field)), lerpf(float(a.get(field)), float(b.get(field)), 0.25), 0.00001, "scalar %s" % field)
	for uniform: StringName in SkyPalette.SKY_UNIFORM_COLORS:
		var expected_sky: Color = _color_param(a.sky_material, uniform).lerp(_color_param(b.sky_material, uniform), 0.25)
		assert_true(_color_param(into.sky_material, uniform).is_equal_approx(expected_sky), "sky %s" % uniform)
	for uniform: StringName in SkyPalette.PUFF_UNIFORM_COLORS:
		var expected_puff: Color = _color_param(a.cloud_puff_material, uniform).lerp(_color_param(b.cloud_puff_material, uniform), 0.25)
		assert_true(_color_param(into.cloud_puff_material, uniform).is_equal_approx(expected_puff), "puff %s" % uniform)


func test_blend_writes_only_the_palette_and_never_the_sources() -> void:
	var a: SkyThemeDef = _themed(0.2)
	var b: SkyThemeDef = _themed(0.9)
	var into: SkyThemeDef = _themed(0.5)
	into.light_rotation_deg = Vector3(-33.0, 12.0, 0.0)
	into.cloud_flat_base = 0.77
	into.cycle_length_seconds = 123.0
	(into.sky_material as ShaderMaterial).set_shader_parameter(&"sun_direction", Vector3(0.0, 1.0, 0.0))
	(into.sky_material as ShaderMaterial).set_shader_parameter(&"cycle_night_mix", 0.6)
	var a_zenith: Color = a.proc_zenith_color
	var b_lit: Color = _color_param(b.cloud_puff_material, &"lit_color")
	SkyPalette.blend(into, a, b, 0.5)
	assert_eq(into.light_rotation_deg, Vector3(-33.0, 12.0, 0.0), "the cycle owns the light direction")
	assert_eq(into.cloud_flat_base, 0.77, "structure is not palette")
	assert_eq(into.cycle_length_seconds, 123.0)
	var sky: ShaderMaterial = into.sky_material as ShaderMaterial
	assert_eq(sky.get_shader_parameter(&"sun_direction"), Vector3(0.0, 1.0, 0.0), "sun direction is not palette")
	assert_eq(sky.get_shader_parameter(&"cycle_night_mix"), 0.6, "the night mix is not palette")
	assert_eq(sky.get_shader_parameter(&"exposure"), 1.5, "exposure is structure, not palette")
	assert_eq(a.proc_zenith_color, a_zenith, "sources are read-only")
	assert_eq(_color_param(b.cloud_puff_material, &"lit_color"), b_lit)
	assert_ne(into.sky_material, a.sky_material, "fixture: into owns its materials")


func test_blend_tolerates_missing_materials_and_null_themes() -> void:
	var a: SkyThemeDef = _themed(0.2)
	var b: SkyThemeDef = _themed(0.9)
	var into: SkyThemeDef = _themed(0.5)
	into.cloud_puff_material = null
	SkyPalette.blend(into, a, b, 0.5)
	assert_true(into.proc_zenith_color.is_equal_approx(a.proc_zenith_color.lerp(b.proc_zenith_color, 0.5)), "the theme fields still blend")
	b.sky_material = null
	var sky_before: Color = _color_param(into.sky_material, &"cloud_lit_color")
	SkyPalette.blend(into, a, b, 0.5)
	assert_eq(_color_param(into.sky_material, &"cloud_lit_color"), sky_before, "no source sky material: the uniforms are left alone")
	SkyPalette.blend(null, a, b, 0.5)
	SkyPalette.blend(into, null, b, 0.5)
	SkyPalette.blend(into, a, null, 0.5)
	pass_test("null themes are a no-op")


func test_blend_skips_a_uniform_a_material_never_set() -> void:
	var a: SkyThemeDef = _themed(0.2)
	var b: SkyThemeDef = _themed(0.9)
	var into: SkyThemeDef = _themed(0.5)
	var untouched: Color = _color_param(into.sky_material, &"sun_halo_color")
	(a.sky_material as ShaderMaterial).set_shader_parameter(&"sun_halo_color", null)
	SkyPalette.blend(into, a, b, 0.5)
	assert_eq(_color_param(into.sky_material, &"sun_halo_color"), untouched, "an unset source uniform leaves the target's value")
	assert_true(_color_param(into.sky_material, &"sun_ray_color").is_equal_approx(
		_color_param(a.sky_material, &"sun_ray_color").lerp(_color_param(b.sky_material, &"sun_ray_color"), 0.5)), "the others still blend")


func test_mix_helpers_hit_their_endpoints_exactly() -> void:
	var a: Color = Color(0.123, 0.456, 0.789, 1.0)
	var b: Color = Color(0.987, 0.654, 0.321, 0.5)
	assert_eq(SkyPalette.mix_color(a, b, 0.0), a)
	assert_eq(SkyPalette.mix_color(a, b, 1.0), b)
	assert_eq(SkyPalette.mix_color(a, b, -1.0), a)
	assert_eq(SkyPalette.mix_color(a, b, 2.0), b)
	assert_true(SkyPalette.mix_color(a, b, 0.5).is_equal_approx(a.lerp(b, 0.5)))
	assert_eq(SkyPalette.mix_scalar(0.3, 0.9, 0.0), 0.3)
	assert_eq(SkyPalette.mix_scalar(0.3, 0.9, 1.0), 0.9)
	assert_almost_eq(SkyPalette.mix_scalar(0.3, 0.9, 0.5), 0.6, 0.00001)


# --- the field lists name real SkyThemeDef properties / shader uniforms -------

func test_every_listed_field_is_a_real_typed_property_of_sky_theme_def() -> void:
	var theme: SkyThemeDef = SkyThemeDef.new()
	var types: Dictionary = {}
	for property: Dictionary in theme.get_property_list():
		types[StringName(property["name"])] = int(property["type"])
	for field: StringName in SkyPalette.THEME_COLORS:
		assert_eq(types.get(field, -1), TYPE_COLOR, "%s is a Color property" % field)
	for field: StringName in SkyPalette.THEME_SCALARS:
		assert_eq(types.get(field, -1), TYPE_FLOAT, "%s is a float property" % field)


func test_every_listed_uniform_exists_in_the_shaders_and_in_the_shipped_themes() -> void:
	var sky_source: String = FileAccess.get_file_as_string(CYCLE_SHADER)
	for uniform: StringName in SkyPalette.SKY_UNIFORM_COLORS:
		assert_true(sky_source.contains("uniform vec3 %s " % uniform) or sky_source.contains("uniform vec4 %s " % uniform),
			"%s is a colour uniform of the cycle sky shader" % uniform)
	var puff_source: String = FileAccess.get_file_as_string("res://shaders/cloud_puffs.gdshader")
	for uniform: StringName in SkyPalette.PUFF_UNIFORM_COLORS:
		assert_true(puff_source.contains("uniform vec3 %s " % uniform) or puff_source.contains("uniform vec4 %s " % uniform),
			"%s is a colour uniform of the puff shader" % uniform)
	for theme_id: String in ["dawn", "sunset"]:
		var shipped: SkyThemeDef = Skybox.load_theme(theme_id)
		for uniform: StringName in SkyPalette.SKY_UNIFORM_COLORS:
			assert_true((shipped.sky_material as ShaderMaterial).get_shader_parameter(uniform) is Color, "%s sky %s" % [theme_id, uniform])
		for uniform: StringName in SkyPalette.PUFF_UNIFORM_COLORS:
			assert_true((shipped.cloud_puff_material as ShaderMaterial).get_shader_parameter(uniform) is Color, "%s puff %s" % [theme_id, uniform])


func test_shipped_dawn_and_sunset_blend_to_their_own_palettes_at_the_ends() -> void:
	var dawn: SkyThemeDef = Skybox.load_theme("dawn")
	var sunset: SkyThemeDef = Skybox.load_theme("sunset")
	assert_ne(dawn.proc_zenith_color, sunset.proc_zenith_color, "fixture: the palettes differ")
	var into: SkyThemeDef = sunset.duplicate(true) as SkyThemeDef
	into.sky_material = sunset.sky_material.duplicate() as Material
	into.cloud_puff_material = sunset.cloud_puff_material.duplicate() as Material
	SkyPalette.blend(into, dawn, sunset, 0.0)
	_assert_palette(into, dawn, "dawn end")
	SkyPalette.blend(into, dawn, sunset, 1.0)
	_assert_palette(into, sunset, "sunset end")
	SkyPalette.blend(into, dawn, sunset, 0.5)
	assert_true(into.proc_zenith_color.is_equal_approx(dawn.proc_zenith_color.lerp(sunset.proc_zenith_color, 0.5)))
	assert_eq(sunset.proc_zenith_color, Skybox.load_theme("sunset").proc_zenith_color, "the shipped resource was not written")
