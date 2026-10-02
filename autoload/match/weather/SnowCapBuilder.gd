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
## Fraction of the cell pitch within which two patches count as edge-adjacent.
const ADJACENT_TOLERANCE: float = 0.05
## Minimum dot of two patch normals / yaw axes for a cross-block merge.
const CROSS_ALIGN_DOT: float = 0.98


class Patch:
	var xform: Transform3D = Transform3D.IDENTITY
	var edge: float = 1.0
	var seed_value: int = 0
	var level: int = 0
	var built_level: int = -1
	## Levels of same-height snowy tops of OTHER blocks touching each side
	## (SnowGeometry.SIDE_*), visual only. cross_valid: computed for the
	## current level, so a build need not recompute it.
	var cross: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
	var cross_valid: bool = false
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
	## A patch hull changed since the last commit (a mesh-only rebuild from a
	## moved neighbour block must not swap colliders or wake anything).
	var hull_changed: bool = false


var tuning: SnowTuning = null
var with_colliders: bool = false
var patches_built: int = 0
var commits: int = 0

var _owners: Dictionary = {}
var _queue: Array[String] = []
## Blocks held frozen (Variant: one may be freed while held).
var _thaw: Array = []
var _thaw_frames: PackedInt32Array = PackedInt32Array()
## Round-robin list of owner keys for the cross-block neighbour refresh;
## rebuilt only when the owner set changes (no per-frame allocation).
var _refresh_keys: Array[String] = []
var _refresh_dirty: bool = true
var _refresh_cursor: int = 0
var _scratch: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])


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
		_refresh_dirty = true
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
	patch.cross_valid = false
	if not owner.dirty.has(patch_key):
		owner.dirty.append(patch_key)
	if region < 0:
		# Flush neighbours reshape their shared edge with this patch.
		for other_key: Variant in owner.patches.keys():
			var other: Patch = owner.patches[other_key] as Patch
			if other != patch and other.level > 0 and _side_of(patch, other) >= 0 and not owner.dirty.has(other_key):
				owner.dirty.append(int(other_key))
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
	_refresh_dirty = true
	_queue.erase(key)
	_clear_owner(owner)


func clear_all() -> void:
	for key: Variant in _owners.keys():
		_clear_owner(_owners[key] as CapOwner)
	_owners.clear()
	_refresh_dirty = true
	_queue.clear()
	_release_all_thaws()


func is_idle() -> bool:
	return _queue.is_empty()


## Builds up to `budget` domes; commits every owner that became complete.
func step(budget: int) -> void:
	_advance_thaws()
	_refresh_cross(tuning.cross_merge_checks_per_frame)
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
			_build_patch(owner.patches[patch_key] as Patch, owner)
			left -= 1
		if owner.dirty.is_empty():
			_queue.pop_front()
			owner.queued = false
			_commit(owner)


func _build_patch(patch: Patch, owner: CapOwner) -> void:
	patch.built_level = patch.level
	var old_hull: PackedVector3Array = patch.hull
	patch.hull = PackedVector3Array()
	patch.vertices = PackedVector3Array()
	patch.normals = PackedVector3Array()
	if patch.level <= 0:
		owner.hull_changed = owner.hull_changed or not old_hull.is_empty()
		return
	var params: PackedFloat32Array = SnowGeometry.dome_params(patch.seed_value, tuning)
	var points: PackedVector3Array
	if owner.region >= 0:
		points = SnowGeometry.dome_points(params, patch.edge, patch.level, tuning, tuning.disc_cap_squareness)
		patch.hull = patch.xform * points
	else:
		# DECISION (Bontago-mp0.31): a per-patch geometry (not a world-space
		# shader term) so the host collider is the same convex hull of the
		# same points the client draws; the patch treats its top face and
		# snowy neighbour cells as one plateau with rounded rims only.
		var levels: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
		for other_key: Variant in owner.patches.keys():
			var other: Patch = owner.patches[other_key] as Patch
			if other != patch and other.level > 0:
				var side: int = _side_of(patch, other)
				if side >= 0:
					levels[side] = other.level
		var pitch: float = patch.edge / maxf(tuning.block_patch_fill, SnowGeometry.EPS)
		if not patch.cross_valid:
			_compute_cross(owner, patch)
		var cross_any: bool = patch.cross[0] > 0 or patch.cross[1] > 0 or patch.cross[2] > 0 or patch.cross[3] > 0
		# DECISION (Bontago-mp0.32): touching same-height tops of DIFFERENT
		# blocks merge in the drawn mesh only (no rim at the shared edge). The
		# collider hull is built from this block's own cells alone: blocks move
		# independently, so a hull that followed a neighbour would swap (and
		# wake bodies) whenever that neighbour shifted, and clients have no
		# hulls to agree on anyway. The hull keeps its small rim shoulder at
		# such an edge; the mesh stays within one rim width of it there.
		if with_colliders:
			var hull_points: PackedVector3Array = SnowGeometry.cap_points(params, patch.edge, pitch, patch.level, levels, tuning)
			patch.hull = patch.xform * hull_points
			points = SnowGeometry.cap_points(params, patch.edge, pitch, patch.level, levels, tuning, patch.cross) if cross_any else hull_points
		else:
			points = SnowGeometry.cap_points(params, patch.edge, pitch, patch.level, levels, tuning, patch.cross)
	if patch.hull != old_hull:
		owner.hull_changed = true
	SnowGeometry.append_dome_triangles(points, tuning, patch.xform, patch.vertices, patch.normals)
	patches_built += 1


## Fills patch.cross with the levels of touching same-height tops of other
## blocks (see the DECISION in _build_patch); returns true when it changed.
## Matches in the patch's own frame: coplanar within cross_merge_height_tol_m,
## yaw-aligned to a quarter turn, across a gap within cross_merge_gap_m and
## overlapping laterally by cross_merge_overlap of a cell.
func _compute_cross(owner: CapOwner, patch: Patch) -> bool:
	patch.cross_valid = true
	_scratch[0] = 0
	_scratch[1] = 0
	_scratch[2] = 0
	_scratch[3] = 0
	if tuning.cross_merge_enabled and patch.level > 0 and owner.region < 0 and is_instance_valid(owner.node) and owner.node.is_inside_tree():
		var a: Transform3D = owner.node.global_transform * patch.xform
		var pitch: float = patch.edge / maxf(tuning.block_patch_fill, SnowGeometry.EPS)
		var reach: float = pitch * (1.0 + tuning.cross_merge_overlap) + tuning.cross_merge_gap_m
		for key: Variant in _owners:
			var other_owner: CapOwner = _owners[key] as CapOwner
			if other_owner == owner or other_owner.region >= 0 or not is_instance_valid(other_owner.node) or not other_owner.node.is_inside_tree():
				continue
			var other_xform: Transform3D = other_owner.node.global_transform
			for patch_key: Variant in other_owner.patches:
				var other: Patch = other_owner.patches[patch_key] as Patch
				if other.level <= 0:
					continue
				var delta: Vector3 = other_xform * other.xform.origin - a.origin
				if absf(delta.dot(a.basis.y)) > tuning.cross_merge_height_tol_m or delta.length_squared() > reach * reach:
					continue
				var b: Basis = other_xform.basis * other.xform.basis
				if a.basis.y.dot(b.y) < CROSS_ALIGN_DOT:
					continue
				if maxf(absf(a.basis.x.dot(b.x)), absf(a.basis.x.dot(b.z))) < CROSS_ALIGN_DOT:
					continue
				var side: int = _cross_side(delta.dot(a.basis.x), delta.dot(a.basis.z), pitch)
				if side >= 0:
					_scratch[side] = maxi(_scratch[side], other.level)
	var changed: bool = false
	for side: int in range(SnowGeometry.SIDE_COUNT):
		if patch.cross[side] != _scratch[side]:
			patch.cross[side] = _scratch[side]
			changed = true
	return changed


func _cross_side(along_x: float, along_z: float, pitch: float) -> int:
	var overlap: float = pitch * tuning.cross_merge_overlap
	var gap: float = tuning.cross_merge_gap_m
	if absf(along_z) <= overlap and absf(absf(along_x) - pitch) <= gap:
		return SnowGeometry.SIDE_PX if along_x > 0.0 else SnowGeometry.SIDE_NX
	if absf(along_x) <= overlap and absf(absf(along_z) - pitch) <= gap:
		return SnowGeometry.SIDE_PZ if along_z > 0.0 else SnowGeometry.SIDE_NZ
	return -1


## Re-examines the cross-block neighbours of up to `count` block owners per
## call (round robin) and queues a mesh-only rebuild where they changed, so a
## seam opens again when a neighbour moves away.
func _refresh_cross(count: int) -> void:
	if not tuning.cross_merge_enabled:
		return
	if _refresh_dirty:
		_refresh_dirty = false
		_refresh_keys.clear()
		for key: Variant in _owners:
			_refresh_keys.append(str(key))
	if _refresh_keys.is_empty():
		return
	for _i: int in range(mini(count, _refresh_keys.size())):
		_refresh_cursor = (_refresh_cursor + 1) % _refresh_keys.size()
		var owner: CapOwner = _owners.get(_refresh_keys[_refresh_cursor]) as CapOwner
		if owner == null or owner.region >= 0 or owner.queued:
			continue
		for patch_key: Variant in owner.patches:
			var patch: Patch = owner.patches[patch_key] as Patch
			if patch.level > 0 and _compute_cross(owner, patch):
				owner.dirty.append(int(patch_key))
		if not owner.dirty.is_empty():
			owner.queued = true
			_queue.append(owner.key)


## Side (SnowGeometry.SIDE_*) of `patch` on which `other` is the edge-adjacent
## coplanar cell patch, or -1.
func _side_of(patch: Patch, other: Patch) -> int:
	var pitch: float = patch.edge / maxf(tuning.block_patch_fill, SnowGeometry.EPS)
	var tol: float = pitch * ADJACENT_TOLERANCE
	var delta: Vector3 = other.xform.origin - patch.xform.origin
	var along_x: float = delta.dot(patch.xform.basis.x)
	var along_z: float = delta.dot(patch.xform.basis.z)
	if absf(delta.dot(patch.xform.basis.y)) > tol:
		return -1
	if absf(along_z) <= tol:
		if absf(along_x - pitch) <= tol:
			return SnowGeometry.SIDE_PX
		if absf(along_x + pitch) <= tol:
			return SnowGeometry.SIDE_NX
	if absf(along_x) <= tol:
		if absf(along_z - pitch) <= tol:
			return SnowGeometry.SIDE_PZ
		if absf(along_z + pitch) <= tol:
			return SnowGeometry.SIDE_NZ
	return -1


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
			if owner.hull_changed:
				_hold_frozen(owner.node as Block)
				SnowCaps.apply_colliders(owner.node, hulls, tuning.collider_margin_m)
		else:
			var body: StaticBody3D = SnowCaps.disc_region_body(owner.node, owner.region, not hulls.is_empty())
			if body != null:
				SnowCaps.apply_colliders(body, hulls, tuning.collider_margin_m)
				if hulls.is_empty():
					SnowCaps.remove_node(owner.node, body.name)
	owner.hull_changed = false
	commits += 1
	if owner.patches.is_empty():
		_owners.erase(owner.key)
		_refresh_dirty = true


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
