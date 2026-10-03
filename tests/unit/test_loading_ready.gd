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
	_stop_counting()
	AgentProbe.set_forced_for_test(-1)
	Settings.set_active_input_device_for_test(Settings.DEVICE_KEYBOARD_MOUSE)
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


## Bontago-1pi.32 L3 (review): an agent-probe run (windowed screenshot/bench tools
## that boot Main and call start_match) must not sit on the ready gate.
func test_gate_is_suppressed_for_headless_and_agent_probe_environments() -> void:
	assert_true(MatchLifecycle.gate_suppressed_for_environment("headless", false))
	assert_true(MatchLifecycle.gate_suppressed_for_environment("windows", true), "a windowed agent probe is not a player")
	assert_true(MatchLifecycle.gate_suppressed_for_environment("headless", true))
	assert_false(MatchLifecycle.gate_suppressed_for_environment("windows", false), "a real window arms the gate")


## What the LoadingScreen does at LOADING: ask the lifecycle to arm the gate.
func _arm_at_loading(results: Array[bool]) -> Callable:
	var on_state: Callable = func(_from: int, to: int) -> void:
		if to == Match.State.LOADING:
			results.append(Match._lifecycle.arm_loading_ready_gate())
	Events.match_state_changed.connect(on_state)
	return on_state


func test_agent_probe_run_leaves_the_gate_unarmed_unless_forced() -> void:
	AgentProbe.set_forced_for_test(1)
	var results: Array[bool] = []
	var on_state: Callable = _arm_at_loading(results)
	Match.start_match(_config(2, 0))
	assert_eq(results, [false] as Array[bool], "the overlay's arm request is refused in a probe run")
	assert_false(Match._lifecycle.is_loading_gate_armed())
	assert_false(Match._lifecycle.loading_gate_blocking())
	assert_eq(_opened_count, 1, "unarmed: the gate announces open at once, nothing waits")
	_step(Match.config.effective_countdown_seconds() + 0.5)
	assert_eq(Match.state(), Match.State.PLAYING, "no ready press needed in a probe run")
	Match.abort_match()
	Match._lifecycle.set_loading_gate_forced(true)
	results.clear()
	Match.start_match(_config(2, 0))
	assert_eq(results, [true] as Array[bool], "the explicit force seam still arms it (tools/screenshot_loading_ready.gd)")
	assert_true(Match._lifecycle.loading_gate_blocking())
	Events.match_state_changed.disconnect(on_state)


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
	await _close(screen)


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


# --- L2: the ready prompt, status line and player list (presentation) ----------

var _intent_probe: Callable


func _match_slots() -> Array[PlayerSlot]:
	var result: Array[PlayerSlot] = []
	for slot_id: int in range(Match.slot_count()):
		result.append(Match.slot(slot_id))
	return result


## A gated match plus a shown overlay (loading not finished until fade_out()).
func _open_screen(net: Variant, players: int, ai: int, hot_seat: bool = false) -> LoadingScreen:
	_start_gated(net, players, ai, hot_seat)
	var screen: LoadingScreen = _screen()
	screen.tuning.min_display_s = MIN_S
	screen.tuning.ready_wait_max_s = MAX_S
	screen.show_for_match(_config(players, ai, hot_seat), _match_slots())
	return screen


## Ends an overlay and lets its fade_out() coroutine resume (and bail on the bumped
## token) while the node still exists, so the run logs no freed-instance resume.
func _close(screen: LoadingScreen) -> void:
	screen.cancel()
	await wait_process_frames(2)


func _accept_pad() -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_A
	event.pressed = true
	return event


## Counts the ready intents that reach the bus (one per accepted press).
func _count_intents() -> Array[int]:
	var counter: Array[int] = [0]
	_intent_probe = func(_peer_id: int) -> void: counter[0] += 1
	Events.net_loading_ready_received.connect(_intent_probe)
	return counter


func _stop_counting() -> void:
	if _intent_probe.is_valid() and Events.net_loading_ready_received.is_connected(_intent_probe):
		Events.net_loading_ready_received.disconnect(_intent_probe)


func _slots_for_layout(count: int, bots: int) -> Array[PlayerSlot]:
	var result: Array[PlayerSlot] = []
	for i: int in range(count):
		var slot_item: PlayerSlot = PlayerSlot.new(i, i, "Player %d" % (i + 1), Color.from_hsv(float(i) / 8.0, 0.6, 0.9))
		slot_item.is_bot = i >= count - bots
		result.append(slot_item)
	return result


func test_prompt_is_hidden_until_loading_finished_and_shows_the_bound_glyph() -> void:
	Settings.set_active_input_device_for_test(Settings.DEVICE_KEYBOARD_MOUSE)
	var screen: LoadingScreen = _open_screen(FakeNet.offline(), 1, 0)
	assert_true(screen.ready_gate_armed())
	assert_false(screen._ready_button.visible, "no prompt while this instance is still loading")
	assert_true(screen._ready_box.visible)
	assert_eq(screen._status_label.text, screen.tuning.get_ready_text, "subtle 'Get ready...' while it loads")
	assert_true(screen._player_list.visible, "the ready list replaces the plain name list")
	assert_false(screen._info_label.visible)
	screen.fade_out()
	assert_true(screen.accepts_ready_input())
	assert_true(screen._ready_button.visible, "the prompt opens with the ready input")
	assert_eq(screen._prompt_prefix.text, "Press")
	assert_eq(screen._prompt_suffix.text, "to ready")
	assert_eq(screen.prompt_glyph_texts(), PackedStringArray(["Enter"]), "keyboard glyph of ui_accept")
	assert_eq(screen._status_label.text, screen.tuning.get_ready_text, "min display still remains")
	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)
	assert_eq(screen.prompt_glyph_texts(), PackedStringArray(["A"]), "a gamepad user sees the A button")
	Settings.set_active_input_device_for_test(Settings.DEVICE_KEYBOARD_MOUSE)
	assert_eq(screen.prompt_glyph_texts(), PackedStringArray(["Enter"]))
	await _close(screen)


func test_synthetic_ui_accept_presses_once_for_key_and_gamepad_a() -> void:
	var counter: Array[int] = _count_intents()
	var screen: LoadingScreen = _open_screen(FakeNet.offline(), 1, 0)
	Input.parse_input_event(_accept_key())
	Input.flush_buffered_events()
	assert_eq(counter[0], 0, "ui_accept before loading finished is not a ready press")
	screen.fade_out()
	Input.parse_input_event(_accept_key())
	Input.flush_buffered_events()
	assert_eq(counter[0], 1, "the Enter key readies through the Input Map")
	assert_true(screen.local_pressed())
	Input.parse_input_event(_accept_pad())
	Input.flush_buffered_events()
	screen._input(_accept_pad())
	assert_eq(counter[0], 1, "idempotent: A afterwards (and a repeat) never re-sends")
	assert_false(screen.press_ready(), "an explicit second call reports it sent nothing")
	assert_true(screen._ready_button.disabled, "the prompt is disabled after the press")
	await _close(screen)
	_stop_counting()


func test_gamepad_a_alone_readies_once() -> void:
	var counter: Array[int] = _count_intents()
	var screen: LoadingScreen = _open_screen(FakeNet.offline(), 1, 0)
	screen.fade_out()
	Input.parse_input_event(_accept_pad())
	Input.flush_buffered_events()
	assert_eq(counter[0], 1)
	assert_true(screen.local_ready(), "the host (offline) accepted it")
	await _close(screen)
	_stop_counting()


func test_clicking_the_prompt_readies_once() -> void:
	var counter: Array[int] = _count_intents()
	var screen: LoadingScreen = _open_screen(FakeNet.offline(), 1, 0)
	screen._ready_button.pressed.emit()
	assert_eq(counter[0], 0, "a click before loading finished does nothing")
	screen.fade_out()
	screen._ready_button.pressed.emit()
	screen._ready_button.pressed.emit()
	assert_eq(counter[0], 1)
	assert_true(screen.local_pressed())
	await _close(screen)
	_stop_counting()


func test_player_list_follows_loading_ready_changed_and_bots_are_ready() -> void:
	var net: FakeNet = FakeNet.host({1: 0, 2: 1}, [0] as Array[int])
	var screen: LoadingScreen = _open_screen(net, 3, 1)
	assert_eq(screen._ready_rows.size(), 3)
	assert_false(screen.player_row_ready(0), "human, not pressed")
	assert_false(screen.player_row_ready(1), "human, not pressed")
	assert_true(screen.player_row_ready(2), "bots are shown ready")
	screen.fade_out()
	screen.press_ready()
	assert_true(screen.player_row_ready(0), "local press ticks the row at once")
	assert_false(screen.player_row_ready(1))
	assert_eq(screen._status_label.text, "Waiting for 1 player...")
	_press(2)
	assert_true(screen.player_row_ready(1), "the other peer's ready reaches the list")
	await _close(screen)


func test_player_list_names_colours_and_bot_marks() -> void:
	var screen: LoadingScreen = _open_screen(FakeNet.offline(), 3, 1)
	var rows: Array[Node] = screen._player_list.get_children()
	assert_eq(rows.size(), 3)
	for slot_id: int in range(3):
		var slot_item: PlayerSlot = Match.slot(slot_id)
		var swatch: Panel = rows[slot_id].get_child(0) as Panel
		var box: StyleBoxFlat = swatch.get_theme_stylebox("panel") as StyleBoxFlat
		assert_eq(box.bg_color, slot_item.color, "swatch is the player's colour")
		var label: Label = rows[slot_id].get_child(1) as Label
		assert_true(label.text.begins_with(slot_item.display_name))
		assert_eq(label.text.ends_with(screen.tuning.bot_suffix), slot_item.is_bot)
	await _close(screen)


func test_waiting_status_counts_the_others_and_the_cap_counts_down() -> void:
	var net: FakeNet = FakeNet.host({1: 0, 2: 1, 3: 2}, [0] as Array[int])
	var screen: LoadingScreen = _open_screen(net, 3, 0)
	screen.fade_out()
	assert_eq(screen._cap_label.text, "Starting in 60s", "the safety cap is running while someone is not ready")
	screen.press_ready()
	assert_eq(screen._status_label.text, "Waiting for 2 players...")
	assert_true(screen._ready_button.visible, "the prompt stays, disabled")
	assert_almost_eq(screen._ready_button.modulate.a, screen.tuning.ready_prompt_disabled_alpha, 0.001)
	screen._displayed_s = MAX_S - 12.4
	screen._refresh_ready_ui()
	assert_eq(screen._cap_label.text, "Starting in 13s", "rounded up to whole seconds")
	_press(2)
	assert_eq(screen._status_label.text, "Waiting for 1 player...")
	_press(3)
	assert_eq(screen._cap_label.text, "", "everyone is ready: the cap no longer matters")
	await _close(screen)


func test_all_ready_before_min_display_shows_get_ready_not_waiting() -> void:
	var screen: LoadingScreen = _open_screen(FakeNet.offline(), 1, 0)
	screen.fade_out()
	screen.press_ready()
	assert_eq(screen._status_label.text, screen.tuning.get_ready_text, "everyone ready but the minimum display time remains")
	_step(MIN_S + 0.2)
	screen._displayed_s = MIN_S + 0.1
	screen._refresh_ready_ui()
	assert_false(screen._ready_button.visible, "the gate opened: prompt gone")
	assert_eq(screen._status_label.text, "")
	await _close(screen)


func test_all_bot_match_and_spectator_get_no_prompt() -> void:
	var screen: LoadingScreen = _open_screen(FakeNet.offline(), 2, 2)
	screen.fade_out()
	assert_false(screen._ready_button.visible, "nobody to press: the minimum display alone holds the screen")
	assert_eq(screen._status_label.text, screen.tuning.get_ready_text)
	await _close(screen)
	var net: FakeNet = FakeNet.host({2: 0, 3: -1}, [0] as Array[int])
	var spectator_screen: LoadingScreen = _open_screen(net, 1, 0)
	spectator_screen.fade_out()
	assert_false(spectator_screen._ready_button.visible, "the local peer holds no seat in this roster")
	await _close(spectator_screen)


func test_client_list_mirrors_the_hosts_sets() -> void:
	var net: FakeNet = FakeNet.client(1)
	net.slots_by_peer = {1: 0, 2: 1}
	var screen: LoadingScreen = _open_screen(net, 2, 0)
	screen.fade_out()
	assert_false(screen._ready_button.visible, "no host message yet: nothing to press for")
	Events.loading_ready_changed.emit(PackedInt32Array(), PackedInt32Array([1, 2]))
	assert_true(screen._ready_button.visible)
	assert_false(screen.player_row_ready(0))
	Events.loading_ready_changed.emit(PackedInt32Array([2]), PackedInt32Array([1, 2]))
	assert_true(screen.player_row_ready(1), "the host's mirror ticks peer 2's row")
	assert_false(screen.player_row_ready(0))
	assert_false(screen._ready_button.disabled)
	Events.loading_gate_opened.emit()
	assert_false(screen._ready_button.visible, "the gate opened")
	await _close(screen)


func test_unarmed_overlay_keeps_the_plain_name_list_and_no_prompt() -> void:
	var screen: LoadingScreen = _screen()
	screen.show_for_match(_config(2, 0), _slots_for_layout(2, 0))
	assert_false(screen.ready_gate_armed())
	assert_true(screen._info_label.visible)
	assert_false(screen._player_list.visible)
	assert_false(screen._ready_box.visible)
	assert_true(screen._info_label.text.findn("Player 1") >= 0)


func _opened_counter(screen: LoadingScreen) -> Array[int]:
	var opened: Array[int] = [0]
	screen.ready_prompt_opened.connect(func() -> void: opened[0] += 1)
	return opened


## Bontago-1pi.32 L3 (review): the prompt and the ready input exist only while the
## gate blocks AND the host waits for the local peer.
func test_spectator_is_never_prompted_and_cannot_press_ready() -> void:
	var counter: Array[int] = _count_intents()
	var net: FakeNet = FakeNet.host({2: 0, 3: -1}, [0] as Array[int])
	var screen: LoadingScreen = _open_screen(net, 1, 0)
	var opened: Array[int] = _opened_counter(screen)
	screen.fade_out()
	assert_false(screen.accepts_ready_input(), "the local peer holds no human seat")
	assert_false(screen._ready_button.visible)
	screen._input(_accept_key())
	screen._input(_accept_pad())
	Input.parse_input_event(_accept_key())
	Input.flush_buffered_events()
	screen._ready_button.pressed.emit()
	assert_false(screen.press_ready())
	assert_false(screen.local_pressed())
	assert_eq(counter[0], 0, "no intent leaves a spectator")
	assert_eq(opened[0], 0, "ready_prompt_opened never fires for a spectator")
	await _close(screen)
	_stop_counting()


func test_client_of_an_ungated_host_is_never_prompted() -> void:
	var counter: Array[int] = _count_intents()
	var net: FakeNet = FakeNet.client(1)
	net.slots_by_peer = {1: 0, 2: 1}
	var screen: LoadingScreen = _open_screen(net, 2, 0)
	var opened: Array[int] = _opened_counter(screen)
	screen.fade_out()
	Events.loading_gate_opened.emit()
	Events.loading_ready_changed.emit(PackedInt32Array(), PackedInt32Array([1, 2]))
	assert_false(Match._lifecycle.loading_gate_blocking(), "the host announced the gate open (it never armed one)")
	assert_false(screen.accepts_ready_input())
	assert_false(screen._ready_button.visible)
	screen._input(_accept_key())
	assert_false(screen.press_ready())
	assert_eq(counter[0], 0)
	assert_eq(opened[0], 0)
	await _close(screen)
	_stop_counting()


func test_late_joiner_after_the_countdown_loses_the_prompt() -> void:
	var counter: Array[int] = _count_intents()
	var net: FakeNet = FakeNet.client(1)
	net.slots_by_peer = {1: 0, 2: 1}
	var screen: LoadingScreen = _open_screen(net, 2, 0)
	screen.fade_out()
	Events.loading_ready_changed.emit(PackedInt32Array(), PackedInt32Array([1, 2]))
	assert_true(screen.accepts_ready_input(), "fixture: a waiting client is prompted")
	Match._lifecycle.apply_replicated_state_change(Match.State.PLAYING)
	screen._refresh_ready_ui()
	assert_false(screen.accepts_ready_input(), "the host's match moved on: nothing left to press for")
	assert_false(screen._ready_button.visible)
	screen._input(_accept_key())
	assert_eq(counter[0], 0)
	await _close(screen)
	_stop_counting()


func test_client_prompt_opens_once_when_the_host_requires_the_local_peer() -> void:
	var counter: Array[int] = _count_intents()
	var net: FakeNet = FakeNet.client(1)
	net.slots_by_peer = {1: 0, 2: 1}
	var screen: LoadingScreen = _open_screen(net, 2, 0)
	var opened: Array[int] = _opened_counter(screen)
	screen.fade_out()
	assert_eq(opened[0], 0, "no host mirror yet")
	Events.loading_ready_changed.emit(PackedInt32Array(), PackedInt32Array([2]))
	assert_false(screen.accepts_ready_input(), "the host waits for peer 2 only")
	assert_eq(opened[0], 0)
	Events.loading_ready_changed.emit(PackedInt32Array(), PackedInt32Array([1, 2]))
	assert_true(screen.accepts_ready_input())
	assert_eq(opened[0], 1)
	Events.loading_ready_changed.emit(PackedInt32Array([2]), PackedInt32Array([1, 2]))
	assert_eq(opened[0], 1, "announced once per match")
	assert_true(screen.press_ready())
	assert_eq(counter[0], 1)
	await _close(screen)
	_stop_counting()


func test_required_human_is_prompted_and_the_signal_fires_once() -> void:
	var screen: LoadingScreen = _open_screen(FakeNet.offline(), 1, 0)
	var opened: Array[int] = _opened_counter(screen)
	assert_eq(opened[0], 0, "still loading")
	screen.fade_out()
	assert_eq(opened[0], 1)
	screen._refresh_ready_ui()
	assert_eq(opened[0], 1)
	await _close(screen)


## Bontago-1pi.32 L3: the loading overlay sits above the HUD's CanvasLayer (player
## bars, held/next, minimap, timer ring and the big countdown digit), fully opaque
## until the fade starts -- which only happens once the gate has opened.
func test_overlay_covers_the_hud_and_stays_opaque_while_the_gate_blocks() -> void:
	var screen: LoadingScreen = _open_screen(FakeNet.offline(), 1, 0)
	var hud: HUD = autofree(load("res://ui/HUD.tscn").instantiate()) as HUD
	add_child_autofree(hud)
	assert_gt(screen.overlay_canvas_layer(), hud.layer, "the overlay draws above the HUD layer")
	assert_lt(screen.overlay_canvas_layer(), PauseMenu.OVERLAY_LAYER, "the pause menu still draws above the overlay")
	screen.fade_out()
	await wait_seconds(0.3, "past the warmup frames; nobody pressed ready")
	assert_true(screen.visible)
	assert_true(screen.overlay_layer_visible())
	assert_almost_eq(screen.overlay_opacity(), 1.0, 0.0001, "no fade (and so no countdown peeking through) while the gate blocks")
	assert_almost_eq(screen.tuning.background_color.a, 1.0, 0.0001, "the backdrop is opaque")
	assert_true(Match._lifecycle.loading_gate_blocking())
	await _close(screen)


## The overlay laid out in a SubViewport that scales like a real window of that
## size (ui/UiScale.gd): the card must stay inside the logical canvas and nothing
## in it may overlap, with the worst-case 8-player list.
func _layout_in(window_size: Vector2i) -> void:
	var net: FakeNet = FakeNet.offline()
	_start_gated(net, 8, 3)
	var viewport: SubViewport = autofree(UiScale.make_viewport(window_size))
	add_child_autofree(viewport)
	# The live HUD is part of the real scene: its top-centre timer ring lands on the
	# title of the 8-player card at both sizes, which is why the overlay must draw on
	# a higher CanvasLayer than the HUD.
	var hud: HUD = autofree(load("res://ui/HUD.tscn").instantiate()) as HUD
	viewport.add_child(hud)
	var screen: LoadingScreen = autofree(load("res://ui/LoadingScreen.tscn").instantiate()) as LoadingScreen
	viewport.add_child(screen)
	screen.show_for_match(_config(8, 3), _match_slots())
	screen.fade_out()
	await wait_process_frames(3)
	var canvas: Rect2 = Rect2(Vector2.ZERO, viewport.get_visible_rect().size)
	var card: Rect2 = screen._card.get_global_rect()
	assert_true(canvas.encloses(card), "%s: card %s inside canvas %s" % [window_size, card, canvas])
	var ring: Rect2 = (hud.get_node("%TimerRing") as Control).get_global_rect()
	assert_gt(screen.overlay_canvas_layer(), hud.layer, "%s: HUD timer ring %s vs card %s: the overlay covers the HUD" % [window_size, ring, card])
	var title_rect: Rect2 = screen._map_label.get_global_rect()
	assert_true(card.encloses(title_rect), "%s: the title is inside the card" % window_size)
	assert_false(title_rect.intersects(screen._player_list.get_global_rect()), "%s: title and player list do not overlap" % window_size)
	var list_rect: Rect2 = screen._player_list.get_global_rect()
	var bar_rect: Rect2 = screen._progress_bar.get_global_rect()
	var ready_rect: Rect2 = screen._ready_box.get_global_rect()
	assert_false(list_rect.intersects(bar_rect), "list and progress bar do not overlap")
	assert_false(list_rect.intersects(ready_rect), "list and ready box do not overlap")
	assert_false(bar_rect.intersects(ready_rect), "progress bar and ready box do not overlap")
	assert_true(screen._ready_button.visible)
	assert_true(ready_rect.encloses(screen._ready_button.get_global_rect()), "the prompt sits inside the reserved ready box")
	assert_gte(screen._ready_button.size.x, screen._prompt_content.get_combined_minimum_size().x, "the pill is wide enough for its content")
	assert_true(card.encloses(ready_rect), "the ready box is inside the card")
	assert_ne(screen._status_label.text, "")
	assert_ne(screen._cap_label.text, "")
	assert_almost_eq(ready_rect.size.y, screen.tuning.ready_box_min_height_px, 0.5, "status + prompt + cap fit the reserved height, so the card never jumps")
	await _close(screen)


func test_eight_player_card_fits_1280x720_without_overlap() -> void:
	await _layout_in(Vector2i(1280, 720))


func test_eight_player_card_fits_ultrawide_without_overlap() -> void:
	await _layout_in(Vector2i(3440, 1440))
