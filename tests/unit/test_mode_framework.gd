extends GutTest
## Game-mode framework (Bontago-22y.11): MatchConfig mode/timer fields, the
## ModeObjective seam in MatchTerritory/MatchLifecycle, replication and the
## lobby/results surfaces. Classic behaviour is covered by the existing
## win_checker/lifecycle/sudden_death tests, which this package must not change.
##
## DECISION: lobby config replication is tested at the Dictionary level
## (FakeNet.set_lobby_data_calls -> _apply_data), the same convention as
## test_lobby.gd and test_match_weather_net.gd; Net.set_lobby_data() ships that
## same dictionary generically over the existing RPC, so no ENet socket is
## opened here.

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
		_set_score(0, team_score(0) + delta)

	func results_fields() -> Dictionary:
		return {"note": "stub"}


var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef
var _fake_net: FakeNet
var _net: MatchNetScript


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _tiny_map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)


func after_each() -> void:
	if _net != null and is_instance_valid(_net):
		_net.set_providers(null, null)
	_net = null
	Match.set_net_provider(null)
	Match.set_replicator(null)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()
	Settings.set_active_input_device_for_test(Settings.DEFAULT_ACTIVE_DEVICE)


func _config(timer_minutes: int = 0) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
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

func test_default_mode_is_classic() -> void:
	var config: MatchConfig = MatchConfig.new()
	assert_eq(config.game_mode, MatchConfig.GameMode.CLASSIC)
	assert_eq(MatchConfig.from_dict({}).game_mode, MatchConfig.GameMode.CLASSIC)


func test_reserved_and_unknown_mode_ids_fall_back_to_classic() -> void:
	for mode: int in [
		MatchConfig.GameMode.ELIMINATION,
		99, -3,
	]:
		assert_false(MatchConfig.is_game_mode_selectable(mode))
		assert_eq(MatchConfig.from_dict({"game_mode": mode}).game_mode, MatchConfig.GameMode.CLASSIC)
		var config: MatchConfig = MatchConfig.new()
		config.game_mode = mode as MatchConfig.GameMode
		config.sanitize()
		assert_eq(config.game_mode, MatchConfig.GameMode.CLASSIC)


func test_mode_and_round_timer_round_trip_and_clamp() -> void:
	var config: MatchConfig = MatchConfig.new()
	config.round_timer_minutes = 17
	var copy: MatchConfig = MatchConfig.from_dict(config.to_dict())
	assert_eq(copy.game_mode, MatchConfig.GameMode.CLASSIC)
	assert_eq(copy.round_timer_minutes, 17)
	assert_eq(MatchConfig.from_dict({"round_timer_minutes": 9999}).round_timer_minutes, MatchConfig.ROUND_TIMER_MAX_MINUTES)
	assert_eq(MatchConfig.from_dict({"round_timer_minutes": -4}).round_timer_minutes, MatchConfig.ROUND_TIMER_MIN_MINUTES)


# --- Objective seam --------------------------------------------------------------

func test_classic_match_gets_a_classic_objective_wrapping_the_win_checker() -> void:
	Match.start_match(_config())
	var objective: ModeObjective = Match._territory._objective
	assert_true(objective is ClassicObjective)
	assert_false(objective.is_timed())
	assert_false(objective.replicates_state(), "classic sends no mode-state traffic")
	assert_eq((objective as ClassicObjective).checker(), Match._territory._win_checker)
	assert_eq(Match._territory.winner_team(), WinChecker.NO_TEAM)


func test_classic_match_timer_without_sudden_death_still_does_not_end_the_match() -> void:
	Match.start_match(_config(1))
	_tick(Match.COUNTDOWN_SECONDS + 0.1)
	Match._lifecycle._match_timer_left = 0.05
	_tick(0.5)
	assert_eq(Match.state(), Match.State.PLAYING, "classic keeps its existing timer semantics")


func test_stub_timed_objective_owns_score_and_the_all_goal_hold_does_not_end_it() -> void:
	var stub: StubTimedObjective = _start_with_stub()
	assert_almost_eq(Match._lifecycle.match_timer_left(), 120.0, 0.5, "round_timer_minutes arms the timer")
	# A latched classic capture must not end a non-classic mode.
	Match._territory._win_checker._winner = 1
	_tick(1.0)
	assert_eq(Match.state(), Match.State.PLAYING)
	assert_gt(stub.team_score(0), 0.0, "the objective was fed every solve")
	assert_almost_eq(stub.team_score(1), 0.0, 0.0001)


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


func test_classic_results_payload_has_no_mode_block() -> void:
	Match.start_match(_config())
	_tick(Match.COUNTDOWN_SECONDS + 0.1)
	var results: Array[Dictionary] = []
	Events.match_results_ready.connect(func(r: Dictionary) -> void: results.append(r))
	Match._finish_match(0)
	assert_eq(results.size(), 1)
	assert_false(results[0].has("mode"))


func test_tie_goes_to_the_lowest_team() -> void:
	var stub: StubTimedObjective = StubTimedObjective.new()
	stub.reset(3)
	assert_eq(stub.on_round_timer_end(), 0)
	stub._set_score(2, 1.0)
	assert_eq(stub.on_round_timer_end(), 2)


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
	Match.set_net_provider(_fake_net)
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
	assert_almost_eq(stub.team_score(0), 3.5, 0.0001)
	assert_almost_eq(Match._lifecycle.match_timer_left(), 42.0, 0.0001)
	assert_signal_emitted(Events, "mode_state_changed")
	assert_eq(stub.winner(), ModeObjective.NO_TEAM, "a client never decides the outcome")
	assert_eq(Match.state(), Match.State.PLAYING)


func test_client_drops_malformed_or_foreign_mode_state() -> void:
	var stub: StubTimedObjective = _start_with_stub()
	var before: float = stub.team_score(0)
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
	assert_almost_eq(stub.team_score(0), before, 0.0001, "nothing reached the objective")
	net.net_match_event(MatchNetScript.EVENT_MODE_STATE, [])


func test_reconnect_snapshot_is_empty_for_classic_and_full_for_a_timed_mode() -> void:
	Match.start_match(_config())
	assert_true(Match.mode_state_snapshot().is_empty())
	Match.abort_match()
	_start_with_stub()
	assert_eq(Match.mode_state_snapshot()["mode_id"], MatchConfig.GameMode.CAPTURE_THE_FLAG)


# --- Results screen ----------------------------------------------------------------

func test_results_text_shows_the_mode_outcome_and_classic_is_unchanged() -> void:
	var base: Dictionary = {"winner_kind": MatchStats.WINNER_KIND_TEAM, "winner_id": 1, "winner_name": "Team 2"}
	assert_eq(ResultsScreen.mode_outcome_text(base), "")
	var with_mode: Dictionary = base.duplicate()
	with_mode["mode"] = {"mode_id": MatchConfig.GameMode.CAPTURE_THE_FLAG, "scores": [3.0, 5.5]}
	var text: String = ResultsScreen.mode_outcome_text(with_mode)
	assert_string_contains(text, "Capture the Flag")
	assert_string_contains(text, "Team 2: 5.5")


func test_results_payload_validation_accepts_and_rejects_the_mode_block() -> void:
	var rows: Array = []
	var payload: Dictionary = {
		"winner_kind": "team", "winner_id": 0, "winner_name": "Team 1", "match_duration": 5.0, "rows": rows,
	}
	assert_false(MatchStats.validate_results_payload(payload).is_empty())
	payload["mode"] = {"mode_id": 1, "scores": [1.0, 2.0], "note": "x"}
	assert_eq(MatchStats.validate_results_payload(payload)["mode"]["scores"], [1.0, 2.0])
	payload["mode"] = {"mode_id": 1, "scores": "bad"}
	assert_true(MatchStats.validate_results_payload(payload).is_empty())


# --- Lobby ---------------------------------------------------------------------------

func _make_lobby(is_host: bool) -> Lobby:
	var lobby: Lobby = autofree((load("res://ui/Lobby.tscn") as PackedScene).instantiate())
	add_child_autofree(lobby)
	var fake: FakeNet = FakeNet.new()
	fake.is_host_value = is_host
	fake.is_offline_value = is_host
	lobby.net_provider = fake
	lobby._update_host_only_state()
	return lobby


func test_lobby_lists_all_modes_but_only_implemented_ones_are_selectable() -> void:
	var lobby: Lobby = _make_lobby(true)
	var option: OptionButton = lobby.get_node("%GameModeOption")
	assert_eq(option.item_count, MatchConfig.GAME_MODE_LABELS.size())
	assert_eq(option.selected, MatchConfig.GameMode.CLASSIC)
	for i: int in range(option.item_count):
		assert_eq(option.is_item_disabled(i), not MatchConfig.is_game_mode_selectable(i))
	assert_false(option.is_item_disabled(MatchConfig.GameMode.CAPTURE_THE_FLAG), "Bontago-22y.7")


func test_lobby_timer_round_trips_through_published_lobby_data_to_a_client() -> void:
	var host: Lobby = _make_lobby(true)
	(host.get_node("%RoundTimerSpin") as SpinBox).value = 15
	var calls: Array[Dictionary] = (host.net_provider as FakeNet).set_lobby_data_calls
	assert_gt(calls.size(), 0)
	var published: Dictionary = calls[-1]
	assert_eq(published["game_mode"], MatchConfig.GameMode.CLASSIC)
	assert_eq(published["round_timer_minutes"], 15)
	# A reserved mode on the wire is coerced, then the client shows the result.
	published["game_mode"] = MatchConfig.GameMode.ELIMINATION
	var client: Lobby = _make_lobby(false)
	client._apply_data(published)
	assert_eq((client.get_node("%RoundTimerSpin") as SpinBox).value, 15.0)
	assert_eq((client.get_node("%GameModeOption") as OptionButton).selected, MatchConfig.GameMode.CLASSIC)
	var calls_after: Array[Dictionary] = (client.net_provider as FakeNet).set_lobby_data_calls
	assert_eq(calls_after.size(), 0, "a client never republishes")


func test_lobby_mode_controls_are_in_the_popup_focus_loop_and_host_gated() -> void:
	var host: Lobby = _make_lobby(true)
	var client: Lobby = _make_lobby(false)
	var mode: OptionButton = host.get_node("%GameModeOption")
	var timer: SpinBox = host.get_node("%RoundTimerSpin")
	assert_false(mode.disabled)
	assert_true(timer.editable)
	assert_ne(mode.focus_neighbor_bottom, NodePath(), "gamepad/keyboard focus reaches the mode option")
	assert_ne(timer.focus_neighbor_top, NodePath())
	assert_true((client.get_node("%GameModeOption") as OptionButton).disabled)
	assert_false((client.get_node("%RoundTimerSpin") as SpinBox).editable)


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


func test_base_objective_does_not_replicate_by_default() -> void:
	assert_false(ModeObjective.new().replicates_state())


func test_client_buffers_mode_state_until_the_objective_exists() -> void:
	Match.start_match(_config())
	_client_net()
	Match._territory._objective = null
	Match._lifecycle.apply_replicated_mode_state(_wire_state())
	var stub: StubTimedObjective = StubTimedObjective.new()
	stub.reset(2)
	Match._territory._objective = stub
	Match._lifecycle.flush_pending_mode_state()
	assert_almost_eq(stub.team_score(0), 3.5, 0.0001)
	assert_true(Match._lifecycle._pending_mode_state.is_empty())
