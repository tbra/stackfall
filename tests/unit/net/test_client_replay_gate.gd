extends GutTest
## ClientReplayGate: the client-side world gate (muted until the first match start)
## and the replay span (net_match_start with a replay id up to net_replay_end), driven
## through its public methods with Events.world_replay_changed as the observable.

const TIMEOUT_S: float = 2.0
const TIMEOUT_MS: int = 2000
const T0_MS: int = 10000
const REPLAY_ID: int = 5

var _gate: ClientReplayGate
var _config: NetConfig


func before_each() -> void:
	_config = (load("res://config/net/net_config.tres") as NetConfig).duplicate() as NetConfig
	_config.replay_ack_timeout = TIMEOUT_S
	_gate = ClientReplayGate.new()
	_bind(FakeNet.client(3))
	watch_signals(Events)


func _bind(fake: FakeNet) -> void:
	_gate.bind(FakeSessionPort.new(fake), _config)


func _emits() -> Array:
	var seen: Array = []
	for index: int in range(get_signal_emit_count(Events, "world_replay_changed")):
		seen.append((get_signal_parameters(Events, "world_replay_changed", index) as Array)[0])
	return seen


# --- Awaiting the first match start ------------------------------------------------

func test_a_fresh_gate_is_not_awaiting() -> void:
	assert_false(_gate.awaiting_world())


func test_a_client_awaits_until_the_first_match_start() -> void:
	_gate.on_mode_changed(true)
	assert_true(_gate.awaiting_world(), "a client waits for the world")
	_gate.on_match_start(0, T0_MS)
	assert_false(_gate.awaiting_world(), "the broadcast start opens the gate")
	assert_eq(_emits(), [], "a plain start is not a replay span")


func test_a_replay_start_also_opens_the_gate() -> void:
	_gate.on_mode_changed(true)
	_gate.on_match_start(REPLAY_ID, T0_MS)
	assert_false(_gate.awaiting_world())


func test_leaving_client_mode_clears_the_wait() -> void:
	_gate.on_mode_changed(true)
	_gate.on_mode_changed(false)
	assert_false(_gate.awaiting_world())


func test_a_host_never_awaits_the_world() -> void:
	_bind(FakeNet.host({1: 0}, [0]))
	_gate.on_mode_changed(true)
	assert_false(_gate.awaiting_world(), "awaiting is client-only, whatever the mode flag says")


func test_a_new_client_mode_after_a_match_waits_again() -> void:
	_gate.on_mode_changed(true)
	_gate.on_match_start(0, T0_MS)
	_gate.on_mode_changed(true)
	assert_true(_gate.awaiting_world())


# --- Replay span -------------------------------------------------------------------

func test_a_replay_start_opens_one_span_and_its_end_closes_it() -> void:
	_gate.on_match_start(REPLAY_ID, T0_MS)
	assert_eq(_emits(), [true])
	assert_true(_gate.on_replay_end(REPLAY_ID), "the matching end is acked")
	assert_eq(_emits(), [true, false])


func test_a_host_does_not_open_a_span() -> void:
	_bind(FakeNet.host({1: 0}, [0]))
	_gate.on_match_start(REPLAY_ID, T0_MS)
	assert_eq(_emits(), [])


func test_a_zero_id_start_opens_no_span() -> void:
	_gate.on_match_start(0, T0_MS)
	assert_eq(_emits(), [])


func test_an_end_for_another_id_is_acked_but_keeps_the_span() -> void:
	_gate.on_match_start(REPLAY_ID, T0_MS)
	assert_true(_gate.on_replay_end(REPLAY_ID + 1))
	assert_eq(_emits(), [true], "a stale end does not lift the mute")
	_gate.on_replay_end(REPLAY_ID)
	assert_eq(_emits(), [true, false])


func test_a_repeated_end_emits_the_close_once() -> void:
	_gate.on_match_start(REPLAY_ID, T0_MS)
	_gate.on_replay_end(REPLAY_ID)
	_gate.on_replay_end(REPLAY_ID)
	assert_eq(_emits(), [true, false])


func test_an_end_with_no_span_emits_nothing() -> void:
	assert_true(_gate.on_replay_end(REPLAY_ID))
	assert_eq(_emits(), [])


# --- Ack rules ---------------------------------------------------------------------

func test_no_ack_for_a_host() -> void:
	_bind(FakeNet.host({1: 0}, [0]))
	assert_false(_gate.on_replay_end(REPLAY_ID))


func test_no_ack_while_awaiting_the_world() -> void:
	_gate.on_mode_changed(true)
	assert_false(_gate.on_replay_end(REPLAY_ID))


func test_no_ack_for_a_zero_or_negative_id() -> void:
	assert_false(_gate.on_replay_end(0))
	assert_false(_gate.on_replay_end(-1))


func test_a_zero_id_end_does_not_close_a_live_span() -> void:
	_gate.on_match_start(REPLAY_ID, T0_MS)
	_gate.on_replay_end(0)
	assert_eq(_emits(), [true])


func test_an_ack_is_owed_once_the_world_arrived() -> void:
	_gate.on_mode_changed(true)
	_gate.on_match_start(REPLAY_ID, T0_MS)
	assert_true(_gate.on_replay_end(REPLAY_ID))


# --- Early ends --------------------------------------------------------------------

func test_a_new_plain_start_ends_the_span() -> void:
	_gate.on_match_start(REPLAY_ID, T0_MS)
	_gate.on_match_start(0, T0_MS + 10)
	assert_eq(_emits(), [true, false])


func test_a_new_replay_start_closes_the_old_span_then_opens_its_own() -> void:
	_gate.on_match_start(REPLAY_ID, T0_MS)
	_gate.on_match_start(REPLAY_ID + 1, T0_MS + 10)
	assert_eq(_emits(), [true, false, true])
	_gate.on_replay_end(REPLAY_ID)
	assert_eq(_emits(), [true, false, true], "the old id no longer matches")
	_gate.on_replay_end(REPLAY_ID + 1)
	assert_eq(_emits(), [true, false, true, false])


func test_a_mode_change_ends_the_span_and_awaits_again() -> void:
	_gate.on_match_start(REPLAY_ID, T0_MS)
	_gate.on_mode_changed(true)
	assert_eq(_emits(), [true, false])
	assert_true(_gate.awaiting_world())
	assert_false(_gate.on_replay_end(REPLAY_ID), "no ack while awaiting")


func test_a_mode_change_to_offline_ends_the_span() -> void:
	_gate.on_match_start(REPLAY_ID, T0_MS)
	_gate.on_mode_changed(false)
	assert_eq(_emits(), [true, false])
	assert_false(_gate.awaiting_world())


func test_a_mode_change_with_no_span_emits_nothing() -> void:
	_gate.on_mode_changed(true)
	_gate.on_mode_changed(false)
	assert_eq(_emits(), [])


func test_end_replay_closes_the_span_once() -> void:
	_gate.on_match_start(REPLAY_ID, T0_MS)
	_gate.end_replay()
	_gate.end_replay()
	assert_eq(_emits(), [true, false])


func test_end_replay_with_no_span_emits_nothing() -> void:
	_gate.end_replay()
	assert_eq(_emits(), [])


func test_end_replay_then_a_late_end_emits_one_close() -> void:
	_gate.on_match_start(REPLAY_ID, T0_MS)
	_gate.end_replay()
	assert_true(_gate.on_replay_end(REPLAY_ID), "the ack is still owed")
	assert_eq(_emits(), [true, false])


# --- Expiry ------------------------------------------------------------------------

func test_a_span_survives_until_the_ack_timeout() -> void:
	_gate.on_match_start(REPLAY_ID, T0_MS)
	_gate.tick(T0_MS + TIMEOUT_MS - 1)
	assert_eq(_emits(), [true])


func test_a_span_expires_at_the_ack_timeout() -> void:
	_gate.on_match_start(REPLAY_ID, T0_MS)
	_gate.tick(T0_MS + TIMEOUT_MS)
	assert_eq(_emits(), [true, false])


func test_expiry_emits_once_however_often_it_ticks() -> void:
	_gate.on_match_start(REPLAY_ID, T0_MS)
	_gate.tick(T0_MS + TIMEOUT_MS * 2)
	_gate.tick(T0_MS + TIMEOUT_MS * 3)
	_gate.on_replay_end(REPLAY_ID)
	assert_eq(_emits(), [true, false])


func test_ticking_with_no_span_emits_nothing() -> void:
	_gate.tick(T0_MS + TIMEOUT_MS * 10)
	assert_eq(_emits(), [])


func test_expiry_counts_from_the_latest_start() -> void:
	_gate.on_match_start(REPLAY_ID, T0_MS)
	_gate.on_match_start(REPLAY_ID + 1, T0_MS + TIMEOUT_MS - 100)
	_gate.tick(T0_MS + TIMEOUT_MS + 100)
	assert_eq(_emits(), [true, false, true], "the second span is only 200 ms old")


func test_expiry_does_not_touch_the_awaiting_flag() -> void:
	_gate.on_mode_changed(true)
	_gate.tick(T0_MS + TIMEOUT_MS * 10)
	assert_true(_gate.awaiting_world())


# --- bind keeps the state ----------------------------------------------------------

func test_a_rebind_keeps_the_wait() -> void:
	_gate.on_mode_changed(true)
	_bind(FakeNet.client(3))
	assert_true(_gate.awaiting_world())
	assert_eq(_emits(), [])


func test_a_rebind_mid_replay_neither_emits_nor_loses_the_span() -> void:
	_gate.on_match_start(REPLAY_ID, T0_MS)
	_bind(FakeNet.client(3))
	assert_eq(_emits(), [true])
	assert_true(_gate.on_replay_end(REPLAY_ID))
	assert_eq(_emits(), [true, false])


func test_a_rebind_to_a_new_config_expires_by_the_new_timeout() -> void:
	_gate.on_match_start(REPLAY_ID, T0_MS)
	var longer: NetConfig = _config.duplicate() as NetConfig
	longer.replay_ack_timeout = TIMEOUT_S * 10.0
	_gate.bind(FakeSessionPort.new(FakeNet.client(3)), longer)
	_gate.tick(T0_MS + TIMEOUT_MS)
	assert_eq(_emits(), [true], "the refreshed config applies")
	_gate.tick(T0_MS + TIMEOUT_MS * 10)
	assert_eq(_emits(), [true, false])
