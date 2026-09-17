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


func _ready() -> void:
	Events.block_placed.connect(_on_block_placed)
	Events.block_removed.connect(_on_block_removed)


## Called once by Match.start_match() once the map is known. `field` supplies
## the disk-local projection; `map_def` sizes the cell grid bodies_over_cells()
## looks cells up against.
func configure(field: Node3D, map_def: MapDef) -> void:
	_field = field
	_grid = CellGrid.new(map_def.field_radius, map_def.cell_size)


## Drops every tracked block (but does not free the bodies themselves — the
## caller, Match, owns and clears blocks_parent). Called when a match starts.
func reset() -> void:
	_entries.clear()
	_net_id_to_block.clear()
	_next_net_id = 1


func _on_block_placed(block: RigidBody3D, _shape_id: StringName) -> void:
	var typed: Block = block as Block
	if typed == null:
		return
	var entry: _Entry = _Entry.new()
	entry.block = typed
	entry.owner_slot = typed.owner_slot
	_entries[typed.get_instance_id()] = entry

	var net_id: int = _next_net_id
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
