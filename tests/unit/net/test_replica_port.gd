extends GutTest
## MatchReplicaPort over a real client Match: every family of mirror write the host's answers
## make reaches the Match and shows in its public reads, and the FakeReplicaPort spy keeps the
## port's shape. Driven through the port the consumers hold; the assertions are Match's own
## readers, so a forwarder that drops, reorders or mistypes an argument fails its family.

const LOCAL_SLOT: int = 1
const CUBE_ID: StringName = &"cube"
const SPECIAL_ID: StringName = &"bomb"
const CAT_ID: int = 1
## Left out of the spy on purpose, see the note in FakeReplicaPort.gd.
const UNSPIED: String = "apply_replicated_staged_gift"

var _tiny_map: MapDef
var _field: Field
var _registry: BlockRegistry
var _blocks_root: Node3D
var _port: MatchReplicaPort


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
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
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 3
	config.game_mode = MatchConfig.GameMode.ELIMINATION
	config.gifts_enabled = false
	config.rng_seed = 4242
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)
	Match._net_provider = FakeNet.client(LOCAL_SLOT)
	_port = MatchReplicaPort.new(Match)


func after_each() -> void:
	_port = null
	Match._net_provider = null
	Match.abort_match()
	for child: Node in _blocks_root.get_children():
		child.free()
	Match.set_process(true)
	await get_tree().process_frame
	MatchTestReset.clear_world()


## Queues SPECIAL_ID for slot 0, so a gift feed activates it.
func _claim_special_for_slot_zero() -> void:
	_port.apply_replicated_gift_claimed(7, 0, SPECIAL_ID)


func _feed_cube(seq: int) -> void:
	_port.apply_replicated_feed(0, CUBE_ID, CUBE_ID, seq)


# --- the port itself ---------------------------------------------------------

func test_a_port_over_a_real_match_is_valid() -> void:
	assert_true(_port.is_valid())


func test_a_port_over_nothing_is_invalid() -> void:
	assert_false(MatchReplicaPort.new().is_valid())
	assert_false(MatchReplicaPort.new(null).is_valid())


# --- lifecycle family --------------------------------------------------------

func test_state_change_moves_the_match_state() -> void:
	watch_signals(Events)
	_port.apply_replicated_state_change(Match.State.SUDDEN_DEATH)
	assert_eq(Match.state(), Match.State.SUDDEN_DEATH)
	assert_signal_emitted_with_parameters(Events, "match_state_changed", [Match.State.PLAYING, Match.State.SUDDEN_DEATH])


func test_countdown_sets_the_seconds_left() -> void:
	_port.apply_replicated_state_change(Match.State.COUNTDOWN)
	_port.apply_replicated_countdown(2)
	assert_eq(Match.countdown_remaining(), 2.0)


func test_turn_sets_the_active_slot() -> void:
	_port.apply_replicated_turn(2)
	assert_eq(Match.active_slot(), 2)


func test_elimination_knocks_the_slot_out_and_credits_the_killer() -> void:
	_port.apply_replicated_elimination(1, 2)
	assert_false(Match.slot(1).home_flag_alive)
	assert_true(Match.slot(0).home_flag_alive)
	assert_eq(Match.eliminated_by(1), 2)


func test_elimination_without_a_killer_credits_nobody() -> void:
	_port.apply_replicated_elimination(1)
	assert_false(Match.slot(1).home_flag_alive)
	assert_eq(Match.eliminated_by(1), -1)


func test_mode_state_is_mirrored_and_announced() -> void:
	var wire: Dictionary = {
		"mode_id": MatchConfig.GameMode.ELIMINATION, "scores": [1.0, 1.0, 0.0],
		"extra": {"out_mask": 4}, "round_left": 0.0,
	}
	watch_signals(Events)
	_port.apply_replicated_mode_state(wire)
	assert_false(Match.slot(2).home_flag_alive)
	assert_true(Match.slot(1).home_flag_alive)
	assert_eq(int((Match.mode_state_snapshot()["extra"] as Dictionary)["out_mask"]), 4)
	assert_signal_emitted(Events, "mode_state_changed")


func test_match_timer_sets_the_clock() -> void:
	_port.apply_replicated_match_timer(33.0)
	assert_eq(Match.match_timer_left(), 33.0)


# --- feed family -------------------------------------------------------------

func test_feed_sets_the_held_shape_and_sequence() -> void:
	_port.apply_replicated_feed(0, CUBE_ID, CUBE_ID, 5, 2.5, true)
	assert_eq(Match.held_shape(0).id, CUBE_ID)
	assert_eq(Match.feed_seq(0), 5)
	assert_eq(Match.feed_time_left(0), 2.5)
	assert_true(Match.is_release_locked(0))


func test_feed_for_an_eliminated_slot_is_refused() -> void:
	_port.apply_replicated_elimination(0, -1)
	_port.apply_replicated_feed(0, CUBE_ID, CUBE_ID, 5)
	assert_ne(Match.feed_seq(0), 5)


func test_qol_mirrors_the_backlog_and_pause() -> void:
	_port.apply_replicated_qol(0, 2, true)
	assert_eq(Match.qol_backlog_count(0), 2)
	assert_true(Match.qol_timer_paused(0))
	_port.apply_replicated_qol(0, 0, false)
	assert_eq(Match.qol_backlog_count(0), 0)
	assert_false(Match.qol_timer_paused(0))


func test_next_gift_makes_the_following_feed_a_gift() -> void:
	_claim_special_for_slot_zero()
	_feed_cube(1)
	assert_eq(Match.held_special(0), &"", "no carrier yet, an ordinary block")
	_port.apply_replicated_next_gift(0, CUBE_ID)
	_feed_cube(2)
	assert_eq(Match.held_special(0), SPECIAL_ID)


func test_staged_gift_becomes_the_carrier_one_block_later() -> void:
	_claim_special_for_slot_zero()
	_port.apply_replicated_staged_gift(0, CUBE_ID)
	_feed_cube(1)
	assert_eq(Match.held_special(0), &"", "the staged carrier is promoted by this feed")
	_feed_cube(2)
	assert_eq(Match.held_special(0), SPECIAL_ID)


# --- gift family -------------------------------------------------------------

func test_gift_crate_spawns_falls_and_lands() -> void:
	_port.apply_replicated_gift_spawned(7, Vector2(1.0, 2.0))
	assert_eq(Match.gift_state(7)["position"], Vector2(1.0, 2.0))
	_port.apply_replicated_gift_flight(7, Vector3(0.0, 10.0, 0.0), Vector3(1.0, 0.5, 2.0))
	var falling: Dictionary = Match.gift_state(7)
	assert_eq(falling["origin"], Vector3(0.0, 10.0, 0.0))
	assert_eq(falling["landing"], Vector3(1.0, 0.5, 2.0))
	var landing: Vector3 = Vector3(1.0, 0.75, 2.0)
	_port.apply_replicated_gift_landed(7, landing)
	assert_eq(Match.gift_state(7)["landing"], landing)
	assert_ne(Match.gift_state(7)["phase"], falling["phase"], "landing ends the fall")


func test_gift_expiry_removes_the_crate() -> void:
	_port.apply_replicated_gift_spawned(7, Vector2.ZERO)
	_port.apply_replicated_gift_expired(7)
	assert_true(Match.gift_state(7).is_empty())


func test_gift_claim_removes_the_crate_and_queues_the_special() -> void:
	_port.apply_replicated_gift_spawned(7, Vector2.ZERO)
	_port.apply_replicated_gift_claimed(7, 0, SPECIAL_ID)
	assert_true(Match.gift_state(7).is_empty())
	assert_eq(Match.pending_special_count(0), 1)
	assert_eq(Match.pending_special_count(1), 0)


func test_special_consumed_clears_the_held_special() -> void:
	_claim_special_for_slot_zero()
	_port.apply_replicated_next_gift(0, CUBE_ID)
	_feed_cube(1)
	assert_eq(Match.held_special(0), SPECIAL_ID, "fixture: the special is held")
	_port.apply_replicated_special_consumed(0, SPECIAL_ID)
	assert_eq(Match.held_special(0), &"")


func test_gift_slot_mirrors_the_contents() -> void:
	_port.apply_replicated_gift_slot(0, [SPECIAL_ID], &"", &"")
	assert_eq(Match.gift_slot_contents(0), [SPECIAL_ID] as Array[StringName])
	assert_eq(Match.gift_slot_count(0), 1)
	_port.apply_replicated_gift_slot(0, [], &"", &"")
	assert_eq(Match.gift_slot_count(0), 0)


func test_gift_slot_with_an_activated_gift_queues_it_with_its_carrier() -> void:
	_port.apply_replicated_gift_slot(0, [], SPECIAL_ID, CUBE_ID)
	_feed_cube(1)
	assert_eq(Match.held_special(0), SPECIAL_ID)


func test_glue_charges_answer_whether_the_revision_was_taken() -> void:
	assert_true(_port.apply_replicated_glue_charges(0, 2, 1))
	assert_eq(Match.glue_drops_left(0), 2)
	assert_eq(Match.glue_revision(0), 1)
	assert_false(_port.apply_replicated_glue_charges(0, 5, 1), "a stale revision is refused")
	assert_eq(Match.glue_drops_left(0), 2)


# --- territory family --------------------------------------------------------

func test_territory_keyframe_rewrites_every_cell() -> void:
	var size: int = Match.raster().owner_bytes().size()
	var owners: PackedByteArray = PackedByteArray()
	owners.resize(size)
	owners.fill(2)
	var states: PackedByteArray = PackedByteArray()
	states.resize(size)
	_port.apply_replicated_territory(PackedInt32Array(), owners, states, true)
	var written: PackedByteArray = Match.raster().owner_bytes()
	assert_eq(written[0], 2)
	assert_eq(written[size - 1], 2)


func test_territory_diff_rewrites_only_the_named_cells() -> void:
	var before: PackedByteArray = Match.raster().owner_bytes().duplicate()
	var cell: int = before.size() / 2
	_port.apply_replicated_territory(
		PackedInt32Array([cell]), PackedByteArray([3]), PackedByteArray([0]), false
	)
	var after: PackedByteArray = Match.raster().owner_bytes()
	assert_eq(after[cell], 3)
	assert_eq(after[cell + 1], before[cell + 1])
	assert_eq(after[cell - 1], before[cell - 1])


# --- block owner and cat families ---------------------------------------------

func test_block_owner_converts_a_tracked_block() -> void:
	_registry.set_host_authority(false)
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = BlockFactory.build(shape, load("res://config/physics/physics_tuning.tres"), 1)
	_field.add_child(block)
	Events.block_placed.emit(block, shape.id)
	_registry.bind_net_id(block, 81)
	assert_false(_port.apply_replicated_block_owner(82, 0), "an unknown block is refused")
	assert_true(_port.apply_replicated_block_owner(81, 0))
	assert_eq(block.owner_slot, 0)
	assert_false(_port.apply_replicated_block_owner(81, 0), "no change, nothing to do")


func test_cat_starts_follows_the_host_and_ends() -> void:
	var point: Vector3 = _field.world_from_disk_local(Vector2.ZERO, 1.0)
	assert_true(_port.apply_replicated_cat_start(CAT_ID, 0, point, 5.0))
	var cat: RigidBody3D = Match.active_cat()
	assert_not_null(cat)
	assert_eq(cat.activation_id, CAT_ID)
	var aim: Vector3 = point + Vector3.BACK * 2.0
	_port.apply_replicated_cat_state(CAT_ID, point + Vector3.RIGHT, Vector3.RIGHT * 3.0, aim, 4.0)
	assert_eq(cat.global_position, point + Vector3.RIGHT)
	assert_eq(cat.linear_velocity, Vector3.RIGHT * 3.0)
	assert_eq(cat.target, aim)
	assert_eq(cat.time_left, 4.0)
	_port.end_cat(CAT_ID + 1)
	assert_not_null(Match.active_cat(), "a stale id ends nothing")
	_port.end_cat(CAT_ID)
	assert_null(Match.active_cat())


func test_cat_start_is_refused_for_an_invalid_duration() -> void:
	assert_false(_port.apply_replicated_cat_start(CAT_ID, 0, Vector3.ZERO, 0.0))
	assert_null(Match.active_cat())


# --- the spy ------------------------------------------------------------------

func test_the_spy_is_valid_and_starts_empty() -> void:
	var spy: FakeReplicaPort = FakeReplicaPort.new()
	assert_true(spy.is_valid())
	assert_eq(spy.calls.size(), 0)


func test_the_spy_records_calls_in_order_with_their_arguments() -> void:
	var spy: FakeReplicaPort = FakeReplicaPort.new()
	spy.apply_replicated_turn(2)
	spy.apply_replicated_elimination(1)
	spy.apply_replicated_turn(0)
	assert_eq(spy.calls.size(), 3)
	assert_eq(spy.calls[1], {"method": &"apply_replicated_elimination", "args": [1, -1]})
	assert_eq(spy.calls_to(&"apply_replicated_turn"), [[2], [0]] as Array[Array])
	assert_eq(spy.calls_to(&"end_cat"), [] as Array[Array])


func test_the_spy_answers_booleans_with_false() -> void:
	var spy: FakeReplicaPort = FakeReplicaPort.new()
	assert_false(spy.apply_replicated_glue_charges(0, 1, 1))
	assert_false(spy.apply_replicated_block_owner(1, 0))
	assert_false(spy.apply_replicated_cat_start(1, 0, Vector3.ZERO, 1.0))
	assert_eq(spy.calls.size(), 3)


func test_the_spy_never_reaches_the_real_match() -> void:
	var spy: FakeReplicaPort = FakeReplicaPort.new()
	spy.apply_replicated_state_change(Match.State.END)
	spy.apply_replicated_elimination(0)
	assert_eq(Match.state(), Match.State.PLAYING)
	assert_true(Match.slot(0).home_flag_alive)


func test_the_spy_overrides_every_public_method_of_the_port() -> void:
	var spied: Dictionary = _methods_of(FakeReplicaPort)
	var missing: Array[String] = []
	for method_name: String in _methods_of(MatchReplicaPort).keys():
		if method_name.begins_with("_") or method_name == UNSPIED:
			continue
		if not spied.has(method_name):
			missing.append(method_name)
	assert_eq(missing, [] as Array[String], "port methods the spy does not answer")


func test_the_spy_keeps_the_port_signatures() -> void:
	var spied: Dictionary = _methods_of(FakeReplicaPort)
	var ported: Dictionary = _methods_of(MatchReplicaPort)
	for method_name: String in spied.keys():
		if method_name.begins_with("_") or not ported.has(method_name):
			continue
		var want: Dictionary = ported[method_name]
		var have: Dictionary = spied[method_name]
		assert_eq((have["args"] as Array).size(), (want["args"] as Array).size(), "%s arity" % method_name)
		assert_eq((have["default_args"] as Array).size(), (want["default_args"] as Array).size(), "%s defaults" % method_name)
		assert_eq((have["return"] as Dictionary)["type"], (want["return"] as Dictionary)["type"], "%s return type" % method_name)


func _methods_of(script: Script) -> Dictionary:
	var found: Dictionary = {}
	for info: Dictionary in script.get_script_method_list():
		found[String(info["name"])] = info
	return found
