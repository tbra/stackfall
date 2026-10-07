extends GutTest
## Bontago-1pi.108: every mode that builds a world (hot-seat, sandbox, tutorial,
## and the gift demo / tower topple sandbox presets) must configure the Skybox for
## the config's theme / cycle, not leave it on the launch fallback sky.

const MAIN_SCENE: PackedScene = preload("res://game/Main.tscn")

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
		load("res://config/match_defaults.tres") as MatchConfig
	).duplicate(true)
	tiny_config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
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
	assert_ne(sky.theme, null, "%s: a theme is applied" % mode)


func test_hot_seat_configures_sky() -> void:
	_main._start_hot_seat_match()
	_assert_sky_configured("hot-seat")


func test_sandbox_configures_sky() -> void:
	_main._start_sandbox_match_with_args(PackedStringArray(["--players=2"]))
	_assert_sky_configured("sandbox")


func test_tutorial_configures_sky() -> void:
	_main.start_tutorial_from_menu()
	_assert_sky_configured("tutorial")


func test_gift_demo_configures_sky() -> void:
	_main.start_gift_demo_from_menu()
	_assert_sky_configured("gift demo")


func test_tower_topple_configures_sky() -> void:
	_main.start_tower_topple_from_menu()
	_assert_sky_configured("tower topple")
