class_name ClientBlockMirror
extends RefCounted
## Client-side mirror of the host's blocks and seat roster: builds a frozen body for a host spawn,
## frees it on a host despawn and writes the roster's peer/name/local flags onto the slots. It owns
## the set of net ids spawned here. Every argument is wire data and is checked before use.

## `gift_id_ok` is a Callable(gift_id: String) -> bool: true when the id names a real roster gift.
var _session: SessionPort = null
var _host: MatchHostPort = null
var _gift_id_ok: Callable = Callable()
var _physics_tuning: PhysicsTuning = null
var _shapes_by_id: Dictionary = {}
var _spawned_net_ids: Dictionary = {}


func _init(session: SessionPort, host: MatchHostPort, gift_id_ok: Callable, physics_tuning: PhysicsTuning) -> void:
	_session = session
	_host = host
	_gift_id_ok = gift_id_ok
	_physics_tuning = physics_tuning


## Builds the frozen replica of a host spawn. Returns true when the body was added; false for an
## unaddressable id, a missing world, a duplicate or an unknown shape.
func on_spawned(net_id: int, shape_id: StringName, owner_slot: int, origin: Vector3, rotation: Quaternion, gift_id: StringName) -> bool:
	if not Quantize.is_wire_id(net_id):
		return false
	var registry: Node = _host.registry()
	var parent: Node3D = _host.blocks_parent()
	if registry == null or parent == null or has_spawned(net_id) or registry.block_for_net_id(net_id) != null:
		return false
	var shape: BlockShape = _shape_for_id(shape_id)
	if shape == null:
		return false
	var owner_slot_ref: PlayerSlot = _host.slot(owner_slot)
	var color: Color = owner_slot_ref.color if owner_slot_ref != null else Color.WHITE
	var factory: GDScript = LateScripts.script(LateScripts.BLOCK_FACTORY)
	var block: BlockBody = factory.call(&"build", shape, _physics_tuning, owner_slot, color) as BlockBody
	# Kinematic freeze before the body enters the tree: it never simulates a step here.
	block.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	block.freeze = true
	parent.add_child(block)
	block.global_transform = Transform3D(Basis(rotation), origin)
	if gift_id != &"" and _gift_id_ok.call(String(gift_id)):
		factory.call(&"apply_gift_visual", block, shape, _physics_tuning, gift_id)
	# block_placed is what BlockRegistry tracks bodies on; with host authority off it allocates no
	# id, so the host's is bound straight after and both ends address the same body.
	Events.block_placed.emit(block, shape.id)
	registry.bind_net_id(block, net_id)
	_spawned_net_ids[net_id] = true
	Events.block_replicated.emit(block, net_id)
	return true


## Frees the replica of a host despawn; `reason` is the host's Events.block_removed reason.
func on_despawned(net_id: int, reason: String) -> void:
	_spawned_net_ids.erase(net_id)
	var registry: Node = _host.registry()
	if registry == null:
		return
	var block: BlockBody = registry.block_for_net_id(net_id)
	if block == null or not is_instance_valid(block):
		return
	Events.block_removed.emit(block, reason)
	block.queue_free()


## Writes the seat roster (one LobbySeats-field dictionary per seat) onto the slots. Returns false
## when an entry was skipped (malformed or an unknown slot), true when all were applied.
func apply_roster(roster: Array) -> bool:
	var all_applied: bool = true
	for entry: Variant in roster:
		if not (entry is Dictionary) or not (entry as Dictionary).has(LobbySeats.FIELD_SLOT_ID):
			all_applied = false
			continue
		var info: Dictionary = entry
		var target: PlayerSlot = _host.slot(int(info[LobbySeats.FIELD_SLOT_ID]))
		if target == null:
			all_applied = false
			continue
		target.peer_id = int(info.get(LobbySeats.FIELD_PEER_ID, 0))
		target.display_name = String(info.get(LobbySeats.FIELD_NAME, target.display_name))
		target.is_local = bool(_session.is_local_slot(target.slot_id))
	return all_applied


## True when this mirror spawned `net_id` and no despawn for it has arrived since.
func has_spawned(net_id: int) -> bool:
	return _spawned_net_ids.has(net_id)


func _shape_for_id(shape_id: StringName) -> BlockShape:
	if _shapes_by_id.is_empty():
		for shape: BlockShape in BlockShape.load_all_shapes():
			_shapes_by_id[shape.id] = shape
	return _shapes_by_id.get(shape_id) as BlockShape
