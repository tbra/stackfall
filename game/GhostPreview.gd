class_name GhostPreview
extends Node3D
## The non-physics held block (spec 2.5): floats at a height PlayerController
## reports (the disk surface plus hover_height plus the wheel's manual
## offset, Bontago-mv0.17 item 5 — never whatever is directly underneath the
## cursor), with a projected footprint (one convex polygon per bottom cell of
## the rotated held shape, item 6, Bontago-mv0.25) showing exactly what each
## part of it would land on.
##
## Bontago-mv0.25 (docs/rotation-issue.png, owner test 2026-09-22): the old
## drop-shadow quad under the ghost is gone -- the footprint is now the only
## ground marker (see config/GhostTuning.gd's DECISION). The footprint quads
## themselves used to always be axis-aligned unit squares whose *position*
## tracked the rotated shape but whose *shape* never did, so a rotated block's
## footprint markers stayed square/overlapping instead of showing the block's
## true rotated silhouette; each quad is now a real convex polygon built from
## that cell's own 8 rotated corners projected to the XZ plane
## (Geometry2D.convex_hull), rebuilt every frame alongside its position.
##
## Rotation is stored as an integer index over the 24 axis-aligned cube
## orientations (core/blocks/BlockOrientations.gd) plus a separate free-
## rotation quaternion layered on top. Resetting clears the quaternion and
## sets the index back to 0, so — unlike the original — rotation can never
## drift (spec 1.7, 2.5).
##
## M2 (spec 2.2, 2.5, docs/M2_PLAN.md P4) adds the placement-validity tint:
## player-colour when Match.preview_placement says VALID, red when it says
## OUTSIDE_TERRITORY/CONTESTED/OFF_DISK/EMPTY, and a hatched pattern over a
## HOLE. It also owns the visual side of a rejected placement (spec 2.2's
## "thrown off the map with a visible reject animation") and the auto-drop
## flash — both purely cosmetic; PlayerController decides *when* to play them.
##
## Territory v2 (docs/TERRITORY_V2_PLAN.md package C): a goal flag's no-build
## zone (Result.GOAL_ZONE) reads the same as HOLE — hatched, hole_tint_color —
## reusing the existing "can't build here" visual language rather than adding
## a fourth tint state or a new GhostTuning field.
##
## DECISION (game/GhostPreview.gd, Bontago-mv0.17 item 3 -- owner feel report
## "the ghost/body pivot is the block's middle"): this node's own origin
## (0, 0, 0) is BlockShape.bottom_center() of the *unrotated* shape (matching
## game/BlockFactory.gd's cell offsets), but rotation still happens about
## that same fixed local origin — after a 90-degree pitch/roll, that point is
## no longer the rotated shape's lowest point. update_placement() corrects
## for this every frame (_rotated_bottom_offset()) so the shape actually
## resting on the cursor's reported height is always the *rotated* one's
## lowest point, per the spec audit's "simplest correct behaviour" note,
## never the original's own "keep the block where it is and let it fall".

const STATE_VALID: StringName = &"valid"
const STATE_INVALID: StringName = &"invalid"
const STATE_HOLE: StringName = &"hole"
const STATE_LOCKED: StringName = &"locked"

const HATCH_TEXTURE_SIZE: int = 32

## The 8 corner signs of a unit box centred on its own local position, used by
## _rotated_bottom_offset() to find a rotated shape's true lowest point.
const _CORNER_SIGNS: Array[Vector3] = [
	Vector3(-1.0, -1.0, -1.0), Vector3(1.0, -1.0, -1.0), Vector3(-1.0, 1.0, -1.0), Vector3(1.0, 1.0, -1.0),
	Vector3(-1.0, -1.0, 1.0), Vector3(1.0, -1.0, 1.0), Vector3(-1.0, 1.0, 1.0), Vector3(1.0, 1.0, 1.0),
]

@export var tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
@export var ghost_tuning: GhostTuning = preload("res://config/ghost_tuning.tres")

var orientation_index: int = 0
var free_quaternion: Quaternion = Quaternion.IDENTITY
## Extra manual raise/lower on top of tuning.hover_height (hover_raise/lower).
var manual_hover_offset: float = 0.0

var _shape: BlockShape = null
var _shape_visual: Node3D = null
## Bontago-mv0.17 item 6: one quad per bottom cell of the *rotated* held
## shape, rebuilt (mesh and position) every time the shape/rotation/position
## changes (_update_footprint()). Replaces the old single vertical guide line;
## Bontago-mv0.25 replaced each quad's fixed unit-square mesh with a convex
## polygon matching that cell's own rotated silhouette.
var _footprint_quads: Array[MeshInstance3D] = []
## World-space XZ polygon currently shown by the footprint quad at the same
## index -- kept alongside _footprint_quads so tests can check the actual
## projected shape, not just where its center landed.
var _footprint_polygons: Array[PackedVector2Array] = []
## Shared by every footprint quad (like _material is shared by every mesh of
## the held shape's own visual) so updating validity/lock state once repaints
## all of them.
var _footprint_material: StandardMaterial3D

var _material: StandardMaterial3D
var _hatch_texture: ImageTexture
var _player_color: Color = Color.WHITE
var _last_result: PlacementRules.Result = PlacementRules.Result.VALID
## Bontago-mv0.10 (spec 2.4/2.5): whether this slot's held piece was released
## early this interval and is now only being aimed/prepared -- see
## Match.is_release_locked(). Overrides the validity tint below whenever true,
## since the lock is about *when* the piece may drop, not *where* the ghost
## sits.
var _locked: bool = false

var _flash_tween: Tween
var _reject_tween: Tween
## Bontago-mv0.25 (docs/rotation-issue.png): a world-space offset added on top
## of update_placement()/sync_remote_position()'s own computed position every
## frame, animated by play_reject_animation()'s kick tween. World-space (not
## a rotated local offset like the old _shape_visual.position kick) so the
## kick direction never depends on the held block's current rotation.
var _reject_offset: Vector3 = Vector3.ZERO


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_material.uv1_triplanar = true

	_footprint_material = StandardMaterial3D.new()
	_footprint_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_footprint_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_footprint_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_hatch_texture = _build_hatch_texture()
	_refresh_materials()


func set_shape(shape: BlockShape) -> void:
	_shape = shape
	if _shape_visual != null:
		_shape_visual.queue_free()
		_shape_visual = null
	if shape == null:
		return
	_shape_visual = BlockFactory.build_visual_only(shape, tuning)
	add_child(_shape_visual)
	_apply_material_to_visual()


func get_shape() -> BlockShape:
	return _shape


func set_orientation_index(index: int) -> void:
	orientation_index = ((index % BlockOrientations.ORIENTATION_COUNT) + BlockOrientations.ORIENTATION_COUNT) % BlockOrientations.ORIENTATION_COUNT
	_apply_rotation()


func reset_rotation() -> void:
	orientation_index = 0
	free_quaternion = Quaternion.IDENTITY
	_apply_rotation()


## Bontago-mv0.22 (spec 2.5 "Rotate block (hold + drag)" [ORIGINAL, owner test
## 2026-09-22]): PlayerController calls this while rotate_drag (MMB) is held,
## driving free_quaternion continuously -- already the exact field
## submit_cursor/submit_place send unmodified over the wire, so no new
## replication path was needed.
##
## Bontago-mv0.25 (docs/rotation-issue.png, owner test 2026-09-22, "like the
## RMB orbit but for the block"): full 3-DOF now, not yaw-only -- `yaw` spins
## about world up (matching CameraRig's own orbit yaw), `pitch` spins about
## `pitch_axis` (PlayerController passes the camera's current world-space
## right axis, so pitching the block always matches "push the mouse forward
## and it tips away from you" regardless of which way the camera currently
## faces). Each axis is composed onto free_quaternion independently
## (`Quaternion(axis, angle) * free_quaternion`, normalised) rather than
## pre-combined into one delta quaternion, so a frame with only one axis of
## motion (the common case) never even nudges the other.
func apply_free_rotation_delta(yaw: float, pitch: float, pitch_axis: Vector3 = Vector3.RIGHT) -> void:
	if yaw != 0.0:
		free_quaternion = (Quaternion(Vector3.UP, yaw) * free_quaternion).normalized()
	if pitch != 0.0:
		free_quaternion = (Quaternion(pitch_axis, pitch) * free_quaternion).normalized()
	_apply_rotation()


func _apply_rotation() -> void:
	var base_basis: Basis = BlockOrientations.get_basis(orientation_index)
	basis = Basis(free_quaternion) * base_basis


## Called every frame by PlayerController with the disk surface point/normal
## straight under the cursor (Bontago-mv0.17 item 5: a raycast that skips
## over any placed block, so this is always the bare disk, tilt-ready via
## `hit_normal` for M4). Positions the ghost at hover height above that
## surface, corrected so the *rotated* held shape's lowest point — not
## necessarily this node's own origin once rotated — is what actually sits at
## that height (item 3's rotated-bounds pivot), then refreshes the footprint
## projection (item 6).
func update_placement(surface_point: Vector3, surface_normal: Vector3) -> void:
	var hover: float = tuning.hover_height + manual_hover_offset
	var anchor: Vector3 = surface_point + surface_normal * hover
	var bottom_offset: float = _rotated_bottom_offset()
	global_position = Vector3(anchor.x, anchor.y - bottom_offset, anchor.z) + _reject_offset
	_update_footprint()


## Positions this ghost at an already-fully-resolved world point, with no
## further hover/rotation-pivot math applied on top -- used by
## game/RemoteCursors.gd for a synced remote peer's ghost, whose `origin` is
## that peer's own already-adjusted GhostPreview.global_position (spec 3.4's
## update_cursor carries a resolved pose, not a surface to re-derive one
## from). Re-running it through update_placement()'s hover/rotated-bottom
## math a second time would double-apply the correction for any slot whose
## held shape isn't null (Bontago-mv0.17 items 3/5); this is the one-line fix
## that keeps game/RemoteCursors.gd correct against the changed
## update_placement() contract above.
func sync_remote_position(origin: Vector3) -> void:
	global_position = origin + _reject_offset
	_update_footprint()


# --- Rotated-bottom pivot correction (spec 2.5, Bontago-mv0.17 item 3) ------

## How far below this node's own local origin (BlockShape.bottom_center() of
## the *unrotated* shape) the current, rotated shape's lowest point sits.
## Zero for an unrotated shape (the origin already is its lowest point); a
## 90-degree pitch/roll can put the true lowest point below (or, for a
## symmetric shape, level with) the origin, never above it, since the origin
## itself is always a point on the shape's own surface. Always <= 0.
func _rotated_bottom_offset() -> float:
	if _shape == null or _shape.cells.is_empty():
		return 0.0
	var half_size: float = (tuning.cube_size - tuning.cube_margin) * 0.5
	var pivot: Vector3 = _shape.bottom_center()
	var min_y: float = INF
	for cell: Vector3i in _shape.cells:
		var local: Vector3 = (Vector3(cell) - pivot) * tuning.cube_size
		for corner_sign: Vector3 in _CORNER_SIGNS:
			var corner: Vector3 = local + corner_sign * half_size
			var rotated_y: float = (basis * corner).y
			min_y = minf(min_y, rotated_y)
	return 0.0 if min_y == INF else min_y


# --- Footprint projection (spec 2.5, Bontago-mv0.17 item 6) -----------------

## One entry per distinct footprint the *rotated* held shape's cells project
## onto the XZ plane, ghost-local (not yet world-translated): each cell's own
## 8 corners (BlockFactory's own cube_size/cube_margin box, same pivot) go
## through the full rotation basis, get projected to (x, z), and their convex
## hull becomes that cell's footprint polygon -- at most a hexagon, per this
## package's brief, since a cube's silhouette under any rotation is convex
## with at most 6 sides. Cells that project to the same polygon (most
## commonly two cells stacked along whatever axis rotation currently maps to
## world up, e.g. an unrotated pillar) collapse to one entry via a
## rounded-vertex string key, so a stack still gets exactly one footprint
## quad -- not one per cell, and not a stale per-axis-aligned-column
## assumption that a continuous rotation would break.
##
## Bontago-mv0.25 (docs/rotation-issue.png): replaces the old
## _rotated_footprint_columns(), whose quads tracked each column's rotated
## *position* but were always drawn as a fixed axis-aligned unit square --
## exactly the bug the owner's screenshot shows (a rotated block, unrotated
## overlapping footprint squares).
func _rotated_footprint_cells() -> Array[Dictionary]:
	var cells_out: Array[Dictionary] = []
	if _shape == null or _shape.cells.is_empty():
		return cells_out
	var half_size: float = (tuning.cube_size - tuning.cube_margin) * 0.5
	var pivot: Vector3 = _shape.bottom_center()
	var seen: Dictionary = {}
	for cell: Vector3i in _shape.cells:
		var local_center: Vector3 = (Vector3(cell) - pivot) * tuning.cube_size
		var rotated_center: Vector3 = basis * local_center
		var points: PackedVector2Array = PackedVector2Array()
		for corner_sign: Vector3 in _CORNER_SIGNS:
			var rotated_corner: Vector3 = basis * (local_center + corner_sign * half_size)
			points.append(Vector2(rotated_corner.x, rotated_corner.z))
		var hull: PackedVector2Array = Geometry2D.convex_hull(points)
		if hull.size() < 3:
			continue
		var key: String = _hull_key(hull)
		if seen.has(key):
			continue
		seen[key] = true
		cells_out.append({"center": Vector2(rotated_center.x, rotated_center.z), "hull": hull})
	return cells_out


## Rounds and stringifies a hull's vertices as a dedup key for
## _rotated_footprint_cells() -- two cells whose rotated corners land on the
## same (rounded) set of 2D points are the same footprint.
func _hull_key(hull: PackedVector2Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for point: Vector2 in hull:
		parts.append("%.3f,%.3f" % [point.x, point.y])
	return ",".join(parts)


## Rebuilds the footprint quad pool to match the current shape/rotation and
## raycasts straight down through each cell's own rotated center (blocks
## included -- unlike PlayerController's disk-only probe, this is meant to
## land on a tower) to show exactly what each part of the held shape would
## rest on, with each quad's mesh reshaped to that cell's own rotated convex
## hull (see _build_polygon_mesh()) rather than a fixed unit square.
func _update_footprint() -> void:
	var cells: Array[Dictionary] = _rotated_footprint_cells()
	_set_footprint_quad_count(cells.size())
	_footprint_polygons.resize(cells.size())
	for i: int in range(cells.size()):
		var center: Vector2 = cells[i]["center"] as Vector2
		var hull: PackedVector2Array = cells[i]["hull"] as PackedVector2Array
		var world_x: float = global_position.x + center.x
		var world_z: float = global_position.z + center.y
		var probe_origin: Vector3 = Vector3(world_x, ghost_tuning.cursor_ray_height, world_z)
		var hit: Dictionary = _raycast_down(probe_origin)
		var landing_point: Vector3
		var landing_normal: Vector3
		if hit.is_empty():
			landing_point = Vector3(world_x, 0.0, world_z)
			landing_normal = Vector3.UP
		else:
			landing_point = hit["position"] as Vector3
			landing_normal = hit["normal"] as Vector3
		_footprint_quads[i].global_position = landing_point + landing_normal * ghost_tuning.footprint_offset
		_footprint_quads[i].mesh = _build_polygon_mesh(hull, center)
		var world_hull: PackedVector2Array = PackedVector2Array()
		for point: Vector2 in hull:
			world_hull.append(Vector2(global_position.x + point.x, global_position.z + point.y))
		_footprint_polygons[i] = world_hull


## Builds a flat (Y = 0 in its own local space), upward-facing triangle-fan
## mesh from `hull` (a convex polygon, in ghost-local XZ) recentered on
## `center` -- the point the caller positions the MeshInstance3D itself at --
## so the mesh's own vertices are the polygon's true rotated shape, not a
## fixed unit square. UVs tile at roughly one cube_size per unit so the hole
## hatch texture (uv1_scale in ghost_tuning.hatch_scale) still reads sensibly.
func _build_polygon_mesh(hull: PackedVector2Array, center: Vector2) -> ArrayMesh:
	var vertex_count: int = hull.size()
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in hull:
		var local: Vector2 = point - center
		verts.append(Vector3(local.x, 0.0, local.y))
		normals.append(Vector3.UP)
		uvs.append(Vector2(local.x / tuning.cube_size + 0.5, local.y / tuning.cube_size + 0.5))
	var indices: PackedInt32Array = PackedInt32Array()
	for i: int in range(1, vertex_count - 1):
		indices.append(0)
		indices.append(i)
		indices.append(i + 1)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var built: ArrayMesh = ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return built


func _raycast_down(origin: Vector3) -> Dictionary:
	if not is_inside_tree():
		return {}
	var world: World3D = get_world_3d()
	if world == null:
		return {}
	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	if space_state == null:
		return {}
	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		origin, origin + Vector3.DOWN * ghost_tuning.placement_ray_length
	)
	return space_state.intersect_ray(params)


func _set_footprint_quad_count(count: int) -> void:
	while _footprint_quads.size() < count:
		var quad: MeshInstance3D = _make_footprint_quad()
		add_child(quad)
		_footprint_quads.append(quad)
	while _footprint_quads.size() > count:
		var extra: MeshInstance3D = _footprint_quads.pop_back()
		extra.queue_free()


## For tests: how many footprint quads are currently shown (spec: one per
## bottom cell of the rotated held shape).
func footprint_quad_count() -> int:
	return _footprint_quads.size()


## For tests: where footprint quad `index` currently sits.
func footprint_quad_position(index: int) -> Vector3:
	return _footprint_quads[index].global_position


## For tests: the world-space (X, Z) convex polygon footprint quad `index` is
## currently showing -- the exact rotated silhouette of that cell, not just
## its center point (see footprint_quad_position()).
func footprint_polygon_world(index: int) -> PackedVector2Array:
	return _footprint_polygons[index]


# --- Ghost-vs-placed-block collision (Bontago-mv0.23, spec 2.5) -------------

## Local (unrotated), cell-local centers of the held shape's own collision
## boxes -- matching game/BlockFactory.gd's build() exactly (same cube_size/
## cube_margin and BlockShape.bottom_center() pivot) so game/PlayerController.
## gd's swept collision test lines up with the box the real spawned Block
## would occupy there. DECISION (game/GhostPreview.gd): duplicated rather
## than calling into BlockFactory's own private, static
## _make_collision_shape() -- BlockFactory is outside this package's file
## ownership, and this is the same few lines _rotated_bottom_offset()/
## _rotated_footprint_columns() above already compute for the same shape.
## Empty (not null) when nothing is held.
func collision_box_local_centers() -> Array[Vector3]:
	var centers: Array[Vector3] = []
	if _shape == null:
		return centers
	var pivot: Vector3 = _shape.bottom_center()
	for cell: Vector3i in _shape.cells:
		centers.append((Vector3(cell) - pivot) * tuning.cube_size)
	return centers


## Half-extent of one collision box, matching game/BlockFactory.gd's own
## `half_size` (see collision_box_local_centers()'s DECISION above). A sloped
## cell (ConvexPolygonShape3D in BlockFactory) is approximated as a full box
## here -- no shipped shape sets sloped_cells today (Bontago-mv0.17 removed
## the only one, config/blocks/wedge.tres), so this never runs against a
## shape it would misrepresent.
func collision_half_size() -> float:
	return (tuning.cube_size - tuning.cube_margin) * 0.5


# --- Placement validity tint (spec 2.2, 2.5) --------------------------------

## The active slot's colour, used for the VALID tint. Setting it re-applies
## the material immediately if the ghost is currently showing VALID, so a
## hot-seat turn change re-colours the ghost without waiting for the next
## preview_placement() poll.
func set_player_color(color: Color) -> void:
	_player_color = color
	if _last_result == PlacementRules.Result.VALID:
		_refresh_materials()


## Maps Match.preview_placement()'s advisory result onto the three tint
## states spec 2.5 calls for. Safe to call every frame.
func apply_validity(result: PlacementRules.Result) -> void:
	_last_result = result
	_refresh_materials()


## Bontago-mv0.10 (spec 2.4/2.5's "distinct timer-locked state"): whether this
## slot's held piece may be released right now. Called every frame alongside
## apply_validity() by game/PlayerController.gd; the locked tint wins over
## whatever validity state was just applied.
func set_locked(locked: bool) -> void:
	_locked = locked
	_refresh_materials()


func _refresh_materials() -> void:
	_apply_validity_material()
	_apply_footprint_material()


## For tests: which tint state the ghost is currently showing.
func current_state() -> StringName:
	if _locked:
		return STATE_LOCKED
	match _last_result:
		PlacementRules.Result.VALID:
			return STATE_VALID
		PlacementRules.Result.HOLE, PlacementRules.Result.GOAL_ZONE:
			return STATE_HOLE
		_:
			return STATE_INVALID


## For tests: the material colour currently applied to the held shape.
func current_tint_color() -> Color:
	return _material.albedo_color if _material != null else Color.WHITE


func _apply_validity_material() -> void:
	if _material == null:
		return
	if _locked:
		_material.albedo_texture = null
		_material.albedo_color = ghost_tuning.locked_tint_color
		return
	match _last_result:
		PlacementRules.Result.VALID:
			_material.albedo_texture = null
			_material.albedo_color = Color(_player_color.r, _player_color.g, _player_color.b, ghost_tuning.tint_color.a)
		PlacementRules.Result.HOLE, PlacementRules.Result.GOAL_ZONE:
			_material.albedo_texture = _hatch_texture
			_material.uv1_scale = Vector3(ghost_tuning.hatch_scale, ghost_tuning.hatch_scale, 1.0)
			_material.albedo_color = ghost_tuning.hole_tint_color
		_:
			_material.albedo_texture = null
			_material.albedo_color = ghost_tuning.invalid_tint_color


## Bontago-mv0.17 item 6: the footprint quads get the same validity/lock
## colours as the held shape's own body (_apply_validity_material() above),
## just at ghost_tuning.footprint_alpha instead of each state's own baked-in
## alpha -- a whole-footprint decal reads better a bit more transparent than
## the held shape itself, and every footprint quad shares this one material.
func _apply_footprint_material() -> void:
	if _footprint_material == null:
		return
	_footprint_material.albedo_color = _footprint_color_for_state()
	var hatched: bool = not _locked and (
		_last_result == PlacementRules.Result.HOLE or _last_result == PlacementRules.Result.GOAL_ZONE
	)
	if hatched:
		_footprint_material.albedo_texture = _hatch_texture
		_footprint_material.uv1_scale = Vector3(ghost_tuning.hatch_scale, ghost_tuning.hatch_scale, 1.0)
	else:
		_footprint_material.albedo_texture = null


## For tests: the footprint's own current tint colour (see current_tint_color()
## for the held shape's own body colour).
func current_footprint_tint_color() -> Color:
	return _footprint_material.albedo_color if _footprint_material != null else Color.WHITE


func _footprint_color_for_state() -> Color:
	if _locked:
		return _with_alpha(ghost_tuning.locked_tint_color, ghost_tuning.footprint_alpha)
	match _last_result:
		PlacementRules.Result.VALID:
			return _with_alpha(_player_color, ghost_tuning.footprint_alpha)
		PlacementRules.Result.HOLE, PlacementRules.Result.GOAL_ZONE:
			return _with_alpha(ghost_tuning.hole_tint_color, ghost_tuning.footprint_alpha)
		_:
			return _with_alpha(ghost_tuning.invalid_tint_color, ghost_tuning.footprint_alpha)


func _with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)


func _apply_material_to_visual() -> void:
	if _shape_visual == null:
		return
	for child: Node in _shape_visual.get_children():
		if child is MeshInstance3D:
			var mesh_instance: MeshInstance3D = child as MeshInstance3D
			mesh_instance.material_override = _material
			# DECISION (owner 2026-09-22, "the ghost has both the indicator and
			# a shadow"): the held block is a preview, so it casts no light
			# shadow; the projected footprint is its only ground marker.
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# --- Reject / auto-drop animation (spec 2.2, 2.5) ---------------------------

## Spec 2.2: "released [in a contested area] ... is thrown off the map with a
## visible reject animation" (docs/M2_PLAN.md owner decision 2: every invalid
## release burns the block, decided by Match.request_place — this is just the
## ghost-side cue: a bright flash plus a small arc kick on _reject_offset, a
## world-space position offset applied on top of update_placement()'s/
## sync_remote_position()'s own computed position every frame.
##
## Bontago-mv0.25 (docs/rotation-issue.png, owner test 2026-09-22): used to
## kick _shape_visual's own *local* position instead -- that offset rides
## along with the ghost's rotation basis (_shape_visual is a plain, non-
## top_level child), so a pitched or rolled held block's reject kick visibly
## went the wrong way (an "upward" kick could come out sideways or backwards
## depending on orientation). _reject_offset is a plain world-space vector
## added after rotation is applied, so the kick direction (world +X sideways,
## +Y up) never depends on the block's current rotation, while still
## surviving PlayerController re-homing the ghost's position every frame --
## the same reason the old local-offset trick existed in the first place.
func play_reject_animation() -> void:
	_flash_material(ghost_tuning.reject_flash_color, ghost_tuning.reject_flash_duration)
	if _reject_tween != null and _reject_tween.is_valid():
		_reject_tween.kill()
	_reject_offset = Vector3.ZERO
	var kick: Vector3 = Vector3(ghost_tuning.reject_arc_sideways, ghost_tuning.reject_arc_height, 0.0)
	var half_duration: float = ghost_tuning.reject_arc_duration * 0.5
	_reject_tween = create_tween()
	_reject_tween.tween_property(self, ^"_reject_offset", kick, half_duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_reject_tween.tween_property(self, ^"_reject_offset", Vector3.ZERO, half_duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## For tests: the reject arc's current world-space position offset (zero
## outside a reject animation).
func reject_offset() -> Vector3:
	return _reject_offset


## Spec 2.5: "When the timer runs out, the held block drops from its current
## ghost position." A quick neutral flash tells the player the drop was
## automatic, not a click.
func play_auto_drop_flash() -> void:
	_flash_material(ghost_tuning.auto_drop_flash_color, ghost_tuning.auto_drop_flash_duration)


func _flash_material(color: Color, duration: float) -> void:
	if _material == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	var restore_color: Color = _material.albedo_color
	_material.albedo_color = color
	_flash_tween = create_tween()
	_flash_tween.tween_property(_material, ^"albedo_color", restore_color, duration)


# --- Mesh / texture builders -------------------------------------------------

## Bontago-mv0.17 item 6: one flat polygon per bottom cell of the rotated
## held shape (replaces _make_guide_mesh()'s old vertical line), tinted by the
## shared _footprint_material so every quad repaints together when validity/
## lock state changes. Starts meshless -- _update_footprint() assigns each
## instance's real convex-hull mesh (_build_polygon_mesh()) every frame, since
## its shape depends on the held shape's current rotation.
func _make_footprint_quad() -> MeshInstance3D:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.material_override = _footprint_material
	mesh_instance.top_level = true
	return mesh_instance


## A small diagonal-stripe pattern (spec 2.5: "hatched pattern when over a
## hole"), generated once instead of shipped as an art asset. Tiled across
## the held shape via ghost_tuning.hatch_scale (StandardMaterial3D.uv1_scale).
func _build_hatch_texture() -> ImageTexture:
	var image: Image = Image.create(HATCH_TEXTURE_SIZE, HATCH_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var period: float = float(HATCH_TEXTURE_SIZE) / 4.0
	for y: int in range(HATCH_TEXTURE_SIZE):
		for x: int in range(HATCH_TEXTURE_SIZE):
			var phase: float = fmod(float(x + y), period) / period
			var opaque: bool = phase < ghost_tuning.hatch_stripe_width
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, 1.0 if opaque else 0.0))
	return ImageTexture.create_from_image(image)
