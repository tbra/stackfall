extends GutTest
## game/Main.gd's Lobby "< Back" pill (Bontago-xtq.32 redo #3, review
## finding #1): pressing it from a hosted lobby must tear the session down
## and land back on the main menu with Net offline, the same way
## ui/PauseMenu.gd's own Leave button does from mid-match
## (test_match_lifecycle.gd's own "Leave during PLAYING" case; that file's
## header explains why these drive the **real** Main scene, Net and Match
## autoloads rather than a fake -- the defect this covers is Main's own
## _on_net_mode_changed() wiring, not anything a fake net_provider seam can
## see, and game/Main.gd has no such seam of its own).
##
## Net.host_game() opens a listen server with no clients, so nothing here
## touches the network beyond binding a loopback port (see
## test_match_lifecycle.gd's own header for the same point).

const MAIN_SCENE: PackedScene = preload("res://game/Main.tscn")

## Well clear of test_net_session.gd's 47800+ range and
## test_match_lifecycle.gd's 47900+ range.
static var _next_port: int = 48000

## game/Main.gd has no class_name (a scene root, not a type other code
## names), so the instance is held through a Variant-typed reference, the
## same as test_match_lifecycle.gd and test_sandbox.gd do.
var _main: Variant = null
var _tiny_map: MapDef


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
	assert_true(Net.is_offline(), "fixture: the real Net must start offline")
	_main = MAIN_SCENE.instantiate()
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	(_main.get_node("Field") as Field).map_def = _tiny_map
	add_child_autofree(_main)
	assert_not_null(_main._main_menu, "fixture: Main boots to the main menu with no command-line flags")


func after_each() -> void:
	Net.leave()
	Match.abort_match()
	SnapshotSync.end_match()
	Match.set_process(true)
	await get_tree().process_frame
	await get_tree().process_frame


func _take_port() -> int:
	var port: int = _next_port
	_next_port += 1
	return port


func test_lobby_back_button_leaves_the_hosted_session_and_returns_to_the_main_menu() -> void:
	assert_eq(Net.host_game(_take_port(), "Hostie"), OK)
	assert_true(Net.is_host())
	assert_not_null(_main._lobby, "hosting swaps the menu for the lobby synchronously")

	(_main._lobby.get_node("%BackButton") as Button).pressed.emit()

	assert_true(Net.is_offline(), "the back pill must leave the hosted session")
	assert_eq(Match.state(), Match.State.LOBBY, "the match never started, so no abort_match() round trip")
	assert_null(_main._lobby, "the lobby is gone")
	assert_not_null(_main._main_menu, "back on the main menu")


## The handler itself (game/Main.gd's _on_lobby_back_requested()), isolated
## from the signal/button wiring the test above already covers -- both are
## kept because the button test would still pass if the handler were wired
## to the wrong method name, and this one would still pass if %BackButton's
## own pressed connection were missing.
func test_on_lobby_back_requested_leaves_the_hosted_session() -> void:
	assert_eq(Net.host_game(_take_port(), "Hostie"), OK)
	assert_true(Net.is_host())

	_main._on_lobby_back_requested()

	assert_true(Net.is_offline())
	assert_not_null(_main._main_menu)
