class_name Field
extends FieldBody
## The match field: a disk (spec 1.7). An AnimatableBody3D so the tilt can carry
## resting blocks. The tilt spring is core/physics/DiscTilt.gd, the hole backlog
## core/physics/HoleBacklog.gd, the flags and beacon body the FieldFlags child;
## Field builds the collision, kill plane and overlay and wires them.
##
## **Cells (spec 2.5).** The collision is one ConcavePolygonShape3D of one quad per
## in-disk cell of the CellGrid (one cell is one raster pixel) plus rim walls. It is
## built once per map and never on a hole change (set_faces() woke every sleeping
## body). Holes live in the HoleBacklog, drained per physics frame; opened cells
## are announced on hole_cells_applied for the host's HoleDissolver. Field decides
## nothing: whether a cell is a hole is TerritoryRaster's answer.
##
## Also owns the kill plane (spec 1.7): a body below `tuning.kill_plane_y` is
## reported on body_fell; BlockRegistry removes it on the host.

## The kill plane is sized as a wide multiple of the field radius.
const KILL_PLANE_RADIUS_FACTOR: float = 20.0
## Thickness of the kill plane's trigger box (more than one step of free fall).
const KILL_PLANE_THICKNESS: float = 1.0
## Two triangles, three vertices each, per quad of the disk trimesh.
const VERTS_PER_QUAD: int = 6
## The four edge neighbours of a cell, in CellGrid (cx, cy) steps.
const NEIGHBOUR_DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]
## Passed after `--`: print the disk trimesh build time on every build.
##   godot --headless --path . res://tests/bench/bench_tower.tscn -- --trace-disk
const TRACE_ARG: String = "--trace-disk"

@export var tuning: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")
@export var tilt_tuning: TiltTuning = preload("res://config/physics/tilt_tuning.tres")
@export var territory_tuning: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")
@export var visuals: TerritoryVisuals = preload("res://config/territory/territory_visuals.tres")
## The disc's purely-visual side band + glowing rim (see game/field/ArenaMesh.gd).
@export var disc_body_visuals: DiscBodyVisuals = preload("res://config/territory/disc_body_visuals.tres")
## which side/underside look the arena draws (default CURRENT).
@export var arena_side_style: ArenaSideStyle = preload("res://config/territory/arena_side_style.tres")
@export var home_flag_scene: PackedScene = preload("res://game/flags/HomeFlag.tscn")
@export var goal_flag_scene: PackedScene = preload("res://game/flags/GoalFlag.tscn")

var _grid: CellGrid = null
## 1 where the cell is in the disk (carries collision).
var _solid: PackedByteArray = PackedByteArray()
var _in_disk_cells: PackedInt32Array = PackedInt32Array()
var _holes: HoleBacklog = HoleBacklog.new()
var _disk_shape: ConcavePolygonShape3D = null
var _disk_owner_id: int = -1
var _kill_plane_area: Area3D = null
## Disk-local meters: cell (cx, cy) spans lines cx..cx+1 and cy..cy+1.
var _grid_lines: PackedFloat32Array = PackedFloat32Array()

## Off by default: no rotation is ever written, so sync_to_physics carries none.
var _tilt_enabled: bool = false
var _tilt: DiscTilt = null
## PHYSICAL_BALANCE tilt (spec 1.7/1.2); only meaningful while _tilt_enabled too.
var _physical_balance_enabled: bool = false
## The registry PHYSICAL_BALANCE reads settled blocks from. Null-safe: no torque.
var _registry: BlockRegistry = null

var _overlay: TerritoryOverlay = null
var _flags: FieldFlags = null


func _ready() -> void:
	_tilt = DiscTilt.new(tilt_tuning)
	# DECISION: AnimatableBody3D defaults sync_to_physics to true, which makes Godot
	# ignore a direct transform write made outside a physics tick. Force it false
	# here and only flip it true while the tilt moves, so callers that place the
	# field themselves keep working until a match turns tilt on.
	sync_to_physics = false
	_rebuild_cells()
	_build_kill_plane()
	_build_overlay()
	_build_flags()
	Events.hole_cells_changed.connect(set_hole_cells)


func _physics_process(delta: float) -> void:
	var opened: PackedInt32Array = _holes.drain(territory_tuning.max_cell_toggles_per_frame)
	if not opened.is_empty():
		hole_cells_applied.emit(opened)
	if _tilt_enabled:
		_step_tilt(delta)


## The disk's cell grid, built on demand so callers before _ready() get it too.
func grid() -> CellGrid:
	if _grid == null:
		_grid = CellGrid.new(map_def.field_radius, map_def.cell_size, map_def.shape_test())
	return _grid


## Turns tilt on for a tilt_mode match; disabling snaps the tilt back to level.
func set_tilt_enabled(enabled: bool) -> void:
	if _tilt_enabled == enabled:
		return
	_tilt_enabled = enabled
	_set_sync(enabled)
	if not enabled:
		_tilt.reset()
		_apply_tilt_transform()
		_push_level_pose_to_physics()


func set_physical_balance_enabled(enabled: bool) -> void:
	_physical_balance_enabled = enabled


func set_registry(registry: BlockRegistry) -> void:
	_registry = registry


func tilt_vector() -> Vector2:
	return _tilt.tilt()


## A special's push on the disk: `direction` is a disk-local XZ unit vector,
## `magnitude` a velocity kick into the spring. No-op while tilt is disabled.
func apply_tilt_impulse(direction: Vector2, magnitude: float) -> void:
	if not _tilt_enabled:
		return
	_tilt.impulse(direction, magnitude)
	_wake_sync()


## net/SnapshotSync.gd's client_tick() feeds the interpolated world-space disk pose
## (spec 2.6) every frame; the first call switches to mirror mode, stopping the
## local spring.
func apply_replicated_pose(offset: Vector3, tilt: Quaternion) -> void:
	_tilt.set_pose(tilt)
	_wake_sync()
	global_transform = Transform3D(Basis(tilt), offset)


## One physics tick of the spring. The balance torque is resampled only while the
## WHOLE stack is settled, else the disk chases a moving target and the stack never sleeps.
func _step_tilt(delta: float) -> void:
	var balance: DiscTilt.Balance = DiscTilt.Balance.OFF
	var samples: PackedVector3Array = PackedVector3Array()
	if _physical_balance_enabled:
		if _registry == null or not is_instance_valid(_registry) or _registry.tracked_block_count() == 0:
			balance = DiscTilt.Balance.EMPTY
		elif _registry.all_settled():
			balance = DiscTilt.Balance.SAMPLED
			samples = _registry.settled_torque_samples()
		else:
			balance = DiscTilt.Balance.HOLD
	var changed: bool = _tilt.step(delta, balance, samples)
	# A sync_to_physics body keeps resting blocks awake; drop it at rest.
	var sync: bool = not _tilt.is_at_rest()
	if sync != sync_to_physics:
		_set_sync(sync)
	if changed:
		_apply_tilt_transform()


## Re-arms sync_to_physics before the first write after a wake (tilt enabled only).
func _wake_sync() -> void:
	if _tilt_enabled:
		_set_sync(true)


## Sets sync_to_physics on the disc and the beacon body together.
func _set_sync(enabled: bool) -> void:
	sync_to_physics = enabled
	if _flags != null:
		_flags.set_sync(enabled)


## Writes the tilt into the local transform; the disk pivots on its own origin.
func _apply_tilt_transform() -> void:
	_tilt.mark_applied()
	transform = Transform3D(_tilt.basis(), transform.origin)


## Writes the level pose straight into the physics body after a reset: with
## sync_to_physics off the node write does not reach it before the next step, so a
## Replay (END -> LOBBY -> LOADING in one frame) would re-sync the old tilted pose.
## Skipped while sync_to_physics is on (the node write is the target) or out of tree.
func _push_level_pose_to_physics() -> void:
	if sync_to_physics or not is_inside_tree():
		return
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)


## Builds the cell grid and collision trimesh from map_def; a rebuild frees the
## previous shape_owner and starts the hole state clean.
func _rebuild_cells() -> void:
	if _disk_owner_id >= 0:
		remove_shape_owner(_disk_owner_id)
		_disk_owner_id = -1
	_grid = null
	var cell_grid: CellGrid = grid()
	_solid = PackedByteArray()
	_solid.resize(cell_grid.cell_count())
	_holes = HoleBacklog.new()
	_in_disk_cells = cell_grid.in_disk_cells()
	for cell: int in _in_disk_cells:
		_solid[cell] = 1
	# DECISION: quad corners come from shared grid lines, so neighbouring quads share
	# bit-identical vertices and Jolt sees one welded surface with no seams.
	_grid_lines = PackedFloat32Array()
	_grid_lines.resize(cell_grid.res + 1)
	for line: int in range(cell_grid.res + 1):
		_grid_lines[line] = float(line) * cell_grid.cell_size - cell_grid.half_extent

	_disk_shape = ConcavePolygonShape3D.new()
	# DECISION: single-sided: every face points out of the slab, so a block below the
	# surface past the rim is never pushed back up.
	_disk_shape.backface_collision = false
	_disk_owner_id = create_shape_owner(self)

	var faces: PackedVector3Array = PackedVector3Array()
	for cell: int in _in_disk_cells:
		var coords: Vector2i = cell_grid.cell_coords(cell)
		faces.append_array(_top_quad(coords.x, coords.y))
	# DECISION: rim walls, disk_height deep, so a block sliding off the edge meets a
	# side rather than a bare triangle edge (holes never cut the mesh).
	for cell: int in _in_disk_cells:
		var coords: Vector2i = cell_grid.cell_coords(cell)
		for dir: Vector2i in NEIGHBOUR_DIRS:
			var next: Vector2i = coords + dir
			if not _cell_in_disk(next.x, next.y):
				faces.append_array(_edge_wall(coords.x, coords.y, dir))

	_build_disk_mesh(faces)
	shape_owner_add_shape(_disk_owner_id, _disk_shape)

	var material: PhysicsMaterial = PhysicsMaterial.new()
	material.friction = tuning.disk_friction
	physics_material_override = material


## Rebuilds this Field for a different MapDef; Main calls it before place_flags().
func rebuild_for_map(new_map_def: MapDef) -> void:
	map_def = new_map_def
	_rebuild_cells()
	_build_kill_plane()
	_flags.map_def = map_def
	if _overlay != null:
		_overlay.configure(map_def, visuals, territory_tuning, disc_body_visuals, arena_side_style)


func _cell_in_disk(cx: int, cy: int) -> bool:
	var cell_grid: CellGrid = grid()
	return cell_grid.in_bounds(cx, cy) and _solid[cell_grid.cell_index(cx, cy)] == 1


## A quad (corners in order, either way round) as two triangles whose front faces
## point along `front`; the winding is picked from the corners' cross product.
func _quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, front: Vector3) -> PackedVector3Array:
	var counter_clockwise_normal: Vector3 = (p1 - p0).cross(p2 - p0)
	if counter_clockwise_normal.dot(front) > 0.0:
		return PackedVector3Array([p0, p3, p2, p0, p2, p1])
	return PackedVector3Array([p0, p1, p2, p0, p2, p3])


## The top face of cell (cx, cy), in the disk surface plane y = 0.
func _top_quad(cx: int, cy: int) -> PackedVector3Array:
	var x0: float = _grid_lines[cx]
	var x1: float = _grid_lines[cx + 1]
	var z0: float = _grid_lines[cy]
	var z1: float = _grid_lines[cy + 1]
	return _quad(Vector3(x0, 0.0, z0), Vector3(x1, 0.0, z0), Vector3(x1, 0.0, z1), Vector3(x0, 0.0, z1), Vector3.UP)


## The side of cell (cx, cy) facing `dir`, from the surface down to the underside.
func _edge_wall(cx: int, cy: int, dir: Vector2i) -> PackedVector3Array:
	var x0: float = _grid_lines[cx]
	var x1: float = _grid_lines[cx + 1]
	var z0: float = _grid_lines[cy]
	var z1: float = _grid_lines[cy + 1]
	var a: Vector3 = Vector3(x0, 0.0, z0)
	var b: Vector3 = Vector3(x1, 0.0, z0)
	if dir.x != 0:
		var x: float = x1 if dir.x > 0 else x0
		a = Vector3(x, 0.0, z0)
		b = Vector3(x, 0.0, z1)
	elif dir.y > 0:
		a = Vector3(x0, 0.0, z1)
		b = Vector3(x1, 0.0, z1)
	var down: Vector3 = Vector3(0.0, -map_def.disk_height, 0.0)
	return _quad(a, b, b + down, a + down, Vector3(float(dir.x), 0.0, float(dir.y)))


## Puts the disk's faces on its one shape; only at map build (set_faces() wakes everything).
func _build_disk_mesh(faces: PackedVector3Array) -> void:
	var started_usec: int = Time.get_ticks_usec()
	# DECISION: Jolt cannot build an empty mesh shape, so a degenerate map with no
	# in-disk cell disables the shape_owner instead.
	var empty: bool = faces.is_empty()
	if not empty:
		_disk_shape.set_faces(faces)
	if is_shape_owner_disabled(_disk_owner_id) != empty:
		shape_owner_set_disabled(_disk_owner_id, empty)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(TRACE_ARG):
			print("FIELD_DISK_REBUILD cells=%d triangles=%d usec=%d" % [
				_in_disk_cells.size(), faces.size() / 3, Time.get_ticks_usec() - started_usec,
			])


## Applies the raster's last hole diff. Both arrays are row-major CellGrid
## indices; they go on the backlog and drain per physics frame.
func set_hole_cells(opened: PackedInt32Array, closed: PackedInt32Array) -> void:
	_holes.want(opened, closed, _in_disk_cells)


## Applied hole cells right now. game/blocks/HoleDissolver.gd skips its per-tick
## contact test entirely while this is zero.
func applied_hole_count() -> int:
	return _holes.applied_count()


## True when this cell is currently an applied hole (dissolve contact; the disk
## collision stays solid). DECISION: reports the *applied* state: a cell the raster
## opened this frame still reads false while it waits in the backlog.
func is_hole_cell(index: int) -> bool:
	return _holes.is_applied(index)


## The ruleset's one physics query: a raycast straight down from the middle of
## the ghost block, from `map_def.cell_wake_height` above the disk to
## `tuning.kill_plane_y`, against the disk and every resting block. Returns the
## hit as disk-local (x, z), or null on a miss. Only the (x, z) of `world_origin`
## is read, and the heights go through world_from_disk_local(), so it stays
## correct while the disk tilts.
func raycast_down_disk_local(world_origin: Vector3) -> Variant:
	var space: PhysicsDirectSpaceState3D = direct_space()
	if space == null:
		return null
	var hit: Dictionary = raycast_disk_column(space, disk_local_from_world(world_origin))
	if hit.is_empty():
		return null
	return disk_local_from_world(hit["position"] as Vector3)


## The live physics space this field queries, or null out of the tree.
func direct_space() -> PhysicsDirectSpaceState3D:
	if not is_inside_tree():
		return null
	var world: World3D = get_world_3d()
	if world == null:
		return null
	return world.direct_space_state


## The straight-down column ray at disk-local `local_xz` (PLACEMENT_QUERY_MASK,
## bodies only): the raw intersect_ray() dictionary, empty on a miss.
func raycast_disk_column(space: PhysicsDirectSpaceState3D, local_xz: Vector2) -> Dictionary:
	var start: Vector3 = world_from_disk_local(local_xz, map_def.cell_wake_height)
	var end: Vector3 = world_from_disk_local(local_xz, tuning.kill_plane_y)
	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(start, end)
	params.collide_with_bodies = true
	params.collide_with_areas = false
	params.collision_mask = PLACEMENT_QUERY_MASK
	params.exclude = []
	return space.intersect_ray(params)


## Straight down from `origin` for `ray_length`, skipping any RigidBody3D so the
## first hit is the disk's own collision. Past `max_skips` skips it reports a miss
## ({}). Shared by PlayerController and GhostPreview.
static func raycast_disk_surface(
	space: PhysicsDirectSpaceState3D, origin: Vector3, ray_length: float, max_skips: int
) -> Dictionary:
	var exclude: Array[RID] = []
	var attempts: int = 0
	while attempts <= max_skips:
		var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			origin, origin + Vector3.DOWN * ray_length
		)
		params.exclude = exclude
		params.collision_mask = PLACEMENT_QUERY_MASK
		var hit: Dictionary = space.intersect_ray(params)
		if hit.is_empty():
			return {}
		if hit["collider"] is RigidBody3D:
			exclude.append(hit["rid"] as RID)
			attempts += 1
			continue
		return hit
	return {}


## Called by Main when a match's world comes down: drops the match's flags,
## overlay raster, holes and tilt so the field behind the menu, or a rehosted
## match, starts clean. DECISION: every hole closes synchronously and the backlog
## is discarded (the per-frame budget protects play-time cost only). No mesh
## rebuild: holes never cut the trimesh, and set_faces() wakes whatever rests on it.
func clear_match_state() -> void:
	_flags.clear()
	set_overlay_source(null, PackedColorArray())
	_holes.clear()
	# The Field outlives a match: reset the spring whether or not tilt is enabled
	# (set_tilt_enabled() alone no-ops on an enabled -> enabled transition). Also
	# drops mirror mode, PHYSICAL_BALANCE and its registry link.
	_tilt.reset()
	_wake_sync()
	_physical_balance_enabled = false
	_registry = null
	_apply_tilt_transform()
	_push_level_pose_to_physics()


func _build_overlay() -> void:
	_overlay = TerritoryOverlay.new()
	_overlay.name = &"DiskMesh"
	_overlay.configure(map_def, visuals, territory_tuning, disc_body_visuals, arena_side_style)
	_overlay.position = Vector3(0.0, -map_def.disk_height * 0.5, 0.0)
	add_child(_overlay)


# SHORTCUT: overlay() and the set_overlay_* pass-throughs stay on Field, until P5 gives the overlay its own owner.
func overlay() -> TerritoryOverlay:
	return _overlay


## Hands the overlay its raster and slot colors; the flags get the colors too (they
## arrive after place_flags).
func set_overlay_source(raster: TerritoryRaster, slot_colors: PackedColorArray) -> void:
	_flags.set_colors(slot_colors)
	if _overlay != null:
		_overlay.set_source(raster, slot_colors)


## Host-only "blocks are churning" flag; the overlay parks its bake until settle.
func set_overlay_churning(churning: bool, solve_waited_s: float = 0.0) -> void:
	if _overlay != null:
		_overlay.set_churning(churning, solve_waited_s)


## Routes the post-solve analytic circle list to the overlay (a hand-off only).
func set_overlay_circles(
	xs: PackedFloat32Array, zs: PackedFloat32Array, radii: PackedFloat32Array, teams: PackedInt32Array,
	goal_positions: PackedVector2Array, goal_radii: PackedFloat32Array, argmax_mode: bool
) -> void:
	if _overlay != null:
		_overlay.set_circles(xs, zs, radii, teams, goal_positions, goal_radii, argmax_mode)


func _build_flags() -> void:
	_flags = FieldFlags.new()
	_flags.name = &"FieldFlags"
	_flags.map_def = map_def
	_flags.visuals = visuals
	_flags.tuning = tuning
	_flags.home_flag_scene = home_flag_scene
	_flags.goal_flag_scene = goal_flag_scene
	add_child(_flags)


# SHORTCUT: place_flags, home_flags and goal_flags forward to FieldFlags, until the programs owning their callers (Main, Sandbox, PerchingBirds, CameraRig, SnowEffect) take the child directly.
func place_flags(slot_count: int, slot_colors: PackedColorArray, goal_count: int) -> void:
	var context: MatchContext = MatchContext.current()
	var config: MatchConfig = context.config()
	_flags.set_colors(slot_colors)
	_flags.place(
		slot_count, goal_count, context.goal_zone_visual_radius(), context.capture_hold_seconds(),
		config != null and config.game_mode == MatchConfig.GameMode.CAPTURE_THE_FLAG
	)


func home_flags() -> Array[HomeFlag]:
	return _flags.home_flags()


func goal_flags() -> Array[GoalFlag]:
	return _flags.goal_flags()


## Builds the kill-plane trigger; a rebuild frees the previous one (old map size).
func _build_kill_plane() -> void:
	if _kill_plane_area != null:
		_kill_plane_area.queue_free()
		_kill_plane_area = null
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
	# Host-only removal is BlockRegistry.remove_block's decision: the area fires on clients too.
	area.body_entered.connect(body_fell.emit)
	_kill_plane_area = area

