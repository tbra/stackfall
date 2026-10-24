extends GutTest
## autoload/match/MatchStats.gd: per-slot stats, the results
## payload MatchLifecycle._finish_match() builds, and net/MatchNet.gd's
## replay/return-to-lobby host intents that reuse the same results flow.

const MatchNetScript := preload("res://net/MatchNet.gd")

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef
var _loopback: LoopbackSession


func before_each() -> void:
	_loopback = LoopbackSession.new(self)
	Match.set_process(false)
	Match.abort_match()
	Match.stats().reset_session_wins()  # the tally outlives a match, not a test
	Net.leave()
	_tiny_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
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
	await _loopback.end()
	Match._net_provider = null
	Match.set_replicator(null)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _tiny_map_config() -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	return config


func _free_for_all_config(player_count: int = 2, block_timer: float = 6.0) -> MatchConfig:
	var config: MatchConfig = _tiny_map_config()
	config.player_count = player_count
	config.block_timer = block_timer
	config.rng_seed = 13579
	return config


func _team_config(player_count: int, team_mode: MatchConfig.TeamMode) -> MatchConfig:
	var config: MatchConfig = _free_for_all_config(player_count)
	config.team_mode = team_mode
	return config


func _run_countdown() -> void:
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)


func _tick_playing(seconds: float) -> void:
	var steps: int = int(ceil(seconds * 60.0))
	for _i: int in range(steps):
		Match._process(1.0 / 60.0)


func _home_world_position(slot_id: int) -> Vector3:
	var home: Vector2 = Match.slot(slot_id).home_position
	return _field.to_global(Vector3(home.x, 5.0, home.y))


func _place(slot_id: int) -> StringName:
	return Match.request_place(slot_id, _home_world_position(slot_id), 0, Quaternion.IDENTITY, false)


# --- Per-slot counters -------------------------------------------------------

func test_blocks_placed_and_blocks_lost_are_tracked_per_slot() -> void:
	var placed_blocks: Array[RigidBody3D] = []
	var collect: Callable = func(block: RigidBody3D, _shape_id: StringName) -> void: placed_blocks.append(block)
	Events.block_placed.connect(collect)

	Match.start_match(_free_for_all_config(2, 6.0))
	_run_countdown()

	assert_eq(_place(0), PlacementRules.REASON_OK, "fixture: a legal placement on slot 0's own home flag")
	assert_eq(_place(1), PlacementRules.REASON_OK, "fixture: a legal placement on slot 1's own home flag")
	# Spec 1.4's release-lock ("one release per fixed interval") refuses a
	# second immediate placement on the same slot -- tick a full interval so
	# slot 0's own second block is a legal, counted placement too.
	_tick_playing(6.0)
	assert_eq(_place(0), PlacementRules.REASON_OK, "fixture: slot 0's second placement, a full interval later")
	Events.block_placed.disconnect(collect)

	assert_eq(Match.stats().blocks_placed(0), 2, "slot 0 placed two blocks")
	assert_eq(Match.stats().blocks_placed(1), 1, "slot 1 placed one block")
	assert_eq(Match.stats().blocks_lost(0), 0, "nothing has fallen off the disc yet")

	# One of slot 0's own blocks falls off the disc (spec 2.7's kill plane);
	# a non-kill-plane despawn (a future body-cap dissolve) must not count.
	Events.block_removed.emit(placed_blocks[0], String(Events.REASON_KILL_PLANE))
	Events.block_removed.emit(placed_blocks[1], "some_other_reason")

	assert_eq(Match.stats().blocks_lost(0), 1, "only the kill-plane removal counts as lost")
	assert_eq(Match.stats().blocks_lost(1), 0, "slot 1 lost nothing")


# --- The reported defect: FFA must not always say "Team X wins!" -----------

func test_team_mode_winner_is_reported_as_a_team() -> void:
	var captured: Array[Dictionary] = []
	var collect: Callable = func(results: Dictionary) -> void: captured.append(results)
	Events.match_results_ready.connect(collect)

	Match.start_match(_team_config(4, MatchConfig.TeamMode.TEAMS_2))
	_run_countdown()
	Match._lifecycle._finish_match(1)
	Events.match_results_ready.disconnect(collect)

	var results: Dictionary = captured[0]
	assert_eq(String(results["winner_kind"]), "team")
	assert_eq(int(results["winner_id"]), 1)
	assert_eq(String(results["winner_name"]), "Team 2", "1-based, matching ui/hud/HUD.gd's existing numbering")
	assert_eq((results["rows"] as Array).size(), 4)


# --- Wire validation (net/MatchNet.gd EVENT_MATCH_RESULTS) ------------------

func _sample_valid_payload() -> Dictionary:
	return {
		"winner_kind": "slot",
		"winner_id": 0,
		"winner_name": "Player 1",
		"match_duration": 42.5,
		"rows": [
			{
				"slot_id": 0, "name": "Player 1", "team_id": 0, "is_bot": false,
				"blocks_placed": 3, "blocks_lost": 1, "gifts_claimed": 1, "specials_used": 0,
				"territory_share": 0.75, "eliminated_at": -1.0,
			},
			{
				"slot_id": 1, "name": "Player 2", "team_id": 1, "is_bot": true,
				"blocks_placed": 2, "blocks_lost": 0, "gifts_claimed": 0, "specials_used": 1,
				"territory_share": 0.25, "eliminated_at": 12.0,
			},
		],
	}


# --- Host-only replay / return-to-lobby intents (net/MatchNet.gd) ----------

const REMOTE_PEER: int = 77
const REMOTE_SLOT: int = 1


var _fake: FakeNet


## The host's intent gateway bound the way MatchNet binds it, for requests that name their sender.
func _gateway() -> MatchIntentGateway:
	var seams: MatchIntentGateway.Seams = MatchIntentGateway.Seams.new()
	seams.can_send = func() -> bool: return false
	seams.send_to_host = func(_method: StringName, _args: Array) -> void: pass
	seams.send_to_peer = func(_peer: int, _method: StringName, _args: Array) -> bool: return true
	seams.broadcast = func(_method: StringName, _args: Array) -> void: pass
	seams.now_s = func() -> float: return 0.0
	seams.is_replay_pending = func(_peer: int) -> bool: return false
	seams.store_cursor = func(_slot: int, _origin: Vector3, _index: int, _quat: Quaternion) -> void: pass
	return MatchIntentGateway.new(FakeSessionPort.new(_fake), MatchHostPort.new(Match), preload("res://config/net/net_config.tres"), NetCounters.new(), seams)


func _make_net(peer_slots: Dictionary) -> MatchNetScript:
	var fake: FakeNet = FakeNet.host(peer_slots, [0])
	_fake = fake
	Match._net_provider = fake
	var node: MatchNetScript = MatchNetScript.new()
	node.set_process(false)
	add_child_autofree(node)
	assert_true(node.bind_ports(FakeSessionPort.new(fake), MatchHostPort.new(Match), MatchReplicaPort.new(Match)))
	return node


func test_replay_request_is_ignored_before_match_end_or_from_an_unseated_peer() -> void:
	var net: MatchNetScript = _make_net({1: 0, REMOTE_PEER: REMOTE_SLOT})
	Match.start_match(_free_for_all_config(2))
	_run_countdown()
	_place(0)
	var placed_before: int = Match.stats().blocks_placed(0)

	# Mid-match (not State.END yet): even a seated peer's request must be
	# dropped -- a replay/return would otherwise abandon every other
	# player's match out from under them with no confirmation.
	net.net_request_replay()
	assert_eq(Match.state(), MatchAutoload.State.PLAYING, "a replay request mid-match must be ignored")

	Match._lifecycle._finish_match(0)
	assert_eq(Match.state(), MatchAutoload.State.END)

	# An unseated sender (no slot at all) must be rejected even after the
	# match has ended.
	_gateway().handle_replay_request(999)
	assert_eq(Match.state(), MatchAutoload.State.END, "an unseated peer's replay request must be ignored")
	assert_eq(Match.stats().blocks_placed(0), placed_before, "no restart happened, so no stats reset happened either")

	# A seated remote peer's request, after the match has actually ended, is
	# honored: the host restarts with the same MatchConfig for everyone.
	_gateway().handle_replay_request(REMOTE_PEER)
	assert_eq(Match.state(), MatchAutoload.State.COUNTDOWN, "a valid replay request restarts the match")
	assert_eq(Match.stats().blocks_placed(0), 0, "the restarted match's stats start over")


func test_net_match_event_match_results_drops_a_malformed_payload() -> void:
	var net: MatchNetScript = _make_net({1: 0})
	var captured: Array[Dictionary] = []
	var collect: Callable = func(results: Dictionary) -> void: captured.append(results)
	Events.match_results_ready.connect(collect)

	net.net_match_event(MatchWireEvents.MATCH_RESULTS, ["not a dictionary"])
	assert_eq(captured.size(), 0, "a malformed results payload must never reach game code")

	net.net_match_event(MatchWireEvents.MATCH_RESULTS, [_sample_valid_payload()])
	Events.match_results_ready.disconnect(collect)
	assert_eq(captured.size(), 1, "a well-formed payload is re-emitted for the client's own game code")
	assert_eq(String(captured[0]["winner_kind"]), "slot")


# --- height, mode stat, session win tally ------------------

func _finish_and_capture(winner: int) -> Dictionary:
	var captured: Array[Dictionary] = []
	var collect: Callable = func(results: Dictionary) -> void: captured.append(results)
	Events.match_results_ready.connect(collect)
	Match._lifecycle._finish_match(winner)
	Events.match_results_ready.disconnect(collect)
	return captured[0]


## Hosts a real private loopback session: the host's own peer holds slot 0, so the tally keys
## its seats on a live roster.
func _host_session() -> void:
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "A", false), OK)


## A hosted session with one remote client seated in slot 1.
func _host_with_client(client_name: String) -> Node:
	_host_session()
	var client: Node = await _loopback.join_remote_client(client_name)
	assert_not_null(client, "fixture: the remote client is seated")
	assert_eq(Net.slot_of_peer(client.local_peer_id()), 1)
	return client


func _wins_of(results: Dictionary) -> Array[int]:
	var wins: Array[int] = []
	for row: Dictionary in (results["rows"] as Array):
		wins.append(int(row["wins"]))
	return wins


func _play_round(winner: int) -> Dictionary:
	Match.start_match(_free_for_all_config(2))
	_run_countdown()
	return _finish_and_capture(winner)


func test_session_wins_accumulate_across_rounds_and_reset_with_the_host_session() -> void:
	await _host_with_client("B")
	assert_eq(_wins_of(_play_round(0)), [1, 0] as Array[int])
	assert_eq(_wins_of(_play_round(0)), [2, 0] as Array[int], "wins carry over a replay")
	assert_eq(_wins_of(_play_round(1)), [2, 1] as Array[int])

	Net.leave()  # host session ended
	_host_session()
	assert_eq(_wins_of(_play_round(1)), [0, 1] as Array[int], "a new session starts the tally at zero")


## Waits until the host's roster no longer lists the departed client.
func _wait_for_roster(size: int) -> void:
	assert_true(await wait_until(func() -> bool: return Net.peer_ids().size() == size, 10.0), "fixture: roster reaches %d peers" % size)


func _play_ffa_round(player_count: int, ai_count: int, winner: int) -> Array[int]:
	var config: MatchConfig = _free_for_all_config(player_count)
	config.ai_count = ai_count
	Match.start_match(config)
	_run_countdown()
	return _wins_of(_finish_and_capture(winner))


func test_a_seat_taken_by_a_different_peer_loses_its_tally_and_the_host_keeps_its_own() -> void:
	var leaver: Node = await _host_with_client("B")
	assert_eq(_play_ffa_round(2, 0, 0), [1, 0] as Array[int])
	assert_eq(_play_ffa_round(2, 0, 1), [1, 1] as Array[int])

	Match.abort_match()  # nothing is in flight to a client while the seat changes hands
	leaver.leave()
	await _wait_for_roster(1)
	var newcomer: Node = await _loopback.join_remote_client("C")
	assert_not_null(newcomer, "fixture: C seated")
	assert_eq(Net.slot_of_peer(newcomer.local_peer_id()), 1, "fixture: C takes the vacated seat")

	assert_eq(_play_ffa_round(2, 0, 0), [2, 0] as Array[int],
		"only the seat that changed occupant starts at 0; the host keeps its wins")


func test_a_peer_joining_a_seat_vacated_during_a_match_starts_at_zero_and_the_host_keeps_its_own() -> void:
	var leaver: Node = await _host_with_client("B")
	assert_eq(_play_ffa_round(2, 0, 1), [0, 1] as Array[int], "fixture: B holds a win")
	Match.abort_match()
	Match.start_match(_free_for_all_config(2))
	_run_countdown()

	leaver.leave()
	await _wait_for_roster(1)
	var newcomer: Node = await _loopback.join_remote_client("C")
	assert_not_null(newcomer, "fixture: C seated mid-match")
	assert_eq(Net.slot_of_peer(newcomer.local_peer_id()), 1, "fixture: C takes the vacated seat")
	await wait_frames(10) # the host's match RPCs reach C's MatchNet without an engine error

	assert_eq(_wins_of(_finish_and_capture(0)), [1, 0] as Array[int],
		"B's win does not pass to C, and the host's round win counts")


func test_a_vacated_seat_that_a_bot_takes_loses_its_tally_and_the_host_keeps_its_own() -> void:
	var client: Node = await _host_with_client("B")
	assert_eq(_play_ffa_round(2, 0, 0), [1, 0] as Array[int])
	assert_eq(_play_ffa_round(2, 0, 1), [1, 1] as Array[int])

	Match.abort_match()
	client.leave()
	await _wait_for_roster(1)

	assert_eq(_play_ffa_round(2, 1, 0), [2, 0] as Array[int], "the seat is a bot now: a fresh tally, the host's stays")
	assert_eq(_play_ffa_round(2, 1, 1), [2, 1] as Array[int], "the bot's own wins count from then on")


func test_a_seat_vacated_during_a_match_starts_again_when_the_round_is_recorded() -> void:
	var leaver: Node = await _host_with_client("B")
	assert_eq(_play_ffa_round(2, 0, 1), [0, 1] as Array[int])
	Match.abort_match()

	# The round starts with B seated (the match-start check sees no change) ...
	var config: MatchConfig = _free_for_all_config(2)
	Match.start_match(config)
	_run_countdown()
	assert_eq(Match.stats().session_wins(1), 1, "fixture: B's win survives the round start")
	# ... then B leaves before the round ends and nobody takes the seat.
	leaver.leave()
	await _wait_for_roster(1)

	assert_eq(_wins_of(_finish_and_capture(1)), [0, 1] as Array[int],
		"the vacated seat starts at 0 and earns this round's win, not B's carried-over 1 plus it")


func test_a_human_seat_that_becomes_a_bot_seat_between_offline_matches_starts_again() -> void:
	assert_eq(_play_ffa_round(2, 0, 1), [0, 1] as Array[int], "fixture: offline, seat 1 is a human with a win")
	Match.abort_match()

	var config: MatchConfig = _free_for_all_config(2)
	config.ai_count = 1
	Match.start_match(config)
	assert_eq(Match.stats().session_wins(1), 0, "the seat is a bot now: its tally is dropped at match start")
	_run_countdown()
	assert_eq(_wins_of(_finish_and_capture(1)), [0, 1] as Array[int], "the bot counts its own wins from zero")


func test_another_net_instance_changing_mode_does_not_wipe_the_hosts_tally() -> void:
	var client: Node = await _host_with_client("B")
	assert_eq(_play_ffa_round(2, 0, 0), [1, 0] as Array[int])
	assert_eq(Match.stats().session_wins(0), 1, "fixture: the host's seat holds a win")

	client.leave()  # a second Net instance leaves its session: it announces on the shared Events bus

	assert_eq(Match.stats().session_wins(0), 1, "only the host's own session ending resets the tally")
	Net.leave()
	assert_eq(Match.stats().session_wins(0), 0, "the host's session ending does")


func test_client_receives_the_same_tally_over_the_results_event() -> void:
	Match.start_match(_free_for_all_config(2))
	_run_countdown()
	Match.stats().record_height(1, 4.0)
	var host_results: Dictionary = _finish_and_capture(1)
	var wire: Dictionary = host_results.duplicate(true)

	var net: MatchNetScript = _make_net({1: 0})
	var captured: Array[Dictionary] = []
	var collect: Callable = func(results: Dictionary) -> void: captured.append(results)
	Events.match_results_ready.connect(collect)
	net.net_match_event(MatchWireEvents.MATCH_RESULTS, [wire])
	Events.match_results_ready.disconnect(collect)
	assert_eq(captured.size(), 1)
	var client_rows: Array = captured[0]["rows"]
	var host_rows: Array = host_results["rows"]
	for i: int in range(host_rows.size()):
		assert_eq(int(client_rows[i]["wins"]), int(host_rows[i]["wins"]))
		assert_almost_eq(float(client_rows[i]["height"]), float(host_rows[i]["height"]), 0.001)
	assert_eq(int(client_rows[1]["wins"]), 1)

	var bad: Dictionary = host_results.duplicate(true)
	(bad["rows"] as Array)[0]["wins"] = -1
	assert_true(ResultsValidation.validate_results_payload(bad).is_empty(), "a negative wins count is dropped")


# --- live scoreboard snapshot ----------------------------------
