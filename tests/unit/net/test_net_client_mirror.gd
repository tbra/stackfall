extends GutTest
## net/match/ClientBlockMirror.gd: the client's mirror of the host's block spawns, despawns and
## seat roster. Asserted through its public calls and what they do to the world it was given
## (registry, blocks parent, slots, Events).

const NET_ID: int = 7
const SHAPE_ID: StringName = &"L3"
const LOCAL_SLOT: int = 1
const ORIGIN: Vector3 = Vector3(1.0, 2.0, 3.0)

var _registry: BlockRegistry
var _parent: Node3D
var _fake: FakeMatch
var _mirror: ClientBlockMirror
var _removed: Array[String] = []


func before_each() -> void:
	_registry = autofree(BlockRegistry.new())
	_registry.set_host_authority(false)
	add_child(_registry)
	_parent = autofree(Node3D.new())
	add_child(_parent)
	_fake = FakeMatch.new()
	_fake.block_registry = _registry
	_fake.blocks_root = _parent
	for slot_id: int in 2:
		var slot: PlayerSlot = PlayerSlot.new()
		slot.slot_id = slot_id
		slot.color = Color.RED if slot_id == 0 else Color.BLUE
		_fake.slots_by_id[slot_id] = slot
	var session: SessionPort = SessionPort.new(FakeNet.client(LOCAL_SLOT), PackedStringArray(["is_local_slot"]))
	var host: MatchHostPort = MatchHostPort.new(_fake, PackedStringArray(["slot", "registry", "blocks_parent"]))
	var gift_ok: Callable = func(_gift_id: String) -> bool: return false
	_mirror = ClientBlockMirror.new(session, host, gift_ok, preload("res://config/physics/physics_tuning.tres"))
	_removed.clear()


func _spawn(net_id: int = NET_ID, shape_id: StringName = SHAPE_ID) -> bool:
	return _mirror.on_spawned(net_id, shape_id, 0, ORIGIN, Quaternion.IDENTITY, &"")


func test_unknown_id_has_not_spawned() -> void:
	assert_false(_mirror.has_spawned(NET_ID))


func test_a_valid_spawn_builds_a_frozen_body_at_the_host_pose() -> void:
	assert_true(_spawn())
	assert_true(_mirror.has_spawned(NET_ID))
	assert_false(_mirror.has_spawned(NET_ID + 1))
	var block: Block = _registry.block_for_net_id(NET_ID)
	assert_not_null(block, "the body is addressable by the host's id")
	assert_true(block.freeze, "clients never simulate a replica")
	assert_eq(block.get_parent(), _parent)
	assert_almost_eq(block.global_position, ORIGIN, Vector3.ONE * 0.001)


func test_a_duplicate_net_id_is_refused_and_builds_nothing() -> void:
	assert_true(_spawn())
	var count: int = _parent.get_child_count()
	assert_false(_spawn(), "the second spawn of the same id is refused")
	assert_eq(_parent.get_child_count(), count)
	assert_true(_mirror.has_spawned(NET_ID))


func test_ids_the_wire_cannot_carry_are_refused() -> void:
	for bad_id: int in [0, -1, Quantize.NET_ID_MAX + 1]:
		assert_false(_spawn(bad_id), "id %d is not a wire id" % bad_id)
		assert_false(_mirror.has_spawned(bad_id))
	assert_eq(_parent.get_child_count(), 0)


func test_the_largest_wire_id_spawns() -> void:
	assert_true(_spawn(Quantize.NET_ID_MAX))
	assert_true(_mirror.has_spawned(Quantize.NET_ID_MAX))


func test_an_unknown_shape_is_refused_and_does_not_block_a_later_good_spawn() -> void:
	assert_false(_spawn(NET_ID, &"no_such_shape"))
	assert_false(_mirror.has_spawned(NET_ID))
	assert_true(_spawn())


func test_the_body_takes_its_owner_slot_colour_or_white_for_an_unknown_slot() -> void:
	assert_true(_mirror.on_spawned(NET_ID, SHAPE_ID, 99, ORIGIN, Quaternion.IDENTITY, &""))
	assert_true(_mirror.on_spawned(NET_ID + 1, SHAPE_ID, 1, ORIGIN, Quaternion.IDENTITY, &""))
	assert_eq(_registry.block_for_net_id(NET_ID).owner_slot, 99, "an unknown owner does not stop the spawn")
	assert_eq(_registry.block_for_net_id(NET_ID + 1).owner_slot, 1)


func test_without_a_world_nothing_spawns() -> void:
	_fake.blocks_root = null
	assert_false(_spawn())
	assert_false(_mirror.has_spawned(NET_ID))


func test_a_spawn_emits_block_replicated_with_the_host_id() -> void:
	watch_signals(Events)
	assert_true(_spawn())
	assert_signal_emitted(Events, "block_replicated")


func test_despawn_removes_the_body_forgets_the_id_and_allows_reuse() -> void:
	_spawn()
	var block: Block = _registry.block_for_net_id(NET_ID)
	Events.block_removed.connect(_on_removed)
	_mirror.on_despawned(NET_ID, "kill_plane")
	Events.block_removed.disconnect(_on_removed)
	assert_eq(_removed, ["kill_plane"], "the host's reason reaches Events.block_removed")
	assert_true(block.is_queued_for_deletion())
	assert_false(_mirror.has_spawned(NET_ID))
	assert_true(_spawn(), "a reused id is a fresh spawn")


func test_a_new_match_accepts_the_ids_the_previous_match_used_and_never_despawned() -> void:
	assert_true(_spawn(), "match 1 spawns a net id")
	# Match start: the world is cleared with no despawn RPC and the registry restarts its ids.
	for child: Node in _parent.get_children():
		child.free()
	_registry.reset()
	assert_false(_mirror.has_spawned(NET_ID), "the cleared world holds nothing")
	assert_true(_spawn(), "match 2 may reuse that id")
	assert_not_null(_registry.block_for_net_id(NET_ID))


func _on_removed(_block: Block, reason: String) -> void:
	_removed.append(reason)


func test_despawn_of_an_unknown_id_is_harmless() -> void:
	_spawn()
	_mirror.on_despawned(NET_ID + 5, "x")
	assert_true(_mirror.has_spawned(NET_ID))
	assert_eq(_removed.size(), 0)


func test_an_empty_roster_is_applied() -> void:
	assert_true(_mirror.apply_roster([]))


func test_a_roster_writes_peer_name_and_local_flag_onto_the_slots() -> void:
	var roster: Array = [
		{LobbySeats.FIELD_SLOT_ID: 0, LobbySeats.FIELD_PEER_ID: 5, LobbySeats.FIELD_NAME: "Ann"},
		{LobbySeats.FIELD_SLOT_ID: LOCAL_SLOT, LobbySeats.FIELD_PEER_ID: 9, LobbySeats.FIELD_NAME: "Me"},
	]
	assert_true(_mirror.apply_roster(roster))
	var other: PlayerSlot = _fake.slots_by_id[0]
	var mine: PlayerSlot = _fake.slots_by_id[LOCAL_SLOT]
	assert_eq(other.peer_id, 5)
	assert_eq(other.display_name, "Ann")
	assert_false(other.is_local)
	assert_eq(mine.peer_id, 9)
	assert_true(mine.is_local)


func test_a_malformed_roster_entry_is_skipped_and_reported() -> void:
	var roster: Array = [42, {}, {LobbySeats.FIELD_SLOT_ID: 77}, {LobbySeats.FIELD_SLOT_ID: 0, LobbySeats.FIELD_PEER_ID: 5}]
	assert_false(_mirror.apply_roster(roster), "something was skipped")
	assert_eq((_fake.slots_by_id[0] as PlayerSlot).peer_id, 5, "the good entry still lands")
