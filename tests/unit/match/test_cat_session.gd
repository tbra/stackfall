extends GutTest
## The cat session through the calls the game itself uses (Match.start_cat and the replica port),
## over a host Match and a client Match: start, replace, owner-gated steering, end by id, the
## serial restarting with every match, a client refusing a stale serial, and the order of the
## cat's end relative to later match-state listeners.

const CLIENT_SLOT: int = 1
const PLAYER_COUNT: int = 3
const SPAWN_HEIGHT_M: float = 1.0
const DURATION_S: float = 5.0
const SHIFT_M: float = 2.0
const SPEED_MPS: float = 3.0
const REMAINING_S: float = 4.0
const FAR_M: float = 500.0

var _field: Field
var _registry: BlockRegistry
var _blocks_root: Node3D
var _config: MatchConfig
var _effect: CatEffect
var _log: Array[String] = []
var _started_ids: Array[int] = []
var _ended_ids: Array[int] = []


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	var map: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)
	_config = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	_config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(_config as TinyMapMatchConfig).set_tiny_map(map)
	_config.player_count = PLAYER_COUNT
	_config.gifts_enabled = false
	_effect = CatEffect.new()
	_log.clear()
	_started_ids.clear()
	_ended_ids.clear()
	Events.cat_started.connect(_on_started)
	Events.cat_ended.connect(_on_ended)
	_play()


func after_each() -> void:
	Events.cat_started.disconnect(_on_started)
	Events.cat_ended.disconnect(_on_ended)
	Match._net_provider = null
	Match.abort_match()
	for child: Node in _blocks_root.get_children():
		child.free()
	Match.set_process(true)
	await get_tree().process_frame
	MatchTestReset.clear_world()


func _on_started(id: int, _slot: int, _position: Vector3, _duration: float) -> void:
	_started_ids.append(id)
	_log.append("started %d" % id)


func _on_ended(id: int) -> void:
	_ended_ids.append(id)
	_log.append("ended %d" % id)


## Starts a match and runs the countdown so it is PLAYING.
func _play() -> void:
	Match.start_match(_config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)


func _spot() -> Vector3:
	return _field.world_from_disk_local(Match.slot(0).home_position, SPAWN_HEIGHT_M)


func _as_client() -> void:
	Match._net_provider = FakeNet.client(CLIENT_SLOT)


func _as_host() -> void:
	Match._net_provider = null


# --- host: start, replace, steer, end ----------------------------------------

func test_start_creates_a_cat_with_serial_one_and_announces_it() -> void:
	assert_true(Match.start_cat(0, _spot(), _effect))
	var cat: CatController = Match.active_cat()
	assert_not_null(cat)
	assert_eq(cat.activation_id, 1)
	assert_eq(cat.owner_slot, 0)
	assert_eq(_started_ids, [1] as Array[int])


func test_start_is_refused_for_a_client_an_unknown_slot_and_a_bad_point() -> void:
	_as_client()
	assert_false(Match.start_cat(0, _spot(), _effect), "a client never starts a cat")
	_as_host()
	assert_false(Match.start_cat(PLAYER_COUNT, _spot(), _effect))
	assert_false(Match.start_cat(-1, _spot(), _effect))
	assert_false(Match.start_cat(0, Vector3.INF, _effect))
	assert_false(Match.start_cat(0, _spot(), null))
	assert_false(Match.start_cat(0, Vector3(FAR_M, 0.0, 0.0), _effect), "outside the field")
	assert_null(Match.active_cat())
	assert_eq(_started_ids.size(), 0)


func test_start_is_refused_outside_play() -> void:
	var spot: Vector3 = _spot()
	Match.abort_match()
	assert_false(Match.start_cat(0, spot, _effect))
	assert_null(Match.active_cat())


func test_start_is_refused_when_the_block_cap_is_reached() -> void:
	_effect.max_active_blocks = 1
	_blocks_root.add_child(Node3D.new())
	assert_false(Match.start_cat(0, _spot(), _effect))
	assert_null(Match.active_cat())


func test_a_second_start_replaces_the_first_ending_it_before_the_new_one_starts() -> void:
	Match.start_cat(0, _spot(), _effect)
	var first: CatController = Match.active_cat()
	assert_true(Match.start_cat(2, _spot(), _effect))
	var second: CatController = Match.active_cat()
	assert_ne(second, first)
	assert_eq(second.activation_id, 2)
	assert_eq(second.owner_slot, 2)
	assert_eq(_log, ["started 1", "ended 1", "started 2"] as Array[String])
	await get_tree().process_frame
	assert_false(is_instance_valid(first), "the replaced cat is freed")


func test_set_target_is_owner_only_and_host_only() -> void:
	Match.start_cat(0, _spot(), _effect)
	var cat: CatController = Match.active_cat()
	var aim: Vector3 = cat.global_position + Vector3.RIGHT
	assert_false(Match.set_cat_target(1, aim), "not the owner")
	assert_true(Match.set_cat_target(0, aim))
	assert_eq(cat.target, aim)
	assert_false(Match.set_cat_target(0, Vector3.INF), "a non-finite point is refused")
	_as_client()
	assert_false(Match.set_cat_target(0, aim), "a client cannot steer")


func test_set_target_with_no_cat_is_refused() -> void:
	assert_false(Match.set_cat_target(0, Vector3.ZERO))


func test_end_with_a_wrong_id_is_a_no_op_and_the_right_id_ends_it() -> void:
	Match.start_cat(0, _spot(), _effect)
	Match.end_cat(2)
	assert_not_null(Match.active_cat())
	assert_eq(_ended_ids.size(), 0)
	Match.end_cat(1)
	assert_null(Match.active_cat())
	assert_eq(_ended_ids, [1] as Array[int])
	Match.end_cat(1)
	assert_eq(_ended_ids.size(), 1, "ending twice announces once")


func test_the_cat_ending_by_its_own_timer_clears_the_session() -> void:
	Match.start_cat(0, _spot(), _effect)
	var cat: CatController = Match.active_cat()
	cat.set_physics_process(false)
	cat._physics_process(_effect.duration_s + 0.1)
	assert_null(Match.active_cat())
	assert_eq(_ended_ids, [1] as Array[int])


func test_steering_an_ended_cat_is_refused() -> void:
	Match.start_cat(0, _spot(), _effect)
	Match.end_cat(1)
	assert_false(Match.set_cat_target(0, _spot()))


# --- serial restarts with every match -----------------------------------------

func test_start_match_ends_the_cat_and_the_serial_restarts_at_one() -> void:
	Match.start_cat(0, _spot(), _effect)
	Match.start_cat(0, _spot(), _effect)
	assert_eq(Match.active_cat().activation_id, 2)
	_play()
	assert_null(Match.active_cat())
	assert_eq(_ended_ids.back(), 2)
	assert_true(Match.start_cat(0, _spot(), _effect))
	assert_eq(Match.active_cat().activation_id, 1)


func test_abort_match_ends_the_cat_and_the_serial_restarts_at_one() -> void:
	Match.start_cat(0, _spot(), _effect)
	Match.abort_match()
	assert_null(Match.active_cat())
	assert_eq(_ended_ids, [1] as Array[int])
	_play()
	assert_true(Match.start_cat(0, _spot(), _effect))
	assert_eq(Match.active_cat().activation_id, 1)
	assert_eq(_started_ids, [1, 1] as Array[int])


# --- client: replicated start, state, end -------------------------------------

func test_a_client_accepts_only_a_higher_id_than_the_last() -> void:
	_as_client()
	assert_true(Match.apply_replicated_cat_start(3, 0, _spot(), DURATION_S))
	assert_false(Match.apply_replicated_cat_start(3, 0, _spot(), DURATION_S), "same id")
	assert_false(Match.apply_replicated_cat_start(2, 0, _spot(), DURATION_S), "older id")
	assert_eq(Match.active_cat().activation_id, 3)
	assert_true(Match.apply_replicated_cat_start(4, 1, _spot(), DURATION_S))
	assert_eq(Match.active_cat().activation_id, 4)
	assert_eq(Match.active_cat().owner_slot, 1)
	assert_eq(_started_ids, [3, 4] as Array[int])


func test_a_stale_id_is_still_refused_after_the_cat_ended() -> void:
	_as_client()
	Match.apply_replicated_cat_start(3, 0, _spot(), DURATION_S)
	Match.end_cat(3)
	assert_false(Match.apply_replicated_cat_start(3, 0, _spot(), DURATION_S))
	assert_null(Match.active_cat())


func test_a_client_refuses_a_bad_slot_point_or_duration() -> void:
	_as_client()
	assert_false(Match.apply_replicated_cat_start(1, PLAYER_COUNT, _spot(), DURATION_S))
	assert_false(Match.apply_replicated_cat_start(1, -1, _spot(), DURATION_S))
	assert_false(Match.apply_replicated_cat_start(1, 0, Vector3.INF, DURATION_S))
	assert_false(Match.apply_replicated_cat_start(1, 0, _spot(), 0.0))
	assert_false(Match.apply_replicated_cat_start(1, 0, _spot(), INF))
	assert_null(Match.active_cat())


func test_the_host_ignores_a_replicated_start() -> void:
	assert_false(Match.apply_replicated_cat_start(1, 0, _spot(), DURATION_S))
	assert_null(Match.active_cat())


func test_a_client_accepts_id_one_again_in_the_next_match() -> void:
	_as_client()
	Match.apply_replicated_cat_start(3, 0, _spot(), DURATION_S)
	_as_host()
	_play()
	_as_client()
	assert_null(Match.active_cat())
	assert_false(Match.apply_replicated_cat_start(0, 0, _spot(), DURATION_S))
	assert_true(Match.apply_replicated_cat_start(1, 0, _spot(), DURATION_S), "the serial restarted")
	assert_eq(Match.active_cat().activation_id, 1)


func test_a_client_accepts_a_lower_id_after_an_abort() -> void:
	_as_client()
	Match.apply_replicated_cat_start(5, 0, _spot(), DURATION_S)
	_as_host()
	Match.abort_match()
	_play()
	_as_client()
	assert_true(Match.apply_replicated_cat_start(2, 0, _spot(), DURATION_S))


func test_snapshot_applies_only_for_the_matching_id() -> void:
	_as_client()
	var point: Vector3 = _spot()
	Match.apply_replicated_cat_start(3, 0, point, DURATION_S)
	var cat: CatController = Match.active_cat()
	var aim: Vector3 = point + Vector3.FORWARD
	Match.apply_replicated_cat_state(2, point + Vector3.RIGHT * SHIFT_M, Vector3.ZERO, aim, REMAINING_S)
	assert_eq(cat.global_position, point, "a stale id changes nothing")
	Match.apply_replicated_cat_state(3, point + Vector3.RIGHT * SHIFT_M,
		Vector3.RIGHT * SPEED_MPS, aim, REMAINING_S)
	assert_eq(cat.global_position, point + Vector3.RIGHT * SHIFT_M)
	assert_eq(cat.linear_velocity, Vector3.RIGHT * SPEED_MPS)
	assert_eq(cat.target, aim)
	assert_eq(cat.time_left, REMAINING_S)


func test_snapshot_with_no_cat_or_a_non_finite_remaining_changes_nothing() -> void:
	_as_client()
	Match.apply_replicated_cat_state(1, _spot(), Vector3.ZERO, _spot(), REMAINING_S)
	assert_null(Match.active_cat())
	Match.apply_replicated_cat_start(1, 0, _spot(), DURATION_S)
	var cat: CatController = Match.active_cat()
	var before: float = cat.time_left
	Match.apply_replicated_cat_state(1, _spot(), Vector3.ZERO, _spot(), NAN)
	assert_eq(cat.time_left, before)


func test_the_host_ignores_a_replicated_snapshot() -> void:
	Match.start_cat(0, _spot(), _effect)
	var cat: CatController = Match.active_cat()
	var before: Vector3 = cat.global_position
	Match.apply_replicated_cat_state(1, before + Vector3.RIGHT * SHIFT_M, Vector3.ZERO, before, REMAINING_S)
	assert_eq(cat.global_position, before)


func test_a_replicated_end_with_a_wrong_id_is_a_no_op() -> void:
	_as_client()
	Match.apply_replicated_cat_start(3, 0, _spot(), DURATION_S)
	Match.end_cat(4)
	assert_not_null(Match.active_cat())
	Match.end_cat(3)
	assert_null(Match.active_cat())
	assert_eq(_ended_ids, [3] as Array[int])


# --- match-state reset ----------------------------------------------------------

func test_a_resetting_state_ends_the_cat_on_a_client() -> void:
	_as_client()
	Match.apply_replicated_cat_start(3, 0, _spot(), DURATION_S)
	Match.apply_replicated_state_change(Match.State.END)
	assert_null(Match.active_cat())
	assert_eq(_ended_ids, [3] as Array[int])


func test_a_non_resetting_state_leaves_the_cat() -> void:
	_as_client()
	Match.apply_replicated_cat_start(3, 0, _spot(), DURATION_S)
	Match.apply_replicated_state_change(Match.State.SUDDEN_DEATH)
	assert_not_null(Match.active_cat())
	assert_eq(_ended_ids.size(), 0)


func test_cat_ended_is_emitted_before_a_later_state_listener_sees_the_reset() -> void:
	_as_client()
	Match.apply_replicated_cat_start(3, 0, _spot(), DURATION_S)
	var seen: Array[String] = []
	var listener: Callable = func(_from: int, to: int) -> void:
		if Match.is_resetting(to):
			seen.append("state")
	var ended: Callable = func(_id: int) -> void: seen.append("ended")
	Events.match_state_changed.connect(listener)
	Events.cat_ended.connect(ended)
	Match.apply_replicated_state_change(Match.State.END)
	Events.match_state_changed.disconnect(listener)
	Events.cat_ended.disconnect(ended)
	assert_eq(seen, ["ended", "state"] as Array[String])


func test_a_resetting_state_keeps_the_serial_so_a_stale_id_stays_refused() -> void:
	_as_client()
	Match.apply_replicated_cat_start(3, 0, _spot(), DURATION_S)
	Match.apply_replicated_state_change(Match.State.END)
	assert_false(Match.apply_replicated_cat_start(3, 0, _spot(), DURATION_S))
	assert_true(Match.apply_replicated_cat_start(4, 0, _spot(), DURATION_S))
