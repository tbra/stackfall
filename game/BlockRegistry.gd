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

@export var tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")

var _entries: Dictionary = {}          ## instance id (int) -> _Entry
var _net_id_to_block: Dictionary = {}  ## net_id (int) -> Block
var _next_net_id: int = 1

## Set by Match.start_match() via configure(). Used only for the disk-local
## projection (Field.to_local/to_global are plain Node3D methods, not part of
## Field's not-yet-landed M2 API — see docs/M2_PLAN.md's Field contract) and
## for bodies_over_cells()'s cell lookup.
var _field: Node3D = null
var _grid: CellGrid = null

## M3a. True on the host **and offline** (Net.is_host()'s contract), so M2's
## single-PC behaviour is the default and nothing had to change for it.
## A client allocates no net_ids — the host's are the only ones a snapshot can
## name — and runs no settled rule, because every one of its bodies is frozen
## and would read as settled the instant it spawned (docs/M3a_PLAN.md, "two
## kinds of asleep").
var _host_authority: bool = true


func _ready() -> void:
	Events.block_placed.connect(_on_block_placed)
	Events.block_removed.connect(_on_block_removed)


## Called once by Match.start_match() once the map is known. `field` supplies
## the disk-local projection; `map_def` sizes the cell grid bodies_over_cells()
## looks cells up against.
func configure(field: Node3D, map_def: MapDef) -> void:
	_field = field
	_grid = CellGrid.new(map_def.field_radius, map_def.cell_size, map_def.shape_test())


## Drops every tracked block (but does not free the bodies themselves — the
## caller, Match, owns and clears blocks_parent). Called when a match starts.
func reset() -> void:
	_entries.clear()
	_net_id_to_block.clear()
	_next_net_id = 1


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
	_entries.erase(id)
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
	for id: Variant in _entries.keys():
		var entry: _Entry = _entries[id]
		if not is_instance_valid(entry.block):
			_entries.erase(id)
			continue
		var settled_now: bool = (
			entry.block.linear_velocity.length() < tuning.sleep_linear_threshold
			and entry.block.angular_velocity.length() < tuning.sleep_angular_threshold
		)
		if settled_now:
			entry.settled_time += delta
		else:
			entry.settled_time = 0.0
		entry.is_settled = entry.settled_time >= tuning.sleep_settle_time


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

	var circles: Array[InfluenceCircle] = []
	for id: Variant in _entries.keys():
		var entry: _Entry = _entries[id]
		if not entry.is_settled or not is_instance_valid(entry.block):
			continue
		if not team_of_slot.has(entry.owner_slot):
			continue
		var local_com: Vector3 = _local_center_of_mass(entry.block)
		var top: float = _top_height_local(entry.block)
		circles.append(InfluenceCircle.for_block(
			Vector2(local_com.x, local_com.z),
			top,
			team_of_slot[entry.owner_slot],
			entry.owner_slot,
			int(id),
			territory_tuning,
			map_def.field_radius
		))
	return circles


## Tallest point any of `slot_id`'s settled blocks reaches above the disk
## surface, in meters, or 0.0 with none.
func max_height_for_slot(slot_id: int) -> float:
	var highest: float = 0.0
	for id: Variant in _entries.keys():
		var entry: _Entry = _entries[id]
		if not entry.is_settled or entry.owner_slot != slot_id or not is_instance_valid(entry.block):
			continue
		highest = maxf(highest, _top_height_local(entry.block))
	return highest


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
	return _net_id_to_block.get(net_id) as Block


func tracked_block_count() -> int:
	return _entries.size()


## Every live tracked Block, host or client alike (M8 P5,
## docs/M8_PLAN.md's own Interface stub) -- game/StableBlockManager.gd's only
## consumer this milestone, so it can scan for asleep-past-threshold blocks
## without this class needing to know anything about freezing. Filters out
## any entry whose Block was freed without going through
## Events.block_removed first, the same defensive is_instance_valid() check
## bodies_over_cells() above already makes.
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
	for id: Variant in _entries.keys():
		var entry: _Entry = _entries[id]
		if not entry.is_settled or not is_instance_valid(entry.block):
			continue
		var local_com: Vector3 = _local_center_of_mass(entry.block)
		samples.append(Vector3(local_com.x, entry.block.mass, local_com.z))
	return samples


func _local_center_of_mass(block: Block) -> Vector3:
	var world_com: Vector3 = block.global_transform * block.center_of_mass
	return _to_local(world_com)


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
