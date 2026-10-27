extends GutTest
## Main on the interactive path hands the background prewarm to AppLoader (loader behaviour:
## test_app_loader). What a player sees of Main itself: headless and flag runs stay synchronous,
## the menu is up at once and the engine keeps the close request.

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")

var _main: Node = null


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
	_main = MAIN_SCENE.instantiate()
	var tiny: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	tiny.field_radius = 20.0
	(_main.get_node("Field") as Field).map_def = tiny


func after_each() -> void:
	Net.leave()
	Match.abort_match()
	SnapshotSync.end_match()
	Match.set_process(true)
	get_tree().auto_accept_quit = true
	await get_tree().process_frame
	await get_tree().process_frame


func test_headless_run_stays_synchronous() -> void:
	add_child_autofree(_main)
	assert_not_null(MainNodes.main_menu(_main), "the menu is up at once")
	assert_true(get_tree().auto_accept_quit, "the engine keeps the close request")


func test_headless_menu_click_starts_at_once() -> void:
	add_child_autofree(_main)
	_main.start_sandbox_from_menu()
	assert_not_null(MainNodes.first(_main, &"Sandbox"), "the click builds the sandbox in the same frame")
