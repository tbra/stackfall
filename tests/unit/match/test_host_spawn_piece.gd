extends GutTest
## The piece the host spawns for a seat: it carries the shape id the feed drew for that seat and the
## orientation the placement intent gave it (spec 1.4 feed, spec 1.3 rotation). Driven through
## Match.request_place on a started match, observed through Events.block_placed and the spawned body.

const ORIENTATION_BASIS_EPSILON: float = 0.001
## A non-identity index inside the 24-entry table (a pose that is not the reset orientation).
const TURNED_INDEX: int = 7
const OTHER_TURNED_INDEX: int = 13

var _field: Field
var _blocks_root: Node3D
var _registry: BlockRegistry
var _placed: Array[Block] = []
var _issued: Array[Dictionary] = []


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_placed.clear()
	_issued.clear()


func after_each() -> void:
	if Events.block_placed.is_connected(_on_block_placed):
		Events.block_placed.disconnect(_on_block_placed)
	if Events.feed_block_issued.is_connected(_on_feed_issued):
		Events.feed_block_issued.disconnect(_on_feed_issued)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _on_block_placed(block: RigidBody3D, _shape_id: StringName) -> void:
	_placed.append(block as Block)


func _on_feed_issued(slot_id: int, shape_id: StringName, next_shape_id: StringName) -> void:
	_issued.append({"slot": slot_id, "shape": shape_id, "next": next_shape_id})


func _start_match() -> void:
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
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(map)
	config.player_count = 2
	config.rng_seed = 13579
	Events.feed_block_issued.connect(_on_feed_issued)
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)
	Events.block_placed.connect(_on_block_placed)


func _place(slot_id: int, index: int, free_quat: Quaternion = Quaternion.IDENTITY) -> StringName:
	return Match.request_place(slot_id, Match.default_ghost_origin(slot_id), index, free_quat, false)


func _assert_basis_matches(actual: Basis, expected: Basis, label: String) -> void:
	assert_true(
		actual.x.is_equal_approx(expected.x) and actual.y.is_equal_approx(expected.y) and actual.z.is_equal_approx(expected.z),
		"%s: spawned orientation %s must be %s" % [label, actual, expected]
	)


func test_spawned_piece_has_the_shape_id_the_seat_held() -> void:
	_start_match()
	var held: BlockShape = Match.held_shape(0)
	assert_not_null(held, "fixture: seat 0 holds a piece")

	assert_eq(_place(0, 0), PlacementRules.REASON_OK, "fixture: the release at the home spawn is accepted")

	assert_eq(_placed.size(), 1, "one block spawned")
	assert_eq(_placed[0].shape_id, held.id, "the body carries the held shape's id")
	assert_eq(_placed[0].owner_slot, 0, "owned by the releasing seat")


func test_second_seat_spawns_its_own_held_shape_not_the_first_seats() -> void:
	_start_match()
	var held_one: BlockShape = Match.held_shape(1)
	assert_not_null(held_one, "fixture: seat 1 holds a piece")

	assert_eq(_place(1, 0), PlacementRules.REASON_OK, "fixture: seat 1's release is accepted")

	assert_eq(_placed.size(), 1)
	assert_eq(_placed[0].shape_id, held_one.id, "seat 1's body carries seat 1's held shape")
	assert_eq(_placed[0].owner_slot, 1)


func test_next_spawn_is_the_shape_previously_shown_as_next() -> void:
	_start_match()
	var shown_next: BlockShape = Match.next_shape(0)
	assert_not_null(shown_next, "fixture: a next piece is shown")

	_place(0, 0)
	assert_eq(Match.held_shape(0).id, shown_next.id, "the shown next piece becomes the held one")
	var issued_before: int = _issued.size()
	await wait_physics_frames(1)
	# Seat 0 may be release-locked after a drop; the auto-drop path is the host's own forced release.
	var reason: StringName = Match.request_place(0, Match.default_ghost_origin(0), 0, Quaternion.IDENTITY, true)
	assert_eq(reason, PlacementRules.REASON_OK, "fixture: the second release is accepted")

	assert_eq(_placed.size(), 2)
	assert_eq(_placed[1].shape_id, shown_next.id, "the second body carries the shape that was shown as next")
	assert_gte(issued_before, 1, "fixture: the feed announced its draws")


func test_feed_announcement_matches_what_spawns() -> void:
	_start_match()
	var seat_zero_draws: Array[Dictionary] = _issued.filter(func(e: Dictionary) -> bool: return e["slot"] == 0)
	assert_gt(seat_zero_draws.size(), 0, "fixture: the feed announced seat 0's first piece")
	var last: Dictionary = seat_zero_draws[seat_zero_draws.size() - 1]
	assert_eq(Match.held_shape(0).id, last["shape"], "the latest announced draw is the held piece")
	assert_eq(Match.next_shape(0).id, last["next"], "the announced next is the shown next piece")

	_place(0, 0)

	assert_eq(_placed[0].shape_id, last["shape"], "the spawned body is the piece the feed drew")


func test_default_orientation_spawns_upright_and_unturned() -> void:
	_start_match()

	_place(0, 0)

	assert_eq(_placed.size(), 1)
	_assert_basis_matches(_placed[0].global_basis, Basis.IDENTITY, "reset orientation")


func _assert_index_sets_basis(index: int) -> void:
	_start_match()

	assert_eq(_place(0, index), PlacementRules.REASON_OK, "fixture: index %d accepted" % index)

	assert_eq(_placed.size(), 1)
	_assert_basis_matches(_placed[0].global_basis, BlockOrientations.get_basis(index), "index %d" % index)
	assert_ne(BlockOrientations.get_basis(index), Basis.IDENTITY, "fixture: index %d is a real turn" % index)


func test_orientation_index_sets_the_spawned_basis() -> void:
	_assert_index_sets_basis(TURNED_INDEX)


func test_another_orientation_index_sets_the_spawned_basis() -> void:
	_assert_index_sets_basis(OTHER_TURNED_INDEX)


func test_free_rotation_composes_on_top_of_the_index() -> void:
	_start_match()
	var free: Quaternion = Quaternion(Vector3.UP, deg_to_rad(30.0))

	_place(0, TURNED_INDEX, free)

	assert_eq(_placed.size(), 1)
	_assert_basis_matches(
		_placed[0].global_basis, Basis(free) * BlockOrientations.get_basis(TURNED_INDEX), "free yaw over index"
	)


func test_refused_release_spawns_nothing() -> void:
	_start_match()
	var refused: StringName = Match.request_place(0, Match.default_ghost_origin(0), 999, Quaternion.IDENTITY, false)

	assert_ne(refused, PlacementRules.REASON_OK, "an orientation index outside the table is refused")
	assert_eq(_placed.size(), 0, "no body spawns for a refused pose")
	assert_eq(_blocks_root.get_child_count(), 0, "nothing was added to the world")
