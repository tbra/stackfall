extends GutTest
## "at night lets add an aurora borealis effect to the
## sky": the aurora borealis curtains of the night sky. game/sky/Skybox.gd writes the
## `aurora_visibility` uniform (night x weather keep x theme switch x graphics preset) and
## the look uniforms from SkyThemeDef.aurora_*; the shaders only draw what that says, so the
## day / night / weather / preset behaviour is checked on the uniforms, like test_sky_moon.gd.

const NIGHT_PHASE: float = 0.75
const NOON_PHASE: float = 0.25
var _original_preset_id: StringName


func before_each() -> void:
	_original_preset_id = Settings.current_graphics_preset().id
	Settings.set_graphics_preset(&"high")
	# these tests check the per-night fade, so every night shows it here;
	# the per-night roll itself is covered by test_sky_aurora_nights.gd.


func after_each() -> void:
	Settings.set_graphics_preset(_original_preset_id)


func _wired_skybox() -> Skybox:
	var environment: Environment = Environment.new()
	environment.sky = Sky.new()
	environment.sky.sky_material = ProceduralSkyMaterial.new()
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.environment = environment
	skybox.theme = SkyThemeDef.new()
	add_child_autofree(skybox)
	# The facade owns a private copy of the sky definition, so the always-shown night is set on it.
	skybox.sky_def.aurora_night_chance = 1.0
	return skybox


func _cycle_skybox() -> Skybox:
	var skybox: Skybox = _wired_skybox()
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.CYCLE
	skybox.configure_match_sky(config)
	return skybox


func _param(skybox: Skybox, parameter: StringName) -> Variant:
	return (skybox.environment.sky.sky_material as ShaderMaterial).get_shader_parameter(parameter)


func _visibility(skybox: Skybox) -> float:
	return float(_param(skybox, &"aurora_visibility"))


func test_a_live_theme_edit_reaches_the_shader() -> void:
	var skybox: Skybox = _cycle_skybox()
	skybox.set_cycle_phase(NIGHT_PHASE)
	skybox.sky_def.aurora_intensity = 1.7
	skybox.sky_def.aurora_color_low = Color(0.9, 0.2, 0.3)
	skybox.refresh_sky_def()
	skybox.set_cycle_phase(NIGHT_PHASE + 0.01)
	assert_almost_eq(float(_param(skybox, &"aurora_intensity")), 1.7, 0.0001)
	assert_eq(_param(skybox, &"aurora_color_low"), Color(0.9, 0.2, 0.3))


func test_aurora_is_off_by_day_and_full_at_midnight() -> void:
	var skybox: Skybox = _cycle_skybox()
	skybox.set_cycle_phase(NOON_PHASE)
	assert_almost_eq(_visibility(skybox), 0.0, 0.0001, "no aurora at noon")
	skybox.set_cycle_phase(NIGHT_PHASE)
	assert_almost_eq(_visibility(skybox), 1.0, 0.0001, "full aurora at midnight")


func test_a_locked_night_shows_the_aurora_and_a_locked_day_does_not() -> void:
	var skybox: Skybox = _wired_skybox()
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.NIGHT
	config.resolve_sky_theme(0)
	skybox.configure_match_sky(config)
	assert_almost_eq(_visibility(skybox), 1.0, 0.0001, "the lobby's Night option")
	config.sky_theme_mode = MatchConfig.SkyThemeMode.DAY
	config.resolve_sky_theme(0)
	skybox.configure_match_sky(config)
	assert_almost_eq(_visibility(skybox), 0.0, 0.0001, "the lobby's Sunset option")


func test_the_low_preset_gates_the_aurora_live() -> void:
	var skybox: Skybox = _cycle_skybox()
	skybox.set_cycle_phase(NIGHT_PHASE)
	assert_almost_eq(_visibility(skybox), 1.0, 0.0001, "high shows it")
	Settings.set_graphics_preset(&"low")
	assert_almost_eq(_visibility(skybox), 0.0, 0.0001, "an already-built sky drops it when the preset goes Low")
	Settings.set_graphics_preset(&"medium")
	assert_almost_eq(_visibility(skybox), 1.0, 0.0001, "and brings it back on Medium")
	Settings.set_graphics_preset(&"low")
	var fresh: Skybox = _cycle_skybox()
	fresh.set_cycle_phase(NIGHT_PHASE)
	assert_almost_eq(_visibility(fresh), 0.0, 0.0001, "a sky built under Low never shows it")


func test_storm_hides_the_aurora() -> void:
	var skybox: Skybox = _cycle_skybox()
	skybox.set_cycle_phase(NIGHT_PHASE)
	skybox.set_storm_sky(1.0, Skybox.load_theme("storm"))
	skybox.flush_weather()
	assert_almost_eq(_visibility(skybox), 0.0, 0.0001, "a full storm covers the aurora like the moon")
	skybox.set_storm_sky(0.0, null)
	skybox.flush_weather()
	assert_almost_eq(_visibility(skybox), 1.0, 0.0001, "clear again")


func test_overcast_dims_the_aurora() -> void:
	var skybox: Skybox = _cycle_skybox()
	skybox.set_cycle_phase(NIGHT_PHASE)
	skybox.set_overcast(1.0, 0.5, 0.6, 0.4, Color(0.4, 0.4, 0.5), 0.5)
	skybox.flush_weather()
	var dimmed: float = _visibility(skybox)
	assert_true(dimmed > 0.0 and dimmed < 1.0, "overcast keeps some aurora, not all (got %s)" % dimmed)
	skybox.set_overcast(0.0, 1.0, 1.0, 1.0, Color.WHITE, 0.0)
	skybox.flush_weather()
	assert_almost_eq(_visibility(skybox), 1.0, 0.0001, "clear sky again")


## Review fix (2): a start edge above the full edge must not invert the fade (a reversed
## smoothstep would be bright at noon and dark at midnight).
func test_swapped_fade_edges_still_fade_in_with_the_night() -> void:
	var def: SkyThemeDef = SkyThemeDef.new()
	def.aurora_start_night_mix = 0.9
	def.aurora_full_night_mix = 0.3
	assert_almost_eq(def.aurora_night_strength(0.0), 0.0, 0.0001, "none by day")
	assert_almost_eq(def.aurora_night_strength(0.2), 0.0, 0.0001, "none below the lower edge")
	var middle: float = def.aurora_night_strength(0.6)
	assert_true(middle > 0.0 and middle < 1.0, "partial between the edges (got %s)" % middle)
	assert_almost_eq(def.aurora_night_strength(1.0), 1.0, 0.0001, "full at night")
	var ordered: SkyThemeDef = SkyThemeDef.new()
	ordered.aurora_start_night_mix = 0.3
	ordered.aurora_full_night_mix = 0.9
	for night: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		assert_almost_eq(def.aurora_night_strength(night), ordered.aurora_night_strength(night), 0.0001, "same fade at night mix %s" % night)
	def.aurora_start_night_mix = 0.5
	def.aurora_full_night_mix = 0.5
	assert_true(is_equal_approx(def.aurora_night_strength(0.2), 0.0) and is_equal_approx(def.aurora_night_strength(0.8), 1.0), "equal edges are a hard step, not NaN")

