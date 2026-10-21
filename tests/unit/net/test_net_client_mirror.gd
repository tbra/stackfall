extends GutTest
## net/match/ClientBlockMirror.gd: the client's mirror of the host's block spawns and despawns.
## Asserted through its public calls only: what a caller sees from on_spawned, on_despawned,
## apply_roster and has_spawned.

const NET_ID: int = 7
const SHAPE_ID: StringName = &"L3"


func _payload(shape_id: StringName = SHAPE_ID) -> Dictionary:
	return {
		"shape_id": shape_id,
		"owner_slot": 0,
		"origin": Vector3(1.0, 2.0, 3.0),
		"rotation": Quaternion.IDENTITY,
		"gift_id": &"",
	}


func test_unknown_id_has_not_spawned() -> void:
	var mirror: ClientBlockMirror = ClientBlockMirror.new()
	assert_false(mirror.has_spawned(NET_ID))


func test_a_valid_spawn_is_applied_and_remembered() -> void:
	var mirror: ClientBlockMirror = ClientBlockMirror.new()
	assert_true(mirror.on_spawned(NET_ID, _payload()), "a well-formed spawn is applied")
	assert_true(mirror.has_spawned(NET_ID))
	assert_false(mirror.has_spawned(NET_ID + 1), "only the announced id")


func test_a_duplicate_net_id_is_refused() -> void:
	var mirror: ClientBlockMirror = ClientBlockMirror.new()
	assert_true(mirror.on_spawned(NET_ID, _payload()))
	assert_false(mirror.on_spawned(NET_ID, _payload()), "the second spawn of the same id is refused")
	assert_true(mirror.has_spawned(NET_ID), "the first body stays")


func test_ids_the_wire_cannot_carry_are_refused() -> void:
	var mirror: ClientBlockMirror = ClientBlockMirror.new()
	for bad_id: int in [0, -1, Quantize.NET_ID_MAX + 1]:
		assert_false(mirror.on_spawned(bad_id, _payload()), "id %d is not a wire id" % bad_id)
		assert_false(mirror.has_spawned(bad_id))


func test_the_largest_wire_id_spawns() -> void:
	var mirror: ClientBlockMirror = ClientBlockMirror.new()
	assert_true(mirror.on_spawned(Quantize.NET_ID_MAX, _payload()))
	assert_true(mirror.has_spawned(Quantize.NET_ID_MAX))


func test_a_malformed_payload_is_refused_and_leaves_no_record() -> void:
	var mirror: ClientBlockMirror = ClientBlockMirror.new()
	assert_false(mirror.on_spawned(NET_ID, {}), "an empty payload")
	assert_false(mirror.on_spawned(NET_ID, _payload(&"no_such_shape")), "an unknown shape")
	assert_false(mirror.has_spawned(NET_ID), "a refused spawn must not block a later good one")
	assert_true(mirror.on_spawned(NET_ID, _payload()))


func test_despawn_forgets_the_id_so_it_can_spawn_again() -> void:
	var mirror: ClientBlockMirror = ClientBlockMirror.new()
	mirror.on_spawned(NET_ID, _payload())
	mirror.on_despawned(NET_ID, 0)
	assert_false(mirror.has_spawned(NET_ID))
	assert_true(mirror.on_spawned(NET_ID, _payload()), "a reused id is a fresh spawn")


func test_despawn_of_an_unknown_id_is_harmless() -> void:
	var mirror: ClientBlockMirror = ClientBlockMirror.new()
	mirror.on_spawned(NET_ID, _payload())
	mirror.on_despawned(NET_ID + 5, 0)
	assert_true(mirror.has_spawned(NET_ID), "an unrelated despawn leaves the others alone")


func test_an_empty_roster_is_applied() -> void:
	var mirror: ClientBlockMirror = ClientBlockMirror.new()
	assert_true(mirror.apply_roster([]))


func test_a_malformed_roster_is_refused() -> void:
	var mirror: ClientBlockMirror = ClientBlockMirror.new()
	assert_false(mirror.apply_roster([42, "not an entry"]), "entries that are not dictionaries")
	assert_false(mirror.apply_roster([{}]), "an entry without a net id")


func test_a_roster_reconciles_the_local_blocks() -> void:
	var mirror: ClientBlockMirror = ClientBlockMirror.new()
	mirror.on_spawned(NET_ID, _payload())
	mirror.on_spawned(NET_ID + 1, _payload())
	var entry: Dictionary = _payload()
	entry["net_id"] = NET_ID + 1
	assert_true(mirror.apply_roster([entry]))
	assert_false(mirror.has_spawned(NET_ID), "a block the host no longer lists is dropped")
	assert_true(mirror.has_spawned(NET_ID + 1))
