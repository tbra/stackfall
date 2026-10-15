extends GutTest
## core/sky/SkyPalette.gd, the dawn -> sunset day palette blend of the
## sky cycle. Pure rules; the Skybox wiring
## (morning = dawn palette, sunset lock = sunset palette) is in test_sky_themes.gd.

const DEFAULT_WINDOW: Vector4 = Vector4(0.30, 0.46, 0.90, 0.98)
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


const VARIATION_SWEEP_STEPS: int = 500
const VARIATION_SEEDS: Array[int] = [0, 1, 7, 42, 1234, 99999, 2147483647]


func test_variation_weight_stays_in_unit_range_for_any_seed_channel_and_phase() -> void:
	for seed_value: int in VARIATION_SEEDS:
		for channel: int in [SkyVariation.CHANNEL_EXPOSURE, SkyVariation.CHANNEL_CLOUD_COVERAGE, SkyVariation.CHANNEL_SEA_COVERAGE]:
			for step: int in range(VARIATION_SWEEP_STEPS + 1):
				var value: float = SkyVariation.weight(float(step) / float(VARIATION_SWEEP_STEPS), 3, seed_value, channel)
				assert_between(value, 0.0, 1.0, "seed %s channel %s step %s" % [seed_value, channel, step])


func test_variation_is_a_pure_function_of_seed_and_phase() -> void:
	for step: int in range(0, VARIATION_SWEEP_STEPS, 7):
		var phase: float = float(step) / float(VARIATION_SWEEP_STEPS)
		assert_eq(SkyVariation.weight(phase, 3, 1234, SkyVariation.CHANNEL_EXPOSURE),
			SkyVariation.weight(phase, 3, 1234, SkyVariation.CHANNEL_EXPOSURE), "repeatable at %s" % phase)


func test_variation_seed_for_uses_the_match_seed_and_a_default_for_random() -> void:
	assert_eq(SkyVariation.seed_for(1234), 1234)
	assert_eq(SkyVariation.seed_for(0), 0)
	assert_eq(SkyVariation.seed_for(-1), SkyVariation.DEFAULT_SEED)


func test_variation_values_stay_inside_the_theme_ranges_whatever_the_seed() -> void:
	var theme: SkyThemeDef = SkyThemeDef.new()
	for seed_value: int in VARIATION_SEEDS:
		for step: int in range(VARIATION_SWEEP_STEPS + 1):
			var phase: float = float(step) / float(VARIATION_SWEEP_STEPS)
			assert_between(SkyVariation.exposure_at(theme, phase, seed_value), theme.variation_exposure_min, theme.variation_exposure_max)
			assert_between(SkyVariation.cloud_coverage_at(theme, phase, seed_value), theme.variation_cloud_coverage_min, theme.variation_cloud_coverage_max)
			assert_between(SkyVariation.sea_coverage_at(theme, phase, seed_value), theme.variation_sea_coverage_min, theme.variation_sea_coverage_max)
	theme.variation_exposure_min = 1.2
	theme.variation_exposure_max = 1.2
	assert_eq(SkyVariation.exposure_at(theme, 0.3, 5), 1.2, "a collapsed range is a fixed exposure")

