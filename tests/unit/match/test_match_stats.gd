extends GutTest
## autoload/match/MatchStats.gd (Bontago-1pi.13): per-slot stats, the results
## payload MatchLifecycle._finish_match() builds, and net/MatchNet.gd's
## replay/return-to-lobby host intents that reuse the same results flow.

const MatchNetScript := preload("res://net/MatchNet.gd")

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	Match.stats().reset_session_wins()  # the tally outlives a match, not a test
	Net._mode = Net.Mode.OFFLINE
	Net._peers.clear()
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
	Match.set_net_provider(null)
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
	config.hot_seat = false
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
	# Spec 2.4's release-lock ("one release per fixed interval") refuses a
	# second immediate placement on the same slot -- tick a full interval so
	# slot 0's own second block is a legal, counted placement too.
	_tick_playing(6.0)
	assert_eq(_place(0), PlacementRules.REASON_OK, "fixture: slot 0's second placement, a full interval later")
	Events.block_placed.disconnect(collect)

	assert_eq(Match.stats().blocks_placed(0), 2, "slot 0 placed two blocks")
	assert_eq(Match.stats().blocks_placed(1), 1, "slot 1 placed one block")
	assert_eq(Match.stats().blocks_lost(0), 0, "nothing has fallen off the disc yet")

	# One of slot 0's own blocks falls off the disc (spec 3.5's kill plane);
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
	Match._finish_match(1)
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


func _make_net(peer_slots: Dictionary) -> MatchNetScript:
	var fake: FakeNet = FakeNet.host(peer_slots, [0])
	Match.set_net_provider(fake)
	var node: MatchNetScript = MatchNetScript.new()
	node.set_process(false)
	add_child_autofree(node)
	node.set_providers(fake, Match)
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

	Match._finish_match(0)
	assert_eq(Match.state(), MatchAutoload.State.END)

	# An unseated sender (no slot at all) must be rejected even after the
	# match has ended.
	net._handle_replay_request(999)
	assert_eq(Match.state(), MatchAutoload.State.END, "an unseated peer's replay request must be ignored")
	assert_eq(Match.stats().blocks_placed(0), placed_before, "no restart happened, so no stats reset happened either")

	# A seated remote peer's request, after the match has actually ended, is
	# honored: the host restarts with the same MatchConfig for everyone.
	net._handle_replay_request(REMOTE_PEER)
	assert_eq(Match.state(), MatchAutoload.State.COUNTDOWN, "a valid replay request restarts the match")
	assert_eq(Match.stats().blocks_placed(0), 0, "the restarted match's stats start over")


func test_net_match_event_match_results_drops_a_malformed_payload() -> void:
	var net: MatchNetScript = _make_net({1: 0})
	var captured: Array[Dictionary] = []
	var collect: Callable = func(results: Dictionary) -> void: captured.append(results)
	Events.match_results_ready.connect(collect)

	net.net_match_event(MatchNetScript.EVENT_MATCH_RESULTS, ["not a dictionary"])
	assert_eq(captured.size(), 0, "a malformed results payload must never reach game code")

	net.net_match_event(MatchNetScript.EVENT_MATCH_RESULTS, [_sample_valid_payload()])
	Events.match_results_ready.disconnect(collect)
	assert_eq(captured.size(), 1, "a well-formed payload is re-emitted for the client's own game code")
	assert_eq(String(captured[0]["winner_kind"]), "slot")


# --- Bontago-1pi.72.2: height, mode stat, session win tally ------------------

func _finish_and_capture(winner: int) -> Dictionary:
	var captured: Array[Dictionary] = []
	var collect: Callable = func(results: Dictionary) -> void: captured.append(results)
	Events.match_results_ready.connect(collect)
	Match._finish_match(winner)
	Events.match_results_ready.disconnect(collect)
	return captured[0]


## Seats two human peers (ids 101/102) in slots 0/1 of a hosted session.
func _host_two_peers() -> void:
	Net._mode = Net.Mode.HOST
	Net._peers = {101: {"slot_id": 0, "name": "A"}, 102: {"slot_id": 1, "name": "B"}}


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
	_host_two_peers()
	assert_eq(_wins_of(_play_round(0)), [1, 0] as Array[int])
	assert_eq(_wins_of(_play_round(0)), [2, 0] as Array[int], "wins carry over a replay")
	assert_eq(_wins_of(_play_round(1)), [2, 1] as Array[int])

	Events.net_mode_changed.emit(Net.Mode.OFFLINE)  # host session ended
	assert_eq(_wins_of(_play_round(1)), [0, 1] as Array[int], "a new session starts the tally at zero")


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
	net.net_match_event(MatchNetScript.EVENT_MATCH_RESULTS, [wire])
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
	assert_true(MatchStats.validate_results_payload(bad).is_empty(), "a negative wins count is dropped")


# --- Bontago-1pi.69: live scoreboard snapshot ----------------------------------
