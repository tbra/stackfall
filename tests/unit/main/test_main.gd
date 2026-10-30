extends GutTest
## game/main/Main.gd's Lobby "< Back" pill (redo #3, review
## finding #1): pressing it from a hosted lobby must tear the session down
## and land back on the main menu with Net offline, the same way
## ui/menus/PauseMenu.gd's own Leave button does from mid-match
## (test_match_lifecycle.gd's own "Leave during PLAYING" case; that file's
## header explains why these drive the **real** Main scene, Net and Match
## autoloads rather than a fake -- the defect this covers is Main's own
## _on_net_mode_changed() wiring, not anything a fake net_provider seam can
## see, and game/main/Main.gd has no such seam of its own).
##
## Net.host_game() opens a listen server with no clients, so nothing here
## touches the network beyond binding a loopback port (see
## test_match_lifecycle.gd's own header for the same point).

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")

## Well clear of test_net_session.gd's 47800+ range and
## test_match_lifecycle.gd's 47900+ range.
static var _next_port: int = 48000

## game/main/Main.gd has no class_name (a scene root, not a type other code
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
	_tiny_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	(_main.get_node("Field") as Field).map_def = _tiny_map
	add_child_autofree(_main)
	assert_not_null(MainNodes.main_menu(_main), "fixture: Main boots to the main menu with no command-line flags")


func after_each() -> void:
	Net.leave()
	Match.abort_match()
	SnapshotSync.end_match()
	Match.set_process(true)
	await get_tree().process_frame
	await get_tree().process_frame


func _take_port() -> int:
	# Parallel gate shards (tools/full_gate.py) run several Godot processes at
	# once; a fixed port sequence collided, so ask the OS for a free port.
	return AgentProbe.free_udp_port()


## Main does the global wiring (the chat bus connect), so a Main booted after the
## connection was dropped restores it, and the wiring is never doubled.
func test_main_ready_attaches_the_global_wiring() -> void:
	remove_child(_main)
	_main.free()
	while Events.chat_send_requested.is_connected(Net.send_chat):
		Events.chat_send_requested.disconnect(Net.send_chat)
	_main = MAIN_SCENE.instantiate()
	(_main.get_node("Field") as Field).map_def = _tiny_map
	add_child_autofree(_main)
	assert_true(Events.chat_send_requested.is_connected(Net.send_chat), "Main wired the UI chat bus to Net")
	Net.attach_global_wiring()
	assert_eq(Net.host_game(_take_port(), "Hostie"), OK)
	watch_signals(Events)
	Events.chat_send_requested.emit("hello")
	assert_signal_emit_count(Events, "chat_line_received", 1, "one chat line per request, however often the wiring ran")


func test_lobby_back_button_leaves_the_hosted_session_and_returns_to_the_main_menu() -> void:
	assert_eq(Net.host_game(_take_port(), "Hostie"), OK)
	assert_true(Net.is_host())
	assert_not_null(MainNodes.lobby(_main), "hosting swaps the menu for the lobby synchronously")

	(MainNodes.lobby(_main).find_child("BackButton", true, false) as Button).pressed.emit()

	assert_true(Net.is_offline(), "the back pill must leave the hosted session")
	assert_eq(Match.state(), Match.State.LOBBY, "the match never started, so no abort_match() round trip")
	assert_null(MainNodes.lobby(_main), "the lobby is gone")
	assert_not_null(MainNodes.main_menu(_main), "back on the main menu")


func test_play_local_bots_opens_private_lobby_with_no_bot() -> void:
	var previous_port: int = Net.config.game_port
	var occupied_port: int = _take_port()
	var blocker: PacketPeerUDP = PacketPeerUDP.new()
	assert_eq(blocker.bind(occupied_port), OK)
	Net.config.game_port = occupied_port
	(MainNodes.main_menu(_main).get_node("%BotsButton") as Button).pressed.emit()
	Net.config.game_port = previous_port
	blocker.close()
	assert_true(Net.is_host())
	assert_not_null(MainNodes.lobby(_main))
	assert_eq(int(Net.lobby_data().get("player_count", -1)), 2)
	assert_eq(int(Net.lobby_data().get("ai_count", -1)), 0, "no bot is preloaded; the lobby adds bots")
	assert_true(Net.is_private_session(), "Play local must stay out of LAN discovery")
	assert_false(Net.accepting_joins(), "Local bots must reject remote peers")
	assert_ne(Net.host_port(), occupied_port, "Local bots must not depend on the standard game port")
