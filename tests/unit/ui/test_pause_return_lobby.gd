extends GutTest
## "return to lobby option from pause
## menu": ui/menus/PauseMenu.gd's Return to lobby entry and game/main/Main.gd's handler.
##
## Two layers. The bare PauseMenu (a Callable context stands in for Main) pins the
## entry per session role -- host enabled, client disabled with the tooltip, offline
## hidden --, the confirmation gate, focus/gamepad reachability and the dialog's
## cancel path. The real Main scene + Net host (same fixture as
## test_match_restart.gd) pins the behaviour: confirm ends the match for everyone and
## puts the session back in its lobby with settings and seats intact, the match scope
## reset runs once, the abandoned match produces no results, a client's mirror of the
## replicated LOBBY lands in the lobby too, and packets still in flight afterwards are
## ignored. tests/enet/return_lobby_enet.gd runs the same flow over real ENet.

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")
const PAUSE_MENU_SCENE: PackedScene = preload("res://ui/menus/PauseMenu.tscn")
const CUSTOM_BLOCK_TIMER: float = 11.5

var _menu: PauseMenu = null
var _main: Variant = null
var _tiny_map: MapDef
var _context: Dictionary = {}
var _loopback: LoopbackSession
var _saved_gravity_multiplier: float


func before_each() -> void:
	_loopback = LoopbackSession.new(self)
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
	_context = {"return_entry": PauseMenu.ReturnEntry.HIDDEN, "match_in_progress": false}
	_saved_gravity_multiplier = (load("res://config/physics/physics_tuning.tres") as PhysicsTuning).gravity_multiplier


func after_each() -> void:
	Input.action_release(&"pause_menu")
	await _loopback.end()
	Match.abort_match()
	SnapshotSync.end_match()
	Match.set_process(true)
	(load("res://config/physics/physics_tuning.tres") as PhysicsTuning).gravity_multiplier = _saved_gravity_multiplier
	Settings._input(InputEventKey.new())
	await get_tree().process_frame
	await get_tree().process_frame


# --- helpers ------------------------------------------------------------------

func _make_menu() -> PauseMenu:
	_menu = autofree(PAUSE_MENU_SCENE.instantiate())
	add_child_autofree(_menu)
	_menu.context_provider = func() -> Dictionary: return _context
	return _menu


func _set_context(entry: int, in_progress: bool) -> void:
	_context = {"return_entry": entry, "match_in_progress": in_progress}


func _open(menu: PauseMenu) -> void:
	menu._open()


func _make_main() -> void:
	assert_true(Net.is_offline(), "fixture: the real Net must start offline")
	_main = MAIN_SCENE.instantiate()
	_tiny_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	(_main.get_node("Field") as Field).map_def = _tiny_map
	add_child_autofree(_main)
	assert_not_null(_main._main_menu, "fixture: Main boots to the main menu with no command-line flags")


func _host() -> void:
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "Hostie"), OK)
	assert_not_null(_main._lobby, "hosting swaps the menu for the lobby synchronously")


func _config() -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.hot_seat = false
	config.rng_seed = 777
	config.block_timer = CUSTOM_BLOCK_TIMER
	return config


func _run_seconds(seconds: float) -> void:
	var step: float = 1.0 / Engine.physics_ticks_per_second
	for _i: int in range(int(ceil(seconds * Engine.physics_ticks_per_second))):
		Match._process(step)


## A hosted session with a custom lobby setting published, then a match in PLAYING.
func _host_a_playing_match() -> void:
	_make_main()
	_host()
	var data: Dictionary = Net.lobby_data().duplicate(true)
	data["block_timer"] = CUSTOM_BLOCK_TIMER
	Net.set_lobby_data(data)
	_main._on_lobby_start_requested(_config())
	_run_seconds(Match.COUNTDOWN_SECONDS + 0.2)
	assert_eq(Match.state(), Match.State.PLAYING, "fixture: the match is live")
	assert_true(_main._world_built, "fixture: the match world exists")


## A real client (the Net autoload joined a loopback host) whose Main mirrors a match the host
## started: the host's start config applied through Match, then the host's PLAYING.
func _client_in_a_playing_match() -> void:
	_make_main()
	assert_true(await _loopback.join_net_as_client(), "fixture: the Net autoload is a seated client")
	assert_not_null(_main._lobby, "fixture: joining swaps the menu for the lobby")
	Match.start_match(_config())
	Match.apply_replicated_state_change(Match.State.PLAYING)
	assert_eq(Match.state(), Match.State.PLAYING, "fixture: the mirrored match is live")
	assert_true(_main._world_built, "fixture: the match world exists")


## Pause -> Return to lobby -> OK, the way the host's Main wires it.
func _host_returns_through_the_pause_menu() -> void:
	var pause: PauseMenu = _main._pause_menu
	pause._open()
	assert_true(pause._return_button.visible and not pause._return_button.disabled, "the host's entry is live")
	pause._on_return_lobby_pressed()
	assert_true(pause._confirm_dialog.visible, "a match in progress asks first")
	pause._on_confirm_dialog_confirmed()


func test_host_sees_the_entry_enabled_between_options_and_leave() -> void:
	_make_menu()
	_set_context(PauseMenu.ReturnEntry.ENABLED, true)
	_open(_menu)

	assert_true(_menu._return_button.visible)
	assert_false(_menu._return_button.disabled)
	assert_eq(_menu._return_button.text, "RETURN TO LOBBY")
	assert_false(_menu.return_hint.visible, "no inline reason while the host can return")
	var order: Array[Node] = _menu._return_button.get_parent().get_children()
	assert_eq(order.find(_menu._return_button), order.find(_menu._options_button) + 1, "after Options")
	assert_eq(order.find(_menu._leave_button), order.find(_menu.return_hint) + 1, "before Leave match (the hidden inline reason sits between them)")


func test_client_sees_the_entry_disabled_with_the_host_only_hint() -> void:
	_make_menu()
	_set_context(PauseMenu.ReturnEntry.DISABLED, true)
	_open(_menu)

	assert_true(_menu._return_button.visible)
	assert_true(_menu._return_button.disabled, "a client cannot end the match for everyone")
	assert_true(_menu.return_hint.visible, "the reason is shown inline under the entry")
	assert_eq(_menu.return_hint.text, "Only the host can return everyone to the lobby")
	assert_eq(_menu._return_button.tooltip_text, "", "no tooltip")
	assert_ne(_menu._leave_button.disabled, true, "the client's normal Leave match stays")


func test_return_in_a_live_match_asks_before_emitting() -> void:
	_make_menu()
	_set_context(PauseMenu.ReturnEntry.ENABLED, true)
	_open(_menu)
	watch_signals(_menu)

	_menu._on_return_lobby_pressed()

	assert_signal_not_emitted(_menu, "return_to_lobby_requested", "pressing only opens the confirmation")
	assert_true(_menu._confirm_dialog.visible)
	assert_eq(_menu._confirm_dialog.dialog_text, PauseMenu.RETURN_CONFIRM_TEXT)
	assert_true(_menu.visible, "the menu stays up behind the dialog")


func test_confirming_return_emits_once_and_closes_the_menu() -> void:
	_make_menu()
	_set_context(PauseMenu.ReturnEntry.ENABLED, true)
	_open(_menu)
	watch_signals(_menu)

	_menu._on_return_lobby_pressed()
	_menu._on_confirm_dialog_confirmed()

	assert_signal_emit_count(_menu, "return_to_lobby_requested", 1)
	assert_signal_not_emitted(_menu, "leave_match_requested", "Return to lobby must not also leave")
	assert_false(_menu.visible)


func test_cancelling_return_emits_nothing_and_refocuses_the_entry() -> void:
	_make_menu()
	_set_context(PauseMenu.ReturnEntry.ENABLED, true)
	_open(_menu)
	watch_signals(_menu)

	_menu._on_return_lobby_pressed()
	_menu._on_confirm_dialog_canceled()

	assert_signal_not_emitted(_menu, "return_to_lobby_requested")
	assert_true(_menu.visible)
	assert_true(_menu._return_button.has_focus(), "focus returns to the button that asked")
	_menu._on_confirm_dialog_confirmed()
	assert_signal_not_emitted(_menu, "return_to_lobby_requested", "a stale confirm after cancel does nothing")
	assert_signal_not_emitted(_menu, "leave_match_requested")


func test_return_with_no_match_in_progress_goes_straight_through() -> void:
	_make_menu()
	_set_context(PauseMenu.ReturnEntry.ENABLED, false)
	_open(_menu)
	watch_signals(_menu)

	_menu._on_return_lobby_pressed()

	assert_false(_menu._confirm_dialog.visible, "the results screen is already up: nothing to lose, no question")
	assert_signal_emit_count(_menu, "return_to_lobby_requested", 1)
	assert_false(_menu.visible)


func test_disabled_entry_never_emits() -> void:
	_make_menu()
	_set_context(PauseMenu.ReturnEntry.DISABLED, true)
	_open(_menu)
	watch_signals(_menu)

	_menu._on_return_lobby_pressed()
	_menu._on_confirm_dialog_confirmed()

	assert_signal_not_emitted(_menu, "return_to_lobby_requested")
	assert_false(_menu._confirm_dialog.visible)


func test_host_return_puts_the_session_back_in_its_lobby() -> void:
	_host_a_playing_match()
	var peers_before: PackedInt32Array = Net.peer_ids()
	var host_slot: int = Net.slot_of_peer(Net.HOST_PEER_ID)
	var lobby_data_before: Dictionary = Net.lobby_data().duplicate(true)
	watch_signals(Events)

	_host_returns_through_the_pause_menu()

	assert_eq(Match.state(), Match.State.LOBBY, "the match is over for everyone")
	assert_not_null(_main._lobby, "the host is looking at the session lobby")
	assert_null(_main._main_menu, "not the main menu: the session survives")
	assert_false(_main._world_built, "the match world is torn down")
	assert_eq(Net.mode(), Net.Mode.HOST, "still hosting")
	assert_false(_main._pause_menu.visible)
	assert_true(_main._pause_menu.suppressed, "the pause overlay is inert in the lobby")
	assert_signal_emit_count(Events, "match_scope_reset", 1, "the match reset hub runs once for the abandoned match")
	assert_eq(Net.peer_ids(), peers_before, "seats are untouched")
	assert_eq(Net.slot_of_peer(Net.HOST_PEER_ID), host_slot)
	assert_eq(Net.lobby_data().get("block_timer"), lobby_data_before.get("block_timer"), "lobby settings are kept")
	assert_eq(Net.lobby_data().get("block_timer"), CUSTOM_BLOCK_TIMER)
	assert_false(Net.match_in_progress(), "Net reopens the session: spectators reseated, reservations dropped")
	assert_true(Net.accepting_joins(), "and joins are open again")


func test_the_abandoned_match_has_no_winner_and_no_results() -> void:
	_host_a_playing_match()
	watch_signals(Events)

	_host_returns_through_the_pause_menu()

	assert_signal_not_emitted(Events, "match_results_ready", "DECISION: ending a match from pause skips results")
	assert_false(_main._results_screen.visible)
	assert_eq(Match.stats().blocks_placed(0), 0, "stats reset like any abort")
	assert_null(Match.config, "the match's config is gone; the lobby's settings live in Net")


func test_a_client_request_is_ignored_by_main() -> void:
	await _client_in_a_playing_match()

	_main._on_pause_return_to_lobby_requested()

	assert_eq(Match.state(), Match.State.PLAYING, "only the host ends a match for everyone")
	assert_true(_main._world_built)


func test_a_client_mirrors_the_hosts_return_into_its_lobby() -> void:
	await _client_in_a_playing_match()
	var pause: PauseMenu = _main._pause_menu
	pause._open()
	assert_true(pause._return_button.disabled, "client: disabled entry")
	pause._on_leave_pressed()
	assert_true(pause._confirm_dialog.visible, "fixture: the client had a Leave confirmation open")
	watch_signals(Events)

	# What net/MatchNet.gd's EVENT_STATE_CHANGED handler does with the host's LOBBY.
	Match.apply_replicated_state_change(Match.State.LOBBY)

	assert_eq(Match.state(), Match.State.LOBBY)
	assert_not_null(_main._lobby, "the client lands in the session lobby, not the main menu")
	assert_null(_main._main_menu)
	assert_false(_main._world_built)
	assert_false(pause.visible, "its pause menu closes")
	assert_false(pause._confirm_dialog.visible, "and takes the stale confirmation with it")
	assert_signal_emit_count(Events, "match_scope_reset", 1, "the client's world is reset once as well")
	assert_signal_emit_count(Events, "pause_menu_closed", 1, "gameplay input is restored")


func test_offline_return_falls_back_to_the_main_menu() -> void:
	_make_main()
	_main.start_sandbox_from_menu()
	assert_true(Net.is_offline())
	assert_eq(_main._pause_menu_context()["return_entry"], PauseMenu.ReturnEntry.HIDDEN)

	_main._on_pause_return_to_lobby_requested()

	assert_eq(Match.state(), Match.State.LOBBY)
	assert_not_null(_main._main_menu, "DECISION: offline has no lobby, so it is Leave match")
	assert_null(_main._lobby)
