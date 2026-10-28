extends "res://tests/unit/match/match_world_test.gd"
## MatchHostPort over the real host Match: every family of forwarder (state, config, slot_count,
## intents, replicator ownership, aim, per-slot reads, gift and feed reads) reaches the Match and
## shows in its public readers, and the FakeHostPort spy keeps the port's shape. Driven through the
## port the consumers hold; the assertions are Match's own readers and effects, so a forwarder that
## drops, reorders or mistypes an argument fails its family.

const SLOT_COUNT: int = 3
const CUBE_ID: StringName = &"cube"
const BOMB_ID: StringName = &"bomb"
## Past the territory settle time after a turn-based placement.
const TURN_SETTLE_FRAMES: int = 480
const POSE_ORIENTATION_OUT_OF_RANGE: int = 9999
## Not overridden by the spy (lint_dead name-ambiguity limit); covered over the real Match above.
const UNSPIED: Array[StringName] = [&"loading_gate_replay_args"]
const AIM: Vector3 = Vector3(1.0, 0.2, 0.0)
const PORT_SCRIPT: Script = preload("res://net/ports/MatchHostPort.gd")
const SPY_SCRIPT: Script = preload("res://tests/support/FakeHostPort.gd")

var _port: MatchHostPort


func before_each() -> void:
	super()
	_port = MatchHostPort.new(Match)


func after_each() -> void:
	_port = null
	Match.set_replicator(null)
	Match._net_provider = null
	for child: Node in _blocks_root.get_children():
		child.free()
	super()
	await get_tree().process_frame


func _config(qol: QolExperiments = null, turn_based: bool = false) -> MatchConfig:
	var config: MatchConfig = _tiny_map_config()
	config.player_count = SLOT_COUNT
	config.game_mode = MatchConfig.GameMode.ELIMINATION
	config.gifts_enabled = false
	config.block_timer = 6.0
	config.rng_seed = 4242
	config.turn_based = turn_based
	config.qol = qol if qol != null else _old_gift_rule()
	return config


## The rule where a claimed gift replaces the next piece (the default queues it one block later).
func _old_gift_rule() -> QolExperiments:
	var qol: QolExperiments = QolExperiments.new()
	qol.gift_loads_next = true
	return qol


func _start(qol: QolExperiments = null, turn_based: bool = false) -> void:
	Match.start_match(_config(qol, turn_based))
	_run_countdown()


## Slot `slot_id` holds a throwable bomb: the gift is queued, then an ordinary piece is placed so
## the feed issues it.
func _hold_bomb(slot_id: int) -> void:
	Match.config.sandbox = true
	assert_true(Match.debug_queue_special(slot_id, BOMB_ID), "fixture: the gift is queued")
	Match.config.sandbox = false
	assert_eq(
		Match.request_place(slot_id, _home_world_position(slot_id), 0, Quaternion.IDENTITY, false),
		PlacementRules.REASON_OK, "fixture: the ordinary piece is placed"
	)
	assert_eq(Match.held_special(slot_id), BOMB_ID, "fixture: the bomb is held")


## The mirror writes a client receives are refused on a host, so a test that seeds Match state
## through them (the replica port's own entry points) runs the Match as a client first.
func _as_client() -> MatchReplicaPort:
	Match._net_provider = FakeNet.client(0)
	return MatchReplicaPort.new(Match)


func _newest_block() -> Block:
	return _blocks_root.get_child(_blocks_root.get_child_count() - 1) as Block


# --- the port itself ---------------------------------------------------------

func test_a_port_over_a_real_match_is_valid() -> void:
	assert_true(_port.is_valid())


# --- state, config, slot_count, slot -----------------------------------------

func test_state_follows_the_match_through_a_whole_round() -> void:
	assert_eq(_port.state(), Match.State.LOBBY)
	_start()
	assert_eq(_port.state(), Match.State.PLAYING)
	Match.abort_match()
	assert_eq(_port.state(), Match.State.LOBBY)


func test_slot_count_is_the_running_matchs_seat_count() -> void:
	_start()
	assert_eq(_port.slot_count(), SLOT_COUNT)


func test_config_is_the_running_matchs_own_config() -> void:
	_start()
	assert_not_null(_port.config())
	assert_same(_port.config(), Match.config)
	assert_eq(_port.config().player_count, SLOT_COUNT)


func test_slot_answers_each_seat_and_none_out_of_range() -> void:
	_start()
	assert_same(_port.slot(0), Match.slot(0))
	assert_same(_port.slot(2), Match.slot(2))
	assert_ne(_port.slot(0), _port.slot(2))
	assert_null(_port.slot(SLOT_COUNT))


func test_start_and_abort_drive_the_match_lifecycle() -> void:
	_port.start_match(_config())
	assert_ne(_port.state(), Match.State.LOBBY)
	assert_eq(Match.config.player_count, SLOT_COUNT, "the port hands over the config it was given")
	_port.abort_match()
	assert_eq(Match.state(), Match.State.LOBBY)


# --- intents -----------------------------------------------------------------

func test_request_place_accepts_a_piece_on_home_ground_and_spends_it() -> void:
	_start()
	var seq: int = Match.feed_seq(0)
	var reason: StringName = _port.request_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, false, seq)
	assert_eq(reason, PlacementRules.REASON_OK)
	assert_eq(_blocks_root.get_child_count(), 1)
	assert_eq(Match.feed_seq(0), seq + 1)


func test_request_place_refusal_reason_comes_back_and_nothing_is_spent() -> void:
	_start()
	var seq: int = Match.feed_seq(0)
	var reason: StringName = _port.request_place(0, _home_world_position(1), 0, Quaternion.IDENTITY, false, seq)
	assert_eq(reason, PlacementRules.REASON_OUTSIDE_TERRITORY)
	assert_eq(_blocks_root.get_child_count(), 0)
	assert_eq(Match.feed_seq(0), seq)


func test_request_place_auto_drop_flag_reaches_the_match() -> void:
	_start()
	var seq: int = Match.feed_seq(0)
	var foreign: Vector3 = _home_world_position(1)
	assert_eq(_port.request_place(0, foreign, 0, Quaternion.IDENTITY, false, seq), PlacementRules.REASON_OUTSIDE_TERRITORY)
	assert_eq(
		_port.request_place(0, foreign, 0, Quaternion.IDENTITY, true, seq), PlacementRules.REASON_OK,
		"an auto-drop is relocated into own ground instead of refused"
	)
	assert_eq(_blocks_root.get_child_count(), 1)


func test_request_place_quotes_the_feed_sequence() -> void:
	_start()
	var stale: int = Match.feed_seq(0) + 5
	var reason: StringName = _port.request_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, false, stale)
	assert_eq(reason, PlacementRules.REASON_NO_BLOCK)
	assert_eq(_blocks_root.get_child_count(), 0)


func test_request_place_names_the_seat_it_acts_for() -> void:
	_start()
	var seq: int = Match.feed_seq(1)
	assert_eq(_port.request_place(1, _home_world_position(1), 0, Quaternion.IDENTITY, false, seq), PlacementRules.REASON_OK)
	assert_eq(Match.feed_seq(1), seq + 1)
	assert_eq(Match.feed_seq(0), 0, "the other seat's piece is untouched")


func test_request_place_in_the_lobby_is_refused_with_a_reason() -> void:
	var reason: StringName = _port.request_place(0, Vector3.ZERO, 0, Quaternion.IDENTITY, false, 0)
	assert_ne(reason, PlacementRules.REASON_OK)


func test_request_throw_launches_the_held_gift_along_the_aim() -> void:
	_start()
	_hold_bomb(0)
	var seq: int = Match.feed_seq(0)
	var reason: StringName = _port.request_throw(0, _home_world_position(0), 0, Quaternion.IDENTITY, AIM, seq)
	assert_eq(reason, PlacementRules.REASON_OK)
	var velocity: Vector3 = _newest_block().linear_velocity
	assert_gt(velocity.x, 0.0, "thrown toward the aim")
	assert_gt(velocity.x, absf(velocity.z))
	assert_eq(Match.feed_seq(0), seq + 1)


func test_request_throw_spawns_at_the_origin_it_was_given() -> void:
	_start()
	_hold_bomb(0)
	var origin: Vector3 = _home_world_position(0)
	assert_eq(_port.request_throw(0, origin, 0, Quaternion.IDENTITY, AIM, Match.feed_seq(0)), PlacementRules.REASON_OK)
	var centre: Vector3 = _field.to_global(Vector3(0.0, 5.0, 0.0))
	var spawned: Vector3 = _newest_block().global_position
	assert_lt(spawned.distance_to(origin), spawned.distance_to(centre), "launched from the home cursor, not the field centre")


func test_request_throw_quotes_the_feed_sequence() -> void:
	_start()
	_hold_bomb(0)
	var blocks: int = _blocks_root.get_child_count()
	var stale: int = Match.feed_seq(0) + 5
	assert_ne(_port.request_throw(0, _home_world_position(0), 0, Quaternion.IDENTITY, AIM, stale), PlacementRules.REASON_OK)
	assert_eq(_blocks_root.get_child_count(), blocks, "a stale throw spawns nothing")
	assert_eq(Match.held_special(0), BOMB_ID, "and the gift stays held")


func test_request_throw_names_the_seat_it_acts_for() -> void:
	_start()
	_hold_bomb(1)
	var reason: StringName = _port.request_throw(
		1, _home_world_position(1), 0, Quaternion.IDENTITY, AIM, Match.feed_seq(1)
	)
	assert_eq(reason, PlacementRules.REASON_OK)
	assert_eq(Match.held_special(1), &"", "seat 1's gift was spent")


func test_request_throw_takes_its_velocity_argument_as_the_aim() -> void:
	_start()
	_hold_bomb(0)
	var reason: StringName = _port.request_throw(
		0, _home_world_position(0), 0, Quaternion.IDENTITY, -AIM, Match.feed_seq(0)
	)
	assert_eq(reason, PlacementRules.REASON_OK)
	assert_lt(_newest_block().linear_velocity.x, 0.0, "the opposite aim throws the opposite way")


func test_request_throw_of_a_plain_piece_is_refused() -> void:
	_start()
	var reason: StringName = _port.request_throw(
		0, _home_world_position(0), 0, Quaternion.IDENTITY, AIM, Match.feed_seq(0)
	)
	assert_ne(reason, PlacementRules.REASON_OK)
	assert_eq(_blocks_root.get_child_count(), 0)


func test_request_use_gift_slot_spends_the_slotted_gift_of_that_seat_only() -> void:
	var qol: QolExperiments = QolExperiments.new()
	qol.gift_slot_enabled = true
	qol.gift_slot_capacity = 1
	_start(qol)
	_as_client().apply_replicated_gift_slot(0, [BOMB_ID], &"", &"")
	Match._net_provider = null
	assert_false(_port.request_use_gift_slot(1), "seat 1's slot is empty")
	assert_eq(Match.held_special(0), &"")
	assert_true(_port.request_use_gift_slot(0))
	assert_eq(Match.held_special(0), BOMB_ID)
	assert_eq(Match.gift_slot_head(0), &"")
	assert_false(_port.request_use_gift_slot(0), "the slot is empty now")


func test_set_cat_target_is_refused_without_a_cat() -> void:
	_start()
	assert_null(_port.active_cat())
	assert_false(_port.set_cat_target(0, Vector3.ZERO))


## A cat owned by seat 0, detonated the way the game does it.
func _release_cat() -> CatController:
	var block: Block = Match.spawn_special_projectile(
		load("res://config/blocks/cube.tres") as BlockShape,
		_field.world_from_disk_local(Match.slot(0).home_position, 5.0),
		Basis.IDENTITY, 0, Vector3.ZERO, null, null
	)
	var effect: CatEffect = CatEffect.new()
	effect.target_range_m = 3.0
	effect.detonate(block, null, 0)
	return Match.active_cat() as CatController


func test_the_active_cat_is_read_and_only_its_owner_may_aim_it() -> void:
	_start()
	var cat: CatController = _release_cat()
	assert_not_null(cat, "fixture: the cat is out")
	assert_same(_port.active_cat(), cat)
	var aim_point: Vector3 = cat.global_position + Vector3.RIGHT * 30.0
	assert_false(_port.set_cat_target(1, aim_point), "another seat cannot steer it")
	assert_true(_port.set_cat_target(0, aim_point))
	assert_almost_eq(cat.target.distance_to(cat._origin), 3.0, 0.01, "the owner's point was taken, clamped to the range")
	assert_false(_port.set_cat_target(0, Vector3.INF), "a non-finite point is refused")


func test_set_cat_target_passes_the_point_not_the_seat() -> void:
	_start()
	var cat: CatController = _release_cat()
	var towards_x: Vector3 = cat.global_position + Vector3.RIGHT * 30.0
	assert_true(_port.set_cat_target(0, towards_x))
	var first: Vector3 = cat.target
	assert_true(_port.set_cat_target(0, cat.global_position + Vector3.BACK * 30.0))
	assert_ne(cat.target, first, "the second point replaced the first")


func test_is_pose_well_formed_judges_the_pose_it_is_given() -> void:
	_start()
	assert_true(_port.is_pose_well_formed(_home_world_position(0), 0, Quaternion.IDENTITY))
	assert_false(_port.is_pose_well_formed(Vector3(NAN, 0.0, 0.0), 0, Quaternion.IDENTITY))
	assert_false(_port.is_pose_well_formed(_home_world_position(0), POSE_ORIENTATION_OUT_OF_RANGE, Quaternion.IDENTITY))


func test_note_aim_steers_the_expiry_throw_of_that_seat() -> void:
	_start()
	_hold_bomb(0)
	_port.note_aim(0, -AIM)
	var reason: StringName = Match.request_place(
		0, _home_world_position(0), 0, Quaternion.IDENTITY, true, Match.feed_seq(0)
	)
	assert_eq(reason, PlacementRules.REASON_OK)
	assert_lt(_newest_block().linear_velocity.x, 0.0, "thrown along the noted aim")


func test_note_aim_for_another_seat_leaves_this_seats_gift_dropped_in_place() -> void:
	_start()
	_hold_bomb(0)
	_port.note_aim(1, AIM)
	var reason: StringName = Match.request_place(
		0, _home_world_position(0), 0, Quaternion.IDENTITY, true, Match.feed_seq(0)
	)
	assert_eq(reason, PlacementRules.REASON_OK)
	assert_eq(_newest_block().linear_velocity, Vector3.ZERO)


# --- replicator ownership ----------------------------------------------------

func test_set_replicator_installs_it_and_null_removes_it() -> void:
	var node: Node = autofree(Node.new())
	_port.set_replicator(node)
	assert_same(Match.replicator(), node)
	_port.set_replicator(null)
	assert_null(Match.replicator())


func test_release_replicator_removes_only_the_installed_one() -> void:
	var mine: Node = autofree(Node.new())
	var other: Node = autofree(Node.new())
	_port.set_replicator(mine)
	_port.release_replicator(other)
	assert_same(Match.replicator(), mine, "a stranger cannot uninstall it")
	_port.release_replicator(mine)
	assert_null(Match.replicator())


func test_release_replicator_leaves_a_replacement_in_place() -> void:
	var old: Node = autofree(Node.new())
	var replacement: Node = autofree(Node.new())
	_port.set_replicator(old)
	_port.set_replicator(replacement)
	_port.release_replicator(old)
	assert_same(Match.replicator(), replacement)


# --- disconnects -------------------------------------------------------------

func test_peer_left_starts_that_seats_grace_and_rejoin_ends_it() -> void:
	_start()
	assert_eq(_port.disconnect_grace_left(1), -1.0, "connected seats have no grace running")
	_port.on_peer_left(1)
	assert_gt(_port.disconnect_grace_left(1), 0.0)
	assert_eq(_port.disconnect_grace_left(1), Match.disconnect_grace_left(1))
	assert_eq(_port.disconnect_grace_left(0), -1.0, "only the seat that left")
	_port.on_peer_rejoined(1)
	assert_eq(_port.disconnect_grace_left(1), -1.0)


func test_default_ghost_origin_is_the_seats_own_start_point() -> void:
	_start()
	var first: Vector3 = _port.default_ghost_origin(0)
	assert_eq(first, Match.default_ghost_origin(0))
	assert_ne(first, _port.default_ghost_origin(1))
	assert_ne(first, Vector3.ZERO)


# --- feed and gift reads -----------------------------------------------------

func test_feed_reads_are_per_seat() -> void:
	_start()
	assert_eq(Match.request_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, false), PlacementRules.REASON_OK)
	assert_eq(_port.feed_seq(0), 1)
	assert_eq(_port.feed_seq(1), 0)
	for slot_id: int in range(SLOT_COUNT):
		assert_same(_port.held_shape(slot_id), Match.held_shape(slot_id))
		assert_same(_port.next_shape(slot_id), Match.next_shape(slot_id))
		assert_eq(_port.feed_time_left(slot_id), Match.feed_time_left(slot_id))
	assert_not_null(_port.held_shape(0))
	assert_not_null(_port.next_shape(2))
	assert_gt(_port.feed_time_left(1), 0.0)


func test_release_lock_is_read_per_seat() -> void:
	_start()
	_as_client().apply_replicated_feed(1, CUBE_ID, CUBE_ID, 3, 2.0, true)
	assert_true(_port.is_release_locked(1))
	assert_false(_port.is_release_locked(0))
	assert_eq(_port.feed_time_left(1), 2.0)
	assert_ne(_port.feed_time_left(0), 2.0, "the other seat's timer is its own")


func test_held_special_is_read_per_seat() -> void:
	_start()
	_hold_bomb(1)
	assert_eq(_port.held_special(1), BOMB_ID)
	assert_eq(_port.held_special(0), &"")


func test_next_special_reads_the_queued_gift_per_seat() -> void:
	_start()
	Match.config.sandbox = true
	assert_true(Match.debug_queue_special(2, BOMB_ID))
	Match.config.sandbox = false
	assert_eq(_port.next_special(2), BOMB_ID)
	assert_eq(_port.next_special(0), &"")


func test_after_next_special_reads_the_staged_gift_per_seat() -> void:
	_start(QolExperiments.new())
	var replica: MatchReplicaPort = _as_client()
	replica.apply_replicated_gift_claimed(7, 2, BOMB_ID)
	replica.apply_replicated_staged_gift(2, CUBE_ID)
	assert_eq(_port.after_next_special(2), BOMB_ID)
	assert_eq(_port.after_next_special(0), &"")


func test_gift_slot_reads_follow_the_qol_toggle_and_the_seat() -> void:
	_start()
	assert_false(_port.gift_slot_enabled())
	Match.abort_match()
	var qol: QolExperiments = QolExperiments.new()
	qol.gift_slot_enabled = true
	_start(qol)
	assert_true(_port.gift_slot_enabled())
	_as_client().apply_replicated_gift_slot(1, [BOMB_ID], &"", &"")
	assert_eq(_port.gift_slot_contents(1), [BOMB_ID] as Array[StringName])
	assert_eq(_port.gift_slot_contents(0), [] as Array[StringName])


func test_gift_crates_are_read_by_id_and_as_a_list() -> void:
	_start()
	assert_true(_port.gift_states().is_empty())
	assert_true(_port.gift_state(7).is_empty())
	_as_client().apply_replicated_gift_spawned(7, Vector2(1.0, 2.0))
	assert_eq(_port.gift_state(7)["position"], Vector2(1.0, 2.0))
	assert_true(_port.gift_state(8).is_empty())
	assert_eq(_port.gift_states().size(), 1)
	assert_eq(_port.gift_states()[0], Match.gift_state(7))


func test_glue_and_qol_counters_are_read_per_seat() -> void:
	_start()
	var replica: MatchReplicaPort = _as_client()
	assert_true(replica.apply_replicated_glue_charges(1, 2, 3))
	assert_eq(_port.glue_drops_left(1), 2)
	assert_eq(_port.glue_revision(1), 3)
	assert_eq(_port.glue_drops_left(0), 0)
	assert_eq(_port.glue_revision(0), 0)
	replica.apply_replicated_qol(2, 2, true)
	assert_eq(_port.qol_backlog_count(2), 2)
	assert_true(_port.qol_timer_paused(2))
	assert_eq(_port.qol_backlog_count(0), 0)
	assert_false(_port.qol_timer_paused(0))


# --- round reads -------------------------------------------------------------

func test_the_active_slot_follows_the_turn_in_a_turn_based_match() -> void:
	_start(null, true)
	var first: int = Match.active_slot()
	assert_gte(first, 0, "fixture: someone has the turn")
	assert_eq(_port.active_slot(), first)
	assert_eq(Match.request_place(first, _home_world_position(first), 0, Quaternion.IDENTITY, false), PlacementRules.REASON_OK)
	for _i: int in range(TURN_SETTLE_FRAMES):
		Match._process(1.0 / Engine.physics_ticks_per_second)
	assert_ne(Match.active_slot(), first, "fixture: the turn passed")
	assert_eq(_port.active_slot(), Match.active_slot())


func test_turn_and_clock_reads_match_the_match() -> void:
	_start()
	assert_eq(_port.active_slot(), Match.active_slot())
	assert_eq(_port.countdown_remaining(), 0.0)
	assert_gt(_port.match_timer_left(), 0.0)
	assert_eq(_port.match_timer_left(), Match.match_timer_left())


func test_countdown_remaining_reads_the_running_countdown() -> void:
	Match.start_match(_config())
	Match._process(1.0 / 60.0)
	assert_eq(Match.state(), Match.State.COUNTDOWN, "fixture: still counting down")
	assert_gt(_port.countdown_remaining(), 0.0)
	assert_eq(_port.countdown_remaining(), Match.countdown_remaining())


func test_elimination_credit_is_read_per_seat() -> void:
	_start()
	_as_client().apply_replicated_elimination(1, 2)
	assert_eq(_port.eliminated_by(1), 2)
	assert_eq(_port.eliminated_by(0), -1)


func test_world_handles_are_the_registered_ones() -> void:
	_start()
	assert_same(_port.field(), Match.field())
	assert_not_null(_port.field())
	assert_same(_port.registry(), _registry)
	assert_same(_port.blocks_parent(), _blocks_root)
	assert_same(_port.raster(), Match.raster())
	assert_not_null(_port.raster())


func test_territory_and_circle_reads_match_the_match() -> void:
	_start()
	for slot_id: int in range(SLOT_COUNT):
		var team: int = Match.slot(slot_id).team_id
		assert_gt(_port.territory_share(team), 0.0)
		assert_eq(_port.territory_share(team), Match.territory_share(team))
	assert_ne(Match.slot(2).team_id, 0, "fixture: the last seat is not team 0")
	assert_gt(_port.circle_wire_radius_max(), 0.0)
	assert_eq(_port.circle_wire_radius_max(), Match.circle_wire_radius_max())
	assert_gt(_port.circle_wire_xz_bound(), 0.0)
	assert_eq(_port.circle_wire_xz_bound(), Match.circle_wire_xz_bound())
	assert_eq(_port.circle_render_arrays(), Match.circle_render_arrays())
	assert_false(_port.circle_render_arrays().is_empty())


func test_mode_state_snapshot_and_collaborator_objects_are_the_matchs() -> void:
	_start()
	assert_eq(_port.mode_state_snapshot(), Match.mode_state_snapshot())
	assert_false(_port.mode_state_snapshot().is_empty())
	assert_same(_port.stats(), Match.stats())
	assert_not_null(_port.stats())
	assert_same(_port.weather(), Match.weather())


func test_stats_is_the_matchs_match_stats_and_writes_through() -> void:
	_start()
	var stats: MatchStats = _port.stats() as MatchStats
	assert_not_null(stats, "the port's stats object is a MatchStats")
	assert_same(stats, Match.stats() as MatchStats)
	stats.record_height(1, 3.5)
	assert_eq((Match.stats() as MatchStats).height_reached(1), 3.5)
	assert_eq(stats.build_live_payload(), (Match.stats() as MatchStats).build_live_payload())


# --- transitional feed and lifecycle collaborators -------------------------------

func test_feed_knows_the_shapes_the_game_ships() -> void:
	_start()
	assert_true(_port.feed_knows_shape(CUBE_ID))
	assert_false(_port.feed_knows_shape(&"no_such_shape"))
	assert_false(_port.feed_knows_shape(&""))


func test_gift_after_next_flag_follows_the_rule_in_force() -> void:
	_start(QolExperiments.new())
	assert_true(_port.feed_gift_after_next_active())
	Match.abort_match()
	_start(_old_gift_rule())
	assert_false(_port.feed_gift_after_next_active())


func test_staged_gift_shape_is_read_per_seat() -> void:
	_start(QolExperiments.new())
	_as_client().apply_replicated_staged_gift(1, CUBE_ID)
	assert_eq(_port.feed_staged_gift_shape_id(1), CUBE_ID)
	assert_eq(_port.feed_staged_gift_shape_id(0), &"")


func test_claim_carrier_shape_is_the_staged_one_or_the_next_one() -> void:
	_start(QolExperiments.new())
	for slot_id: int in range(SLOT_COUNT):
		assert_eq(_port.feed_claim_carrier_shape_id(slot_id), Match.next_shape(slot_id).id, "no staged gift yet")
	_as_client().apply_replicated_staged_gift(1, CUBE_ID)
	assert_eq(_port.feed_claim_carrier_shape_id(1), CUBE_ID)
	assert_eq(_port.feed_claim_carrier_shape_id(0), Match.next_shape(0).id)


func test_a_triggered_special_pauses_block_timers_through_the_port() -> void:
	var qol: QolExperiments = QolExperiments.new()
	qol.timer_pause_enabled = true
	_start(qol)
	var before: float = Match.feed_time_left(0)
	_port.feed_note_special_triggered()
	Match._process(0.5)
	assert_eq(Match.feed_time_left(0), before, "the pause held the block timer")


func test_starting_match_is_false_once_the_round_runs() -> void:
	_start()
	assert_false(_port.is_starting_match())


func test_loading_gate_replay_args_answer_the_open_gate_of_a_host() -> void:
	_start()
	var args: Array = _port.loading_gate_replay_args()
	assert_eq(args.size(), 3)
	assert_true(args[2], "an unarmed gate replays as open")


# --- the spy -----------------------------------------------------------------

func test_the_spy_is_valid_and_starts_empty() -> void:
	var spy: FakeHostPort = FakeHostPort.new()
	assert_true(spy.is_valid())
	assert_eq(spy.calls.size(), 0)


func test_the_spy_records_calls_in_order_with_their_arguments() -> void:
	var spy: FakeHostPort = FakeHostPort.new()
	spy.on_peer_left(2)
	spy.note_aim(1, AIM)
	spy.on_peer_left(0)
	assert_eq(spy.calls.size(), 3)
	assert_eq(spy.calls[1], {"method": &"note_aim", "args": [1, AIM]})
	assert_eq(spy.calls_to(&"on_peer_left"), [[2], [0]] as Array[Array])
	assert_eq(spy.calls_to(&"abort_match"), [] as Array[Array])


func test_the_spy_accepts_intents_and_answers_reads_neutrally() -> void:
	var spy: FakeHostPort = FakeHostPort.new()
	assert_eq(spy.request_place(0, Vector3.ONE, 1, Quaternion.IDENTITY, true, 4), PlacementRules.REASON_OK)
	assert_eq(spy.request_throw(0, Vector3.ONE, 1, Quaternion.IDENTITY, AIM, 4), PlacementRules.REASON_OK)
	assert_eq(spy.calls_to(&"request_place"), [[0, Vector3.ONE, 1, Quaternion.IDENTITY, true, 4]] as Array[Array])
	assert_eq(spy.state(), 0)
	assert_eq(spy.slot_count(), 0)
	assert_null(spy.config())
	assert_null(spy.slot(0))
	assert_eq(spy.active_slot(), -1)
	assert_eq(spy.eliminated_by(0), -1)
	assert_eq(spy.disconnect_grace_left(0), -1.0)
	assert_false(spy.request_use_gift_slot(0))
	assert_true(spy.gift_slot_contents(0).is_empty())


func test_the_spy_never_reaches_the_real_match() -> void:
	_start()
	var spy: FakeHostPort = FakeHostPort.new()
	spy.abort_match()
	spy.on_peer_left(1)
	assert_eq(Match.state(), Match.State.PLAYING)
	assert_eq(Match.disconnect_grace_left(1), -1.0)
	assert_eq(spy.state(), 0)


func test_the_spy_answers_every_public_method_of_the_port() -> void:
	var spy: FakeHostPort = FakeHostPort.new()
	var asked: Array[StringName] = []
	for info: Dictionary in PORT_SCRIPT.get_script_method_list():
		var method_name: StringName = StringName(info["name"])
		if String(method_name).begins_with("_") or method_name == &"is_valid" or UNSPIED.has(method_name):
			continue
		spy.callv(method_name, _neutral_args(info))
		asked.append(method_name)
		assert_eq(
			spy.calls_to(method_name).size(), 1, "%s is answered, and recorded, by the spy" % method_name
		)
	assert_gt(asked.size(), 49, "fixture: the port's methods were enumerated")


func test_the_spy_keeps_the_port_signatures() -> void:
	var ported: Dictionary = {}
	for info: Dictionary in PORT_SCRIPT.get_script_method_list():
		ported[String(info["name"])] = info
	for info: Dictionary in SPY_SCRIPT.get_script_method_list():
		var method_name: String = String(info["name"])
		if method_name.begins_with("_") or not ported.has(method_name):
			continue
		var want: Dictionary = ported[method_name]
		assert_eq((info["args"] as Array).size(), (want["args"] as Array).size(), "%s arity" % method_name)
		assert_eq((info["default_args"] as Array).size(), (want["default_args"] as Array).size(), "%s defaults" % method_name)
		assert_eq((info["return"] as Dictionary)["type"], (want["return"] as Dictionary)["type"], "%s return type" % method_name)


## One argument of the declared type per parameter of `info`.
func _neutral_args(info: Dictionary) -> Array:
	var args: Array = []
	for arg: Dictionary in info["args"]:
		match int(arg["type"]):
			TYPE_INT:
				args.append(0)
			TYPE_FLOAT:
				args.append(0.0)
			TYPE_BOOL:
				args.append(false)
			TYPE_VECTOR3:
				args.append(Vector3.ZERO)
			TYPE_QUATERNION:
				args.append(Quaternion.IDENTITY)
			TYPE_STRING_NAME:
				args.append(&"")
			_:
				args.append(null)
	return args
