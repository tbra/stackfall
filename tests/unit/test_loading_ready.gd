extends GutTest
## Bontago-1pi.32 (owner playtest 2026-10-03): the loading screen stays up for a
## minimum time and every human presses ready (ui_accept / gamepad A) before the
## host starts the countdown. Covers the pure rule (core/LoadingReadyGate.gd),
## the host's authoritative gate in autoload/match/MatchLifecycle.gd, Net's
## intent validation, and ui/LoadingScreen.gd's input glue.

const MIN_S: float = 5.0
const MAX_S: float = 60.0
const STEP_S: float = 0.1

var _field: Field
var _blocks_root: Node3D
var _registry: BlockRegistry
var _map: MapDef
var _published: Array[Dictionary] = []
var _opened_count: int = 0
var _on_changed: Callable
var _on_opened: Callable


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)
	_published = []
	_opened_count = 0
	_on_changed = func(ready_ids: PackedInt32Array, required_ids: PackedInt32Array) -> void:
		_published.append({"ready": ready_ids, "required": required_ids})
	_on_opened = func() -> void: _opened_count += 1
	Events.loading_ready_changed.connect(_on_changed)
	Events.loading_gate_opened.connect(_on_opened)


func after_each() -> void:
	Events.loading_ready_changed.disconnect(_on_changed)
	Events.loading_gate_opened.disconnect(_on_opened)
	Match._lifecycle.set_loading_gate_forced(false)
	Match._lifecycle._loading_tuning = Match._lifecycle.LOADING_TUNING
	Match.set_net_provider(null)
	Net._mode = Net.Mode.OFFLINE
	Net._peers = {}
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _config(players: int, ai: int, hot_seat: bool = false) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_map)
	config.player_count = players
	config.ai_count = ai
	config.hot_seat = hot_seat
	config.gifts_enabled = false
	config.block_timer = 6.0
	config.rng_seed = 4242
	return config


func _start_gated(net: Variant, players: int, ai: int, hot_seat: bool = false) -> void:
	Match.set_net_provider(net)
	Match._lifecycle.set_loading_gate_forced(true)
	Match.start_match(_config(players, ai, hot_seat))


func _step(seconds: float) -> void:
	var ticks: int = int(round(seconds / STEP_S))
	for _i: int in range(ticks):
		Match._process(STEP_S)


func _press(peer_id: int) -> void:
	Events.net_loading_ready_received.emit(peer_id)


# --- the pure rule -----------------------------------------------------------

func test_gate_min_display_holds_even_when_everyone_is_ready() -> void:
	var gate: LoadingReadyGate = LoadingReadyGate.new()
	gate.begin(MIN_S, MAX_S)
	assert_true(gate.mark_ready(1, PackedInt32Array([1])))
	assert_false(gate.tick(4.9, PackedInt32Array([1])), "ready at once, but 5 s have not passed")
	assert_almost_eq(gate.min_display_remaining_s(), 0.1, 0.001)
	assert_true(gate.tick(0.2, PackedInt32Array([1])), "opens on the tick that crosses min_display_s")
	assert_false(gate.opened_by_timeout())
	assert_false(gate.tick(1.0, PackedInt32Array([1])), "opens exactly once")


func test_gate_waits_for_every_required_peer() -> void:
	var required: PackedInt32Array = PackedInt32Array([1, 2])
	var gate: LoadingReadyGate = LoadingReadyGate.new()
	gate.begin(MIN_S, MAX_S)
	gate.mark_ready(1, required)
	assert_false(gate.tick(MIN_S + 1.0, required), "peer 2 has not pressed")
	assert_false(gate.all_ready(required))
	gate.mark_ready(2, required)
	assert_true(gate.tick(0.1, required))
	assert_eq(gate.ready_ids(required), required)


func test_gate_with_nobody_to_wait_for_opens_at_min_display() -> void:
	var gate: LoadingReadyGate = LoadingReadyGate.new()
	gate.begin(MIN_S, MAX_S)
	assert_false(gate.tick(MIN_S - 0.5, PackedInt32Array()))
	assert_true(gate.tick(0.6, PackedInt32Array()), "all-bot match: only the minimum display applies")


func test_gate_max_wait_opens_without_the_laggard() -> void:
	var required: PackedInt32Array = PackedInt32Array([1, 2])
	var gate: LoadingReadyGate = LoadingReadyGate.new()
	gate.begin(MIN_S, MAX_S)
	gate.mark_ready(1, required)
	assert_false(gate.tick(MAX_S - 1.0, required))
	assert_true(gate.tick(1.5, required), "safety cap: an AFK peer cannot block everyone forever")
	assert_true(gate.opened_by_timeout())


func test_gate_refuses_spoofed_duplicate_and_late_intents() -> void:
	var required: PackedInt32Array = PackedInt32Array([1, 2])
	var gate: LoadingReadyGate = LoadingReadyGate.new()
	gate.begin(MIN_S, MAX_S)
	assert_false(gate.mark_ready(99, required), "a peer that is not required")
	assert_false(gate.mark_ready(-1, required))
	assert_true(gate.mark_ready(1, required))
	assert_false(gate.mark_ready(1, required), "repeat press changes nothing")
	gate.tick(MIN_S + 1.0, PackedInt32Array([1]))
	assert_true(gate.is_open())
	assert_false(gate.mark_ready(2, required), "an open gate takes no more intents")


func test_gate_leaver_drops_out_of_the_required_set() -> void:
	var gate: LoadingReadyGate = LoadingReadyGate.new()
	gate.begin(MIN_S, MAX_S)
	gate.mark_ready(1, PackedInt32Array([1, 2]))
	assert_false(gate.tick(MIN_S + 1.0, PackedInt32Array([1, 2])))
	assert_true(gate.tick(0.1, PackedInt32Array([1])), "peer 2 left: only peer 1 is still waited for")


# --- the host's gate in MatchLifecycle ---------------------------------------

func test_headless_default_has_no_gate_and_opens_at_once() -> void:
	Match.start_match(_config(2, 0))
	assert_false(Match._lifecycle.is_loading_gate_armed(), "nothing armed it: tests drive Match by hand")
	assert_false(Match._lifecycle.loading_gate_blocking())
	assert_eq(_opened_count, 1, "an unarmed host still announces the open gate (a client of a headless host must not wait)")
	_step(Match.config.effective_countdown_seconds() + 0.5)
	assert_eq(Match.state(), Match.State.PLAYING, "the countdown ran with no ready presses")


func test_countdown_waits_for_min_display_and_all_humans() -> void:
	var net: FakeNet = FakeNet.host({1: 0, 2: 1}, [0] as Array[int])
	_start_gated(net, 2, 0)
	var full: float = Match.countdown_remaining()
	assert_true(Match._lifecycle.loading_gate_blocking())
	assert_eq(Match._lifecycle.loading_required_peers(), PackedInt32Array([1, 2]))
	_step(MIN_S - 1.0)
	assert_eq(Match.countdown_remaining(), full, "the countdown has not started running down")
	_press(1)
	_step(2.0)
	assert_eq(Match.countdown_remaining(), full, "min display elapsed but peer 2 is not ready")
	assert_eq(Match._lifecycle.loading_ready_peers(), PackedInt32Array([1]))
	_press(2)
	_step(STEP_S * 2.0)
	assert_lt(Match.countdown_remaining(), full, "all ready and 5 s gone: countdown runs")
	assert_eq(_opened_count, 1)
	_step(full + 0.5)
	assert_eq(Match.state(), Match.State.PLAYING)


func test_early_ready_still_waits_for_the_minimum_display_time() -> void:
	var net: FakeNet = FakeNet.offline()
	_start_gated(net, 1, 0)
	var full: float = Match.countdown_remaining()
	_press(1)
	_step(MIN_S - 0.6)
	assert_eq(Match.countdown_remaining(), full, "ready at t=0 must not skip the 5 s")
	assert_eq(_opened_count, 0)
	_step(0.8)
	assert_eq(_opened_count, 1)


func test_bots_are_auto_ready_and_never_required() -> void:
	var net: FakeNet = FakeNet.offline()
	_start_gated(net, 3, 2)
	assert_eq(Match._lifecycle.loading_required_peers(), PackedInt32Array([Net.HOST_PEER_ID]), "one human seat, bots are not listed")
	assert_true(Match._lifecycle.loading_slot_ready(1), "bot")
	assert_true(Match._lifecycle.loading_slot_ready(2), "bot")
	assert_false(Match._lifecycle.loading_slot_ready(0), "the human has not pressed yet")
	_press(Net.HOST_PEER_ID)
	assert_true(Match._lifecycle.loading_slot_ready(0))


func test_all_bot_match_needs_only_the_minimum_display() -> void:
	var net: FakeNet = FakeNet.offline()
	_start_gated(net, 2, 2)
	assert_eq(Match._lifecycle.loading_required_peers().size(), 0)
	_step(MIN_S - 0.5)
	assert_true(Match._lifecycle.loading_gate_blocking())
	_step(0.7)
	assert_false(Match._lifecycle.loading_gate_blocking())


func test_hot_seat_one_press_readies_every_local_human() -> void:
	var net: FakeNet = FakeNet.offline()
	_start_gated(net, 3, 0, true)
	assert_eq(Match._lifecycle.loading_required_peers(), PackedInt32Array([Net.HOST_PEER_ID]), "one shared device, one required peer")
	_press(Net.HOST_PEER_ID)
	for slot_id: int in range(3):
		assert_true(Match._lifecycle.loading_slot_ready(slot_id), "slot %d" % slot_id)
	_step(MIN_S + 0.2)
	assert_false(Match._lifecycle.loading_gate_blocking())


func test_disconnected_peer_drops_out_and_the_gate_opens() -> void:
	var net: FakeNet = FakeNet.host({1: 0, 2: 1}, [0] as Array[int])
	_start_gated(net, 2, 0)
	_press(1)
	_step(MIN_S + 1.0)
	assert_true(Match._lifecycle.loading_gate_blocking(), "peer 2 never pressed")
	net.slots_by_peer.erase(2)
	Events.net_peer_left.emit(2, 1, Net.LeaveReason.TIMEOUT)
	assert_eq(_published.back()["required"], PackedInt32Array([1]), "the leaver is no longer waited for")
	_step(STEP_S * 2.0)
	assert_false(Match._lifecycle.loading_gate_blocking())
	assert_eq(_opened_count, 1)


func test_max_wait_starts_the_match_without_an_afk_player() -> void:
	var net: FakeNet = FakeNet.host({1: 0, 2: 1}, [0] as Array[int])
	_start_gated(net, 2, 0)
	_press(1)
	_step(MAX_S - 1.0)
	assert_true(Match._lifecycle.loading_gate_blocking())
	_step(1.5)
	assert_false(Match._lifecycle.loading_gate_blocking(), "ready_wait_max_s elapsed")
	assert_true(Match._lifecycle._ready_gate.opened_by_timeout())


func test_spoofed_spectator_and_late_intents_are_refused() -> void:
	var net: FakeNet = FakeNet.host({1: 0, 2: 1, 3: -1}, [0] as Array[int])
	_start_gated(net, 2, 0)
	_press(99)
	assert_eq(Match._lifecycle.loading_ready_refused, 1, "a peer id that holds no slot")
	_press(3)
	assert_eq(Match._lifecycle.loading_ready_refused, 2, "a spectator holds no human seat")
	assert_eq(Match._lifecycle.loading_ready_peers().size(), 0)
	var published_before: int = _published.size()
	_press(1)
	_press(1)
	assert_eq(Match._lifecycle.loading_ready_peers(), PackedInt32Array([1]), "a repeat press is idempotent")
	assert_eq(_published.size(), published_before + 1, "...and not re-broadcast")
	assert_eq(Match._lifecycle.loading_ready_refused, 2, "a repeat is not a refusal")
	_press(2)
	_step(MIN_S + 0.5)
	assert_false(Match._lifecycle.loading_gate_blocking())
	_press(2)
	assert_eq(Match._lifecycle.loading_ready_refused, 3, "after the gate opened the phase is over")


func test_ready_outside_loading_is_refused() -> void:
	Match.start_match(_config(2, 0))
	_press(1)
	assert_eq(Match._lifecycle.loading_ready_refused, 1, "no armed gate in this match")
	assert_eq(Match._lifecycle.loading_ready_peers().size(), 0)


func test_a_new_match_starts_with_a_fresh_gate() -> void:
	var net: FakeNet = FakeNet.offline()
	_start_gated(net, 1, 0)
	_press(Net.HOST_PEER_ID)
	assert_eq(Match._lifecycle.loading_ready_peers().size(), 1)
	Match.start_match(_config(1, 0))
	assert_eq(Match._lifecycle.loading_ready_peers().size(), 0, "last match's presses never leak")
	assert_true(Match._lifecycle.loading_gate_blocking())


# --- clients mirror the host --------------------------------------------------

func test_client_waits_for_the_hosts_open_message_and_mirrors_the_sets() -> void:
	var net: FakeNet = FakeNet.client(1)
	_start_gated(net, 2, 0)
	assert_true(Match._lifecycle.loading_gate_blocking())
	Events.loading_ready_changed.emit(PackedInt32Array([1]), PackedInt32Array([1, 2]))
	assert_eq(Match._lifecycle.loading_ready_peers(), PackedInt32Array([1]))
	assert_eq(Match._lifecycle.loading_required_peers(), PackedInt32Array([1, 2]))
	assert_true(Match._lifecycle.loading_gate_blocking(), "still waiting for the host")
	Events.loading_gate_opened.emit()
	assert_false(Match._lifecycle.loading_gate_blocking())


func test_client_stops_waiting_when_the_host_match_moved_on() -> void:
	var net: FakeNet = FakeNet.client(1)
	_start_gated(net, 2, 0)
	assert_true(Match._lifecycle.loading_gate_blocking())
	Match._lifecycle.apply_replicated_state_change(Match.State.PLAYING)
	assert_false(Match._lifecycle.loading_gate_blocking(), "a missed open message cannot strand a client")


# --- Net validates the sender --------------------------------------------------

func test_net_forwards_only_seated_peers() -> void:
	var seen: Array[int] = []
	var on_intent: Callable = func(peer_id: int) -> void: seen.append(peer_id)
	Events.net_loading_ready_received.connect(on_intent)
	Net._mode = Net.Mode.HOST
	Net._peers = {
		1: {"peer_id": 1, "slot_id": 0},
		2: {"peer_id": 2, "slot_id": 1},
		3: {"peer_id": 3, "slot_id": -1},
	}
	assert_true(Net._handle_loading_ready(2))
	assert_false(Net._handle_loading_ready(3), "a spectator")
	assert_false(Net._handle_loading_ready(77), "an unknown peer id")
	Net._mode = Net.Mode.CLIENT
	assert_false(Net._handle_loading_ready(2), "only the host takes intents")
	Events.net_loading_ready_received.disconnect(on_intent)
	assert_eq(seen, [2] as Array[int])


func test_net_request_on_host_and_offline_uses_the_local_peer_id() -> void:
	var seen: Array[int] = []
	var on_intent: Callable = func(peer_id: int) -> void: seen.append(peer_id)
	Events.net_loading_ready_received.connect(on_intent)
	Net.request_loading_ready()
	Events.net_loading_ready_received.disconnect(on_intent)
	assert_eq(seen, [Net.HOST_PEER_ID] as Array[int])


func test_net_client_rejects_malformed_or_oversized_mirrors() -> void:
	var count: Array[int] = [0]
	var on_set: Callable = func(_r: PackedInt32Array, _q: PackedInt32Array) -> void: count[0] += 1
	Events.loading_ready_changed.connect(on_set)
	Net._mode = Net.Mode.CLIENT
	Net._rpc_loading_ready_state(PackedInt32Array([1]), PackedInt32Array([1, 2]))
	assert_eq(count[0], 1)
	var too_many: PackedInt32Array = PackedInt32Array()
	for i: int in range(Net.config.max_peers + 1):
		too_many.append(i + 1)
	Net._rpc_loading_ready_state(PackedInt32Array(), too_many)
	Net._rpc_loading_ready_state(PackedInt32Array([-5]), PackedInt32Array([1]))
	assert_eq(count[0], 1, "oversized and negative ids are dropped")
	Net._mode = Net.Mode.HOST
	Net._rpc_loading_ready_state(PackedInt32Array([1]), PackedInt32Array([1]))
	Net._rpc_loading_gate_open()
	assert_eq(count[0], 1, "a host never applies a mirror")
	assert_eq(_opened_count, 0)
	Events.loading_ready_changed.disconnect(on_set)


# --- tuning + the LoadingScreen glue -------------------------------------------

func test_tuning_defaults_are_the_owners_values() -> void:
	var tuning: LoadingScreenTuning = load("res://config/loading_screen_tuning.tres") as LoadingScreenTuning
	assert_almost_eq(tuning.min_display_s, 5.0, 0.0001)
	assert_almost_eq(tuning.ready_wait_max_s, 60.0, 0.0001)
	assert_almost_eq(tuning.ready_timeout_s, 20.0, 0.0001, "asset-loading timeout keeps its meaning")


func _screen() -> LoadingScreen:
	var screen: LoadingScreen = autofree(load("res://ui/LoadingScreen.tscn").instantiate()) as LoadingScreen
	add_child_autofree(screen)
	screen.tuning = LoadingScreenTuning.new()
	screen.tuning.warmup_frames = 1
	screen.tuning.fade_out_duration_s = 0.02
	screen.tuning.min_display_s = 0.05
	screen.tuning.ready_wait_max_s = 5.0
	return screen


func _accept_key() -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_ENTER
	event.physical_keycode = KEY_ENTER
	event.pressed = true
	return event


func test_screen_ready_input_is_off_until_loading_finished_and_holds_the_overlay() -> void:
	var net: FakeNet = FakeNet.offline()
	_start_gated(net, 1, 0)
	Match._lifecycle._loading_tuning = LoadingScreenTuning.new()
	Match._lifecycle._loading_tuning.min_display_s = 0.05
	Match._lifecycle._ready_gate.begin(0.05, 5.0)
	var screen: LoadingScreen = _screen()
	screen.show_for_match(_config(1, 0), [] as Array[PlayerSlot])
	assert_true(screen.ready_gate_armed())
	assert_false(screen.accepts_ready_input())
	assert_false(screen.press_ready(), "no ready before this instance finished loading")
	screen._input(_accept_key())
	assert_eq(Match._lifecycle.loading_ready_peers().size(), 0, "the early press did nothing")
	screen.fade_out()
	assert_true(screen.accepts_ready_input())
	await wait_seconds(0.3, "no press yet")
	assert_true(screen.visible, "the overlay stays up until the player is ready")
	screen._input(_accept_key())
	assert_eq(Match._lifecycle.loading_ready_peers(), PackedInt32Array([Net.HOST_PEER_ID]), "Enter is ui_accept")
	_step(0.3)
	assert_false(Match._lifecycle.loading_gate_blocking())
	await wait_seconds(0.4, "warmup frame + fade")
	assert_false(screen.visible)
	assert_false(screen.accepts_ready_input())


func test_screen_gamepad_a_is_the_same_ready_action() -> void:
	var net: FakeNet = FakeNet.offline()
	_start_gated(net, 1, 0)
	var screen: LoadingScreen = _screen()
	screen.show_for_match(_config(1, 0), [] as Array[PlayerSlot])
	screen.fade_out()
	var pad: InputEventJoypadButton = InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	screen._input(pad)
	assert_true(screen.local_ready(), "A on a gamepad readies")
	var released: InputEventJoypadButton = InputEventJoypadButton.new()
	released.button_index = JOY_BUTTON_A
	released.pressed = false
	screen._input(released)
	screen.cancel()


func test_screen_client_gives_up_after_the_wait_cap() -> void:
	var net: FakeNet = FakeNet.client(1)
	_start_gated(net, 2, 0)
	var screen: LoadingScreen = _screen()
	screen.tuning.ready_wait_max_s = 0.15
	screen.show_for_match(_config(2, 0), [] as Array[PlayerSlot])
	screen.fade_out()
	await wait_seconds(0.1)
	assert_true(screen.visible, "still waiting for the host")
	await wait_seconds(0.6, "cap + warmup + fade")
	assert_false(screen.visible, "a lost host message never freezes a client")


func test_screen_unarmed_fade_is_unchanged() -> void:
	var screen: LoadingScreen = _screen()
	screen.show_for_match(_config(1, 0), [] as Array[PlayerSlot])
	assert_false(screen.ready_gate_armed(), "headless and not in LOADING: no gate")
	screen.fade_out()
	assert_false(screen.accepts_ready_input())
	await wait_seconds(0.3)
	assert_false(screen.visible)
