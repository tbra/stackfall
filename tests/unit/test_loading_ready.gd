extends GutTest
## Bontago-1pi.32 (owner playtest 2026-10-03): the loading screen stays up for a
## minimum time and every human presses ready (ui_accept / gamepad A) before the
## host starts the countdown. Covers the pure rule (core/LoadingReadyGate.gd),
## the host's authoritative gate in autoload/match/MatchLifecycle.gd, Net's
## intent validation, and ui/LoadingScreen.gd's input glue.

const MatchNetScript := preload("res://net/MatchNet.gd")
const MIN_S: float = 5.0  # a long step that used to be the minimum display time
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
var _wire_nets: Array[MatchNetScript] = []


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
	for wire_net: MatchNetScript in _wire_nets:
		if wire_net != null and is_instance_valid(wire_net):
			wire_net.set_providers(null, null)
	_wire_nets.clear()
	Match.set_replicator(null)
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

func test_gate_opens_on_the_tick_everyone_is_ready_with_no_minimum_display() -> void:
	var gate: LoadingReadyGate = LoadingReadyGate.new()
	gate.begin()
	assert_false(gate.tick(0.0, PackedInt32Array([1])), "nobody pressed yet")
	assert_true(gate.mark_ready(1, PackedInt32Array([1])))
	assert_true(gate.tick(0.01, PackedInt32Array([1])), "opens at once: the 5 s minimum is gone (1pi.63)")
	assert_false(gate.tick(1.0, PackedInt32Array([1])), "opens exactly once")


func test_gate_waits_for_every_required_peer() -> void:
	var required: PackedInt32Array = PackedInt32Array([1, 2])
	var gate: LoadingReadyGate = LoadingReadyGate.new()
	gate.begin()
	gate.mark_ready(1, required)
	assert_false(gate.tick(MIN_S + 1.0, required), "peer 2 has not pressed")
	assert_false(gate.all_ready(required))
	gate.mark_ready(2, required)
	assert_true(gate.tick(0.1, required))
	assert_eq(gate.ready_ids(required), required)


func test_gate_with_nobody_to_wait_for_opens_at_once() -> void:
	var gate: LoadingReadyGate = LoadingReadyGate.new()
	gate.begin()
	assert_true(gate.tick(0.01, PackedInt32Array()), "all-bot match: nothing to wait for")


## Bontago-1pi.125: the hidden auto-start timer is gone; no elapsed time opens the gate.
func test_gate_never_opens_by_elapsed_time_without_the_laggard() -> void:
	var required: PackedInt32Array = PackedInt32Array([1, 2])
	var gate: LoadingReadyGate = LoadingReadyGate.new()
	gate.begin()
	gate.mark_ready(1, required)
	assert_false(gate.tick(MAX_S * 10.0, required), "no cap: the old 60 s auto-start is removed")
	assert_false(gate.is_open())
	gate.mark_ready(2, required)
	assert_true(gate.tick(0.01, required), "opens only once the laggard is ready")


func test_gate_refuses_spoofed_duplicate_and_late_intents() -> void:
	var required: PackedInt32Array = PackedInt32Array([1, 2])
	var gate: LoadingReadyGate = LoadingReadyGate.new()
	gate.begin()
	assert_false(gate.mark_ready(99, required), "a peer that is not required")
	assert_false(gate.mark_ready(-1, required))
	assert_true(gate.mark_ready(1, required))
	assert_false(gate.mark_ready(1, required), "repeat press changes nothing")
	gate.tick(MIN_S + 1.0, PackedInt32Array([1]))
	assert_true(gate.is_open())
	assert_false(gate.mark_ready(2, required), "an open gate takes no more intents")


func test_gate_leaver_drops_out_of_the_required_set() -> void:
	var gate: LoadingReadyGate = LoadingReadyGate.new()
	gate.begin()
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


func test_countdown_waits_for_all_humans() -> void:
	var net: FakeNet = FakeNet.host({1: 0, 2: 1}, [0] as Array[int])
	_start_gated(net, 2, 0)
	var full: float = Match.countdown_remaining()
	assert_true(Match._lifecycle.loading_gate_blocking())
	assert_eq(Match._lifecycle.loading_required_peers(), PackedInt32Array([1, 2]))
	_step(MIN_S - 1.0)
	assert_eq(Match.countdown_remaining(), full, "the countdown has not started running down")
	_press(1)
	_step(2.0)
	assert_eq(Match.countdown_remaining(), full, "peer 2 is not ready")
	assert_eq(Match._lifecycle.loading_ready_peers(), PackedInt32Array([1]))
	_press(2)
	_step(STEP_S * 2.0)
	assert_lt(Match.countdown_remaining(), full, "all ready: countdown runs")
	assert_eq(_opened_count, 1)
	_step(full + 0.5)
	assert_eq(Match.state(), Match.State.PLAYING)


## Bontago-1pi.67: the host is seeded exactly like a client -- nobody is ready when
## LOADING starts, whatever the lobby Ready toggle said (a host's lobby entry is
## seeded ready for the Start gate; the loading gate must not read it).
func test_host_and_clients_start_loading_not_ready_and_host_needs_its_own_press() -> void:
	var net: FakeNet = FakeNet.host({1: 0, 2: 1}, [0] as Array[int])
	_start_gated(net, 2, 0)
	assert_eq(Match._lifecycle.loading_required_peers(), PackedInt32Array([1, 2]))
	assert_eq(Match._lifecycle.loading_ready_peers().size(), 0, "no peer is pre-readied")
	assert_false(Match._lifecycle.loading_slot_ready(0), "host row: not ready")
	assert_false(Match._lifecycle.loading_slot_ready(1), "client row: not ready")
	assert_eq(_published.back()["ready"], PackedInt32Array(), "the first publish carries no ready peer")
	_press(2)
	assert_eq(Match._lifecycle.loading_ready_peers(), PackedInt32Array([2]))
	assert_true(Match._lifecycle.loading_gate_blocking(), "the host still has to press its own ready")
	_press(1)
	assert_eq(Match._lifecycle.loading_ready_peers(), PackedInt32Array([1, 2]))


func test_ready_press_opens_the_gate_with_no_minimum_display_time() -> void:
	var net: FakeNet = FakeNet.offline()
	_start_gated(net, 1, 0)
	var full: float = Match.countdown_remaining()
	_step(STEP_S * 2.0)
	assert_eq(Match.countdown_remaining(), full, "nobody pressed: still holding")
	assert_eq(_opened_count, 0)
	_press(1)
	_step(STEP_S * 2.0)
	assert_eq(_opened_count, 1, "one press opens it at once (1pi.63: no 5 s minimum)")


func test_bots_are_auto_ready_and_never_required() -> void:
	var net: FakeNet = FakeNet.offline()
	_start_gated(net, 3, 2)
	assert_eq(Match._lifecycle.loading_required_peers(), PackedInt32Array([Net.HOST_PEER_ID]), "one human seat, bots are not listed")
	assert_true(Match._lifecycle.loading_slot_ready(1), "bot")
	assert_true(Match._lifecycle.loading_slot_ready(2), "bot")
	assert_false(Match._lifecycle.loading_slot_ready(0), "the human has not pressed yet")
	_press(Net.HOST_PEER_ID)
	assert_true(Match._lifecycle.loading_slot_ready(0))


func test_all_bot_match_opens_at_once() -> void:
	var net: FakeNet = FakeNet.offline()
	_start_gated(net, 2, 2)
	assert_eq(Match._lifecycle.loading_required_peers().size(), 0)
	_step(STEP_S * 2.0)
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


## Bontago-1pi.125: a slow peer delays the start indefinitely; the match never auto-starts.
func test_no_auto_start_after_the_old_wait_cap_and_slow_peer_delays_start() -> void:
	var net: FakeNet = FakeNet.host({1: 0, 2: 1}, [0] as Array[int])
	_start_gated(net, 2, 0)
	_press(1)
	_step(MAX_S * 3.0)
	assert_true(Match._lifecycle.loading_gate_blocking(), "peer 2 never loaded: still waiting, no start")
	assert_eq(_opened_count, 0)
	_press(2)
	_step(STEP_S * 2.0)
	assert_false(Match._lifecycle.loading_gate_blocking(), "starts once the slow peer is ready")
	assert_eq(_opened_count, 1)


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


# --- a peer that joins while the gate is closed (Bontago-1pi.42) ---------------
#
# Real wire shape: the host's replay is captured (MatchNet.capture_replay) and then
# played into a client-mode MatchNet, the way test_late_join.gd does. On the host
# the lifecycle's net_peer_joined handler runs BEFORE MatchNet's (autoload order),
# so Net's roster broadcast of the sets reaches the joiner ahead of the replay's
# net_match_start, whose start_match() resets the gate mirror.

func _wire_world() -> void:
	var map: MapDef = load("res://config/maps/round_small.tres") as MapDef
	var wire_field: Field = Field.new()
	wire_field.map_def = map
	add_child_autofree(wire_field)
	var wire_root: Node3D = Node3D.new()
	add_child_autofree(wire_root)
	var wire_registry: BlockRegistry = BlockRegistry.new()
	add_child_autofree(wire_registry)
	Match.register_world(wire_field, wire_registry, wire_root)


## A config the wire can carry (a preset map, not TinyMapMatchConfig's seam).
func _wire_config(players: int) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.map_variant = MatchConfig.MapVariant.ROUND
	config.map_size = MapDef.MapSize.SMALL
	config.player_count = players
	config.ai_count = 0
	config.team_mode = MatchConfig.TeamMode.OFF
	config.hot_seat = false
	config.gifts_enabled = false
	config.block_timer = 6.0
	config.rng_seed = 4242
	config.allow_mid_match_join = true
	return config


func _make_wire_net(session: FakeNet) -> MatchNetScript:
	Match.set_net_provider(session)
	var node: MatchNetScript = MatchNetScript.new()
	node.set_process(false)
	add_child_autofree(node)
	node.set_providers(session, Match)
	_wire_nets.append(node)
	return node


## Host with a gated 3-player match (peers 1 and 2 seated, slot 2 still open) and a
## capturing MatchNet; peer 1 has pressed ready.
func _gated_host_for_joiner() -> Array:
	_wire_world()
	var host_session: FakeNet = FakeNet.host({1: 0, 2: 1}, [0] as Array[int])
	var host_net: MatchNetScript = _make_wire_net(host_session)
	host_net.capture_replay = true
	Match._lifecycle.set_loading_gate_forced(true)
	Match.start_match(_wire_config(3))
	_press(1)
	_step(1.0)
	return [host_session, host_net]


## The joiner is seated (`slot_id`, -1 = spectator) and the host's handlers run in
## production order. Returns what the joiner receives, in order: [the roster-change
## sets broadcast (or {}), the replay messages].
func _host_admits(host_session: FakeNet, joiner_peer: int, slot_id: int) -> Array:
	host_session.slots_by_peer[joiner_peer] = slot_id
	_published.clear()
	Events.net_peer_joined.emit(joiner_peer, slot_id, "Latey")
	var pre: Dictionary = {}
	if not _published.is_empty():
		pre = _published.back()
	return [pre, (_wire_nets[0] as MatchNetScript).replay_capture.duplicate()]


## Match turns into the joiner: first the roster-change broadcast, then the replay.
func _become_joiner(joiner_peer: int, joiner_slot: int, received: Array) -> MatchNetScript:
	_wire_nets[0].queue_free()
	await get_tree().process_frame
	var session: FakeNet = FakeNet.client(joiner_slot)
	session.local_peer_id_value = joiner_peer
	var client_net: MatchNetScript = _make_wire_net(session)
	client_net._on_net_mode_changed(Net.Mode.CLIENT)
	var pre: Dictionary = received[0]
	if not pre.is_empty():
		Events.loading_ready_changed.emit(pre["ready"], pre["required"])
	for entry: Array in received[1]:
		client_net.callv(StringName(entry[1]), entry[2] as Array)
	return client_net


func test_late_joiner_mirrors_the_hosts_ready_sets_after_the_replay() -> void:
	var fixture: Array = _gated_host_for_joiner()
	assert_true(Match._lifecycle.loading_gate_blocking())
	var received: Array = _host_admits(fixture[0] as FakeNet, 3, 2)
	assert_eq((received[0] as Dictionary).get("required"), PackedInt32Array([1, 2, 3]), "the roster change reaches the joiner before the replay")
	await _become_joiner(3, 2, received)
	assert_eq(Match._lifecycle.loading_ready_peers(), PackedInt32Array([1]), "the joiner sees who already pressed")
	assert_eq(Match._lifecycle.loading_required_peers(), PackedInt32Array([1, 2, 3]), "and who the host waits for")
	assert_true(Match._lifecycle.loading_gate_blocking(), "the gate is still closed on the host, so on the joiner")


func test_late_spectator_gets_the_sets_but_is_not_required() -> void:
	var fixture: Array = _gated_host_for_joiner()
	var received: Array = _host_admits(fixture[0] as FakeNet, 3, -1)
	await _become_joiner(3, -1, received)
	assert_eq(Match._lifecycle.loading_ready_peers(), PackedInt32Array([1]))
	assert_eq(Match._lifecycle.loading_required_peers(), PackedInt32Array([1, 2]), "a spectator never becomes required")


func test_late_joiner_after_the_gate_opened_does_not_wait() -> void:
	var fixture: Array = _gated_host_for_joiner()
	_press(2)
	_step(STEP_S * 2.0)
	assert_false(Match._lifecycle.loading_gate_blocking(), "the host's gate is open")
	assert_eq(Match.state(), Match.State.COUNTDOWN, "the countdown is still running")
	var received: Array = _host_admits(fixture[0] as FakeNet, 3, 2)
	await _become_joiner(3, 2, received)
	assert_false(Match._lifecycle.loading_gate_blocking(), "the open message is replayed to the joiner, not left to a missed broadcast")


func test_replay_carries_the_gate_only_while_the_countdown_runs() -> void:
	var fixture: Array = _gated_host_for_joiner()
	var host_net: MatchNetScript = fixture[1] as MatchNetScript
	var gate_events: int = 0
	for message: Array in host_net.build_world_replay():
		if message[0] == &"net_match_event" and (message[1] as Array)[0] == MatchNetScript.EVENT_LOADING_GATE:
			gate_events += 1
	assert_eq(gate_events, 1, "one gate snapshot in a COUNTDOWN replay")
	Match._lifecycle._set_state(Match.State.PLAYING)
	for message: Array in host_net.build_world_replay():
		if message[0] == &"net_match_event":
			assert_ne((message[1] as Array)[0], MatchNetScript.EVENT_LOADING_GATE, "no gate state once the match is playing")


func test_joiner_that_leaves_again_does_not_hold_the_host_gate() -> void:
	var fixture: Array = _gated_host_for_joiner()
	var host_session: FakeNet = fixture[0] as FakeNet
	var host_net: MatchNetScript = fixture[1] as MatchNetScript
	host_session.slots_by_peer[3] = 2
	Events.net_peer_joined.emit(3, 2, "Latey")
	assert_true(host_net.replay_pending_for(3))
	_press(2)
	_step(MIN_S + 1.0)
	assert_true(Match._lifecycle.loading_gate_blocking(), "the joiner holds a human seat and never pressed")
	host_session.slots_by_peer.erase(3)
	Events.net_peer_left.emit(3, 2, Net.LeaveReason.TIMEOUT)
	assert_false(host_net.replay_pending_for(3), "no replay ack is owed any more")
	assert_eq(_published.back()["required"], PackedInt32Array([1, 2]), "the leaver is no longer waited for")
	_step(STEP_S * 2.0)
	assert_false(Match._lifecycle.loading_gate_blocking(), "the gate opens without the joiner")
	assert_eq(_opened_count, 1)


func test_client_ignores_malformed_or_host_side_gate_snapshots() -> void:
	var count: Array[int] = [0]
	var on_set: Callable = func(_r: PackedInt32Array, _q: PackedInt32Array) -> void: count[0] += 1
	Events.loading_ready_changed.connect(on_set)
	var session: FakeNet = FakeNet.client(1)
	var client_net: MatchNetScript = _make_wire_net(session)
	client_net._on_net_mode_changed(Net.Mode.CLIENT)
	client_net._awaiting_match_start = false
	var event: StringName = MatchNetScript.EVENT_LOADING_GATE
	client_net.net_match_event(event, [])
	client_net.net_match_event(event, [PackedInt32Array([1]), PackedInt32Array([1, 2])])
	client_net.net_match_event(event, ["x", PackedInt32Array([1]), true])
	client_net.net_match_event(event, [PackedInt32Array([1]), PackedInt32Array([1, 2]), 1])
	client_net.net_match_event(event, [PackedInt32Array([-3]), PackedInt32Array([1]), false])
	var too_many: PackedInt32Array = PackedInt32Array()
	for i: int in range(client_net.config.max_peers + 1):
		too_many.append(i + 1)
	client_net.net_match_event(event, [PackedInt32Array(), too_many, false])
	assert_eq(count[0], 0, "malformed, negative and oversized snapshots are dropped")
	client_net.net_match_event(event, [PackedInt32Array([1]), PackedInt32Array([1, 2]), false])
	assert_eq(count[0], 1, "a well-formed one is applied")
	client_net.set_providers(FakeNet.host({1: 0}, [0] as Array[int]), Match)
	client_net.net_match_event(event, [PackedInt32Array([1]), PackedInt32Array([1]), true])
	assert_eq(count[0], 1, "a host never applies a snapshot")
	assert_eq(_opened_count, 0)
	Events.loading_ready_changed.disconnect(on_set)


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

func test_tuning_has_no_ready_wait_auto_start_cap() -> void:
	var tuning: LoadingScreenTuning = load("res://config/loading_screen_tuning.tres") as LoadingScreenTuning
	assert_gt(tuning.ready_timeout_s, 0.0, "the asset-load failure timeout stays (it aborts, never starts)")
	assert_false("ready_wait_max_s" in tuning, "Bontago-1pi.125: the auto-start cap is removed")


func _screen() -> LoadingScreen:
	var screen: LoadingScreen = autofree(load("res://ui/LoadingScreen.tscn").instantiate()) as LoadingScreen
	add_child_autofree(screen)
	screen.tuning = LoadingScreenTuning.new()
	screen.tuning.warmup_frames = 1
	screen.tuning.fade_out_duration_s = 0.02
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
	Match._lifecycle._ready_gate.begin()
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


func test_screen_client_keeps_waiting_with_no_wait_cap() -> void:
	var net: FakeNet = FakeNet.client(1)
	_start_gated(net, 2, 0)
	var screen: LoadingScreen = _screen()
	screen.show_for_match(_config(2, 0), [] as Array[PlayerSlot])
	screen.fade_out()
	await wait_seconds(0.8, "well past warmup + fade")
	assert_true(screen.visible, "Bontago-1pi.125: no cap; the client waits for the host's open message")
	await _close(screen)


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
	assert_false(screen.ready_prompt_visible(), "no prompt while this instance is still loading")
	assert_true(screen._player_list.visible, "the ready list shows the players")
	screen.fade_out()
	assert_true(screen.accepts_ready_input())
	assert_true(screen.ready_prompt_visible(), "the prompt opens with the ready input")
	assert_eq(screen.ready_prompt_text(), "Ready?")
	assert_eq(screen.prompt_glyph_texts(), PackedStringArray(["Enter"]), "keyboard glyph of ui_accept")
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
	assert_almost_eq(screen._ready_box.modulate.a, screen.tuning.ready_prompt_disabled_alpha, 0.001, "the prompt is dimmed after the press")
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


func test_prompt_is_not_a_button() -> void:
	var screen: LoadingScreen = _open_screen(FakeNet.offline(), 1, 0)
	screen.fade_out()
	assert_null(screen.find_child("ReadyButton", true, false), "1pi.63: no button, only the action glyph")
	assert_eq(screen.find_children("*", "BaseButton", true, false).size(), 0)
	await _close(screen)


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


func test_pressed_prompt_stays_dimmed_while_the_others_catch_up() -> void:
	var net: FakeNet = FakeNet.host({1: 0, 2: 1, 3: 2}, [0] as Array[int])
	var screen: LoadingScreen = _open_screen(net, 3, 0)
	screen.fade_out()
	assert_almost_eq(screen._ready_box.modulate.a, 1.0, 0.001)
	screen.press_ready()
	assert_true(screen.ready_prompt_visible(), "the prompt stays, dimmed")
	assert_almost_eq(screen._ready_box.modulate.a, screen.tuning.ready_prompt_disabled_alpha, 0.001)
	_press(2)
	_press(3)
	_step(STEP_S * 2.0)
	screen._refresh_ready_ui()
	assert_false(screen.ready_prompt_visible(), "everyone is ready: the gate opened")
	await _close(screen)


func test_all_ready_opens_the_gate_and_hides_the_prompt() -> void:
	var screen: LoadingScreen = _open_screen(FakeNet.offline(), 1, 0)
	screen.fade_out()
	screen.press_ready()
	_step(STEP_S * 2.0)
	screen._refresh_ready_ui()
	assert_false(screen.ready_prompt_visible(), "the gate opened: prompt gone")
	await _close(screen)


func test_all_bot_match_and_spectator_get_no_prompt() -> void:
	var screen: LoadingScreen = _open_screen(FakeNet.offline(), 2, 2)
	screen.fade_out()
	assert_false(screen.ready_prompt_visible(), "nobody to press")
	await _close(screen)
	var net: FakeNet = FakeNet.host({2: 0, 3: -1}, [0] as Array[int])
	var spectator_screen: LoadingScreen = _open_screen(net, 1, 0)
	spectator_screen.fade_out()
	assert_false(spectator_screen.ready_prompt_visible(), "the local peer holds no seat in this roster")
	await _close(spectator_screen)


func test_client_list_mirrors_the_hosts_sets() -> void:
	var net: FakeNet = FakeNet.client(1)
	net.slots_by_peer = {1: 0, 2: 1}
	var screen: LoadingScreen = _open_screen(net, 2, 0)
	screen.fade_out()
	assert_false(screen.ready_prompt_visible(), "no host message yet: nothing to press for")
	Events.loading_ready_changed.emit(PackedInt32Array(), PackedInt32Array([1, 2]))
	assert_true(screen.ready_prompt_visible())
	assert_false(screen.player_row_ready(0))
	Events.loading_ready_changed.emit(PackedInt32Array([2]), PackedInt32Array([1, 2]))
	assert_true(screen.player_row_ready(1), "the host's mirror ticks peer 2's row")
	assert_false(screen.player_row_ready(0))
	assert_almost_eq(screen._ready_box.modulate.a, 1.0, 0.001, "not pressed yet: full opacity")
	Events.loading_gate_opened.emit()
	assert_false(screen.ready_prompt_visible(), "the gate opened")
	await _close(screen)


func test_unarmed_overlay_lists_the_players_and_has_no_prompt() -> void:
	var screen: LoadingScreen = _screen()
	screen.show_for_match(_config(2, 0), _slots_for_layout(2, 0))
	assert_false(screen.ready_gate_armed())
	assert_true(screen._player_list.visible)
	assert_false(screen._ready_box.visible)
	assert_true(screen.player_row_names()[0].findn("Player 1") >= 0)


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
	assert_false(screen.ready_prompt_visible())
	screen._input(_accept_key())
	screen._input(_accept_pad())
	Input.parse_input_event(_accept_key())
	Input.flush_buffered_events()
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
	assert_false(screen.ready_prompt_visible())
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
	assert_false(screen.ready_prompt_visible())
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
	var ready_rect: Rect2 = screen._ready_box.get_global_rect()
	assert_false(list_rect.intersects(ready_rect), "list and ready box do not overlap")
	assert_true(screen.ready_prompt_visible())
	assert_true(card.encloses(ready_rect), "the ready box is inside the card")
	assert_true(ready_rect.size.x > 0.0 and ready_rect.size.y > 0.0, "the Ready? prompt and glyph have room")
	await _close(screen)


func test_eight_player_card_fits_1280x720_without_overlap() -> void:
	await _layout_in(Vector2i(1280, 720))


func test_eight_player_card_fits_ultrawide_without_overlap() -> void:
	await _layout_in(Vector2i(3440, 1440))
