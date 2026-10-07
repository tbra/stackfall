extends GutTest
## Bontago-1pi.11.62: game/Main.gd no longer preloads its rarely used scenes
## and presets at parse time; each loads on first use.

const MAIN_SCRIPT_PATH: String = "res://game/Main.gd"
const MAIN_SCENE: PackedScene = preload("res://game/Main.tscn")
const DEFERRED_PATHS: PackedStringArray = [
	"res://ui/Lobby.tscn",
	"res://game/HotSeat.tscn",
	"res://game/Sandbox.tscn",
	"res://ui/Tutorial.tscn",
	"res://game/RemoteCursors.tscn",
	"res://ui/NetDebugOverlay.tscn",
	"res://config/sandbox_gift_demo.tres",
	"res://config/sandbox_tower_topple.tres",
]

var _main: Variant = null


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
	DebugMode.set_override_for_test(true)
	_main = MAIN_SCENE.instantiate()
	var tiny_map: MapDef = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	tiny_map.field_radius = 20.0
	(_main.get_node("Field") as Field).map_def = tiny_map
	var tiny_match_config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true)
	tiny_match_config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
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


func test_main_source_has_no_preload_of_deferred_paths() -> void:
	var source: String = FileAccess.get_file_as_string(MAIN_SCRIPT_PATH)
	for path: String in DEFERRED_PATHS:
		assert_false(source.contains("preload(\"%s\")" % path), "%s must not be preloaded" % path)


func test_main_boots_to_menu_without_lobby_or_match_nodes() -> void:
	assert_not_null(_main._main_menu)
	assert_null(_main._lobby)
	assert_null(_main._hot_seat)
	assert_null(_main._sandbox)
	assert_null(_main._tutorial)
	assert_null(_main._remote_cursors)
	assert_null(_main._debug_overlay)


func test_each_deferred_path_loads_on_first_use() -> void:
	for path: String in DEFERRED_PATHS:
		assert_not_null(load(path), "%s loads" % path)
	assert_not_null(_main._load_scene(_main.HOT_SEAT_SCENE_PATH))


func test_lobby_is_built_on_demand() -> void:
	_main._show_lobby()
	assert_not_null(_main._lobby, "lobby instantiates from the on-demand load")


func test_gift_demo_preset_loads_on_use() -> void:
	_main.start_gift_demo_from_menu()
	assert_not_null(_main._sandbox)
	assert_eq(_main._sandbox_preset.resource_path, "res://config/sandbox_gift_demo.tres")


func test_tower_topple_preset_loads_on_use() -> void:
	_main.start_tower_topple_from_menu()
	assert_not_null(_main._sandbox)
	assert_eq(_main._sandbox_preset.resource_path, "res://config/sandbox_tower_topple.tres")
