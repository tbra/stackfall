extends Node
## Bontago-1pi.50: host + one lagged client over real ENet, each running the real
## game/Main.tscn. The host plays a match, ends it through the pause menu's Return to
## lobby (open, press, confirm), and both peers must land in the session lobby with seats
## and the published lobby setting intact, the match scope reset fired exactly once per
## peer, no results screen, the client's own entry disabled with its tooltip and its open
## pause menu closed by the host's return. The host then starts a second match from that
## lobby and both peers must reach PLAYING again. Per-peer "RLENET <role> ..." lines;
## exit 0 = this peer passed, 1 = a check failed, 2 = setup, 3 = deadline.
## Run via tools/run_return_lobby_enet.ps1 (host: --headless-host, client: --join=).

const MAIN_SCENE: PackedScene = preload("res://game/Main.tscn")
const HARD_DEADLINE_S: float = 120.0
const CONNECT_TIMEOUT_S: float = 20.0
const STATE_TIMEOUT_S: float = 25.0
const HOST_AND_CLIENT_PEERS: int = 2
const SEED: int = 4242
const COUNTDOWN_S: float = 2.0
const CUSTOM_BLOCK_TIMER: float = 11.5
const SETTLE_S: float = 1.0
const PLAY_S: float = 2.0
const CLIENT_PAUSE_AFTER_S: float = 0.5

var _main: Node
var _role_name: String = ""
var _started_msec: int = 0
var _scope_resets: int = 0
var _results_emitted: int = 0
var _finish_requested: bool = false


func _ready() -> void:
	_started_msec = Time.get_ticks_msec()
	Events.match_scope_reset.connect(func() -> void: _scope_resets += 1)
	Events.match_results_ready.connect(func(_results: Dictionary) -> void: _results_emitted += 1)
	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	await get_tree().process_frame
	if Net.mode() == Net.Mode.HOST:
		_role_name = "host"
		await _run_host()
	elif Net.mode() == Net.Mode.CLIENT:
		_role_name = "client"
		await _run_client()
	else:
		print("RLENET setup result=FAIL reason=no_net_mode")
		get_tree().quit(2)


func _process(_delta: float) -> void:
	if float(Time.get_ticks_msec() - _started_msec) / 1000.0 > HARD_DEADLINE_S:
		print("RLENET %s result=FAIL reason=hard_deadline" % _role_name)
		get_tree().quit(3)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _until(condition: Callable, seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await _wait(0.05)
	return condition.call()


func _fail(reason: String) -> void:
	print("RLENET %s result=FAIL reason=%s" % [_role_name, reason])
	get_tree().quit(1)


func _config() -> MatchConfig:
	var config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true) as MatchConfig
	config.map_size = MapDef.MapSize.SMALL
	config.player_count = 2
	config.ai_count = 0
	config.hot_seat = false
	config.rng_seed = SEED
	config.countdown_seconds = COUNTDOWN_S
	config.block_timer = CUSTOM_BLOCK_TIMER
	return config


func _pause() -> PauseMenu:
	return _main.get("_pause_menu") as PauseMenu


func _slots() -> Dictionary:
	var slots: Dictionary = {}
	for peer_id: int in Net.peer_ids():
		slots[peer_id] = Net.slot_of_peer(peer_id)
	return slots


## What a peer must look like once the host has returned the session to the lobby.
func _lobby_problems(slots_before: Dictionary) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	if Match.state() != Match.State.LOBBY:
		problems.append("state=%d" % int(Match.state()))
	if _main.get("_lobby") == null:
		problems.append("no_lobby_screen")
	if _main.get("_main_menu") != null:
		problems.append("main_menu_shown")
	if bool(_main.get("_world_built")):
		problems.append("world_still_built")
	if _pause().visible:
		problems.append("pause_menu_still_open")
	if _scope_resets != 1:
		problems.append("scope_resets=%d" % _scope_resets)
	if _results_emitted != 0:
		problems.append("results_emitted=%d" % _results_emitted)
	if bool((_main.get("_results_screen") as Control).visible):
		problems.append("results_screen_visible")
	if _slots() != slots_before:
		problems.append("seats_changed before=%s after=%s" % [str(slots_before), str(_slots())])
	return problems


# --- host ---------------------------------------------------------------------------------

func _run_host() -> void:
	if not await _until(func() -> bool: return Net.peer_ids().size() >= HOST_AND_CLIENT_PEERS, CONNECT_TIMEOUT_S):
		print("RLENET host result=FAIL reason=no_client")
		get_tree().quit(2)
		return
	await _wait(SETTLE_S)
	var data: Dictionary = Net.lobby_data().duplicate(true)
	data["block_timer"] = CUSTOM_BLOCK_TIMER
	Net.set_lobby_data(data)
	var slots_before: Dictionary = _slots()
	_main.call(&"_on_lobby_start_requested", _config())
	if not await _until(func() -> bool: return Match.state() == Match.State.PLAYING, STATE_TIMEOUT_S):
		_fail("host never reached PLAYING")
		return
	await _wait(PLAY_S)

	var pause: PauseMenu = _pause()
	pause._open()
	if not pause._return_button.visible or pause._return_button.disabled:
		_fail("host entry not live visible=%s disabled=%s" % [pause._return_button.visible, pause._return_button.disabled])
		return
	_scope_resets = 0
	pause._on_return_lobby_pressed()
	if not pause._confirm_dialog.visible:
		_fail("no confirmation asked")
		return
	pause._on_confirm_dialog_confirmed()
	var problems: PackedStringArray = _lobby_problems(slots_before)
	if float(Net.lobby_data().get("block_timer", -1.0)) != CUSTOM_BLOCK_TIMER:
		problems.append("lobby_setting_lost=%s" % str(Net.lobby_data().get("block_timer")))
	if Net.match_in_progress() or not Net.accepting_joins():
		problems.append("net_not_reopened")
	if not problems.is_empty():
		_fail("host lobby: %s" % ", ".join(problems))
		return
	print("RLENET host returned_to_lobby seats=%s scope_resets=%d" % [str(slots_before), _scope_resets])

	# The client has its own checks to run on the replicated LOBBY; then a fresh match
	# from this lobby must start for both.
	await _wait(SETTLE_S + SETTLE_S)
	_main.call(&"_on_lobby_start_requested", _config())
	if not await _until(func() -> bool: return Match.state() == Match.State.PLAYING, STATE_TIMEOUT_S):
		_fail("host never reached PLAYING again")
		return
	await _wait(PLAY_S)
	print("RLENET host result=PASS seats=%s" % str(slots_before))
	rpc(&"h_finish")
	await _wait(SETTLE_S)
	get_tree().quit(0)


# --- client -------------------------------------------------------------------------------

func _run_client() -> void:
	if not await _until(func() -> bool: return Match.state() == Match.State.PLAYING, CONNECT_TIMEOUT_S + STATE_TIMEOUT_S):
		_fail("client never reached PLAYING")
		return
	var slots_before: Dictionary = _slots()
	await _wait(CLIENT_PAUSE_AFTER_S)
	var pause: PauseMenu = _pause()
	pause._open()
	var tooltip_ok: bool = pause._return_button.tooltip_text == PauseMenu.RETURN_CLIENT_TOOLTIP
	if not pause._return_button.visible or not pause._return_button.disabled or not tooltip_ok:
		_fail("client entry visible=%s disabled=%s tooltip_ok=%s" % [pause._return_button.visible, pause._return_button.disabled, tooltip_ok])
		return
	pause._return_button.pressed.emit()
	if Match.state() != Match.State.PLAYING or pause._confirm_dialog.visible:
		_fail("client press acted")
		return
	_scope_resets = 0
	print("RLENET client playing entry_disabled=true pause_open=true")

	if not await _until(func() -> bool: return Match.state() == Match.State.LOBBY, STATE_TIMEOUT_S):
		_fail("client never saw the host's return to the lobby")
		return
	await get_tree().process_frame
	var problems: PackedStringArray = _lobby_problems(slots_before)
	if Net.mode() != Net.Mode.CLIENT:
		problems.append("net_mode=%d" % int(Net.mode()))
	if not problems.is_empty():
		_fail("client lobby: %s" % ", ".join(problems))
		return
	print("RLENET client in_lobby scope_resets=%d" % _scope_resets)

	if not await _until(func() -> bool: return Match.state() == Match.State.PLAYING, STATE_TIMEOUT_S + 2.0 * SETTLE_S):
		_fail("client never reached PLAYING again")
		return
	print("RLENET client result=PASS seats=%s" % str(slots_before))


@rpc("authority", "call_remote", "reliable")
func h_finish() -> void:
	if _finish_requested:
		return
	_finish_requested = true
	get_tree().quit(0)
