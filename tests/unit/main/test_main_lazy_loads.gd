extends GutTest
## game/main/Main.gd no longer preloads its rarely used scenes
## and presets at parse time; each loads on first use.

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")
var _main: Variant = null


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
	DebugMode.set_override_for_test(true)
	_main = MAIN_SCENE.instantiate()
	var tiny_map: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	tiny_map.field_radius = 20.0
	(_main.get_node("Field") as Field).map_def = tiny_map
	var tiny_match_config: MatchConfig = (load("res://config/match/match_defaults.tres") as MatchConfig).duplicate(true)
	tiny_match_config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(tiny_match_config as TinyMapMatchConfig).set_tiny_map(tiny_map)
	_main.match_config = tiny_match_config
	add_child_autofree(_main)


func after_each() -> void:
	DebugMode.clear_override_for_test()
	Match.abort_match()
	Match.set_process(true)
	await get_tree().process_frame
	await get_tree().process_frame
	MatchTestReset.clear_world()


func test_sandbox_flow_loads_on_first_use_through_the_queue() -> void:
	assert_null(_main._sandbox_flow, "no flow before the first sandbox/tutorial/hot-seat use")
	_main.start_sandbox_from_menu()
	assert_true(_main._sandbox_flow is MainSandboxFlowPort)
	assert_eq((_main._sandbox_flow as RefCounted).get_script().resource_path, "res://game/main/MainSandboxFlow.gd")
	assert_true(_main._prewarm_queue.is_ready("res://game/main/MainSandboxFlow.gd"))


func test_main_boots_to_menu_without_lobby_or_match_nodes() -> void:
	assert_not_null(_main._main_menu)
	assert_null(_main._lobby)
	assert_null(_main._hot_seat)
	assert_null(_main._sandbox)
	assert_null(_main._tutorial)
	assert_null(_main._remote_cursors)
	assert_null(_main._debug_overlay)


func test_lobby_is_built_on_demand() -> void:
	_main._show_lobby()
	assert_not_null(_main._lobby, "lobby instantiates from the on-demand load")


func test_headless_bots_flow_loads_on_first_use_through_the_queue() -> void:
	assert_null(_main._headless_bots_flow, "no flow before the first bots use")
	assert_eq(_main._headless_bots_flow_port().call(&"_bots_arg", PackedStringArray(["--bots=3"])), 3)
	assert_true(_main._headless_bots_flow is MainHeadlessBotsFlowPort)
	assert_eq((_main._headless_bots_flow as RefCounted).get_script().resource_path, "res://game/main/MainHeadlessBotsFlow.gd")
	assert_true(_main._prewarm_queue.is_ready("res://game/main/MainHeadlessBotsFlow.gd"))
