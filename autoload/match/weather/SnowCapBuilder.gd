class_name SnowCapBuilder
extends RefCounted
## Amortised snow geometry (Bontago-22y.6). Callers set patch levels (cheap);
## step() computes at most `budget` dome meshes/hulls per frame, and once
## every changed patch of an owner (a block, or a disc region) is ready it
## commits that owner in one go: its mesh and its colliders swap together,
## so a block never shows half-updated snow or a collider without its mesh.
## The host uses it with colliders, clients without, with the same geometry.
##
## Host only (with colliders): a block that is asleep and not already frozen
## is held with its own freeze reason for THAW_FRAMES around the collider
## swap and put back to sleep after. Jolt wakes a body whose shape changes,
## and an awake body wakes the resting pile it touches (a probe woke a 6-box
## island from one shape change); a frozen static body wakes nothing.

const FREEZE_REASON: StringName = &"snow_rebuild"
## Physics steps a block stays frozen around its collider swap: the engine
## rebuilds the shape inside the next step, so the hold is exactly that one
## step and is released at the start of the following tick.
const THAW_FRAMES: int = 1


class Patch:
	var xform: Transform3D = Transform3D.IDENTITY
	var edge: float = 1.0
	var seed_value: int = 0
	var level: int = 0
	var built_level: int = -1
	var hull: PackedVector3Array = PackedVector3Array()
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()


class CapOwner:
	var key: String = ""
	var node: Node3D = null
	## -1 for a block; the disc region id otherwise.
	var region: int = -1
	var patches: Dictionary = {}
	var dirty: Array[int] = []
	var queued: bool = false


var tuning: SnowTuning = null
var with_colliders: bool = false
var patches_built: int = 0
var commits: int = 0

var _owners: Dictionary = {}
var _queue: Array[String] = []
## Blocks held frozen (Variant: one may be freed while held).
var _thaw: Array = []
var _thaw_frames: PackedInt32Array = PackedInt32Array()


func _init(snow_tuning: SnowTuning, colliders: bool) -> void:
	tuning = snow_tuning
	with_colliders = colliders


## Records `patch_key`'s level on owner `key`; the rebuild happens in step().
func set_patch(key: String, node: Node3D, region: int, patch_key: int, xform: Transform3D, edge: float, seed_value: int, level: int) -> void:
	var owner: CapOwner = _owners.get(key) as CapOwner
	if owner == null:
		if level <= 0:
			return
		owner = CapOwner.new()
		owner.key = key
		owner.node = node
		owner.region = region
		_owners[key] = owner
	var patch: Patch = owner.patches.get(patch_key) as Patch
	if patch == null:
		if level <= 0:
			return
		patch = Patch.new()
		owner.patches[patch_key] = patch
	patch.xform = xform
	patch.edge = edge
	patch.seed_value = seed_value
	if patch.level == level and patch.built_level == level:
		return
	patch.level = level
	if not owner.dirty.has(patch_key):
		owner.dirty.append(patch_key)
	if not owner.queued:
		owner.queued = true
		_queue.append(key)


func has_owner(key: String) -> bool:
	return _owners.has(key)


func owner_level(key: String, patch_key: int) -> int:
	var owner: CapOwner = _owners.get(key) as CapOwner
	if owner == null:
		return 0
	var patch: Patch = owner.patches.get(patch_key) as Patch
	return patch.level if patch != null else 0


## Removes an owner's snow at once (a despawned or tipped block).
func drop_owner(key: String) -> void:
	var owner: CapOwner = _owners.get(key) as CapOwner
	if owner == null:
		return
	_owners.erase(key)
	_queue.erase(key)
	_clear_owner(owner)


func clear_all() -> void:
	for key: Variant in _owners.keys():
		_clear_owner(_owners[key] as CapOwner)
	_owners.clear()
	_queue.clear()
	_release_all_thaws()


func is_idle() -> bool:
	return _queue.is_empty()


## Builds up to `budget` domes; commits every owner that became complete.
func step(budget: int) -> void:
	_advance_thaws()
	var left: int = maxi(budget, 1)
	while left > 0 and not _queue.is_empty():
		var owner: CapOwner = _owners.get(_queue[0]) as CapOwner
		if owner == null or not is_instance_valid(owner.node):
			if owner != null:
				_owners.erase(owner.key)
			_queue.pop_front()
			continue
		while left > 0 and not owner.dirty.is_empty():
			var patch_key: int = owner.dirty.pop_back()
			_build_patch(owner.patches[patch_key] as Patch, owner.region >= 0)
			left -= 1
		if owner.dirty.is_empty():
			_queue.pop_front()
			owner.queued = false
			_commit(owner)


func _build_patch(patch: Patch, disc: bool) -> void:
	patch.built_level = patch.level
	patch.hull = PackedVector3Array()
	patch.vertices = PackedVector3Array()
	patch.normals = PackedVector3Array()
	if patch.level <= 0:
		return
	var params: PackedFloat32Array = SnowGeometry.dome_params(patch.seed_value, tuning)
	var squareness: float = tuning.disc_cap_squareness if disc else 0.0
	var points: PackedVector3Array = SnowGeometry.dome_points(params, patch.edge, patch.level, tuning, squareness)
	patch.hull = patch.xform * points
	SnowGeometry.append_dome_triangles(points, tuning, patch.xform, patch.vertices, patch.normals)
	patches_built += 1


func _commit(owner: CapOwner) -> void:
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var hulls: Array[PackedVector3Array] = []
	var keys: Array = owner.patches.keys()
	keys.sort()
	for key: Variant in keys:
		var patch: Patch = owner.patches[key]
		if patch.level <= 0:
			owner.patches.erase(key)
			continue
		vertices.append_array(patch.vertices)
		normals.append_array(patch.normals)
		hulls.append(patch.hull)
	var cap_name: StringName = SnowCaps.CAP_NAME if owner.region < 0 else SnowCaps.disc_cap_name(owner.region)
	SnowCaps.apply_mesh(owner.node, cap_name, vertices, normals, tuning, owner.region >= 0)
	if with_colliders:
		if owner.region < 0:
			_hold_frozen(owner.node as Block)
			SnowCaps.apply_colliders(owner.node, hulls, tuning.collider_margin_m)
		else:
			var body: StaticBody3D = SnowCaps.disc_region_body(owner.node, owner.region, not hulls.is_empty())
			if body != null:
				SnowCaps.apply_colliders(body, hulls, tuning.collider_margin_m)
				if hulls.is_empty():
					SnowCaps.remove_node(owner.node, body.name)
	commits += 1
	if owner.patches.is_empty():
		_owners.erase(owner.key)


func _clear_owner(owner: CapOwner) -> void:
	if not is_instance_valid(owner.node):
		return
	if owner.region < 0:
		SnowCaps.remove_node(owner.node, SnowCaps.CAP_NAME)
		if with_colliders:
			_hold_frozen(owner.node as Block)
			var empty: Array[PackedVector3Array] = []
			SnowCaps.apply_colliders(owner.node, empty)
	else:
		SnowCaps.remove_node(owner.node, SnowCaps.disc_cap_name(owner.region))
		SnowCaps.remove_node(owner.node, SnowCaps.disc_body_name(owner.region))


# --- Freeze around a collider swap -------------------------------------------------------

func _hold_frozen(block: Block) -> void:
	if block == null or not tuning.freeze_during_rebuild or not is_instance_valid(block):
		return
	if block.freeze or not block.sleeping or not block.is_inside_tree():
		return
	block.request_freeze_static(FREEZE_REASON)
	_thaw.append(block)
	_thaw_frames.append(THAW_FRAMES)


func _advance_thaws() -> void:
	var index: int = 0
	while index < _thaw.size():
		_thaw_frames[index] -= 1
		if _thaw_frames[index] > 0:
			index += 1
			continue
		_release(_thaw[index])
		_thaw.remove_at(index)
		_thaw_frames.remove_at(index)


func _release_all_thaws() -> void:
	for held: Variant in _thaw:
		_release(held)
	_thaw.clear()
	_thaw_frames.clear()


static func _release(held: Variant) -> void:
	if not is_instance_valid(held):
		return
	var block: Block = held as Block
	if block == null:
		return
	block.release_freeze_static(FREEZE_REASON)
	if not block.freeze:
		block.sleeping = true


func pending_thaws() -> int:
	return _thaw.size()
