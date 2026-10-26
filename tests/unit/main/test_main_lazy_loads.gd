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


func test_sandbox_flow_loads_on_first_use() -> void:
	assert_null(MainNodes.first(_main, &"Sandbox"), "no sandbox before the first sandbox use")
	_main.start_sandbox_from_menu()
	assert_not_null(MainNodes.first(_main, &"Sandbox"), "the sandbox flow loaded on demand and built its world")


func test_main_boots_to_menu_without_lobby_or_match_nodes() -> void:
	assert_not_null(MainNodes.main_menu(_main))
	assert_null(MainNodes.lobby(_main))
	assert_null(MainNodes.local_player(_main))
	assert_null(MainNodes.first(_main, &"Sandbox"))
	assert_null(MainNodes.first(_main, &"Tutorial"))
	assert_null(MainNodes.first(_main, &"RemoteCursors"))


func test_lobby_is_built_on_demand() -> void:
	assert_eq(Net.host_game(0, "Host", false), OK)
	assert_not_null(MainNodes.lobby(_main), "hosting instantiates the lobby from the on-demand load")
	Net.leave()
