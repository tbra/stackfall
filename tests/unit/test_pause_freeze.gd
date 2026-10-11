extends GutTest
## Bontago-1pi.167: the pause menu freezes the whole tree when no remote human is connected
## (Net.solo_session_rule), never otherwise. Predicate, PauseMenu wiring, a real Vs-bots match, and an
## ENet host with a connected client.

const MAIN_SCENE: PackedScene = preload("res://game/Main.tscn")
const _NET_SCRIPT: GDScript = preload("res://autoload/Net.gd")
const FROZEN_FRAMES: int = 12
const BOT_COUNT: int = 2
const JOIN_WAIT_MSEC: int = 6000

var _main: Variant = null
var _menu: PauseMenu = null


func after_each() -> void:
	get_tree().paused = false
	Net.leave()
	Match.abort_match()
	SnapshotSync.end_match()
	Match.set_process(true)
	await get_tree().process_frame


# --- predicate ----------------------------------------------------------------

func test_offline_is_solo() -> void:
	assert_true(_NET_SCRIPT.call(&"solo_session_rule", true, false, PackedInt32Array(), 1))


func test_host_with_only_itself_is_solo() -> void:
	assert_true(_NET_SCRIPT.call(&"solo_session_rule", false, false, PackedInt32Array([1]), 1))


func test_host_with_a_remote_peer_is_not_solo() -> void:
	assert_false(_NET_SCRIPT.call(&"solo_session_rule", false, false, PackedInt32Array([1, 4242]), 1))


func test_client_is_never_solo() -> void:
	assert_false(_NET_SCRIPT.call(&"solo_session_rule", false, true, PackedInt32Array([1]), 7))


# --- PauseMenu wiring ---------------------------------------------------------

func _bare_menu(freeze: bool) -> PauseMenu:
	var menu: PauseMenu = autofree(load("res://ui/PauseMenu.tscn").instantiate()) as PauseMenu
	add_child_autofree(menu)
	menu.context_provider = func() -> Dictionary: return {"freeze_tree": freeze}
	return menu


func test_menu_without_context_never_pauses() -> void:
	var menu: PauseMenu = autofree(load("res://ui/PauseMenu.tscn").instantiate()) as PauseMenu
	add_child_autofree(menu)
	menu._open()
	assert_false(get_tree().paused)
	menu.force_close()


func test_open_pauses_and_close_resumes_when_solo() -> void:
	var menu: PauseMenu = _bare_menu(true)
	menu._open()
	assert_true(get_tree().paused, "solo session: open freezes the tree")
	assert_eq(menu.process_mode, Node.PROCESS_MODE_ALWAYS)
	menu.force_close()
	assert_false(get_tree().paused, "close restores it")


func test_open_does_not_pause_with_a_remote_human() -> void:
	var menu: PauseMenu = _bare_menu(false)
	menu._open()
	assert_false(get_tree().paused)
	menu.force_close()


func test_peer_joining_while_frozen_unfreezes() -> void:
	var solo: Array[bool] = [true]
	var menu: PauseMenu = autofree(load("res://ui/PauseMenu.tscn").instantiate()) as PauseMenu
	add_child_autofree(menu)
	menu.context_provider = func() -> Dictionary: return {"freeze_tree": solo[0]}
	menu._open()
	assert_true(get_tree().paused)
	solo[0] = false
	Events.net_peer_joined.emit(4242, 1, "Joiner")
	assert_false(get_tree().paused, "a joining human unfreezes the world")
	assert_true(menu.visible, "the menu itself stays open")
	menu.force_close()


func test_menu_removal_while_frozen_unpauses() -> void:
	var menu: PauseMenu = _bare_menu(true)
	menu._open()
	menu.free()
	assert_false(get_tree().paused)


# --- real Vs-bots match -------------------------------------------------------

func _snapshot() -> Dictionary:
	var body_positions: Array[Vector3] = []
	for node: Node in _main.get_tree().get_nodes_in_group(&"blocks"):
		if node is Node3D:
			body_positions.append((node as Node3D).global_position)
	var bot_countdowns: Array[float] = []
	for child: Node in _main.get_children():
		if child is BotController:
			bot_countdowns.append(float(child._countdown))
	return {
		"timer": Match.match_timer_left(),
		"feed": Match.feed_time_left(0),
		"bots": bot_countdowns,
		"bodies": body_positions,
		"cycle_clock": float(_main.get_node("Skybox")._cycle_clock_s),
		"day_phase": float(_main.get_node("Skybox")._cycle_phase_last),
		"host_clock": SnapshotSync.sky_cycle_seconds(),
		"sky": float(_main.get_node("Skybox")._sky_clock_s) if _main.has_node("Skybox") else -1.0,
	}


func test_paused_vs_bots_match_freezes_everything_then_resumes() -> void:
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
	_main = MAIN_SCENE.instantiate()
	var tiny_map: MapDef = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	tiny_map.field_radius = 20.0
	(_main.get_node("Field") as Field).map_def = tiny_map
	var cfg: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true)
	cfg.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(cfg as TinyMapMatchConfig).set_tiny_map(tiny_map)
	cfg.rng_seed = 90210
	cfg.match_timer_minutes = 5
	_main.match_config = cfg
	add_child_autofree(_main)
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "Hostie"), OK)
	_main._start_headless_bot_match_with_args(PackedStringArray(["--bots=%d" % BOT_COUNT]))
	await get_tree().process_frame
	Match.set_process(true)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)
	assert_eq(Match.state(), Match.State.PLAYING)
	assert_true(Net.is_solo_session(), "Vs bots host has only the local peer")
	for _i: int in range(FROZEN_FRAMES):
		await get_tree().physics_frame

	var menu: PauseMenu = _main._pause_menu as PauseMenu
	menu.suppressed = false
	menu._open()
	assert_true(get_tree().paused)
	var before: Dictionary = _snapshot()
	for _i: int in range(FROZEN_FRAMES):
		await get_tree().physics_frame
		await get_tree().process_frame
	var after: Dictionary = _snapshot()
	assert_eq(after["timer"], before["timer"], "match timer frozen")
	assert_eq(after["feed"], before["feed"], "block feed frozen")
	assert_eq(after["bots"], before["bots"], "bot think timers frozen")
	assert_eq(after["bodies"], before["bodies"], "physics bodies frozen")
	assert_eq(after["sky"], before["sky"], "sky clock frozen")
	assert_eq(after["host_clock"], before["host_clock"], "shared match clock frozen")
	assert_eq(after["cycle_clock"], before["cycle_clock"], "day cycle clock frozen")
	assert_eq(after["day_phase"], before["day_phase"], "day phase frozen")
	assert_gt(float(before["host_clock"]), 0.0, "fixture: the shared clock was running")
	assert_true((before["bots"] as Array).size() > 0, "fixture: bots exist")
	assert_gt(float(before["timer"]), 0.0, "fixture: the match timer is running")
	assert_gt(float(before["feed"]), 0.0, "fixture: the feed timer is running")

	menu.force_close()
	assert_false(get_tree().paused)
	for _i: int in range(FROZEN_FRAMES):
		await get_tree().physics_frame
		await get_tree().process_frame
	var resumed: Dictionary = _snapshot()
	assert_ne(resumed["timer"], before["timer"], "match timer runs again after resume")
	assert_ne(resumed["sky"], before["sky"], "sky clock runs again after resume")
	assert_gt(float(resumed["host_clock"]), float(before["host_clock"]), "shared clock advances after resume")
	assert_lt(float(resumed["host_clock"]) - float(before["host_clock"]), 2.0, "no wall-clock catch-up jump after resume")
	assert_ne(resumed["cycle_clock"], before["cycle_clock"], "day cycle advances after resume")


# --- ENet: a connected client prevents the freeze ----------------------------

func test_connected_client_prevents_the_freeze() -> void:
	var host: Node = _NET_SCRIPT.new()
	host.name = "HostNet"
	var client: Node = _NET_SCRIPT.new()
	client.name = "ClientNet"
	for side: Node in [host, client]:
		get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), NodePath(String(get_path()) + "/" + side.name))
		add_child_autofree(side)
	var port: int = AgentProbe.free_udp_port()
	assert_eq(host.host_game(port, "Hostie"), OK)
	assert_true(host.is_solo_session(), "host alone is solo")
	assert_eq(client.join_game("127.0.0.1", port, "Clienty"), OK)
	var deadline: int = Time.get_ticks_msec() + JOIN_WAIT_MSEC
	while host.peer_ids().size() < 2 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert_eq(host.peer_ids().size(), 2, "fixture: client joined")
	assert_false(host.is_solo_session(), "host with a connected client never freezes")
	assert_false(client.is_solo_session(), "a client never freezes")
	var menu: PauseMenu = autofree(load("res://ui/PauseMenu.tscn").instantiate()) as PauseMenu
	add_child_autofree(menu)
	menu.context_provider = func() -> Dictionary: return {"freeze_tree": host.is_solo_session()}
	menu._open()
	assert_false(get_tree().paused)
	menu.force_close()
	client.leave()
	host.leave()
	await get_tree().process_frame


# --- a peer joining during a solo pause ----------------------------------------

func test_peer_joining_during_a_solo_pause_gets_through_and_releases() -> void:
	var host: Node = _NET_SCRIPT.new()
	host.name = "HostNet"
	var client: Node = _NET_SCRIPT.new()
	client.name = "ClientNet"
	for side: Node in [host, client]:
		get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), NodePath(String(get_path()) + "/" + side.name))
		add_child_autofree(side)
		assert_eq(side.process_mode, Node.PROCESS_MODE_ALWAYS, "Net keeps polling while paused")
	var port: int = AgentProbe.free_udp_port()
	assert_eq(host.host_game(port, "Hostie"), OK)
	var menu: PauseMenu = _bare_menu(false)
	menu.context_provider = func() -> Dictionary: return {"freeze_tree": host.is_solo_session()}
	menu._open()
	assert_true(get_tree().paused, "solo host: frozen")
	assert_eq(client.join_game("127.0.0.1", port, "Joiner"), OK)
	var deadline: int = Time.get_ticks_msec() + JOIN_WAIT_MSEC
	while host.peer_ids().size() < 2 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert_eq(host.peer_ids().size(), 2, "the join was processed while paused")
	assert_false(get_tree().paused, "the pause released when the human joined")
	assert_true(menu.visible)
	menu.force_close()
	client.leave()
	host.leave()
	await get_tree().process_frame
