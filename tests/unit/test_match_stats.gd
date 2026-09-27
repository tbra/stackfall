extends GutTest
## autoload/match/MatchStats.gd (Bontago-1pi.13): per-slot stats, the results
## payload MatchLifecycle._finish_match() builds, and net/MatchNet.gd's
## replay/return-to-lobby host intents that reuse the same results flow.
##
## Regression focus: the owner's playtest report is "always says Team x
## wins! even when not playing in teams" -- ui/HUD.gd's own show_winner()
## always renders "Team %d wins!" regardless of MatchConfig.team_mode. This
## file proves the new results payload actually carries a "slot" vs "team"
## distinction the (later) results-screen UI worker can act on, so a
## free-for-all match reports a player, not a phantom team.
##
## Fixture mirrors tests/unit/test_match_feed.gd's own before_each/after_each
## and helpers (duplicated rather than shared -- GDScript test scripts don't
## inherit each other's private helpers).

const MatchNetScript := preload("res://net/MatchNet.gd")

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef


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
	Match.set_net_provider(null)
	Match.set_replicator(null)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _tiny_map_config() -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
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


func _cube_shape() -> BlockShape:
	return load("res://config/blocks/cube.tres") as BlockShape


## Review fix (Bontago-1pi.13, finding B): MatchPlacement.spawn_special_
## projectile() (a special effect's own runtime spawn, e.g. Volcano's 8-14
## lava orbs -- not a player intent) used to share the same Events.block_
## placed emission as a real placement, inflating the triggering slot's own
## blocks_placed stat by however many orbs it launched.
func test_special_projectile_spawns_do_not_count_as_blocks_placed() -> void:
	Match.start_match(_free_for_all_config(2))
	_run_countdown()
	var tuning: SpecialTuning = (load("res://config/special_tuning.tres") as SpecialTuning).duplicate(true)

	assert_eq(_place(0), PlacementRules.REASON_OK, "fixture: one genuine player placement for slot 0")
	assert_eq(Match.stats().blocks_placed(0), 1)

	for _i: int in range(10):
		var orb: Block = Match.spawn_special_projectile(
			_cube_shape(), _home_world_position(0), Basis.IDENTITY, 0, Vector3(0.0, 5.0, 0.0), null, tuning
		)
		assert_not_null(orb, "fixture: the projectile spawn itself must still succeed")

	assert_eq(
		Match.stats().blocks_placed(0), 1,
		"ten Volcano-like orb spawns for slot 0 must not move its blocks_placed stat at all"
	)


func test_gifts_claimed_and_specials_used_are_tracked_per_slot() -> void:
	Match.start_match(_free_for_all_config(2))
	_run_countdown()

	Events.gift_claimed.emit(1, 0, &"bomb")
	Events.gift_claimed.emit(2, 0, &"volcano")
	Events.gift_claimed.emit(3, 1, &"rocket")
	Events.special_consumed.emit(0, &"bomb")

	assert_eq(Match.stats().gifts_claimed(0), 2, "slot 0 claimed two gifts")
	assert_eq(Match.stats().gifts_claimed(1), 1, "slot 1 claimed one gift")
	assert_eq(Match.stats().specials_used(0), 1, "slot 0 spent one special")
	assert_eq(Match.stats().specials_used(1), 0, "slot 1 has not spent one yet")


func test_elimination_time_is_recorded_once_per_slot() -> void:
	Match.start_match(_free_for_all_config(2))
	_run_countdown()
	_tick_playing(0.5)

	Events.player_eliminated.emit(0, 0)
	var first_reading: float = Match.stats().eliminated_at(0)
	assert_gt(first_reading, 0.0, "the elimination time must be a real elapsed duration, not the sentinel")
	assert_eq(Match.stats().eliminated_at(1), MatchStats.NOT_ELIMINATED, "slot 1 was never eliminated")

	# A repeat emission for the same slot (defensive: two listeners racing on
	# the same elimination) must not overwrite the first, more accurate,
	# elapsed time with a later one.
	_tick_playing(0.5)
	Events.player_eliminated.emit(0, 0)
	assert_eq(Match.stats().eliminated_at(0), first_reading, "a repeat emission must not move the recorded time")


func test_stats_reset_between_matches() -> void:
	Match.start_match(_free_for_all_config(2))
	_run_countdown()
	_place(0)
	assert_eq(Match.stats().blocks_placed(0), 1)

	# request_replay()'s own host branch is exactly this call
	# (net/MatchNet.gd's _replay_current_match()) -- a replay must not leak
	# the ended match's stats into the new one.
	Match.start_match(_free_for_all_config(2))
	assert_eq(Match.stats().blocks_placed(0), 0, "a fresh match starts every counter back at zero")


# --- The reported defect: FFA must not always say "Team X wins!" -----------

func test_ffa_winner_is_reported_as_a_slot_not_a_team() -> void:
	var captured: Array[Dictionary] = []
	var collect: Callable = func(results: Dictionary) -> void: captured.append(results)
	Events.match_results_ready.connect(collect)

	Match.start_match(_free_for_all_config(2))
	_run_countdown()
	_place(0)
	Match._finish_match(0)
	Events.match_results_ready.disconnect(collect)

	assert_eq(captured.size(), 1, "exactly one results payload per match end")
	var results: Dictionary = captured[0]
	assert_eq(String(results["winner_kind"]), "slot", "free-for-all (TeamMode.OFF) must report a slot winner, not a team")
	assert_eq(int(results["winner_id"]), 0)
	assert_eq(String(results["winner_name"]), Match.slot(0).display_name, "FFA's winner name is the winning slot's own display name")
	assert_almost_eq(float(results["match_duration"]), Match.stats().match_duration(), 0.001)

	var rows: Array = results["rows"]
	assert_eq(rows.size(), 2, "one row per slot")
	var row0: Dictionary = rows[0]
	assert_eq(int(row0["slot_id"]), 0)
	assert_eq(int(row0["blocks_placed"]), 1)
	assert_eq(float(row0["eliminated_at"]), MatchStats.NOT_ELIMINATED, "slot 0 won, it was never eliminated")
	assert_between(float(row0["territory_share"]), 0.0, 1.0)


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
	assert_eq(String(results["winner_name"]), "Team 2", "1-based, matching ui/HUD.gd's existing numbering")
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


func test_validate_results_payload_accepts_a_well_formed_payload() -> void:
	var validated: Dictionary = MatchStats.validate_results_payload(_sample_valid_payload())
	assert_false(validated.is_empty(), "a well-formed payload must not be rejected")
	assert_eq(String(validated["winner_kind"]), "slot")
	assert_eq((validated["rows"] as Array).size(), 2)


func test_validate_results_payload_rejects_malformed_payloads() -> void:
	assert_true(MatchStats.validate_results_payload("not a dictionary").is_empty(), "a non-Dictionary must be dropped")

	var bad_kind: Dictionary = _sample_valid_payload()
	bad_kind["winner_kind"] = "clan"
	assert_true(MatchStats.validate_results_payload(bad_kind).is_empty(), "an unknown winner_kind must be dropped")

	var missing_rows: Dictionary = _sample_valid_payload()
	missing_rows.erase("rows")
	assert_true(MatchStats.validate_results_payload(missing_rows).is_empty(), "a payload with no rows array must be dropped")

	var negative_duration: Dictionary = _sample_valid_payload()
	negative_duration["match_duration"] = -1.0
	assert_true(MatchStats.validate_results_payload(negative_duration).is_empty(), "a negative duration must be dropped")

	var nan_duration: Dictionary = _sample_valid_payload()
	nan_duration["match_duration"] = NAN
	assert_true(MatchStats.validate_results_payload(nan_duration).is_empty(), "a non-finite duration must be dropped")

	var bad_row: Dictionary = _sample_valid_payload()
	var rows: Array = (bad_row["rows"] as Array).duplicate(true)
	var row0: Dictionary = rows[0]
	row0["blocks_placed"] = -1
	rows[0] = row0
	bad_row["rows"] = rows
	assert_true(MatchStats.validate_results_payload(bad_row).is_empty(), "a negative counter inside a row must be dropped")

	var wrong_type_row: Dictionary = _sample_valid_payload()
	var rows2: Array = (wrong_type_row["rows"] as Array).duplicate(true)
	var row1: Dictionary = rows2[0]
	row1["is_bot"] = "yes"
	rows2[0] = row1
	wrong_type_row["rows"] = rows2
	assert_true(MatchStats.validate_results_payload(wrong_type_row).is_empty(), "a wrong-typed field inside a row must be dropped")


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


func test_return_to_lobby_request_sends_the_match_back_to_lobby() -> void:
	var net: MatchNetScript = _make_net({1: 0, REMOTE_PEER: REMOTE_SLOT})
	Match.start_match(_free_for_all_config(2))
	_run_countdown()
	Match._finish_match(0)
	assert_eq(Match.state(), MatchAutoload.State.END)

	net._handle_return_to_lobby_request(REMOTE_PEER)
	assert_eq(Match.state(), MatchAutoload.State.LOBBY, "a valid return-to-lobby request ends the match for everyone")


## Review fix (Bontago-1pi.13, finding A): the host's own local call used to
## skip the END-state gate entirely (only a *remote* request was checked),
## so a stray local request_replay()/request_return_to_lobby() call
## mid-match would restart or abandon everyone's match with no confirmation.
func test_host_local_replay_and_return_requests_are_ignored_mid_match() -> void:
	var net: MatchNetScript = _make_net({1: 0})
	Match.start_match(_free_for_all_config(2))
	_run_countdown()
	_place(0)
	var placed_before: int = Match.stats().blocks_placed(0)

	net.request_replay()
	assert_eq(Match.state(), MatchAutoload.State.PLAYING, "the host's own local replay request must be ignored mid-match")
	assert_eq(Match.stats().blocks_placed(0), placed_before, "no restart happened, so stats must be untouched")

	net.request_return_to_lobby()
	assert_eq(Match.state(), MatchAutoload.State.PLAYING, "the host's own local return-to-lobby request must be ignored mid-match")

	# After the match actually ends, the same local calls are honored.
	Match._finish_match(0)
	assert_eq(Match.state(), MatchAutoload.State.END)
	net.request_replay()
	assert_eq(Match.state(), MatchAutoload.State.COUNTDOWN, "a local replay request is honored once the match has ended")


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
