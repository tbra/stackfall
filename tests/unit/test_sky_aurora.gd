extends GutTest
## Bontago-mp0.129 (owner playtest: "at night lets add an aurora borealis effect to the
## sky"): the aurora borealis curtains of the night sky. game/Skybox.gd writes the
## `aurora_visibility` uniform (night x weather keep x theme switch x graphics preset) and
## the look uniforms from SkyThemeDef.aurora_*; the shaders only draw what that says, so the
## day / night / weather / preset behaviour is checked on the uniforms, like test_sky_moon.gd.

const NIGHT_PHASE: float = 0.75
const NOON_PHASE: float = 0.25
## Dusk and dawn phases with a night mix between aurora_start_night_mix and aurora_full_night_mix.
const DUSK_PHASE: float = 0.51
const DAWN_PHASE: float = 0.99
const SUNSET_SHADER: String = "res://shaders/sunset_clouds.gdshader"
const NIGHT_SHADER: String = "res://shaders/night_sky.gdshader"
const INCLUDE_PATH: String = "res://shaders/include/cloud_common.gdshaderinc"

var _original_preset_id: StringName
var _original_chance: float = 0.0


func before_each() -> void:
	_original_preset_id = Settings.current_graphics_preset().id
	Settings.set_graphics_preset(&"high")
	# Bontago-1pi.131: these tests check the per-night fade, so every night shows it here;
	# the per-night roll itself is covered by test_sky_aurora_nights.gd.
	var source: SkyThemeDef = Skybox.load_theme(Skybox.DEFAULT_THEME_ID)
	_original_chance = source.aurora_night_chance
	source.aurora_night_chance = 1.0


func after_each() -> void:
	Skybox.load_theme(Skybox.DEFAULT_THEME_ID).aurora_night_chance = _original_chance
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


func _shader_source(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func test_look_uniforms_come_from_the_theme() -> void:
	var skybox: Skybox = _cycle_skybox()
	skybox.set_cycle_phase(NIGHT_PHASE)
	var def: SkyThemeDef = skybox.theme
	assert_almost_eq(float(_param(skybox, &"aurora_intensity")), def.aurora_intensity, 0.0001)
	assert_almost_eq(float(_param(skybox, &"aurora_speed")), def.aurora_speed, 0.0001)
	assert_almost_eq(float(_param(skybox, &"aurora_base_height")), def.aurora_base_height, 0.0001)
	assert_almost_eq(float(_param(skybox, &"aurora_curtain_height")), def.aurora_curtain_height, 0.0001)
	assert_eq(_param(skybox, &"aurora_color_low"), def.aurora_color_low)
	assert_eq(_param(skybox, &"aurora_color_mid"), def.aurora_color_mid)
	assert_eq(_param(skybox, &"aurora_color_top"), def.aurora_color_top)


func test_a_live_theme_edit_reaches_the_shader() -> void:
	var skybox: Skybox = _cycle_skybox()
	skybox.set_cycle_phase(NIGHT_PHASE)
	skybox.theme.aurora_intensity = 1.7
	skybox.theme.aurora_color_low = Color(0.9, 0.2, 0.3)
	skybox.set_cycle_phase(NIGHT_PHASE + 0.01)
	assert_almost_eq(float(_param(skybox, &"aurora_intensity")), 1.7, 0.0001)
	assert_eq(_param(skybox, &"aurora_color_low"), Color(0.9, 0.2, 0.3))


func test_aurora_is_off_by_day_and_full_at_midnight() -> void:
	var skybox: Skybox = _cycle_skybox()
	skybox.set_cycle_phase(NOON_PHASE)
	assert_almost_eq(_visibility(skybox), 0.0, 0.0001, "no aurora at noon")
	skybox.set_cycle_phase(NIGHT_PHASE)
	assert_almost_eq(_visibility(skybox), 1.0, 0.0001, "full aurora at midnight")


func test_aurora_fades_in_at_dusk_and_out_at_dawn() -> void:
	var skybox: Skybox = _cycle_skybox()
	for phase: float in [DUSK_PHASE, DAWN_PHASE]:
		skybox.set_cycle_phase(phase)
		var fading: float = _visibility(skybox)
		assert_true(fading > 0.0 and fading < 1.0, "partial aurora at phase %s (got %s)" % [phase, fading])
	skybox.set_cycle_phase(0.45)
	assert_almost_eq(_visibility(skybox), 0.0, 0.0001, "none before the sunset")
	skybox.set_cycle_phase(0.05)
	assert_almost_eq(_visibility(skybox), 0.0, 0.0001, "none after the dawn")


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


func test_the_theme_switch_hides_the_aurora() -> void:
	var skybox: Skybox = _cycle_skybox()
	skybox.set_cycle_phase(NIGHT_PHASE)
	skybox.theme.aurora_enabled = false
	skybox.set_cycle_phase(NIGHT_PHASE + 0.01)
	assert_almost_eq(_visibility(skybox), 0.0, 0.0001)
	skybox.theme.aurora_enabled = true
	skybox.set_cycle_phase(NIGHT_PHASE)
	assert_almost_eq(_visibility(skybox), 1.0, 0.0001)


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


func test_preset_resources_carry_the_gate() -> void:
	var low: GraphicsPreset = load("res://config/graphics_presets/low.tres") as GraphicsPreset
	var medium: GraphicsPreset = load("res://config/graphics_presets/medium.tres") as GraphicsPreset
	var high: GraphicsPreset = load("res://config/graphics_presets/high.tres") as GraphicsPreset
	assert_false(low.aurora_enabled, "Low drops the aurora like the other sky extras")
	assert_true(medium.aurora_enabled)
	assert_true(high.aurora_enabled)


func test_storm_hides_the_aurora() -> void:
	var skybox: Skybox = _cycle_skybox()
	skybox.set_cycle_phase(NIGHT_PHASE)
	skybox.set_storm_sky(1.0, Skybox.load_theme("storm"))
	assert_almost_eq(_visibility(skybox), 0.0, 0.0001, "a full storm covers the aurora like the moon")
	skybox.set_storm_sky(0.0, null)
	assert_almost_eq(_visibility(skybox), 1.0, 0.0001, "clear again")


func test_overcast_dims_the_aurora() -> void:
	var skybox: Skybox = _cycle_skybox()
	skybox.set_cycle_phase(NIGHT_PHASE)
	skybox.set_overcast(1.0, 0.5, 0.6, 0.4, Color(0.4, 0.4, 0.5), 0.5)
	var dimmed: float = _visibility(skybox)
	assert_true(dimmed > 0.0 and dimmed < 1.0, "overcast keeps some aurora, not all (got %s)" % dimmed)
	skybox.set_overcast(0.0, 1.0, 1.0, 1.0, Color.WHITE, 0.0)
	assert_almost_eq(_visibility(skybox), 1.0, 0.0001, "clear sky again")


func test_the_static_night_theme_shows_it_and_a_static_day_theme_does_not() -> void:
	var skybox: Skybox = _wired_skybox()
	assert_true(skybox.set_theme_by_id("night"))
	assert_false(skybox.is_cycle_active())
	var sky: ShaderMaterial = skybox.theme.sky_material as ShaderMaterial
	assert_eq(sky.shader.resource_path, NIGHT_SHADER, "the static night theme is the night_sky shader")
	assert_almost_eq(_visibility(skybox), 1.0, 0.0001, "night.tres sets aurora_always_on")
	Settings.set_graphics_preset(&"low")
	assert_almost_eq(_visibility(skybox), 0.0, 0.0001, "and the Low preset still gates it")
	Settings.set_graphics_preset(&"high")
	assert_true(skybox.set_theme_by_id("sunset"))
	assert_almost_eq(_visibility(skybox), 0.0, 0.0001, "a static day theme has no night to show it in")


func test_theme_defaults_are_a_green_teal_violet_ramp_that_fades_in_after_dusk_starts() -> void:
	var def: SkyThemeDef = SkyThemeDef.new()
	assert_true(def.aurora_enabled)
	assert_false(def.aurora_always_on)
	assert_true(def.aurora_color_low.g > def.aurora_color_low.r and def.aurora_color_low.g > def.aurora_color_low.b, "lower edge is green")
	assert_true(def.aurora_color_mid.g > def.aurora_color_mid.r and def.aurora_color_mid.b > def.aurora_color_mid.r, "middle is teal")
	assert_true(def.aurora_color_top.b > def.aurora_color_top.g and def.aurora_color_top.r > def.aurora_color_top.g, "tips are violet")
	assert_true(def.aurora_start_night_mix < def.aurora_full_night_mix, "the fade-in window has a width")
	assert_true(def.aurora_curtain_height > 0.0 and def.aurora_intensity > 0.0)
	var night: SkyThemeDef = Skybox.load_theme("night")
	assert_true(night.aurora_always_on, "the static Night theme opts in")


## Review fix (1): a hidden aurora costs nothing per frame. A sentinel written straight onto the
## material survives phase ticks while the aurora is hidden (day) and while the look is unchanged
## (night); it is replaced when the aurora becomes visible, and when the theme's look changes.
const SENTINEL: float = 9.0


func _sky_material(skybox: Skybox) -> ShaderMaterial:
	return skybox.environment.sky.sky_material as ShaderMaterial


func test_nothing_is_written_while_the_aurora_is_hidden() -> void:
	var skybox: Skybox = _cycle_skybox()
	skybox.set_cycle_phase(NOON_PHASE)
	var material: ShaderMaterial = _sky_material(skybox)
	assert_almost_eq(_visibility(skybox), 0.0, 0.0001)
	material.set_shader_parameter(&"aurora_intensity", SENTINEL)
	for phase: float in [0.27, 0.3, 0.35, 0.05, 0.1]:
		skybox.set_cycle_phase(phase)
	assert_eq(float(_param(skybox, &"aurora_intensity")), SENTINEL, "day ticks leave the material alone")
	assert_almost_eq(_visibility(skybox), 0.0, 0.0001)
	skybox.set_cycle_phase(NIGHT_PHASE)
	assert_almost_eq(float(_param(skybox, &"aurora_intensity")), skybox.theme.aurora_intensity, 0.0001, "the look lands as soon as it is visible")


func test_the_look_is_written_only_when_it_changes() -> void:
	var skybox: Skybox = _cycle_skybox()
	skybox.set_cycle_phase(NIGHT_PHASE)
	var material: ShaderMaterial = _sky_material(skybox)
	material.set_shader_parameter(&"aurora_intensity", SENTINEL)
	skybox.set_cycle_phase(NIGHT_PHASE + 0.02)
	assert_eq(float(_param(skybox, &"aurora_intensity")), SENTINEL, "an unchanged look is not rewritten on a tick")
	skybox.theme.aurora_intensity = 1.1
	skybox.set_cycle_phase(NIGHT_PHASE + 0.03)
	assert_almost_eq(float(_param(skybox, &"aurora_intensity")), 1.1, 0.0001, "a changed look is")


func test_a_new_sky_material_gets_the_look_and_visibility_afresh() -> void:
	var skybox: Skybox = _wired_skybox()
	assert_true(skybox.set_theme_by_id("night"))
	var night_material: ShaderMaterial = _sky_material(skybox)
	assert_almost_eq(_visibility(skybox), 1.0, 0.0001)
	assert_true(skybox.set_theme_by_id("sunset"))
	assert_ne(_sky_material(skybox), night_material)
	assert_almost_eq(_visibility(skybox), 0.0, 0.0001, "the day material is written hidden")
	assert_true(skybox.set_theme_by_id("night"))
	assert_almost_eq(float(night_material.get_shader_parameter(&"aurora_visibility")), 1.0, 0.0001, "and the night one is shown again")
	assert_almost_eq(float(night_material.get_shader_parameter(&"aurora_intensity")), skybox.theme.aurora_intensity, 0.0001)


## The preset is read from graphics_preset_changed, not looked up on every call: a preset handed
## to the handler wins even though Settings still reports High.
func test_the_preset_flag_comes_from_the_signal_not_a_per_call_lookup() -> void:
	var skybox: Skybox = _cycle_skybox()
	skybox.set_cycle_phase(NIGHT_PHASE)
	assert_almost_eq(_visibility(skybox), 1.0, 0.0001)
	var quiet: GraphicsPreset = Settings.current_graphics_preset().duplicate() as GraphicsPreset
	quiet.aurora_enabled = false
	skybox._on_graphics_preset_changed(quiet)
	assert_true(Settings.current_graphics_preset().aurora_enabled, "fixture: Settings itself still says High")
	assert_almost_eq(_visibility(skybox), 0.0, 0.0001, "the handler's preset gates it")
	skybox.set_cycle_phase(NIGHT_PHASE + 0.02)
	assert_almost_eq(_visibility(skybox), 0.0, 0.0001, "and later ticks keep using it")
	skybox._on_graphics_preset_changed(Settings.current_graphics_preset())
	assert_almost_eq(_visibility(skybox), 1.0, 0.0001, "restored by the next preset change")


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


func test_swapped_fade_edges_on_the_live_sky_still_show_the_aurora_at_midnight() -> void:
	var skybox: Skybox = _cycle_skybox()
	skybox.theme.aurora_start_night_mix = 0.95
	skybox.theme.aurora_full_night_mix = 0.2
	skybox.set_cycle_phase(NOON_PHASE)
	assert_almost_eq(_visibility(skybox), 0.0, 0.0001, "hidden at noon")
	skybox.set_cycle_phase(NIGHT_PHASE)
	assert_almost_eq(_visibility(skybox), 1.0, 0.0001, "shown at midnight")


func test_both_night_shaders_draw_it_behind_the_moon_in_the_background_pass_only() -> void:
	var include_src: String = _shader_source(INCLUDE_PATH)
	assert_true(include_src.contains("vec3 aurora_borealis("), "the shared aurora function exists")
	assert_true(include_src.contains("dir.y >= AURORA_ZENITH_CUT"), "atan() is never evaluated at the pole")
	assert_false(include_src.contains("texture(noise_tex, vec2(a *"), "aurora taps use textureLod (no derivative line at the azimuth wrap)")
	var sunset: String = _shader_source(SUNSET_SHADER)
	var call_at: int = sunset.find("aurora_borealis(")
	assert_true(call_at > 0, "sunset_clouds draws the aurora")
	assert_true(sunset.substr(maxi(call_at - 160, 0), 160).contains("!AT_CUBEMAP_PASS"), "no noise taps in the radiance pass")
	assert_true(call_at < sunset.find("if (moon_visibility > 0.0"), "the moon is drawn over the aurora")
	assert_true(call_at > sunset.find("COLOR = mix(COLOR, night * exposure"), "the aurora is added over the night sky, not under its mix")
	var night: String = _shader_source(NIGHT_SHADER)
	var night_call: int = night.find("aurora_borealis(")
	assert_true(night_call > 0, "night_sky draws the aurora")
	assert_true(night_call > night.find("col += stars * star_mask;"), "after the stars")
	assert_true(night_call < night.find("// Moon disc with a phase terminator"), "before the moon disc")
	assert_true(night_call < night.find("// Moonlit cel-banded clouds."), "before the clouds")
	assert_true(night.substr(0, night_call).rfind("if (!AT_CUBEMAP_PASS)") > 0, "inside the background-pass block")
	for source: String in [sunset, night]:
		assert_true(source.contains("aurora_visibility > 0.0"), "no aurora work when the visibility is 0")
		assert_true(source.contains("aurora_visibility > 0.0 && aurora_intensity > 0.0"), "no texture taps when the intensity is 0")
