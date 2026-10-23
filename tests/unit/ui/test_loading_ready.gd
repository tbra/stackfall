extends GutTest
## the loading screen stays up for a
## minimum time and every human presses ready (ui_accept / gamepad A) before the
## host starts the countdown. Covers the pure rule (core/rules/LoadingReadyGate.gd),
## the host's authoritative gate in autoload/match/MatchLifecycle.gd, Net's
## intent validation, and ui/menus/LoadingScreen.gd's input glue.

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
	_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
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
	_release_accept_inputs()
	_wire_nets.clear()
	Match.set_replicator(null)
	Settings._input(InputEventKey.new())
	Events.loading_ready_changed.disconnect(_on_changed)
	Events.loading_gate_opened.disconnect(_on_opened)
	Match._lifecycle.set_loading_gate_forced(false)
	Match._lifecycle._loading_tuning = Match._lifecycle.LOADING_TUNING
	Match._net_provider = null
	Net.leave()
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _config(players: int, ai: int) -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_map)
	config.player_count = players
	config.ai_count = ai
	config.gifts_enabled = false
	config.block_timer = 6.0
	config.rng_seed = 4242
	return config


func _start_gated(net: Variant, players: int, ai: int) -> void:
	Match._net_provider = net
	Match._lifecycle.set_loading_gate_forced(true)
	Match.start_match(_config(players, ai))


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


func test_bots_are_auto_ready_and_never_required() -> void:
	var net: FakeNet = FakeNet.offline()
	_start_gated(net, 3, 2)
	assert_eq(Match._lifecycle.loading_required_peers(), PackedInt32Array([Net.HOST_PEER_ID]), "one human seat, bots are not listed")
	assert_true(Match._lifecycle.loading_slot_ready(1), "bot")
	assert_true(Match._lifecycle.loading_slot_ready(2), "bot")
	assert_false(Match._lifecycle.loading_slot_ready(0), "the human has not pressed yet")
	_press(Net.HOST_PEER_ID)
	assert_true(Match._lifecycle.loading_slot_ready(0))


## a slow peer delays the start indefinitely; the match never auto-starts.
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


func _make_wire_net(session: FakeNet) -> MatchNetScript:
	Match._net_provider = session
	var node: MatchNetScript = MatchNetScript.new()
	node.set_process(false)
	add_child_autofree(node)
	assert_true(node.bind_ports(SessionPort.new(session), MatchHostPort.new(Match), MatchReplicaPort.new(Match)))
	_wire_nets.append(node)
	return node


func test_client_ignores_malformed_or_host_side_gate_snapshots() -> void:
	var count: Array[int] = [0]
	var on_set: Callable = func(_r: PackedInt32Array, _q: PackedInt32Array) -> void: count[0] += 1
	Events.loading_ready_changed.connect(on_set)
	var session: FakeNet = FakeNet.client(1)
	var client_net: MatchNetScript = _make_wire_net(session)
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
	assert_true(client_net.bind_ports(SessionPort.new(FakeNet.host({1: 0}, [0] as Array[int])), MatchHostPort.new(Match), MatchReplicaPort.new(Match)))
	client_net.net_match_event(event, [PackedInt32Array([1]), PackedInt32Array([1]), true])
	assert_eq(count[0], 1, "a host never applies a snapshot")
	assert_eq(_opened_count, 0)
	Events.loading_ready_changed.disconnect(on_set)


# --- Net validates the sender --------------------------------------------------

func _screen() -> LoadingScreen:
	var screen: LoadingScreen = autofree(load("res://ui/menus/LoadingScreen.tscn").instantiate()) as LoadingScreen
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


var _intent_probe: Callable


func _match_slots() -> Array[PlayerSlot]:
	var result: Array[PlayerSlot] = []
	for slot_id: int in range(Match.slot_count()):
		result.append(Match.slot(slot_id))
	return result


## A gated match plus a shown overlay (loading not finished until fade_out()).
func _open_screen(net: Variant, players: int, ai: int) -> LoadingScreen:
	_start_gated(net, players, ai)
	var screen: LoadingScreen = _screen()
	screen.show_for_match(_config(players, ai), _match_slots())
	return screen


## Ends an overlay and lets its fade_out() coroutine resume (and bail on the bumped
## token) while the node still exists, so the run logs no freed-instance resume.
func _close(screen: LoadingScreen) -> void:
	screen.cancel()
	await wait_process_frames(2)


## The synthetic Enter / pad-A presses above are never released by the tests; an unreleased
## Enter/A keeps ui_accept, ghost_place, chat_open ... held for every later script in this
## process (sharded gate failures in test_playercontroller_gamepad).
func _release_accept_inputs() -> void:
	var key: InputEventKey = _accept_key()
	key.pressed = false
	Input.parse_input_event(key)
	var pad: InputEventJoypadButton = _accept_pad()
	pad.pressed = false
	Input.parse_input_event(pad)
	Input.flush_buffered_events()


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
	Input.parse_input_event(_accept_pad())
	Input.flush_buffered_events()
	screen._input(_accept_pad())
	assert_eq(counter[0], 1, "idempotent: A afterwards (and a repeat) never re-sends")
	assert_false(screen.press_ready(), "an explicit second call reports it sent nothing")
	assert_almost_eq(screen._ready_box.modulate.a, screen.tuning.ready_prompt_disabled_alpha, 0.001, "the prompt is dimmed after the press")
	await _close(screen)
	_stop_counting()
