extends GutTest
## Skybox.set_capture_pin (tools/shot_targets.gd parity captures): a pinned running cycle holds the
## phase set_cycle_phase gave it while the shared clock runs on, the pin redraws the sky with the
## fixed default variation seed whatever seed the match rolled, and only a pin moves the cloud puffs
## off engine TIME.

const PIN_SKY_TIME_S: float = 100.0
const PIN_DRIFT_S: float = 50.0
const SET_PHASE: float = 0.25
const LATER_CLOCK_S: float = 200.0
const MATCH_SEED: int = 5551

var _previous_context: MatchContext = null
var _context: FakeMatchContext = null


func before_each() -> void:
	_previous_context = MatchContext.installed()
	_context = FakeMatchContext.new()
	MatchContext.install(_context)


func after_each() -> void:
	MatchContext.install(_previous_context)


func _skybox() -> Skybox:
	var sky: Sky = Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var environment: Environment = Environment.new()
	environment.sky = sky
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.environment = environment
	skybox.sky_def = SkyTestKit.cycle()
	add_child_autofree(skybox)
	return skybox


func _running_at_set_phase(pinned: bool) -> Skybox:
	var skybox: Skybox = _skybox()
	skybox.start_cycle()
	if pinned:
		skybox.set_capture_pin(PIN_SKY_TIME_S, PIN_DRIFT_S)
	skybox.set_cycle_phase(SET_PHASE)
	SkyTestKit.run_to_clock(skybox, _context, LATER_CLOCK_S)
	return skybox


func test_a_pinned_running_cycle_holds_the_phase_it_was_set_to() -> void:
	var skybox: Skybox = _running_at_set_phase(true)
	assert_almost_eq(skybox.current_cycle_phase(), SET_PHASE, 0.0001, "a radiance tick does not move a pinned cycle")
	var expected_sun: Vector3 = SkyEvaluator.sun_direction(skybox.sky_def, SET_PHASE)
	assert_true(skybox.sun_direction().is_equal_approx(expected_sun), "the sun stays at the set phase")


func test_an_unpinned_running_cycle_follows_the_shared_clock() -> void:
	var skybox: Skybox = _running_at_set_phase(false)
	assert_false(is_equal_approx(skybox.current_cycle_phase(), SET_PHASE), "positive control: the radiance tick moves it")


func test_a_pin_redraws_the_sky_with_the_default_variation_seed() -> void:
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.CYCLE
	config.resolve_sky_variation_seed(MATCH_SEED)
	var skybox: Skybox = _skybox()
	skybox.configure_match_sky(config)
	var phase: float = skybox.current_cycle_phase()
	var def: SkyCycleDef = skybox.sky_def
	var match_exposure: float = SkyVariation.value_at(def.variation_exposure_min, def.variation_exposure_max,
		def.variation_knots_per_cycle, phase, MATCH_SEED, SkyVariation.CHANNEL_EXPOSURE)
	var default_exposure: float = SkyVariation.value_at(def.variation_exposure_min, def.variation_exposure_max,
		def.variation_knots_per_cycle, phase, SkyVariation.DEFAULT_SEED, SkyVariation.CHANNEL_EXPOSURE)
	assert_ne(match_exposure, default_exposure, "the two seeds draw different skies at this phase")
	var material: ShaderMaterial = SkyTestKit.sky_material(skybox)
	assert_eq(float(material.get_shader_parameter(&"exposure")), match_exposure, "before the pin: the match's seed")
	skybox.set_capture_pin(PIN_SKY_TIME_S, PIN_DRIFT_S)
	assert_eq(skybox.variation_seed(), SkyVariation.DEFAULT_SEED)
	assert_eq(float(material.get_shader_parameter(&"exposure")), default_exposure, "the pin redraws with the default seed")


## The live puff material (every puff layer shares it).
func _puff_material(skybox: Skybox) -> ShaderMaterial:
	for sea: Node in skybox.find_children("*", "CloudSea", true, false):
		for child: Node in sea.get_children():
			if child is MultiMeshInstance3D and not child.is_queued_for_deletion():
				return (child as MultiMeshInstance3D).material_override as ShaderMaterial
	return null


## In play the puffs animate by TIME, never by the sky clock: that wraps at time_wrap_seconds and
## would re-roll every puff's lumps and billow at once (an hourly pop). A pin holds them at its clock,
## also across a cloud-sea rebuild, and the unpin hands them back to TIME.
func test_puffs_animate_by_engine_time_in_play_and_by_the_pinned_clock_under_a_pin() -> void:
	var skybox: Skybox = _skybox()
	var puffs: ShaderMaterial = _puff_material(skybox)
	assert_not_null(puffs, "the cloud sea built its puffs")
	if puffs == null:
		return
	assert_null(puffs.get_shader_parameter(CloudSea.CAPTURE_TIME_PARAMETER), "in play: no capture clock, so TIME")
	skybox.set_capture_pin(PIN_SKY_TIME_S, PIN_DRIFT_S)
	assert_eq(float(puffs.get_shader_parameter(CloudSea.CAPTURE_TIME_PARAMETER)), PIN_SKY_TIME_S, "pinned: the pin's clock")
	skybox.refresh_sky_def()
	puffs = _puff_material(skybox)
	assert_eq(float(puffs.get_shader_parameter(CloudSea.CAPTURE_TIME_PARAMETER)), PIN_SKY_TIME_S, "a rebuilt sea keeps the pin")
	skybox.set_capture_pin(-1.0, -1.0)
	assert_lt(float(puffs.get_shader_parameter(CloudSea.CAPTURE_TIME_PARAMETER)), 0.0, "unpinned: back to TIME")
