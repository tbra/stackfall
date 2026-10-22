extends GutTest
## Sandbox and tutorial are the real match with extra features: each entry point
## configures the Skybox from its own MatchConfig (the same configure_match_sky a match uses)
## rather than leaving the pre-match boot sky, and both begin the shared match clock, so the
## cycle advances in both.

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")
const CLOCK_STEP_FRAMES: int = 6

var _main: Variant = null


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
	_main = MAIN_SCENE.instantiate()
	var tiny_map: MapDef = MapDef.new()
	tiny_map.id = &"tiny_sky_cfg"
	tiny_map.field_radius = 12.0
	tiny_map.cell_size = 1.0
	var tiny_config: MatchConfig = (load("res://config/match/match_defaults.tres") as MatchConfig).duplicate(true)
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


func _configure(mode: MatchConfig.SkyThemeMode) -> void:
	(_main.match_config as MatchConfig).sky_theme_mode = mode


func _step_clock() -> void:
	for _i: int in CLOCK_STEP_FRAMES:
		await get_tree().physics_frame


func _assert_locked_from_config(mode: String, expected_phase: float) -> void:
	var sky: Skybox = _main.get_node("Skybox") as Skybox
	assert_true(sky.is_cycle_active(), "%s: configured cycle is active" % mode)
	assert_almost_eq(sky.locked_phase(), expected_phase, 0.0001, "%s: locked at the config's sky phase" % mode)
	assert_true(SnapshotSync.is_running(), "%s: the shared match clock runs" % mode)
	await _step_clock()
	assert_gt(SnapshotSync.sky_cycle_seconds(), 0.0, "%s: the clock advances after stepping" % mode)


func test_sandbox_sky_comes_from_its_config() -> void:
	_configure(MatchConfig.SkyThemeMode.NIGHT)
	_main.start_sandbox_from_menu()
	await _assert_locked_from_config("sandbox", (_main.get_node("Skybox") as Skybox).sky_def.cycle_locked_phase_night)


func test_tutorial_sky_comes_from_its_config_and_the_clock_runs() -> void:
	_configure(MatchConfig.SkyThemeMode.DAWN)
	_main.start_tutorial_from_menu()
	await _assert_locked_from_config("tutorial", (_main.get_node("Skybox") as Skybox).sky_def.cycle_locked_phase_dawn)


func test_running_cycle_config_runs_the_cycle_in_the_sandbox() -> void:
	_configure(MatchConfig.SkyThemeMode.CYCLE)
	_main.start_sandbox_from_menu()
	var sky: Skybox = _main.get_node("Skybox") as Skybox
	assert_lt(sky.locked_phase(), 0.0, "a CYCLE config leaves the cycle unlocked")
	await _step_clock()
	assert_gt(SnapshotSync.sky_cycle_seconds(), 0.0, "the running cycle has a clock to follow")


func test_running_cycle_config_runs_the_cycle_in_the_tutorial() -> void:
	_configure(MatchConfig.SkyThemeMode.CYCLE)
	_main.start_tutorial_from_menu()
	var sky: Skybox = _main.get_node("Skybox") as Skybox
	assert_lt(sky.locked_phase(), 0.0, "a CYCLE config leaves the cycle unlocked")
	await _step_clock()
	assert_true(SnapshotSync.is_running(), "the tutorial runs the shared clock")
	assert_gt(SnapshotSync.sky_cycle_seconds(), 0.0, "the tutorial cycle follows a running clock")
