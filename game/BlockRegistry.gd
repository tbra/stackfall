class_name BlockRegistry
extends Node
## Tracks every live Block, whether it has settled, and the net_id <-> Block
## mapping the territory solve and (from M3) snapshot sync both need.
##
## Listens to Events.block_placed / Events.block_removed instead of walking
## the scene tree (CLAUDE.md's global signal bus), and runs the settled rule
## every physics frame: spec 2.2, "A block counts as settled when its linear
## speed is below sleep_linear_threshold and its angular speed below
## sleep_angular_threshold for sleep_settle_time. One frame above either
## threshold resets the accumulator to zero" — not a decay, so a falling
## block never flashes influence on the way down (docs/M2_PLAN.md).
##
## Lives in game/, not core/, because it watches live RigidBody3D nodes;
## everything it hands back to Match (InfluenceCircle, floats, RigidBody3D
## references) is plain data, so Match and core/ stay decoupled from how it
## tracks them.

class _Entry:
	var block: Block
	var owner_slot: int = -1
	var settled_time: float = 0.0
	var is_settled: bool = false
	## Transform last reported to the territory dirty state (settled only).
	var marked_transform: Transform3D = Transform3D.IDENTITY
	## Bontago-1pi.11.22: cached pure geometry, keyed on exact inputs.
	var geom_valid: bool = false
	var geom_block_xform: Transform3D = Transform3D.IDENTITY
	var geom_field_xform: Transform3D = Transform3D.IDENTITY
	var geom_child_count: int = -1
	var geom_com_xz: Vector2 = Vector2.ZERO
	var geom_top: float = 0.0
	var geom_com_y: float = 0.0
	## Bontago-1pi.11.25: the last circle handed out. Circles are never mutated
	## after creation, so an identical one is reused (same object) instead of
	## allocating; any changed field allocates a fresh circle.
	var circle: InfluenceCircle = null

@export var tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")

## Host: a block just became settled (the sleep rule above); `height` is its top
## above the disk along the disk normal, the HUD's tower measure. Reach the Sky
## (Bontago-22y.9) records its players' heights from this, so a block that is
## still falling or balancing never counts.
signal block_settled(owner_slot: int, height: float)

var _entries: Dictionary = {}          ## instance id (int) -> _Entry
var _net_id_to_block: Dictionary = {}  ## net_id (int) -> Block
var _next_net_id: int = 1
## Bontago-1pi.11.32: instance ids of entries not yet settled. Together with
## Block's awake set (Block.awake_blocks()) this is everything the per-tick
## settle loop must visit: an awake body, or a body still accumulating
## settled_time (it may have gone to sleep before sleep_settle_time elapsed).
## A settled, sleeping or statically frozen block needs no per-tick work.
var _unsettled: Dictionary = {}
## Settled sleepers are not visited per tick, so a freed one (no block_removed)
## is pruned by a periodic sweep over every entry.
const STALE_SWEEP_TICKS: int = 60
var _sweep_ticks: int = 0
## Bontago-1pi.11.10: bumped by anything that can change territory influence
## (block placed/removed, settled flag flips, a settled block moving beyond
## TerritoryTuning.dirty_move_epsilon, owner change). MatchTerritory compares it
## to skip solves on an unchanged board.
var _territory_revision: int = 0
var _move_epsilon: float = 0.005

## Set by Match.start_match() via configure(). Used only for the disk-local
## projection (Field.to_local/to_global are plain Node3D methods, not part of
## Field's not-yet-landed M2 API — see docs/M2_PLAN.md's Field contract) and
## for bodies_over_cells()'s cell lookup.
var _field: Node3D = null
## Test seam: false recomputes every block's geometry (the oracle path).
var _geometry_cache_enabled: bool = true
var _grid: CellGrid = null

## M3a. True on the host **and offline** (Net.is_host()'s contract), so M2's
## single-PC behaviour is the default and nothing had to change for it.
## A client allocates no net_ids — the host's are the only ones a snapshot can
## name — and runs no settled rule, because every one of its bodies is frozen
## and would read as settled the instant it spawned (docs/M3a_PLAN.md, "two
## kinds of asleep").
var _host_authority: bool = true

## Bontago-1pi.11.41: host-side hole contact and dissolve (game/
## HoleDissolver.gd). Built by _ensure_dissolver(); fed this registry's moving
## blocks every physics tick.
var _dissolver: HoleDissolver = null


func _ready() -> void:
	Events.block_placed.connect(_on_block_placed)
	Events.block_removed.connect(_on_block_removed)
	_ensure_dissolver()


func _ensure_dissolver() -> HoleDissolver:
	if _dissolver == null:
		_dissolver = HoleDissolver.new()
		_dissolver.name = &"HoleDissolver"
		_dissolver.setup(self)
		add_child(_dissolver)
	return _dissolver


## The host's hole dissolver (Bontago-1pi.11.41); never null.
func hole_dissolver() -> HoleDissolver:
	return _ensure_dissolver()


## Called once by Match.start_match() once the map is known. `field` supplies
## the disk-local projection; `map_def` sizes the cell grid bodies_over_cells()
## looks cells up against.
func configure(field: Node3D, map_def: MapDef) -> void:
	_field = field
	_grid = CellGrid.new(map_def.field_radius, map_def.cell_size, map_def.shape_test())
	_ensure_dissolver().set_field(field)


## Drops every tracked block (but does not free the bodies themselves — the
## caller, Match, owns and clears blocks_parent). Called when a match starts.
func reset() -> void:
	_territory_revision += 1
	_entries.clear()
	_unsettled.clear()
	_net_id_to_block.clear()
	_next_net_id = 1
	_ensure_dissolver().reset()


## Monotonic counter of territory-relevant changes (see _territory_revision).
func territory_revision() -> int:
	return _territory_revision


## Forces the next territory comparison to see a change (tests, external edits).
func mark_territory_dirty() -> void:
	_territory_revision += 1


## Settled-block movement below this (metres; also the basis column delta)
## does not dirty the territory. Set by Match from TerritoryTuning.
func set_move_epsilon(epsilon: float) -> void:
	_move_epsilon = maxf(epsilon, 0.0)


## Whether this instance is the authority (see _host_authority). Set by
## Match.register_world() and Match.start_match() from Net.is_host().
func set_host_authority(is_authority: bool) -> void:
	_host_authority = is_authority


func is_host_authority() -> bool:
	return _host_authority


## Test-only seam (tests/unit/test_block_registry.gd, test_snapshot_wire.gd):
## moves the allocator to `value` so a test can reach the wire's id boundaries
## without placing tens of thousands of blocks. Game code never calls it;
## reset() puts the counter back to 1 as usual. Values below 1 are clamped,
## because 0 is the wire's reserved "no body" id (core/net/Quantize.gd).
func debug_set_next_net_id(value: int) -> void:
	_next_net_id = maxi(value, 1)


## Test-only: the id the next host-side placement will receive.
func debug_next_net_id() -> int:
	return _next_net_id


## Binds a host-allocated net_id to a block a client just built from
## net_block_spawned. The counterpart of the host's allocation below; a client
## never invents one, so the two ends can never disagree about which body a
## snapshot moves.
func bind_net_id(block: Block, net_id: int) -> void:
	if block == null or not Quantize.is_wire_id(net_id):
		return
	block.net_id = net_id
	_net_id_to_block[net_id] = block


func _on_block_placed(block: RigidBody3D, _shape_id: StringName) -> void:
	var typed: Block = block as Block
	if typed == null:
		return
	var entry: _Entry = _Entry.new()
	entry.block = typed
	entry.owner_slot = typed.owner_slot
	_entries[typed.get_instance_id()] = entry
	_unsettled[typed.get_instance_id()] = true
	_territory_revision += 1

	if not _host_authority:
		# The spawner calls bind_net_id() with the host's id instead.
		return

	# Monotonic and never reused within a match: reusing an id would let a
	# snapshot still in flight move the wrong body (docs/M3a_PLAN.md,
	# "net_id allocation and the spawn/snapshot race").
	var net_id: int = _next_net_id
	if not Quantize.is_wire_id(net_id):
		# The wire carries a u24 id (core/net/Quantize.gd's DECISION: 72 days
		# of the fastest possible feed to get here). Past that ceiling the only
		# alternatives are wrapping — the aliasing bug the ceiling exists to
		# prevent — or handing out an id the wire would truncate onto another
		# body. So the block keeps net_id -1: it lives and simulates on the
		# host, SnapshotSync skips it (net_id <= 0), bind_net_id() refuses it
		# on a client, and the error below is the record that it happened.
		push_error(
			"BlockRegistry: net_id space exhausted (next id %d > %d); block not replicated"
			% [net_id, Quantize.NET_ID_MAX]
		)
		return
	_next_net_id += 1
	typed.net_id = net_id
	_net_id_to_block[net_id] = typed


func _on_block_removed(block: RigidBody3D, _reason: String) -> void:
	var id: int = block.get_instance_id()
	_unsettled.erase(id)
	if _entries.erase(id):
		_territory_revision += 1
	var typed: Block = block as Block
	if typed != null and _net_id_to_block.get(typed.net_id) == typed:
		_net_id_to_block.erase(typed.net_id)


func _physics_process(delta: float) -> void:
	if not _host_authority:
		# Every body here is frozen and moved by net/SnapshotSync.gd, so its
		# velocities are zero and the settled rule would report the whole
		# field settled on the frame it spawned. influence_circles() returns
		# nothing on a client for the same reason; territory arrives as a
		# replicated raster instead.
		return
	var probe_registry: int = PerfProbe.start()
	var lin_sq: float = tuning.sleep_linear_threshold * tuning.sleep_linear_threshold
	var ang_sq: float = tuning.sleep_angular_threshold * tuning.sleep_angular_threshold
	var settle_time: float = tuning.sleep_settle_time
	var stale: Array = []
	# Bontago-1pi.11.41: blocks that moved this tick (unsettled, just settled or
	# settled-but-shifted), collected only while the field has a hole, so the
	# dissolver tests just those instead of every block.
	var dissolver: HoleDissolver = _ensure_dissolver()
	var collect: bool = dissolver.wants_candidates()
	var moving: Array[Block] = []
	var visited: Dictionary = {}
	# Awake bodies first, then unsettled ones that are not awake (asleep before
	# settling finished, or freed): the only entries the old full scan could
	# have changed state for.
	for awake_block: Block in Block.awake_blocks():
		var awake_id: int = awake_block.get_instance_id()
		var awake_entry: _Entry = _entries.get(awake_id) as _Entry
		if awake_entry == null:
			continue
		visited[awake_id] = true
		_step_entry(awake_id, awake_entry, delta, lin_sq, ang_sq, settle_time, collect, moving, stale)
	for id: Variant in _unsettled.keys():
		if visited.has(id):
			continue
		var entry: _Entry = _entries.get(id) as _Entry
		if entry == null:
			_unsettled.erase(id)
			continue
		_step_entry(id, entry, delta, lin_sq, ang_sq, settle_time, collect, moving, stale)
	_sweep_ticks += 1
	if _sweep_ticks >= STALE_SWEEP_TICKS:
		_sweep_ticks = 0
		for sweep_id: Variant in _entries:
			var swept: _Entry = _entries[sweep_id]
			if not is_instance_valid(swept.block) and not stale.has(sweep_id):
				stale.append(sweep_id)
	for id: Variant in stale:
		_entries.erase(id)
		_unsettled.erase(id)
		_territory_revision += 1
	dissolver.physics_tick(delta, moving)
	PerfProbe.stop(&"registry", probe_registry)


## One entry's settle accounting (the former loop body, unchanged arithmetic).
func _step_entry(
	id: int, entry: _Entry, delta: float, lin_sq: float, ang_sq: float, settle_time: float,
	collect: bool, moving: Array[Block], stale: Array
) -> void:
	var block: Block = entry.block
	if not is_instance_valid(block):
		stale.append(id)
		return
	# Squared compare matches `length() < t` for the non-negative thresholds.
	var settled_now: bool = (
		block.linear_velocity.length_squared() < lin_sq
		and block.angular_velocity.length_squared() < ang_sq
	)
	if settled_now:
		entry.settled_time += delta
	else:
		entry.settled_time = 0.0
	var was_settled: bool = entry.is_settled
	entry.is_settled = entry.settled_time >= settle_time
	if entry.is_settled != was_settled:
		_territory_revision += 1
		if entry.is_settled:
			_unsettled.erase(id)
			entry.marked_transform = block.global_transform
			_refresh_geometry(entry, field_global_transform())
			block_settled.emit(entry.owner_slot, entry.geom_top)
		else:
			_unsettled[id] = true
		if collect:
			moving.append(block)
	elif entry.is_settled and _moved_beyond_epsilon(entry):
		_territory_revision += 1
		entry.marked_transform = block.global_transform
		if collect:
			moving.append(block)
	elif collect and not entry.is_settled:
		moving.append(block)


func _moved_beyond_epsilon(entry: _Entry) -> bool:
	var current: Transform3D = entry.block.global_transform
	var last: Transform3D = entry.marked_transform
	var eps: float = _move_epsilon
	return (
		current.origin.distance_squared_to(last.origin) > eps * eps
		or current.basis.x.distance_squared_to(last.basis.x) > eps * eps
		or current.basis.y.distance_squared_to(last.basis.y) > eps * eps
		or current.basis.z.distance_squared_to(last.basis.z) > eps * eps
	)


## One InfluenceCircle per settled, still-owned block (spec 2.2). Home circles
## are Match's job, not this one — this only ever returns block circles.
func influence_circles(
	slots: Array[PlayerSlot], territory_tuning: TerritoryTuning, map_def: MapDef
) -> Array[InfluenceCircle]:
	var circles_empty: Array[InfluenceCircle] = []
	if not _host_authority:
		return circles_empty

	var team_of_slot: Dictionary = {}
	for slot: PlayerSlot in slots:
		team_of_slot[slot.slot_id] = slot.team_id

	var field_xform: Transform3D = field_global_transform()
	var circles: Array[InfluenceCircle] = []
	var base: float = territory_tuning.influence_base
	var k: float = territory_tuning.influence_k
	var cap: float = territory_tuning.influence_max_fraction * map_def.field_radius
	for id: Variant in _entries:
		var entry: _Entry = _entries[id]
		if not entry.is_settled or not is_instance_valid(entry.block):
			continue
		var team_id: Variant = team_of_slot.get(entry.owner_slot)
		if team_id == null:
			continue
		_refresh_geometry(entry, field_xform)
		# Same arithmetic as InfluenceCircle.radius_for_height.
		var radius: float = minf(base + k * maxf(entry.geom_top, 0.0), cap)
		var circle: InfluenceCircle = entry.circle
		if (
			circle == null or circle.center != entry.geom_com_xz or circle.radius != radius
			or circle.team_id != team_id or circle.slot_id != entry.owner_slot
			or circle.top_height != entry.geom_top or circle.body_id != id
		):
			circle = InfluenceCircle.new(
				entry.geom_com_xz, radius, team_id, entry.owner_slot, false, id, entry.geom_top
			)
			entry.circle = circle
		circles.append(circle)
	return circles


## Tallest point any of `slot_id`'s settled blocks reaches above the disk
## surface, in meters, or 0.0 with none.
func max_height_for_slot(slot_id: int) -> float:
	var highest: float = 0.0
	var field_xform: Transform3D = field_global_transform()
	for id: Variant in _entries.keys():
		var entry: _Entry = _entries[id]
		if not entry.is_settled or entry.owner_slot != slot_id or not is_instance_valid(entry.block):
			continue
		_refresh_geometry(entry, field_xform)
		highest = maxf(highest, entry.geom_top)
	return highest


## Bontago-1t5.3: `slot_id`'s tallest settled block as {"height": top above the
## disk, "xz": disk-local centre of mass}, or {} with none (the bot's Reach the
## Sky tower target). Read-only; same geometry as max_height_for_slot().
func tallest_settled_for_slot(slot_id: int) -> Dictionary:
	var best: Dictionary = {}
	var highest: float = -INF
	var field_xform: Transform3D = field_global_transform()
	for id: Variant in _entries.keys():
		var entry: _Entry = _entries[id]
		if not entry.is_settled or entry.owner_slot != slot_id or not is_instance_valid(entry.block):
			continue
		_refresh_geometry(entry, field_xform)
		if entry.geom_top > highest:
			highest = entry.geom_top
			best = {"height": entry.geom_top, "xz": entry.geom_com_xz}
	return best


## Every live body (settled or not) whose disk-local projection falls in one
## of `cells` (CellGrid row-major indices). Field uses this to wake bodies
## above a cell that just changed hole state (spec 3.3).
func bodies_over_cells(cells: PackedInt32Array) -> Array[RigidBody3D]:
	var result: Array[RigidBody3D] = []
	if _grid == null:
		return result
	var wanted: Dictionary = {}
	for cell: int in cells:
		wanted[cell] = true

	for id: Variant in _entries.keys():
		var entry: _Entry = _entries[id]
		if not is_instance_valid(entry.block):
			continue
		var local: Vector3 = _to_local(entry.block.global_position)
		var coords: Vector2i = _grid.world_to_cell(Vector2(local.x, local.z))
		if not _grid.in_bounds(coords.x, coords.y):
			continue
		if wanted.has(_grid.cell_index(coords.x, coords.y)):
			result.append(entry.block)
	return result


func net_id_for_block(block: Block) -> int:
	return block.net_id if block != null else -1


func block_for_net_id(net_id: int) -> Block:
	# Read as Variant: casting a freed instance with `as Block` is an error.
	var stored: Variant = _net_id_to_block.get(net_id)
	if stored == null:
		return null
	if not is_instance_valid(stored):
		# DECISION: drop the stale entry (block freed without block_removed, e.g. teardown).
		_net_id_to_block.erase(net_id)
		return null
	return stored as Block


## Host Paintball conversion and client mirror converge here so influence
## attribution and the visible material cannot diverge from Block.owner_slot.
func convert_owner(block: Block, new_slot: int, color: Color) -> bool:
	if not _host_authority or block == null or new_slot < 0:
		return false
	return _set_owner(block, new_slot, color)


func apply_replicated_owner(net_id: int, new_slot: int, color: Color) -> bool:
	if _host_authority or new_slot < 0:
		return false
	return _set_owner(block_for_net_id(net_id), new_slot, color)


func _set_owner(block: Block, new_slot: int, color: Color) -> bool:
	if block == null or not is_instance_valid(block):
		return false
	var id: int = block.get_instance_id()
	if not _entries.has(id) or block.net_id <= 0 or block.owner_slot == new_slot:
		return false
	var entry: _Entry = _entries[id]
	entry.owner_slot = new_slot
	_territory_revision += 1
	block.owner_slot = new_slot
	BlockFactory.recolor(block, color)
	Events.block_owner_changed.emit(block.net_id, new_slot)
	return true


func tracked_block_count() -> int:
	return _entries.size()


## Whether `block` is a live block this registry tracks.
func is_tracked(block: Block) -> bool:
	return block != null and _entries.has(block.get_instance_id())


## Every live tracked Block, host or client alike (M8 P5,
## docs/M8_PLAN.md's own Interface stub) -- game/StableBlockManager.gd's only
## consumer this milestone, so it can scan for asleep-past-threshold blocks
## without this class needing to know anything about freezing. Filters out
## any entry whose Block was freed without going through
## Events.block_removed first, the same defensive is_instance_valid() check
## bodies_over_cells() above already makes.
## The field's current global transform (identity with no field). Lets
## StableBlockManager notice a tilting/moving disc (Bontago-sen.11).
func field_global_transform() -> Transform3D:
	if _field == null or not is_instance_valid(_field):
		return Transform3D.IDENTITY
	return _field.global_transform


## Bontago-1pi.18.1: adds, per owner slot, the blocks faster than sqrt(limit_sq)
## into `counts` (pre-sized by the caller). Allocation-free, unlike all_blocks().
func count_fast_blocks_by_owner(limit_sq: float, counts: PackedInt32Array) -> void:
	for id: Variant in _entries:
		var block: Block = (_entries[id] as _Entry).block
		if not is_instance_valid(block):
			continue
		if block.owner_slot >= 0 and block.owner_slot < counts.size() and block.linear_velocity.length_squared() > limit_sq:
			counts[block.owner_slot] += 1


func all_blocks() -> Array[Block]:
	var result: Array[Block] = []
	for id: Variant in _entries.keys():
		var entry: _Entry = _entries[id]
		if is_instance_valid(entry.block):
			result.append(entry.block)
	return result


## True once every tracked block's own settled flag (the per-block accumulator
## _physics_process() above maintains from PhysicsTuning.sleep_linear_threshold
## / sleep_angular_threshold / sleep_settle_time) is true. Used by
## MatchLifecycle._tick_turn_based() (M6 B4, spec 2.7) to decide when to hand
## the turn to the next player. An empty registry (no blocks placed yet) is
## vacuously settled, matching the "nothing left to wait for" case.
func all_settled() -> bool:
	for id: Variant in _entries.keys():
		var entry: _Entry = _entries[id]
		if not entry.is_settled:
			return false
	return true


## One Vector3 per settled block, packed as (disk-local x offset from
## center, mass, disk-local z offset) -- the same "a spare component carries a
## second scalar" packing this codebase already uses to avoid a per-frame
## Array[Object] allocation. game/Field.gd's PHYSICAL_BALANCE tilt (M6 B5,
## spec 2.1/2.7; kinematic-torque approximation, docs/M6_PLAN.md DECISION,
## owner-approved Bontago-keo.16) sums mass * lever-arm across these to drive
## its tilt spring every physics tick.
##
## Host-authority gated exactly like influence_circles(): every body on a
## client is frozen (this file's own _physics_process() doc), so a client
## contributes no torque of its own -- it only ever mirrors the host's
## already-tilted pose via Field.apply_replicated_pose().
func settled_torque_samples() -> PackedVector3Array:
	var samples: PackedVector3Array = PackedVector3Array()
	if not _host_authority:
		return samples
	var field_xform: Transform3D = field_global_transform()
	for id: Variant in _entries.keys():
		var entry: _Entry = _entries[id]
		if not entry.is_settled or not is_instance_valid(entry.block):
			continue
		_refresh_geometry(entry, field_xform)
		samples.append(Vector3(entry.geom_com_xz.x, entry.block.mass, entry.geom_com_xz.y))
	return samples


## True when `node` is the field this registry projects into.
func uses_field(node: Node3D) -> bool:
	return node != null and node == _field


## Field-local center-of-mass height (>= 0) of the live block with `body_id`,
## or -1.0 when the registry does not track it. Bit-identical to
## `maxf(field.to_local(b.global_transform * b.center_of_mass).y, 0.0)`.
func center_height_for_body_id(body_id: int, field_xform: Transform3D) -> float:
	var entry: _Entry = _entries.get(body_id) as _Entry
	if entry == null or not is_instance_valid(entry.block):
		return -1.0
	_refresh_geometry(entry, field_xform)
	return maxf(entry.geom_com_y, 0.0)


## Drops the cached geometry of `block` (call after swapping a live block's
## mesh in place; nothing does today).
func invalidate_geometry(block: Block) -> void:
	if block == null:
		return
	var entry: _Entry = _entries.get(block.get_instance_id()) as _Entry
	if entry != null:
		entry.geom_valid = false


## Recomputes entry.geom_* unless the exact inputs (block transform, field
## transform, child count) are unchanged; Transform3D == is componentwise, so a
## hit is bit-identical to a recompute.
func _refresh_geometry(entry: _Entry, field_xform: Transform3D) -> void:
	var block: Block = entry.block
	var block_xform: Transform3D = block.global_transform
	var child_count: int = block.get_child_count()
	if (
		_geometry_cache_enabled and entry.geom_valid
		and block_xform == entry.geom_block_xform
		and field_xform == entry.geom_field_xform
		and child_count == entry.geom_child_count
	):
		return
	var local_com: Vector3 = _local_center_of_mass(block)
	entry.geom_com_xz = Vector2(local_com.x, local_com.z)
	entry.geom_com_y = local_com.y
	entry.geom_top = _top_height_local(block)
	entry.geom_block_xform = block_xform
	entry.geom_field_xform = field_xform
	entry.geom_child_count = child_count
	entry.geom_valid = true


func _local_center_of_mass(block: Block) -> Vector3:
	var world_com: Vector3 = block.global_transform * block.center_of_mass
	return _to_local(world_com)


## Exposes the same visual top height used by influence_circles() to sandbox
## comparisons without duplicating the mesh-bound calculation there.
func top_height_for_block(block: Block) -> float:
	return _top_height_local(block)


## Highest point of `block`'s visual meshes above the disk surface, along the
## disk normal (spec 2.2). Reads mesh AABBs rather than collision shapes so
## the wedge's sloped visual, not its convex collision hull, decides the
## reported height.
func _top_height_local(block: Block) -> float:
	var max_y: float = -INF
	for child: Node in block.get_children():
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var aabb: AABB = mesh_instance.mesh.get_aabb()
		for corner_index: int in range(8):
			var corner: Vector3 = aabb.position + Vector3(
				aabb.size.x * float(corner_index & 1),
				aabb.size.y * float((corner_index >> 1) & 1),
				aabb.size.z * float((corner_index >> 2) & 1)
			)
			var world_corner: Vector3 = mesh_instance.global_transform * corner
			max_y = maxf(max_y, _to_local(world_corner).y)
	if max_y == -INF:
		return 0.0
	return maxf(max_y, 0.0)


func _to_local(world_pos: Vector3) -> Vector3:
	return _field.to_local(world_pos) if _field != null else world_pos
