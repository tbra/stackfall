class_name Field
extends StaticBody3D
## The match field: a disk (spec 2.1). Static for M1/M2 — no tilt yet, so it's
## a plain StaticBody3D. It becomes an AnimatableBody3D (SPECIALS_ONLY tilt) or
## RigidBody3D (PHYSICAL_BALANCE tilt) from M4/M6 onward.
##
## **Cells (spec 3.3).** The disk's collision is not one cylinder but a square
## grid of `map_def.cell_size` BoxShape3Ds clipped to the disk, all inside this
## one body, one shape owner per cell. One cell is one CellGrid index is one
## pixel of the territory raster, so the rules, the picture and the collision
## can never disagree about where a hole is. A hole is that cell's shape owner
## disabled; the toggles are batched at
## `TerritoryTuning.max_cell_toggles_per_frame` per physics frame through a
## FIFO backlog, and every body above a cell that changed is woken, because a
## sleeping tower would otherwise sit happily on collision that is no longer
## there.
##
## **What this node does not do.** Field decides nothing. Whether a cell is a
## hole is TerritoryRaster's answer (core/, pure); Field only applies it, and
## only ever through set_hole_cells(). Likewise the overlay draws the raster it
## is handed and never reads a rule.
##
## Also owns the kill plane (spec 2.1): any body that falls below
## `tuning.kill_plane_y` is freed and reported on the Events bus.

## The kill plane only needs to catch blocks that fall off the disk, so it's
## sized as a wide multiple of the field radius rather than a magic constant.
const KILL_PLANE_RADIUS_FACTOR: float = 20.0
## Thickness of the kill plane's trigger box, in meters. It only has to be
## thicker than one physics step of free fall.
const KILL_PLANE_THICKNESS: float = 1.0

@export var map_def: MapDef = preload("res://config/maps/round_medium.tres")
@export var tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
@export var territory_tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")
@export var visuals: TerritoryVisuals = preload("res://config/territory_visuals.tres")
@export var home_flag_scene: PackedScene = preload("res://game/HomeFlag.tscn")
@export var goal_flag_scene: PackedScene = preload("res://game/GoalFlag.tscn")

var _grid: CellGrid = null
## cell index -> shape owner id, or -1 for a cell outside the disk.
var _cell_owner_ids: PackedInt32Array = PackedInt32Array()
var _in_disk_cells: PackedInt32Array = PackedInt32Array()
## 1 where the cell's shape owner is currently disabled.
var _hole_applied: PackedByteArray = PackedByteArray()
## 1 where the rules want the cell to be a hole; the backlog is the difference.
var _hole_wanted: PackedByteArray = PackedByteArray()
## FIFO backlog of (cell, disabled) pairs, consumed from _toggle_head so that
## draining never has to shift a PackedInt32Array.
var _toggle_cells: PackedInt32Array = PackedInt32Array()
var _toggle_disabled: PackedByteArray = PackedByteArray()
var _toggle_head: int = 0

var _overlay: TerritoryOverlay = null
var _home_flags: Array[HomeFlag] = []
var _goal_flags: Array[GoalFlag] = []
var _slot_colors: PackedColorArray = PackedColorArray()


func _ready() -> void:
	_build_cells()
	_build_kill_plane()
	_build_overlay()
	Events.hole_cells_changed.connect(_on_hole_cells_changed)
	Events.goal_capture_progress.connect(_on_goal_capture_progress)


func _physics_process(_delta: float) -> void:
	_drain_toggles()


# --- Geometry ---------------------------------------------------------------

## The disk's cell grid. Built on demand so callers that reach Field before
## _ready() (the editor, a unit test) still get the real convention.
func grid() -> CellGrid:
	if _grid == null:
		_grid = CellGrid.new(map_def.field_radius, map_def.cell_size)
	return _grid


func map_definition() -> MapDef:
	return map_def


## World Y of the disk's top surface. 0.0 while the disk is flat and centered;
## from M4 the tilt makes this only an approximation and callers that care use
## world_from_disk_local() instead.
func surface_y() -> float:
	return global_transform.origin.y


## World point -> disk-local (x, z), the convention CellGrid documents. This
## and world_from_disk_local() are the only two functions that change when the
## disk starts tilting in M4.
func disk_local_from_world(world: Vector3) -> Vector2:
	var local: Vector3 = to_local(world)
	return Vector2(local.x, local.z)


## Disk-local (x, z) plus a height above the disk surface -> world point.
func world_from_disk_local(local: Vector2, height: float) -> Vector3:
	return to_global(Vector3(local.x, height, local.y))


func _build_cells() -> void:
	var cell_grid: CellGrid = grid()
	var cell_count: int = cell_grid.cell_count()
	_cell_owner_ids = PackedInt32Array()
	_cell_owner_ids.resize(cell_count)
	_cell_owner_ids.fill(-1)
	_hole_applied = PackedByteArray()
	_hole_applied.resize(cell_count)
	_hole_wanted = PackedByteArray()
	_hole_wanted.resize(cell_count)
	_in_disk_cells = _collect_in_disk_cells(cell_grid)

	# One BoxShape3D resource is shared by every owner: the boxes are all the
	# same size, and thousands of identical shapes would be thousands of
	# identical physics shapes for no gain.
	var box: BoxShape3D = BoxShape3D.new()
	var edge: float = map_def.cell_size + map_def.cell_overlap
	box.size = Vector3(edge, map_def.disk_height, edge)

	for cell: int in _in_disk_cells:
		var center: Vector2 = cell_grid.index_center(cell)
		var owner_id: int = create_shape_owner(self)
		shape_owner_add_shape(owner_id, box)
		shape_owner_set_transform(
			owner_id,
			Transform3D(Basis(), Vector3(center.x, -map_def.disk_height * 0.5, center.y))
		)
		_cell_owner_ids[cell] = owner_id

	var material: PhysicsMaterial = PhysicsMaterial.new()
	material.friction = tuning.disk_friction
	physics_material_override = material


## Every in-disk cell index in row-major order. CellGrid is the one authority
## on where the disk ends (it builds this list once and caches it), so the
## collision cells, the raster pixels and placement validation share a rim by
## construction. P3 carried a local fallback here while CellGrid was a stub;
## P1's core landed, so the fallback is gone.
func _collect_in_disk_cells(cell_grid: CellGrid) -> PackedInt32Array:
	return cell_grid.in_disk_cells()


## How many cells carry collision, in or out of a hole. The denominator the
## grid tests count against.
func cell_count() -> int:
	return _in_disk_cells.size()


func cell_owner_id(index: int) -> int:
	if index < 0 or index >= _cell_owner_ids.size():
		return -1
	return _cell_owner_ids[index]


# --- Holes (spec 2.2, 3.3) --------------------------------------------------

## Applies the raster's last hole diff. Both arrays are row-major CellGrid
## indices. Nothing toggles here: the pairs go on the backlog and drain at
## `TerritoryTuning.max_cell_toggles_per_frame` per physics frame.
func set_hole_cells(opened: PackedInt32Array, closed: PackedInt32Array) -> void:
	for cell: int in opened:
		_enqueue_toggle(cell, true)
	for cell: int in closed:
		_enqueue_toggle(cell, false)


func _enqueue_toggle(cell: int, disabled: bool) -> void:
	if cell < 0 or cell >= _cell_owner_ids.size():
		return
	if _cell_owner_ids[cell] < 0:
		return
	var wanted: int = 1 if disabled else 0
	if _hole_wanted[cell] == wanted:
		return
	_hole_wanted[cell] = wanted
	_toggle_cells.append(cell)
	_toggle_disabled.append(wanted)


## True when this cell's collision is currently switched off.
##
## DECISION (game/Field.gd): the M2 plan does not say whether this reports the
## requested or the applied state. It reports the *applied* one — a cell the
## raster opened this frame still reads false while it waits in the backlog —
## because that is the only question this node can answer that TerritoryRaster
## cannot, and pending_toggle_count() exists precisely to expose the gap. No
## rule reads it; rule code asks TerritoryRaster.is_hole_index().
func is_hole_cell(index: int) -> bool:
	if index < 0 or index >= _hole_applied.size():
		return false
	return _hole_applied[index] == 1


## Toggles requested but not yet applied.
func pending_toggle_count() -> int:
	return _toggle_cells.size() - _toggle_head


func _drain_toggles() -> void:
	if _toggle_head >= _toggle_cells.size():
		return
	var budget: int = maxi(territory_tuning.max_cell_toggles_per_frame, 1)
	var applied: PackedInt32Array = PackedInt32Array()
	while _toggle_head < _toggle_cells.size() and applied.size() < budget:
		var cell: int = _toggle_cells[_toggle_head]
		var disabled: bool = _toggle_disabled[_toggle_head] == 1
		_toggle_head += 1
		var owner_id: int = _cell_owner_ids[cell]
		if owner_id < 0:
			continue
		if (_hole_applied[cell] == 1) == disabled:
			continue
		shape_owner_set_disabled(owner_id, disabled)
		_hole_applied[cell] = 1 if disabled else 0
		applied.append(cell)
	if _toggle_head >= _toggle_cells.size():
		_toggle_cells = PackedInt32Array()
		_toggle_disabled = PackedByteArray()
		_toggle_head = 0
	if not applied.is_empty():
		wake_blocks_above_cells(applied)


## Spec 3.3: "Wake up any sleeping blocks above cells that change state."
## Without this a settled tower keeps sleeping on a cell whose collision has
## just been switched off and never falls through it.
func wake_blocks_above_cells(cells: PackedInt32Array) -> void:
	if cells.is_empty() or not is_inside_tree():
		return
	var world: World3D = get_world_3d()
	if world == null:
		return
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	if space == null:
		return

	var height: float = map_def.cell_wake_height
	var column: BoxShape3D = BoxShape3D.new()
	column.size = Vector3(map_def.cell_size, height, map_def.cell_size)
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = column
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [get_rid()]

	var cell_grid: CellGrid = grid()
	var woken: Dictionary[int, bool] = {}
	for cell: int in cells:
		var center: Vector2 = cell_grid.index_center(cell)
		query.transform = Transform3D(
			Basis(), world_from_disk_local(center, height * 0.5)
		)
		var hits: Array[Dictionary] = space.intersect_shape(
			query, map_def.cell_wake_max_bodies
		)
		for hit: Dictionary in hits:
			var body: RigidBody3D = hit.get("collider") as RigidBody3D
			if body == null or woken.has(body.get_instance_id()):
				continue
			woken[body.get_instance_id()] = true
			if body.freeze:
				body.freeze = false
			body.sleeping = false


func _on_hole_cells_changed(opened: PackedInt32Array, closed: PackedInt32Array) -> void:
	set_hole_cells(opened, closed)


# --- Territory overlay (spec 2.10, 3.3) -------------------------------------

func _build_overlay() -> void:
	_overlay = TerritoryOverlay.new()
	_overlay.name = &"DiskMesh"
	_overlay.configure(map_def, visuals, territory_tuning)
	_overlay.position = Vector3(0.0, -map_def.disk_height * 0.5, 0.0)
	add_child(_overlay)


func overlay() -> TerritoryOverlay:
	return _overlay


## Hands the overlay the live raster to draw and the per-slot colors to draw it
## in. Receivers read the raster and never mutate it; the overlay rebuilds its
## ImageTexture at TerritoryTuning.raster_upload_hz, not every frame.
func set_overlay_source(raster: TerritoryRaster, slot_colors: PackedColorArray) -> void:
	_slot_colors = slot_colors
	if _overlay != null:
		_overlay.set_source(raster, slot_colors)


# --- Flags (spec 2.2, 2.3) --------------------------------------------------

## Disk-local position of a slot's home flag. Delegates to MapDef so that
## Field, PlayerSlot and the solver's home circles all read one definition.
func home_flag_position(slot_id: int, slot_count: int) -> Vector2:
	return map_def.home_flag_position(slot_id, slot_count)


func goal_flag_positions(count: int) -> PackedVector2Array:
	return map_def.goal_flag_positions(count)


## Builds the match's flags. Called once by Main after Match.start_match(),
## because only the match knows how many players and goals there are.
func place_flags(slot_count: int, slot_colors: PackedColorArray, goal_count: int) -> void:
	_slot_colors = slot_colors
	_clear_flags()
	for slot_id: int in range(maxi(slot_count, 0)):
		var flag: HomeFlag = home_flag_scene.instantiate() as HomeFlag
		flag.visuals = visuals
		var local: Vector2 = home_flag_position(slot_id, slot_count)
		flag.position = Vector3(local.x, 0.0, local.y)
		add_child(flag)
		flag.set_slot(slot_id, _color_for_index(slot_id))
		_home_flags.append(flag)
	for local: Vector2 in goal_flag_positions(goal_count):
		var flag: GoalFlag = goal_flag_scene.instantiate() as GoalFlag
		flag.visuals = visuals
		flag.position = Vector3(local.x, 0.0, local.y)
		add_child(flag)
		_goal_flags.append(flag)


func _clear_flags() -> void:
	for flag: HomeFlag in _home_flags:
		flag.queue_free()
	for flag: GoalFlag in _goal_flags:
		flag.queue_free()
	_home_flags = []
	_goal_flags = []


func home_flags() -> Array[HomeFlag]:
	return _home_flags


func goal_flags() -> Array[GoalFlag]:
	return _goal_flags


## Spec 2.3: "A radial progress ring appears on each goal flag while someone is
## capturing it." `progress` runs 0..1 over TerritoryTuning.capture_hold;
## team_id -1 with progress 0 clears the ring.
func set_capture_progress(team_id: int, progress: float) -> void:
	var color: Color = _color_for_index(team_id)
	for flag: GoalFlag in _goal_flags:
		flag.set_capture(team_id, progress, color)


func _on_goal_capture_progress(team_id: int, progress: float) -> void:
	set_capture_progress(team_id, progress)


## Slot/team colors come from MatchConfig.player_colors by way of
## set_overlay_source()/place_flags(), never from a literal. The fallback is
## the goal flag's neutral color, used before a match hands its colors over.
func _color_for_index(index: int) -> Color:
	if index < 0 or index >= _slot_colors.size():
		return visuals.goal_flag_color
	return _slot_colors[index]


# --- Kill plane (spec 2.1) --------------------------------------------------

func _build_kill_plane() -> void:
	var area: Area3D = Area3D.new()
	area.name = &"KillPlane"
	var collision: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	var span: float = map_def.field_radius * KILL_PLANE_RADIUS_FACTOR
	box.size = Vector3(span, KILL_PLANE_THICKNESS, span)
	collision.shape = box
	area.add_child(collision)
	area.position = Vector3(0.0, tuning.kill_plane_y, 0.0)
	add_child(area)
	area.body_entered.connect(_on_kill_plane_body_entered)


func _on_kill_plane_body_entered(body: Node3D) -> void:
	var rigid_body: RigidBody3D = body as RigidBody3D
	if rigid_body == null:
		return
	Events.block_removed.emit(rigid_body, String(Events.REASON_KILL_PLANE))
	rigid_body.queue_free()
