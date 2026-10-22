extends GutTest
## every mode that builds a world (sandbox, tutorial, and the gift demo / tower topple
## sandbox presets) goes through the one match path, so it must configure the Skybox for
## the config's theme / cycle, not leave it on the launch fallback sky, and run the shared clock.

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")
const CLOCK_STEP_FRAMES: int = 6

var _main: Variant = null


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
	_main = MAIN_SCENE.instantiate()
	var tiny_map: MapDef = MapDef.new()
	tiny_map.id = &"tiny_sky"
	tiny_map.field_radius = 12.0
	tiny_map.cell_size = 1.0
	var tiny_config: MatchConfig = (
		load("res://config/match/match_defaults.tres") as MatchConfig
	).duplicate(true)
	tiny_config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(tiny_config as TinyMapMatchConfig).set_tiny_map(tiny_map)
	tiny_config.rng_seed = 90210
	_main.match_config = tiny_config
	add_child_autofree(_main)


func after_each() -> void:
	Net.leave()
	Match.abort_match()
	SnapshotSync.end_match()
	Match.set_process(true)
	await get_tree().process_frame


func _assert_sky_configured(mode: String) -> void:
	var sky: Skybox = _main.get_node("Skybox") as Skybox
	assert_true(sky.is_cycle_active(), "%s: the Skybox must run the configured sky cycle" % mode)
	assert_ne(sky.sky_def, null, "%s: a sky cycle is applied" % mode)
	# the panorama is absent: the live
	# sky is the cycle's own procedural material.
	assert_ne(sky.environment.sky.sky_material, null, "%s: the dome material is bound" % mode)
	assert_eq(sky.environment.sky.sky_material, SkyTestKit.sky_material(sky), "%s: the cycle's material is the live sky" % mode)
	assert_eq(float(SkyTestKit.sky_material(sky).get_shader_parameter(&"procedural_sea_mix")), SkyDomeWriter.PROCEDURAL_SEA_MIX, "%s: procedural sky look" % mode)


func test_menu_tutorial_configures_sky_and_runs_the_clock() -> void:
	_main.start_tutorial_from_menu()
	_assert_sky_configured("tutorial")
	assert_true(SnapshotSync.is_running(), "tutorial: the shared clock runs")
	for _i: int in CLOCK_STEP_FRAMES:
		await get_tree().physics_frame
	assert_gt(SnapshotSync.sky_cycle_seconds(), 0.0, "tutorial: the sky cycle clock advances")


func test_menu_sandbox_configures_sky_and_runs_the_clock() -> void:
	_main.start_sandbox_from_menu()
	_assert_sky_configured("sandbox")
	assert_true(SnapshotSync.is_running(), "sandbox: the shared clock runs")
	for _i: int in CLOCK_STEP_FRAMES:
		await get_tree().physics_frame
	assert_gt(SnapshotSync.sky_cycle_seconds(), 0.0, "sandbox: the sky cycle clock advances")


## A screenshot showed the painted sunset: the real menu
## entry, with the match clock running, keeps the painted panorama off the live sky material
## (procedural_sea_mix replaces it entirely) and survives the F5 reset's restart.
func test_menu_sandbox_never_samples_the_painted_panorama() -> void:
	Match.set_process(true)
	_main.start_sandbox_from_menu()
	var sky: Skybox = _main.get_node("Skybox") as Skybox
	for step: int in 3:
		await get_tree().create_timer(0.2).timeout
		_assert_sky_configured("menu sandbox step %d" % step)
		var material: ShaderMaterial = sky.environment.sky.sky_material as ShaderMaterial
		assert_eq(float(material.get_shader_parameter(&"procedural_sea_mix")), 1.0, "painted panorama fully replaced")
		if step == 1:
			_main._sandbox._reset_field()
	Match.set_process(false)
