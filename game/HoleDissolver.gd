class_name HoleDissolver
extends Node
## Bontago-1pi.11.41 (owner decision Bontago-gdb, option A): holes no longer
## cut the disc's collision. On the host, a block whose footprint rests or
## lands on an applied hole cell (Field.is_hole_cell) dissolves: after
## HoleDissolveTuning.dissolve_delay_s it is removed through
## Field.remove_fallen_block(), the edge-fall path (REASON_KILL_PLANE, same
## stats, same despawn replication). Blocks stacked on it are woken when it
## goes, fall onto the hole and dissolve in turn.
##
## Owned by game/BlockRegistry.gd (one per registry, built in its _ready()),
## which already holds the field, the host-authority flag and the per-tick
## settled loop. Two triggers, both bounded:
## - **A hole opens** (Field.hole_cells_applied): one thin shape query at disc
##   level per newly opened cell finds the bodies touching it. Queries never
##   wake anything, and they see sleeping and stable-frozen (STATIC) bodies
##   alike, so a settled tower's base dissolves without the far side of the
##   disc noticing.
## - **A block moves** (BlockRegistry passes its unsettled or just-moved
##   blocks to physics_tick()): only those are tested, only while the field
##   has any applied hole. That catches a block dropped into a hole, a stack
##   falling onto one and a block sliding onto one.
##
## "Touches" (owner: resting or landing contact, not merely being above it):
## some collision corner of the block, pulled HoleDissolveTuning.contact_inset_m
## toward its shape's centre, lies within contact_height_m of the disc surface
## over an applied hole cell, and the block is not moving away from the disc
## faster than contact_leave_speed. The last clause keeps a Jumping Bean that
## has just punched a hole under itself and kicked off from dissolving in it.
##
## DECISION (game/HoleDissolver.gd): once started, a dissolve always completes
## (unless something else removes the block first, e.g. the kill plane): the
## A2 fade and the clients' copy of the start event then never need a cancel
## message, and a block bouncing off the hole edge mid-fade still goes.

@export var tuning: HoleDissolveTuning = preload("res://config/hole_dissolve_tuning.tres")

class _Footprint:
	## Child count the points were built from (gift visuals swap collision).
	var child_count: int = -1
	## Fingerprint of the collision children's shape resources and local
	## transforms; a swap that keeps the child count still invalidates.
	var signature: int = 0
	## Block-local sample points: every collision corner, inset.
	var points: PackedVector3Array = PackedVector3Array()
	## Largest distance of any point from the block origin.
	var reach: float = 0.0

var _registry: BlockRegistry = null
var _field: Field = null
## instance id -> seconds until removal, for blocks dissolving now.
var _pending: Dictionary = {}
## instance id -> Block, alongside _pending.
var _pending_blocks: Dictionary = {}
## instance id -> _Footprint cache.
var _footprints: Dictionary = {}
var _slab: BoxShape3D = null
var _slab_query: PhysicsShapeQueryParameters3D = null

## Diagnostics / tests: dissolves started and hole-open queries run since the
## last reset().
var dissolves_started: int = 0
var open_queries: int = 0


func _ready() -> void:
	Events.block_removed.connect(_on_block_removed)


func setup(registry: BlockRegistry) -> void:
	_registry = registry


## Points this dissolver at `field` (BlockRegistry.configure()). A null or
## non-Field node disables it.
func set_field(field: Node3D) -> void:
	var typed: Field = field as Field
	if _field == typed:
		return
	if _field != null and is_instance_valid(_field) and _field.hole_cells_applied.is_connected(_on_hole_cells_applied):
		_field.hole_cells_applied.disconnect(_on_hole_cells_applied)
	_field = typed
	_slab = null
	_slab_query = null
	if _field != null:
		_field.hole_cells_applied.connect(_on_hole_cells_applied)


## Drops every pending dissolve and cached footprint (a new match).
func reset() -> void:
	_pending.clear()
	_pending_blocks.clear()
	_footprints.clear()
	dissolves_started = 0
	open_queries = 0


func _is_host() -> bool:
	return _registry != null and _registry.is_host_authority()


func _field_ready() -> bool:
	return _field != null and is_instance_valid(_field) and _field.is_inside_tree()


## True when BlockRegistry should hand over its moving blocks this tick: the
## host, with a field that has at least one applied hole.
func wants_candidates() -> bool:
	return _is_host() and _field_ready() and _field.applied_hole_count() > 0


func is_dissolving(block: Block) -> bool:
	return block != null and _pending.has(block.get_instance_id())


func pending_count() -> int:
	return _pending.size()


## One host tick: contact-tests `candidates` (moving blocks; may be empty),
## then advances every pending dissolve and removes the ones that are due.
func physics_tick(delta: float, candidates: Array[Block]) -> void:
	if not _is_host():
		return
	if not candidates.is_empty() and wants_candidates():
		for block: Block in candidates:
			if touches_hole(block):
				start_dissolve(block)
	if _pending.is_empty():
		return
	var due: Array[Block] = []
	for id: Variant in _pending.keys():
		var block: Block = _pending_blocks.get(id) as Block
		if block == null or not is_instance_valid(block) or block.is_queued_for_deletion():
			_pending.erase(id)
			_pending_blocks.erase(id)
			continue
		var left: float = float(_pending[id]) - delta
		_pending[id] = left
		if left <= 0.0:
			due.append(block)
	for block: Block in due:
		_finish(block)


## Starts `block`'s dissolve (idempotent). Host only.
func start_dissolve(block: Block) -> void:
	if not _is_host() or block == null or not is_instance_valid(block) or block.is_queued_for_deletion():
		return
	var id: int = block.get_instance_id()
	if _pending.has(id):
		return
	_pending[id] = tuning.dissolve_delay_s
	_pending_blocks[id] = block
	dissolves_started += 1
	Events.block_dissolve_started.emit(block, block.net_id, tuning.dissolve_delay_s)
	if tuning.dissolve_delay_s <= 0.0:
		_finish(block)


func _finish(block: Block) -> void:
	var id: int = block.get_instance_id()
	_pending.erase(id)
	_pending_blocks.erase(id)
	_footprints.erase(id)
	if not _field_ready():
		return
	_wake_supported(block)
	_field.remove_fallen_block(block)


func _on_block_removed(block: RigidBody3D, _reason: String) -> void:
	if block == null:
		return
	var id: int = block.get_instance_id()
	_pending.erase(id)
	_pending_blocks.erase(id)
	_footprints.erase(id)


# --- Contact -----------------------------------------------------------------

## Whether `block` rests or lands on an applied hole cell right now (see the
## class doc for the exact rule). Pure reads: never wakes or moves anything.
func touches_hole(block: Block) -> bool:
	if not _field_ready() or block == null or not is_instance_valid(block):
		return false
	if _field.applied_hole_count() == 0:
		return false
	var field_xform: Transform3D = _field.global_transform
	var up: Vector3 = field_xform.basis.y.normalized()
	if block.linear_velocity.dot(up) > tuning.contact_leave_speed:
		return false
	var footprint: _Footprint = _footprint(block)
	if footprint.points.is_empty():
		return false
	var to_disk: Transform3D = field_xform.affine_inverse() * block.global_transform
	var contact_height: float = tuning.contact_height_m
	# Cheap reject: the whole body is clear of the contact band.
	if to_disk.origin.y - footprint.reach > contact_height:
		return false
	var grid: CellGrid = _field.grid()
	for point: Vector3 in footprint.points:
		var local: Vector3 = to_disk * point
		if local.y > contact_height:
			continue
		var coords: Vector2i = grid.world_to_cell(Vector2(local.x, local.z))
		if not grid.in_bounds(coords.x, coords.y):
			continue
		if _field.is_hole_cell(grid.cell_index(coords.x, coords.y)):
			return true
	return false


## Hash of every collision child's shape instance id, local transform and
## disabled flag: changes whenever the shape or collision does, even with an
## unchanged child count.
static func _collision_signature(block: Block) -> int:
	var signature: int = 17
	for child: Node in block.get_children():
		var collision: CollisionShape3D = child as CollisionShape3D
		if collision == null:
			continue
		var shape_id: int = collision.shape.get_instance_id() if collision.shape != null else 0
		signature = hash([signature, child.get_instance_id(), shape_id, collision.transform, collision.disabled])
	return signature


func _footprint(block: Block) -> _Footprint:
	var id: int = block.get_instance_id()
	var child_count: int = block.get_child_count()
	var cached: _Footprint = _footprints.get(id) as _Footprint
	var signature: int = _collision_signature(block)
	if cached != null and cached.child_count == child_count and cached.signature == signature:
		return cached
	var footprint: _Footprint = _Footprint.new()
	footprint.child_count = child_count
	footprint.signature = signature
	var inset: float = tuning.contact_inset_m
	for child: Node in block.get_children():
		var collision: CollisionShape3D = child as CollisionShape3D
		if collision == null or collision.shape == null or collision.disabled:
			continue
		var center: Vector3 = collision.transform.origin
		for corner: Vector3 in _shape_corners(collision.shape):
			var point: Vector3 = collision.transform * corner
			var toward: Vector3 = center - point
			var distance: float = toward.length()
			if distance > 0.0:
				point += toward * (minf(inset, distance) / distance)
			footprint.points.append(point)
			footprint.reach = maxf(footprint.reach, point.length())
	_footprints[id] = footprint
	return footprint


## Shape-local corner points: a box's 8 corners, a convex hull's points, or
## (any other shape) its debug mesh's bounding-box corners.
static func _shape_corners(shape: Shape3D) -> PackedVector3Array:
	var box: BoxShape3D = shape as BoxShape3D
	if box != null:
		return _aabb_corners(AABB(-box.size * 0.5, box.size))
	var convex: ConvexPolygonShape3D = shape as ConvexPolygonShape3D
	if convex != null:
		return convex.points
	var mesh: ArrayMesh = shape.get_debug_mesh()
	if mesh == null:
		return PackedVector3Array()
	return _aabb_corners(mesh.get_aabb())


static func _aabb_corners(aabb: AABB) -> PackedVector3Array:
	var corners: PackedVector3Array = PackedVector3Array()
	for index: int in range(8):
		corners.append(aabb.position + Vector3(
			aabb.size.x * float(index & 1),
			aabb.size.y * float((index >> 1) & 1),
			aabb.size.z * float((index >> 2) & 1)
		))
	return corners


# --- Hole opened ---------------------------------------------------------------

## Field just applied `opened` as holes: test only the bodies touching those
## cells at disc level, found with one shape query per cell (no wake, sleeping
## and frozen bodies included).
func _on_hole_cells_applied(opened: PackedInt32Array) -> void:
	if not _is_host() or not _field_ready() or opened.is_empty():
		return
	var space: PhysicsDirectSpaceState3D = _field.get_world_3d().direct_space_state
	if space == null:
		return
	var query: PhysicsShapeQueryParameters3D = _open_query()
	var grid: CellGrid = _field.grid()
	var basis: Basis = _field.global_transform.basis.orthonormalized()
	var half_height: float = tuning.contact_height_m * 0.5
	var seen: Dictionary = {}
	for cell: int in opened:
		query.transform = Transform3D(basis, _field.world_from_disk_local(grid.index_center(cell), half_height))
		open_queries += 1
		for hit: Dictionary in space.intersect_shape(query, tuning.open_query_max_bodies):
			var block: Block = hit.get("collider") as Block
			if block == null:
				continue
			var id: int = block.get_instance_id()
			if seen.has(id) or _pending.has(id):
				continue
			seen[id] = true
			if not _registry.is_tracked(block):
				continue
			if touches_hole(block):
				start_dissolve(block)


func _open_query() -> PhysicsShapeQueryParameters3D:
	if _slab_query != null:
		return _slab_query
	var cell_size: float = _field.map_def.cell_size
	var side: float = maxf(cell_size - 2.0 * tuning.contact_inset_m, cell_size * 0.5)
	_slab = BoxShape3D.new()
	_slab.size = Vector3(side, tuning.contact_height_m, side)
	_slab_query = PhysicsShapeQueryParameters3D.new()
	_slab_query.shape = _slab
	_slab_query.collide_with_bodies = true
	_slab_query.collide_with_areas = false
	_slab_query.collision_mask = Field.PLACEMENT_QUERY_MASK
	_slab_query.exclude = [_field.get_rid()]
	return _slab_query


# --- Removal -------------------------------------------------------------------

## Wakes (and releases from the stable freeze) every body in the column above
## `block`'s footprint, up to MapDef.cell_wake_height, so a tower standing on
## it falls onto the hole instead of hanging in the air. Jolt would wake an
## ordinary sleeping body that loses its support, but not a stable-frozen
## (STATIC) one, and those are exactly the long-settled towers. One query per
## dissolve, bounded by the block's own footprint; never global.
func _wake_supported(block: Block) -> void:
	if not block.is_inside_tree():
		return
	var space: PhysicsDirectSpaceState3D = block.get_world_3d().direct_space_state
	if space == null:
		return
	var footprint: _Footprint = _footprint(block)
	if footprint.points.is_empty():
		return
	var field_xform: Transform3D = _field.global_transform
	var to_disk: Transform3D = field_xform.affine_inverse() * block.global_transform
	var low: Vector3 = Vector3(INF, INF, INF)
	var high: Vector3 = Vector3(-INF, -INF, -INF)
	for point: Vector3 in footprint.points:
		var local: Vector3 = to_disk * point
		low = low.min(local)
		high = high.max(local)
	var top: float = maxf(_field.map_def.cell_wake_height, high.y)
	var column: BoxShape3D = BoxShape3D.new()
	column.size = Vector3(
		maxf(high.x - low.x, tuning.contact_inset_m), top - low.y, maxf(high.z - low.z, tuning.contact_inset_m)
	)
	var center: Vector3 = Vector3((low.x + high.x) * 0.5, (low.y + top) * 0.5, (low.z + high.z) * 0.5)
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = column
	query.transform = Transform3D(field_xform.basis.orthonormalized(), field_xform * center)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [block.get_rid(), _field.get_rid()]
	for hit: Dictionary in space.intersect_shape(query, _field.map_def.cell_wake_max_bodies):
		var body: RigidBody3D = hit.get("collider") as RigidBody3D
		if body == null:
			continue
		var other: Block = body as Block
		if other != null:
			other.wake_for_impulse()
			other.wake()
		else:
			body.sleeping = false
