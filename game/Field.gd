class_name Field
extends AnimatableBody3D
## The match field: a disk (spec 2.1). Plain StaticBody3D through M1/M2 (no
## tilt). From M4 (Bontago M4 P0b) it is an AnimatableBody3D so the
## SPECIALS_ONLY tilt (spec 2.1, 2.7, 3.5) can carry resting blocks along with
## it; AnimatableBody3D is a kinematic special case of StaticBody3D (Jolt and
## Godot both treat it as static collision the physics step sees moved, not
## simulated), so every existing shape-owner/collision API below keeps
## working unchanged. `PHYSICAL_BALANCE` tilt (a RigidBody3D on a joint) is
## M6 scope, out of this package.
##
## **Cells (spec 3.3).** The disk's collision is one ConcavePolygonShape3D on
## one shape owner (Bontago-ruw, docs/M4_PLAN.md P0a): a trimesh with one
## `map_def.cell_size` quad per solid in-disk cell of the square CellGrid, plus
## vertical walls wherever a solid cell meets a hole or the rim. One cell is
## one CellGrid index is one pixel of the territory raster, so the rules, the
## picture and the collision can never disagree about where a hole is. A hole
## is that cell's quad left out of the mesh: an exact cell_size opening with
## nothing overhanging it. The toggles are batched at
## `TerritoryTuning.max_cell_toggles_per_frame` per physics frame through a
## FIFO backlog, the mesh is rebuilt at most once per physics frame (only when
## a toggle was applied), and every body above a cell that changed is woken,
## because a sleeping tower would otherwise sit happily on collision that is
## no longer there.
##
## The trimesh replaced one BoxShape3D per cell, grown by MapDef.cell_overlap
## so towers stood on the boxes' flat middles past Jolt's convex rounding.
## That overlap left a lone hole only cell_size - cell_overlap wide, so a 1 m
## block could not fall into it; a mesh has neither the per-cell rounding nor
## the overhang, so Field no longer reads cell_overlap.
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
## Two triangles, three vertices each, per quad of the disk trimesh.
const VERTS_PER_QUAD: int = 6
## The four edge neighbours of a cell, in CellGrid (cx, cy) steps.
const NEIGHBOUR_DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]
## --trace-disk=<rebuilds>: print the disk trimesh rebuild time every N
## rebuilds (1 = every rebuild); 0, the default, prints nothing. Same pattern
## as tests/bench/bench_tower.gd's --trace=, under its own name so tracing a
## tower does not also flood the log with rebuild lines. Passed after `--`:
##   godot --headless --path . res://tests/bench/bench_tower.tscn -- --trace-disk=1
const TRACE_ARG_PREFIX: String = "--trace-disk="

@export var map_def: MapDef = preload("res://config/maps/round_medium.tres")
@export var tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
@export var tilt_tuning: TiltTuning = preload("res://config/tilt_tuning.tres")
@export var territory_tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")
@export var visuals: TerritoryVisuals = preload("res://config/territory_visuals.tres")
@export var home_flag_scene: PackedScene = preload("res://game/HomeFlag.tscn")
@export var goal_flag_scene: PackedScene = preload("res://game/GoalFlag.tscn")

var _grid: CellGrid = null
## cell index -> the disk's shape owner id, or -1 for a cell outside the disk.
##
## DECISION (game/Field.gd, Bontago-ruw): cell_owner_id() keeps its contract
## ("-1 means no collision cell here"), but every in-disk cell now reports the
## same id, the one owner of the disk trimesh, because per-cell owners no
## longer exist. Nothing outside Field and its tests reads the id itself.
var _cell_owner_ids: PackedInt32Array = PackedInt32Array()
var _in_disk_cells: PackedInt32Array = PackedInt32Array()
## 1 where the cell's quad is currently left out of the disk trimesh.
var _hole_applied: PackedByteArray = PackedByteArray()
## 1 where the rules want the cell to be a hole; the backlog is the difference.
var _hole_wanted: PackedByteArray = PackedByteArray()
## FIFO backlog of (cell, disabled) pairs, consumed from _toggle_head so that
## draining never has to shift a PackedInt32Array.
var _toggle_cells: PackedInt32Array = PackedInt32Array()
var _toggle_disabled: PackedByteArray = PackedByteArray()
var _toggle_head: int = 0

## The disk's one collision shape and the one shape owner carrying it.
var _disk_shape: ConcavePolygonShape3D = null
var _disk_owner_id: int = -1
## Grid line coordinates, disk-local meters: line i is the -x (or -z) edge of
## column (or row) i, so cell (cx, cy) spans lines cx..cx+1 and cy..cy+1.
var _grid_lines: PackedFloat32Array = PackedFloat32Array()
## Top quad of every in-disk cell, VERTS_PER_QUAD vertices each, in
## _in_disk_cells order, built once so a rebuild copies slices of it.
var _top_faces: PackedVector3Array = PackedVector3Array()
## Per grid row: where the row's in-disk cells start in _in_disk_cells, how
## many there are (the disk is convex, so they are contiguous), and how many
## are applied holes. A row with no hole is copied as one slice.
var _row_first_slot: PackedInt32Array = PackedInt32Array()
var _row_slot_count: PackedInt32Array = PackedInt32Array()
var _row_hole_count: PackedInt32Array = PackedInt32Array()
var _applied_hole_total: int = 0
## Rim walls (a solid cell's side facing out of the disk): the cell each one
## belongs to, and its VERTS_PER_QUAD vertices. Left out while that cell is a hole.
var _rim_wall_cells: PackedInt32Array = PackedInt32Array()
var _rim_wall_faces: PackedVector3Array = PackedVector3Array()
## --trace-disk bookkeeping.
var _trace_every: int = 0
var _rebuild_count: int = 0
var _max_rebuild_usec: int = 0

## SPECIALS_ONLY tilt (spec 2.1, 2.7, 3.5). Off by default so a Field nobody
## has called set_tilt_enabled(true) on -- every scene and test that predates
## this package -- behaves exactly as before: sync_to_physics carries no
## rotation because _physics_process() never writes one.
var _tilt_enabled: bool = false
## The 2-axis tilt vector the critically damped spring integrates: x is the
## rotation (radians) about the disk's local X axis, y about its local Z
## axis. Chosen to read the same way disk-local (x, z) already does
## everywhere else in this file, not because it is a literal disk-local
## point.
var _tilt: Vector2 = Vector2.ZERO
var _tilt_velocity: Vector2 = Vector2.ZERO

var _overlay: TerritoryOverlay = null
var _home_flags: Array[HomeFlag] = []
var _goal_flags: Array[GoalFlag] = []
var _slot_colors: PackedColorArray = PackedColorArray()


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(TRACE_ARG_PREFIX):
			_trace_every = maxi(arg.substr(TRACE_ARG_PREFIX.length()).to_int(), 0)
	# DECISION (game/Field.gd, Bontago M4 P0b): AnimatableBody3D defaults
	# sync_to_physics to true (verified against this exact build, not assumed
	# from the docs), which -- as test_field_cells.gd's
	# test_coordinates_follow_the_field_transform demonstrated -- makes Godot
	# stop honouring a direct transform/global_position write made outside a
	# physics tick, silently holding the node at its last physics-synced
	# transform instead. Explicitly forcing it false here, and only flipping
	# it true from set_tilt_enabled(true), keeps every caller that places the
	# field itself (this scene, Main, that test) working exactly as it did as
	# a StaticBody3D, right up until a match actually turns tilt on.
	sync_to_physics = false
	_build_cells()
	_build_kill_plane()
	_build_overlay()
	Events.hole_cells_changed.connect(_on_hole_cells_changed)
	Events.goal_capture_progress.connect(_on_goal_capture_progress)


func _physics_process(delta: float) -> void:
	_drain_toggles()
	if _tilt_enabled:
		_update_tilt(delta)


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


# --- Tilt (SPECIALS_ONLY, spec 2.1, 2.7, 3.5) --------------------------------
#
# Only PlayerSlot/Match-side wiring decides *when* this runs: Field itself
# just carries the flag. Defaults to false so nothing about this package
# changes behaviour for a caller that never touches it.

## The smallest typed setter Match needs to turn tilt on for a
## `tilt_mode == SPECIALS_ONLY` match (autoload/Match.gd already has the one
## configure()/clear_match_state() path that reaches Field; wiring an actual
## call from there is left to whichever package next reads MatchConfig into
## Field, per this package's scope). Disabling mid-match also snaps the tilt
## itself back to level rather than leaving it wherever the spring stopped,
## since a mode switch that is not a fresh match should not leave stale
## rotation behind.
##
## DECISION (game/Field.gd, Bontago M4 P0b): `sync_to_physics` (spec 3.5: "the
## disk is an AnimatableBody3D with sync_to_physics = true") is flipped on
## here, not unconditionally in _ready(). Once it is true, Godot's kinematic
## body only accepts transform writes made through the physics step and
## otherwise holds the node at its last physics-synced transform -- so
## test_field_cells.gd's test_coordinates_follow_the_field_transform (setting
## field.global_position once, outside any physics tick, to place the whole
## disk) silently stopped taking effect the moment sync_to_physics was ever
## true, tilt or no tilt. Gating it on the same flag that turns tilt on keeps
## every existing direct-transform caller (placing the field itself in the
## world) working exactly as before right up until a match actually turns
## tilt on, which is the only time anything needs the physics-synced path.
func set_tilt_enabled(enabled: bool) -> void:
	if _tilt_enabled == enabled:
		return
	_tilt_enabled = enabled
	sync_to_physics = enabled
	if not enabled:
		_tilt = Vector2.ZERO
		_tilt_velocity = Vector2.ZERO
		_apply_tilt_transform()


func tilt_enabled() -> bool:
	return _tilt_enabled


## Current tilt vector (radians, disk-local X/Z rotation angles as documented
## on _tilt above). Read-only; tests use it to check the spring's motion and
## its clamp without waiting out real seconds of physics frames.
func tilt_vector() -> Vector2:
	return _tilt


## The one public entry point a special (Anvil, Fan, Earthquake -- P5) uses to
## push the disk. `direction` is a disk-local XZ unit vector; `magnitude` is
## an impulse into the spring model (added to the tilt vector's velocity, unit
## "mass"), not a direct angle -- the critically damped spring then eases the
## disk back toward level over roughly tilt_tuning.return_time_constant_s.
## A no-op while tilt is disabled, so a special fired under `PHYSICAL_BALANCE`
## (or before any match wires tilt on at all) cannot leave Field with a
## velocity that only shows up the moment something else enables it later.
##
## DECISION (game/Field.gd, Bontago M4 P0b): direction (dx, dz) is turned into
## a velocity kick on (rotation about local X, rotation about local Z) via
## Vector2(dz, -dx) * magnitude. That is the unique small-angle decomposition
## whose combined rotation moves the disk surface point at unit offset
## `direction` downward by exactly `magnitude` radians (a first-order
## expansion of rotating around the horizontal axis perpendicular to
## `direction`, i.e. treating the two single-axis rotations Field already
## keeps as state as independent contributions rather than composing them as
## one single-axis tilt) -- so "hit the disk over there" reads as "that side
## dips", the same intuition apply_tilt_impulse's own doc promises callers.
func apply_tilt_impulse(direction: Vector2, magnitude: float) -> void:
	if not _tilt_enabled:
		return
	var dir: Vector2 = direction.normalized()
	if dir == Vector2.ZERO or magnitude == 0.0:
		return
	_tilt_velocity += Vector2(dir.y, -dir.x) * magnitude


## One physics tick of the critically damped spring (x'' + 2*omega*x'
## + omega^2*x = 0 pulling _tilt back toward Vector2.ZERO), then the
## max_tilt_deg clamp, then the transform write sync_to_physics carries to
## Jolt. Split out from _physics_process so tests can step the dynamics
## directly without waiting on real engine frames.
func _update_tilt(delta: float) -> void:
	var stiffness: float = tilt_tuning.spring_stiffness()
	var damping: float = tilt_tuning.spring_damping()
	var accel: Vector2 = (-stiffness * _tilt) - (damping * _tilt_velocity)
	_tilt_velocity += accel * delta
	_tilt += _tilt_velocity * delta
	_clamp_tilt()
	_apply_tilt_transform()


## Clamps _tilt's magnitude to tilt_tuning.max_tilt_deg regardless of how many
## apply_tilt_impulse() calls landed this frame or how large any one of them
## was -- the clamp runs once per integrated step, after every impulse queued
## for that step has already been folded into _tilt_velocity. Also drops the
## outward-pointing part of the velocity at the clamp so a saturated hit does
## not keep re-clamping every subsequent frame while it decays.
func _clamp_tilt() -> void:
	var max_rad: float = tilt_tuning.max_tilt_rad()
	var magnitude: float = _tilt.length()
	if magnitude <= max_rad or magnitude <= 0.0:
		return
	var outward: Vector2 = _tilt / magnitude
	var radial_speed: float = _tilt_velocity.dot(outward)
	if radial_speed > 0.0:
		_tilt_velocity -= outward * radial_speed
	_tilt = outward * max_rad


## Builds the disk's rotation from the tilt vector as two independent
## small-angle rotations (see apply_tilt_impulse's DECISION above): first
## about the local Z axis (tilt.y), then about the local X axis (tilt.x).
## Composing in a fixed order makes the transform this writes and the
## impulse math above exact inverses of each other regardless of which order
## was picked, which is all a NEW system with no original geometry to match
## needs.
func _tilt_basis(tilt: Vector2) -> Basis:
	return Basis(Vector3.RIGHT, tilt.x) * Basis(Vector3.BACK, tilt.y)


## Writes the tilt into this Node3D's own local transform (never the parent's)
## so disk_local_from_world()/world_from_disk_local() -- already plain
## to_local()/to_global() -- pick it up through the live global_transform with
## no code change of their own, and so the rotation pivots on Field's own
## origin (spec 2.1 "the disk pivots around its center").
func _apply_tilt_transform() -> void:
	transform = Transform3D(_tilt_basis(_tilt), transform.origin)


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
	_applied_hole_total = 0

	# DECISION (game/Field.gd, Bontago-ruw): quad corners come from shared grid
	# lines (i * cell_size - half_extent, CellGrid's own origin offset) rather
	# than from index_center() +/- cell_size / 2 per cell. They are the same
	# points (index_center() is the midpoint of two lines), but computed once
	# per line, neighbouring quads share bit-identical vertices, so Jolt sees
	# one welded surface with no hairline seams between cells.
	_grid_lines = PackedFloat32Array()
	_grid_lines.resize(cell_grid.res + 1)
	for line: int in range(cell_grid.res + 1):
		_grid_lines[line] = float(line) * cell_grid.cell_size - cell_grid.half_extent

	_row_first_slot = PackedInt32Array()
	_row_first_slot.resize(cell_grid.res)
	_row_first_slot.fill(-1)
	_row_slot_count = PackedInt32Array()
	_row_slot_count.resize(cell_grid.res)
	_row_hole_count = PackedInt32Array()
	_row_hole_count.resize(cell_grid.res)

	_disk_shape = ConcavePolygonShape3D.new()
	# DECISION (game/Field.gd, Bontago-ruw): single-sided (backface_collision
	# off, the default). Every face points out of the disk slab (up, or out of
	# a cell side into a hole or past the rim), so a block that has already
	# dropped below the surface into a hole is never pushed back up by the
	# underside of a neighbour's top quad.
	_disk_shape.backface_collision = false
	_disk_owner_id = create_shape_owner(self)

	_top_faces = PackedVector3Array()
	for slot: int in range(_in_disk_cells.size()):
		var cell: int = _in_disk_cells[slot]
		var coords: Vector2i = cell_grid.cell_coords(cell)
		if _row_first_slot[coords.y] < 0:
			_row_first_slot[coords.y] = slot
		_row_slot_count[coords.y] += 1
		_cell_owner_ids[cell] = _disk_owner_id
		_top_faces.append_array(_top_quad(coords.x, coords.y))

	# DECISION (game/Field.gd, Bontago-ruw): the plan names only the top quads;
	# the mesh also carries vertical walls, disk_height deep, on every solid
	# cell side that faces a hole or the rim, where the old boxes' sides
	# stood. A block tipping or sliding into a hole then meets a side that
	# pushes it off sideways, not a bare triangle edge that can pop it back up
	# onto the surface. Walls cost boundary cells only, not the whole disk.
	_rim_wall_cells = PackedInt32Array()
	_rim_wall_faces = PackedVector3Array()
	for cell: int in _in_disk_cells:
		var coords: Vector2i = cell_grid.cell_coords(cell)
		for dir: Vector2i in NEIGHBOUR_DIRS:
			var next: Vector2i = coords + dir
			if not _cell_in_disk(next.x, next.y):
				_rim_wall_cells.append(cell)
				_rim_wall_faces.append_array(_edge_wall(coords.x, coords.y, dir))

	# Faces first, then the shape onto the owner, so Jolt never sees an empty mesh.
	_rebuild_disk_mesh()
	shape_owner_add_shape(_disk_owner_id, _disk_shape)

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


func _cell_in_disk(cx: int, cy: int) -> bool:
	var cell_grid: CellGrid = grid()
	if not cell_grid.in_bounds(cx, cy):
		return false
	return _cell_owner_ids[cell_grid.cell_index(cx, cy)] >= 0


func _cell_solid(cx: int, cy: int) -> bool:
	if not _cell_in_disk(cx, cy):
		return false
	return _hole_applied[grid().cell_index(cx, cy)] == 0


# --- Disk trimesh (Bontago-ruw) ---------------------------------------------

## A quad as two triangles whose front faces point along `front`. Godot takes
## clockwise-wound triangles as front faces; the winding is picked from the
## corners' own cross product so no caller has to get it right by hand.
## Corners go round the quad in order, either way round.
func _quad(
	p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, front: Vector3
) -> PackedVector3Array:
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
	return _quad(
		Vector3(x0, 0.0, z0), Vector3(x1, 0.0, z0),
		Vector3(x1, 0.0, z1), Vector3(x0, 0.0, z1),
		Vector3.UP
	)


## The side of solid cell (cx, cy) that faces `dir`, from the surface down to
## the disk's underside, its front face pointing out of the cell.
func _edge_wall(cx: int, cy: int, dir: Vector2i) -> PackedVector3Array:
	var x0: float = _grid_lines[cx]
	var x1: float = _grid_lines[cx + 1]
	var z0: float = _grid_lines[cy]
	var z1: float = _grid_lines[cy + 1]
	# dir (0, -1), the -z side, unless one of the branches below says otherwise.
	var a: Vector3 = Vector3(x0, 0.0, z0)
	var b: Vector3 = Vector3(x1, 0.0, z0)
	if dir.x > 0:
		a = Vector3(x1, 0.0, z0)
		b = Vector3(x1, 0.0, z1)
	elif dir.x < 0:
		a = Vector3(x0, 0.0, z0)
		b = Vector3(x0, 0.0, z1)
	elif dir.y > 0:
		a = Vector3(x0, 0.0, z1)
		b = Vector3(x1, 0.0, z1)
	var down: Vector3 = Vector3(0.0, -map_def.disk_height, 0.0)
	return _quad(a, b, b + down, a + down, Vector3(float(dir.x), 0.0, float(dir.y)))


## Walls around one applied hole: each solid neighbour's side facing into it.
func _append_hole_walls(faces: PackedVector3Array, hole_cell: int) -> void:
	var coords: Vector2i = grid().cell_coords(hole_cell)
	for dir: Vector2i in NEIGHBOUR_DIRS:
		var next: Vector2i = coords + dir
		if _cell_solid(next.x, next.y):
			faces.append_array(_edge_wall(next.x, next.y, -dir))


## Rebuilds the whole disk trimesh from _hole_applied. set_faces() takes the
## whole face array (no partial update), so this is O(in-disk cells), but a
## row without a hole is one native slice copy and GDScript only walks the
## cells of rows that hold holes. Called at most once per physics frame by
## _drain_toggles(), plus once at build and once per clear_match_state().
func _rebuild_disk_mesh() -> void:
	var started_usec: int = Time.get_ticks_usec()
	var faces: PackedVector3Array = PackedVector3Array()
	for cy: int in range(_row_slot_count.size()):
		var count: int = _row_slot_count[cy]
		if count == 0:
			continue
		var first: int = _row_first_slot[cy]
		var end: int = first + count
		if _row_hole_count[cy] == 0:
			faces.append_array(_top_faces.slice(first * VERTS_PER_QUAD, end * VERTS_PER_QUAD))
			continue
		var run_start: int = -1
		for slot: int in range(first, end):
			var cell: int = _in_disk_cells[slot]
			if _hole_applied[cell] == 1:
				if run_start >= 0:
					faces.append_array(
						_top_faces.slice(run_start * VERTS_PER_QUAD, slot * VERTS_PER_QUAD)
					)
					run_start = -1
				_append_hole_walls(faces, cell)
			elif run_start < 0:
				run_start = slot
		if run_start >= 0:
			faces.append_array(_top_faces.slice(run_start * VERTS_PER_QUAD, end * VERTS_PER_QUAD))

	if _applied_hole_total == 0:
		faces.append_array(_rim_wall_faces)
	else:
		for wall: int in range(_rim_wall_cells.size()):
			if _hole_applied[_rim_wall_cells[wall]] == 0:
				faces.append_array(
					_rim_wall_faces.slice(wall * VERTS_PER_QUAD, (wall + 1) * VERTS_PER_QUAD)
				)

	# DECISION (game/Field.gd, Bontago-ruw): a disk whose every cell is a hole
	# has no triangles, and Jolt cannot build an empty mesh shape, so the owner
	# is disabled instead and the last non-empty faces stay on it unused.
	var empty: bool = faces.is_empty()
	if not empty:
		_disk_shape.set_faces(faces)
	if is_shape_owner_disabled(_disk_owner_id) != empty:
		shape_owner_set_disabled(_disk_owner_id, empty)

	_rebuild_count += 1
	var elapsed_usec: int = Time.get_ticks_usec() - started_usec
	_max_rebuild_usec = maxi(_max_rebuild_usec, elapsed_usec)
	if _trace_every > 0 and _rebuild_count % _trace_every == 0:
		print(
			"FIELD_DISK_REBUILD n=%d cells=%d holes=%d triangles=%d usec=%d max_usec=%d" % [
				_rebuild_count, _in_disk_cells.size(), _applied_hole_total,
				faces.size() / 3, elapsed_usec, _max_rebuild_usec,
			]
		)


## Flips one cell's applied hole state and the per-row counts the rebuild
## reads. The caller rebuilds the mesh, once per batch.
func _set_hole_applied(cell: int, hole: bool) -> void:
	var value: int = 1 if hole else 0
	if _hole_applied[cell] == value:
		return
	_hole_applied[cell] = value
	var step: int = 1 if hole else -1
	_row_hole_count[grid().cell_coords(cell).y] += step
	_applied_hole_total += step


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


## True when this cell's quad is currently left out of the disk trimesh.
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
		if _cell_owner_ids[cell] < 0:
			continue
		if (_hole_applied[cell] == 1) == disabled:
			continue
		_set_hole_applied(cell, disabled)
		applied.append(cell)
	if _toggle_head >= _toggle_cells.size():
		_toggle_cells = PackedInt32Array()
		_toggle_disabled = PackedByteArray()
		_toggle_head = 0
	if not applied.is_empty():
		# One rebuild for the whole batch, before the wake, so the woken bodies
		# step against the new surface.
		_rebuild_disk_mesh()
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


# --- Placement validity raycast (docs/TERRITORY_V2_PLAN.md) -----------------

## The v2 ruleset's one physics query (owner clarifications 2026-09-20): "just
## do a raycast from the middle of the ghost block and straight down". Casts
## from `map_def.cell_wake_height` above the disk down to `tuning.kill_plane_y`
## against the live physics world (the disk's own cell collision and every
## resting block), and returns the hit point converted to disk-local (x, z),
## or null when nothing was hit (only possible off the rim with nothing
## beneath).
##
## Deliberately independent of however `world_origin` itself was aimed —
## PlayerController's own ghost-follow ray can graze the side of a tower at an
## angle; this always asks "what is directly beneath the ghost's current
## position", straight down along the disk's own vertical axis.
##
## DECISION (game/Field.gd): the start/end heights are read off through
## world_from_disk_local() (disk-local (x, z) plus a height) rather than by
## building world-space points directly from `world_origin.y`, `cell_
## wake_height` and `kill_plane_y` as bare world Y values. That matches how
## Field's own wake_blocks_above_cells() and _build_kill_plane() already treat
## those two numbers — as heights along the disk's own axis, converted through
## the disk's transform — so this raycast keeps working unchanged once M4 lets
## Field tilt (disk_local_from_world()/world_from_disk_local() are documented
## as "the only two functions that change" then). `world_origin.y` itself is
## never read: only its (x, z) projection onto the disk matters here.
func raycast_down_disk_local(world_origin: Vector3) -> Variant:
	if not is_inside_tree():
		return null
	var world: World3D = get_world_3d()
	if world == null:
		return null
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	if space == null:
		return null

	var local_xz: Vector2 = disk_local_from_world(world_origin)
	var start: Vector3 = world_from_disk_local(local_xz, map_def.cell_wake_height)
	var end: Vector3 = world_from_disk_local(local_xz, tuning.kill_plane_y)
	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(start, end)
	params.collide_with_bodies = true
	params.collide_with_areas = false
	params.exclude = []

	var hit: Dictionary = space.intersect_ray(params)
	if hit.is_empty():
		return null
	return disk_local_from_world(hit["position"] as Vector3)


## Called by game/Main.gd's _end_match_world() when a match's world comes down
## (Beads Bontago-mv0.1.9): drops every trace of the match that just ended --
## its flags, the overlay's reference to its raster, and every hole it opened
## -- so the field sitting behind the main menu (or a fresh rehosted match)
## starts from nothing left over. Field is a persistent node (unlike HotSeat,
## RemoteCursors and NetDebugOverlay, which Main frees and rebuilds), so
## nobody else resets this state: Match's own teardown (_reset_match_state())
## clears its blocks and slots, never Field's.
##
## DECISION (game/Field.gd): the hole backlog normally drains at
## TerritoryTuning.max_cell_toggles_per_frame per physics frame
## (_drain_toggles(), spec 3.3) so opening many holes at once cannot spike one
## frame's physics cost during play. At teardown there is no future frame
## whose budget is worth protecting -- the field sits idle behind a menu until
## the next match -- and a hole left open, or a toggle left queued, until the
## backlog happens to catch up is exactly the leak this method exists to
## close. So every applied hole is closed synchronously here instead of
## through the backlog, and the backlog itself is discarded rather than
## drained.
func clear_match_state() -> void:
	_clear_flags()
	set_overlay_source(null, PackedColorArray())
	var had_holes: bool = _applied_hole_total > 0
	for cell: int in _in_disk_cells:
		_set_hole_applied(cell, false)
		_hole_wanted[cell] = 0
	_toggle_cells = PackedInt32Array()
	_toggle_disabled = PackedByteArray()
	_toggle_head = 0
	if had_holes:
		_rebuild_disk_mesh()
	# Bontago-1en.9 review: the Field outlives a match, so a tilt (and its
	# velocity) left over from the previous match must not carry into the next
	# one. Reset the spring state whether or not tilt is currently enabled;
	# set_tilt_enabled() alone would no-op on an enabled -> enabled transition.
	_tilt = Vector2.ZERO
	_tilt_velocity = Vector2.ZERO
	_apply_tilt_transform()


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


## Routes the post-solve analytic circle list to the overlay (Bontago-cmc.5).
## Field decides nothing here, same contract as set_overlay_source() above:
## autoload/Match.gd builds the list (host) or net/MatchNet.gd decodes it
## (client), and this is only the hand-off.
func set_overlay_circles(
	xs: PackedFloat32Array,
	zs: PackedFloat32Array,
	radii: PackedFloat32Array,
	teams: PackedInt32Array,
	goal_positions: PackedVector2Array,
	goal_radii: PackedFloat32Array,
	argmax_mode: bool
) -> void:
	if _overlay != null:
		_overlay.set_circles(xs, zs, radii, teams, goal_positions, goal_radii, argmax_mode)


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
	# DECISION (M3a integration): a client's synced blocks are frozen-kinematic
	# mirrors (docs/M3a_PLAN.md "Frozen bodies") whose transforms SnapshotSync
	# writes directly, so the kill-plane Area3D still overlaps and fires this
	# callback there too even though only the host runs physics (CLAUDE.md).
	# Only the host may decide a block is dead; a client learns about it from
	# MatchNet.net_block_despawned instead (net/MatchNet.gd), so it must not
	# free the body itself here — doing so races the replicated despawn and
	# can double-free or desync the registry.
	if not Net.is_host():
		return
	var rigid_body: RigidBody3D = body as RigidBody3D
	if rigid_body == null:
		return
	Events.block_removed.emit(rigid_body, String(Events.REASON_KILL_PLANE))
	rigid_body.queue_free()
