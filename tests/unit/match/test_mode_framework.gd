extends "res://tests/unit/match/match_world_test.gd"
## Game-mode framework: the ModeObjective seam in MatchTerritory/MatchLifecycle and its replication.

const MatchNetScript := preload("res://net/MatchNet.gd")


## A timed objective: team 0 scores the time each solve covers; the round
## timer decides the winner. Everything goes through the typed ModeObjective
## interface, exactly as a real mode will.
class StubTimedObjective:
	extends ModeObjective

	func mode_id() -> int:
		return MatchConfig.GameMode.CAPTURE_THE_FLAG

	func is_timed() -> bool:
		return true

	func replicates_state() -> bool:
		return true

	func update(_raster: TerritoryRaster, delta: float) -> void:
		_set_score(0, scores()[0] + delta)

	func results_fields() -> Dictionary:
		return {"note": "stub"}


var _fake_net: FakeNet
var _net: MatchNetScript


func after_each() -> void:
	if _net != null and is_instance_valid(_net):
		_net.set_providers(null, null)
	_net = null
	Match._net_provider = null
	Match.set_replicator(null)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()
	Settings.set_active_input_device_for_test(Settings.DEFAULT_ACTIVE_DEVICE)


func _config(timer_minutes: int = 0) -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.hot_seat = true
	config.block_timer = 6.0
	config.rng_seed = 99
	config.match_timer_minutes = timer_minutes
	config.sudden_death = false
	config.round_timer_minutes = 2
	return config


func _tick(seconds: float) -> void:
	var step: float = 1.0 / Engine.physics_ticks_per_second
	for _i: int in range(int(ceil(seconds / step))):
		Match._process(step)


## Starts a match, swaps in the stub objective before PLAYING arms the timer.
func _start_with_stub() -> StubTimedObjective:
	Match.start_match(_config())
	var stub: StubTimedObjective = StubTimedObjective.new()
	stub.reset(2)
	Match._territory._objective = stub
	_tick(Match.COUNTDOWN_SECONDS + 0.1)
	assert_eq(Match.state(), Match.State.PLAYING)
	return stub


# --- MatchConfig ---------------------------------------------------------------

# --- Objective seam --------------------------------------------------------------

func test_classic_match_timer_without_sudden_death_still_does_not_end_the_match() -> void:
	Match.start_match(_config(1))
	_tick(Match.COUNTDOWN_SECONDS + 0.1)
	Match._lifecycle._match_timer_left = 0.05
	_tick(0.5)
	assert_eq(Match.state(), Match.State.PLAYING, "classic keeps its existing timer semantics")


func test_round_timer_end_finishes_a_timed_mode_through_the_objective() -> void:
	var stub: StubTimedObjective = _start_with_stub()
	_tick(1.0)
	var results: Array[Dictionary] = []
	Events.match_results_ready.connect(func(r: Dictionary) -> void: results.append(r))
	watch_signals(Events)
	Match._lifecycle._match_timer_left = 0.02
	_tick(0.2)
	assert_eq(Match.state(), Match.State.END)
	assert_signal_emitted_with_parameters(Events, "match_won", [0])
	assert_eq(results.size(), 1)
	var mode: Dictionary = results[0]["mode"]
	assert_eq(mode["mode_id"], MatchConfig.GameMode.CAPTURE_THE_FLAG)
	assert_eq((mode["scores"] as Array).size(), 2)
	assert_eq(mode["note"], "stub")
	assert_eq(stub.on_round_timer_end(), 0)


func test_host_publishes_mode_state_when_scores_change() -> void:
	_start_with_stub()
	var states: Array[Dictionary] = []
	Events.mode_state_changed.connect(func(s: Dictionary) -> void: states.append(s))
	_tick(0.5)
	assert_gt(states.size(), 0)
	assert_eq(states[-1]["mode_id"], MatchConfig.GameMode.CAPTURE_THE_FLAG)
	assert_true(states[-1].has("round_left"))


# --- Replication -------------------------------------------------------------------

func _client_net() -> MatchNetScript:
	_fake_net = FakeNet.client(1)
	Match._net_provider = _fake_net
	var node: MatchNetScript = MatchNetScript.new()
	node.set_process(false)
	add_child_autofree(node)
	node.set_providers(_fake_net, Match)
	_net = node
	return node


func _wire_state() -> Dictionary:
	return {"mode_id": MatchConfig.GameMode.CAPTURE_THE_FLAG, "scores": [3.5, 1.0], "extra": {"beacons": 2}, "round_left": 42.0}


func test_client_mirrors_a_valid_host_mode_state_for_display_only() -> void:
	var stub: StubTimedObjective = _start_with_stub()
	var net: MatchNetScript = _client_net()
	watch_signals(Events)
	net.net_match_event(MatchNetScript.EVENT_MODE_STATE, [_wire_state()])
	assert_almost_eq(stub.scores()[0], 3.5, 0.0001)
	assert_almost_eq(Match._lifecycle.match_timer_left(), 42.0, 0.0001)
	assert_signal_emitted(Events, "mode_state_changed")
	assert_eq(stub.winner(), ModeObjective.NO_TEAM, "a client never decides the outcome")
	assert_eq(Match.state(), Match.State.PLAYING)


func test_client_drops_malformed_or_foreign_mode_state() -> void:
	var stub: StubTimedObjective = _start_with_stub()
	var before: float = stub.scores()[0]
	var net: MatchNetScript = _client_net()
	var bad_states: Array = [
		"nope", {}, {"mode_id": 99, "scores": [1.0]},
		{"mode_id": 1, "scores": [NAN, 1.0]}, {"mode_id": 1, "scores": "x"},
		{"mode_id": 1, "scores": [1.0], "round_left": -1.0},
		{"mode_id": 1, "scores": [1.0], "extra": {"k": [1]}},
		{"mode_id": 1, "scores": [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0]},
		{"mode_id": MatchConfig.GameMode.ELIMINATION, "scores": [9.0, 9.0], "round_left": 1.0},
	]
	for bad: Variant in bad_states:
		net.net_match_event(MatchNetScript.EVENT_MODE_STATE, [bad])
	assert_almost_eq(stub.scores()[0], before, 0.0001, "nothing reached the objective")
	net.net_match_event(MatchNetScript.EVENT_MODE_STATE, [])


# --- Results screen ----------------------------------------------------------------

# --- Lobby ---------------------------------------------------------------------------

# --- Review fixes ------------------------------------------------------------------

class EndingStubObjective:
	extends StubTimedObjective

	var armed: bool = false

	func update(_raster: TerritoryRaster, _delta: float) -> void:
		if armed:
			_winner = 1


func test_round_ending_in_territory_tick_and_timer_zero_same_frame_finishes_once() -> void:
	Match.start_match(_config())
	var stub: EndingStubObjective = EndingStubObjective.new()
	stub.reset(2)
	Match._territory._objective = stub
	_tick(Match.COUNTDOWN_SECONDS + 0.1)
	var results: Array[Dictionary] = []
	Events.match_results_ready.connect(func(r: Dictionary) -> void: results.append(r))
	watch_signals(Events)
	Match._territory._force_dirty = true
	stub.armed = true
	Match._lifecycle._match_timer_left = 0.001
	_tick(0.2)
	assert_eq(Match.state(), Match.State.END)
	assert_signal_emit_count(Events, "match_won", 1)
	assert_eq(results.size(), 1)

