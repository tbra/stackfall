class_name GhostPreview
extends Node3D
## The non-physics held block (spec 2.5): floats at a height PlayerController
## reports (the disk surface plus hover_height plus the wheel's manual
## offset, Bontago-mv0.17 item 5 — never whatever is directly underneath the
## cursor), with a projected footprint (one convex polygon for the *whole*
## rotated held shape's silhouette, item 6, Bontago-xtq.7) showing exactly
## what it would land on.
##
## Bontago-mv0.25 (docs/rotation-issue.png, owner test 2026-09-22): the old
## drop-shadow quad under the ghost is gone -- the footprint is now the only
## ground marker (see config/GhostTuning.gd's DECISION). The footprint quad
## used to always be an axis-aligned unit square whose *position* tracked the
## rotated shape but whose *shape* never did; it is now a real convex polygon
## built from the rotated shape's own corners projected to the XZ plane
## (Geometry2D.convex_hull), rebuilt every frame alongside its position.
##
## Bontago-xtq.7 (docs/solid-blocks2-issue.png, owner test 2026-09-23, "the
## ghost blocks are still clearly made up of smaller blocks ... I can see the
## internal dividers inside the ghost blocks and the preview is also clearly
## the smaller blocks footprints ... in the original the ghost block projects
## its whole shape downwards to the disc"): two independent fixes.
## (1) The "dividers" were never geometry -- BlockMeshBuilder already emits
## one seamless shell per shape with interior faces removed (game/
## BlockFactory.gd, Bontago-xtq.3/xtq.5) -- they were this material's own
## CULL_DISABLED: with alpha blending (no depth write) and both faces drawn,
## every triangle on the *far* side of the shape bled through the near side
## in emission order (not camera depth order), so the far shell's own face
## seams (a bar's side is several coplanar-but-separate quads, one per cell --
## BlockMeshBuilder never merges them) painted visible lines across the near
## face. _material is now CULL_BACK (front faces only): a translucent solid
## has nothing to bleed through, and no other project code ever relied on
## seeing the ghost's inside (the winding-order bug CULL_DISABLED used to
## paper over, BlockMeshBuilder's own header, was fixed independently at
## Bontago-xtq.5).
## (2) The footprint was one polygon *per bottom cell*, so a shape whose cells
## span different heights underneath it (e.g. a tilted bar with its middle
## cell over a placed tower and its ends over the bare disc) showed a broken-
## up set of footprints at different heights instead of one whole-shape
## marker -- and had no vertical "this is the volume in between" cue at all,
## unlike the original's own translucent silhouette prism reaching from the
## held shape straight down to the disc. _update_footprint() now computes one
## convex hull of *every* rotated cell's corners (not per cell), shows it
## flat on the disc surface exactly as before (landing_y from a disk-only
## raycast that skips placed blocks, matching PlayerController's own surface
## probe -- never a tower's top), and adds a second, separate mesh
## (_projection_mesh): the same hull extruded as vertical walls from the
## ghost's own current lowest point down to that same disc height, so the
## whole rotated silhouette reads as one solid prism the way the original
## does, regardless of what is directly underneath any one part of it.
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
##
## Bontago-mv0.28 (owner test 2026-09-22, "when rotating the block the camera
## adjusts; lock the camera to the center of the box without messing up the
## bottom center"): rotation still swings this node's own fixed local origin
## around, which used to be what game/CameraRig.gd followed -- so a pitch/
## roll visibly dragged the camera's framing sideways even though the block
## itself should just spin in place. update_placement() now also re-centres
## this node's XZ so the *rotated* shape's own geometric centre (not the
## fixed origin) sits over the cursor (rotated_center_offset()), and
## game/PlayerController.gd's camera follow now tracks
## rotated_center_world() instead of this node's own global_position. The Y
## fix above is untouched: bottom_offset still measures from the same fixed
## origin, so the shape's rotated lowest point still lands exactly at the
## reported hover height.

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
## Bontago-xtq.7: at most one entry now (the whole rotated shape's own convex
## hull, not one per bottom cell -- see this file's own header). Kept as an
## Array (not a single nullable MeshInstance3D) so _set_footprint_quad_count()
## and the footprint_quad_count()/footprint_quad_position() test contracts
## below stay unchanged in shape, just always 0 or 1 long now.
var _footprint_quads: Array[MeshInstance3D] = []
## World-space XZ polygon currently shown by the footprint quad at the same
## index -- kept alongside _footprint_quads so tests can check the actual
## projected shape, not just where its center landed.
var _footprint_polygons: Array[PackedVector2Array] = []
## Shared by every footprint quad (like _material is shared by every mesh of
## the held shape's own visual) so updating validity/lock state once repaints
## all of them.
var _footprint_material: StandardMaterial3D
## Bontago-xtq.7: the vertical prism connecting the held shape's own lowest
## point down to the footprint on the disc (this file's own header, fix 2) --
## a single persistent node (unlike the footprint quads, its mesh is rebuilt
## in place every frame rather than pooled/recreated, since there is always
## at most one).
var _projection_mesh: MeshInstance3D
var _projection_material: StandardMaterial3D
## For tests: the world-space Y span _projection_mesh currently covers (top,
## bottom) -- Vector2.ZERO (and no visible mesh) when nothing is held or the
## prism collapsed (top <= bottom; see _update_footprint()'s own guard).
var _projection_span_y: Vector2 = Vector2.ZERO
## Bontago-xtq.7: the last disk-surface point PlayerController's own
## placed-block-skipping probe reported (update_placement()'s own
## `surface_point` argument), kept so _update_footprint()'s disk-under-the-
## hull-centre raycast has a same-frame fallback height (the ghost's own
## already-known landing height) for a shape wide enough to overhang the
## disk's edge at its own rotated centre. sync_remote_position() never
## updates this -- a remote peer's ghost has no local surface_point to store,
## so its footprint prism fallback (also never exercised: a remote ghost
## always shows a footprint sized from a surface point the *sending* peer
## already resolved) simply keeps whatever this last held, same as it held no
## fallback data at all before this field existed.
var _last_surface_point: Vector3 = Vector3.ZERO

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
	# DECISION (game/GhostPreview.gd, Bontago-xtq.7): CULL_BACK, not the old
	# CULL_DISABLED -- see this file's own header, fix (1). Front faces only,
	# so translucency reads as a solid surface instead of bleeding through to
	# the far side's own face seams.
	_material.cull_mode = BaseMaterial3D.CULL_BACK
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_material.uv1_triplanar = true

	_footprint_material = StandardMaterial3D.new()
	_footprint_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_footprint_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_footprint_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Bontago-xtq.7 (this file's own header, fix (2)): the flat footprint
	# above stays CULL_DISABLED (a flat quad has no "back" a camera can't
	# already see straight through from below the disk, and it's viewed from
	# above), but the vertical prism's own walls are a convex hull's outer
	# surface -- CULL_DISABLED here on purpose too, unlike the shape's own
	# body, because a *convex* hull has no internal face seams to bleed
	# through (no adjacent-but-separate coplanar quads at cell boundaries the
	# way BlockMeshBuilder's per-cell shell has); double-siding it just lets
	# the far wall read faintly through the near one, exactly like the
	# original's own translucent legs (docs/original_in-game.png).
	_projection_material = StandardMaterial3D.new()
	_projection_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_projection_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_projection_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_projection_mesh = MeshInstance3D.new()
	_projection_mesh.material_override = _projection_material
	_projection_mesh.top_level = true
	_projection_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_projection_mesh)

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
## `hit_normal` for M4). Positions the ghost so the *rotated* held shape's
## lowest point sits at hover height above that surface (item 3's
## rotated-bounds pivot, Y only -- unchanged by Bontago-mv0.28 below), and so
## the *rotated* shape's own geometric centre column sits over the cursor's
## XZ (Bontago-mv0.28, owner report "lock the camera to the center of the box
## without messing up the bottom center" -- see rotated_center_offset()'s own
## doc comment), then refreshes the footprint projection (item 6).
func update_placement(surface_point: Vector3, surface_normal: Vector3) -> void:
	var hover: float = tuning.hover_height + manual_hover_offset
	var anchor: Vector3 = surface_point + surface_normal * hover
	var bottom_offset: float = _rotated_bottom_offset()
	var center_offset: Vector3 = rotated_center_offset()
	global_position = Vector3(
		anchor.x - center_offset.x, anchor.y - bottom_offset, anchor.z - center_offset.z
	) + _reject_offset
	_last_surface_point = surface_point
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


## Bontago-mv0.28 (owner report 2026-09-22, "when rotating the block the
## camera adjusts; lock the camera to the center of the box without messing
## up the bottom center"): how far this node's own local origin (still
## BlockShape.bottom_center() of the *unrotated* shape) sits from the
## *rotated* held shape's own geometric centre, in world space. The
## unrotated centre-to-origin vector is always purely vertical -- the AABB
## centre of `cells` shares bottom_center()'s own X/Z (both are the same cell
## bounds' midpoint by construction, whatever shape the cells happen to
## trace), so only Y ever differs before rotation -- so a yaw-only rotation
## (about world/local up) never moves this in XZ, while a pitch/roll tips
## that vertical offset sideways exactly as update_placement() needs to keep
## the *rotated* shape's centre, not this fixed local origin, under the
## cursor. Zero for a shape with no cells and when nothing is held (global_
## position itself is then already the only sensible "centre").
func rotated_center_offset() -> Vector3:
	if _shape == null or _shape.cells.is_empty():
		return Vector3.ZERO
	var pivot: Vector3 = _shape.bottom_center()
	var min_local: Vector3 = Vector3(INF, INF, INF)
	var max_local: Vector3 = Vector3(-INF, -INF, -INF)
	for cell: Vector3i in _shape.cells:
		var local: Vector3 = (Vector3(cell) - pivot) * tuning.cube_size
		min_local.x = minf(min_local.x, local.x)
		min_local.y = minf(min_local.y, local.y)
		min_local.z = minf(min_local.z, local.z)
		max_local.x = maxf(max_local.x, local.x)
		max_local.y = maxf(max_local.y, local.y)
		max_local.z = maxf(max_local.z, local.z)
	var center_local: Vector3 = (min_local + max_local) * 0.5
	return basis * center_local


## The rotated held shape's own geometric centre, in world space -- what
## game/CameraRig.gd's follow target should track instead of this node's own
## origin (see rotated_center_offset()'s doc comment) so orbiting/pitching the
## block spins it in place instead of visibly swinging the camera's framing.
## Falls back to global_position itself (rotated_center_offset() is then
## Vector3.ZERO) when nothing is held, so callers never need a null check.
func rotated_center_world() -> Vector3:
	return global_position + rotated_center_offset()


# --- Footprint projection (spec 2.5, Bontago-mv0.17 item 6, Bontago-xtq.7) --

## The *whole* rotated held shape's own convex hull, projected onto the XZ
## plane, ghost-local (not yet world-translated): every cell's own 8 corners
## (BlockFactory's own cube_size/cube_margin box, same pivot) go through the
## full rotation basis, get projected to (x, z), and the convex hull of *all*
## of them together becomes the one footprint/projection polygon -- not one
## hull per cell (Bontago-xtq.7, docs/solid-blocks2-issue.png, this file's own
## header fix (2)): a shape's silhouette from directly above is one shape,
## however many cells or landing heights are underneath different parts of
## it.
func _rotated_shape_hull() -> PackedVector2Array:
	if _shape == null or _shape.cells.is_empty():
		return PackedVector2Array()
	var half_size: float = (tuning.cube_size - tuning.cube_margin) * 0.5
	var pivot: Vector3 = _shape.bottom_center()
	var points: PackedVector2Array = PackedVector2Array()
	for cell: Vector3i in _shape.cells:
		var local_center: Vector3 = (Vector3(cell) - pivot) * tuning.cube_size
		for corner_sign: Vector3 in _CORNER_SIGNS:
			var rotated_corner: Vector3 = basis * (local_center + corner_sign * half_size)
			points.append(Vector2(rotated_corner.x, rotated_corner.z))
	return Geometry2D.convex_hull(points)


## Rebuilds the footprint quad (0 or 1 -- see _rotated_shape_hull()'s own
## comment) and the vertical projection prism to match the current shape/
## rotation. Bontago-xtq.7: the footprint's own landing height now comes from
## a disk-only raycast (_raycast_disk_surface(), skipping any placed
## RigidBody3D -- the same technique game/PlayerController.gd's own surface
## probe uses to keep the ghost's *own* height off of towers, Bontago-mv0.17
## item 5) straight down from the hull's own centroid, so the marker always
## lands on the bare disc even when part of the held shape hovers over a
## placed block -- never that block's own top face, which the old per-cell
## raycast (against the unfiltered world) happily landed on. If nothing is
## under the hull's centroid (a wide shape overhanging the disk's edge), this
## falls back to the ghost's own already-known landing height (this file's
## `_last_surface_point`, set by update_placement() every frame) rather than
## leaving the marker with no floor at all.
func _update_footprint() -> void:
	var hull: PackedVector2Array = _rotated_shape_hull()
	if hull.size() < 3:
		_set_footprint_quad_count(0)
		_footprint_polygons.clear()
		_clear_projection_mesh()
		return

	_set_footprint_quad_count(1)
	_footprint_polygons.resize(1)

	var centroid: Vector2 = _polygon_centroid(hull)
	var world_x: float = global_position.x + centroid.x
	var world_z: float = global_position.z + centroid.y
	var probe_origin: Vector3 = Vector3(world_x, ghost_tuning.cursor_ray_height, world_z)
	var hit: Dictionary = _raycast_disk_surface(probe_origin)
	var landing_y: float
	var landing_normal: Vector3
	if hit.is_empty():
		landing_y = _last_surface_point.y
		landing_normal = Vector3.UP
	else:
		landing_y = (hit["position"] as Vector3).y
		landing_normal = hit["normal"] as Vector3

	_footprint_quads[0].global_position = Vector3(world_x, landing_y, world_z) + landing_normal * ghost_tuning.footprint_offset
	_footprint_quads[0].mesh = _build_polygon_mesh(hull, centroid)
	var world_hull: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in hull:
		world_hull.append(Vector2(global_position.x + point.x, global_position.z + point.y))
	_footprint_polygons[0] = world_hull

	_update_projection_mesh(hull, landing_y)


## Bontago-xtq.7 (this file's own header, fix (2)): the vertical walls of a
## prism running from the held shape's own current lowest world point (the
## ghost visual's own underside -- exactly what _rotated_bottom_offset() also
## measures, added back onto global_position.y) down to `landing_y` (the
## footprint's own disc height, just computed by _update_footprint()), traced
## around `hull`'s edges in world XZ. No top or bottom cap: the shape's own
## body already covers the top, and the flat footprint quad already covers
## the bottom, so this is only ever the side walls -- a plain vertical
## extrusion (not tilted to match the ghost's own rotation) exactly like the
## original's own straight-down silhouette (docs/original_in-game.png), not a
## rotated tube.
func _update_projection_mesh(hull: PackedVector2Array, landing_y: float) -> void:
	var top_y: float = global_position.y + _rotated_bottom_offset()
	var bottom_y: float = landing_y
	_projection_span_y = Vector2(top_y, bottom_y)
	if top_y - bottom_y <= ghost_tuning.footprint_offset:
		_clear_projection_mesh()
		return
	_projection_mesh.global_position = Vector3(global_position.x, 0.0, global_position.z)
	_projection_mesh.mesh = _build_prism_mesh(hull, top_y, bottom_y)


## Hides the projection prism (nothing held, or the prism collapsed -- see
## _update_projection_mesh()'s own guard) without freeing the persistent node.
func _clear_projection_mesh() -> void:
	_projection_span_y = Vector2.ZERO
	if _projection_mesh != null:
		_projection_mesh.mesh = null


## Builds the projection prism's side walls: for every edge of `hull` (in
## ghost-local XZ, already offset to world X/Z by _projection_mesh's own
## global_position), one vertical quad (2 triangles) from `top_y` down to
## `bottom_y`. One winding is enough -- _projection_material's own
## CULL_DISABLED (see _ready()) draws both sides of every triangle regardless
## of winding, so this never has to know or match the hull's own winding
## direction the way a single-sided material would.
func _build_prism_mesh(hull: PackedVector2Array, top_y: float, bottom_y: float) -> ArrayMesh:
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var edge_count: int = hull.size()
	for i: int in range(edge_count):
		var a: Vector2 = hull[i]
		var b: Vector2 = hull[(i + 1) % edge_count]
		var edge_length: float = a.distance_to(b)
		if edge_length <= 0.0:
			continue
		# Outward-ish normal for this edge (SHADING_MODE_UNSHADED means it
		# has no visible effect today, but a correct value costs nothing and
		# keeps the mesh sane if the material ever changes).
		var edge_dir: Vector2 = (b - a) / edge_length
		var normal: Vector3 = Vector3(edge_dir.y, 0.0, -edge_dir.x)
		var base_index: int = verts.size()
		verts.append(Vector3(a.x, top_y, a.y))
		verts.append(Vector3(b.x, top_y, b.y))
		verts.append(Vector3(b.x, bottom_y, b.y))
		verts.append(Vector3(a.x, bottom_y, a.y))
		for _k: int in range(4):
			normals.append(normal)
		uvs.append(Vector2(0.0, 0.0))
		uvs.append(Vector2(edge_length / tuning.cube_size, 0.0))
		uvs.append(Vector2(edge_length / tuning.cube_size, (top_y - bottom_y) / tuning.cube_size))
		uvs.append(Vector2(0.0, (top_y - bottom_y) / tuning.cube_size))
		indices.append(base_index)
		indices.append(base_index + 2)
		indices.append(base_index + 1)
		indices.append(base_index)
		indices.append(base_index + 3)
		indices.append(base_index + 2)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var built: ArrayMesh = ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return built


## Unweighted average of `hull`'s own vertices -- good enough as "roughly the
## middle of the shape" for the one straight-down probe _update_footprint()
## needs (a true polygon centroid would weight by edge geometry, which buys
## nothing here: the probe only has to land somewhere inside a convex shape
## the disc is expected to be under almost all of, with _last_surface_point
## as the fallback for the rare edge-of-disk overhang anyway).
func _polygon_centroid(hull: PackedVector2Array) -> Vector2:
	var sum: Vector2 = Vector2.ZERO
	for point: Vector2 in hull:
		sum += point
	return sum / float(hull.size())


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


## Straight down from `origin`, skipping any RigidBody3D (a placed block) so
## the first hit reported is the disk's own collision -- never a tower
## underneath the hull's own centroid (Bontago-xtq.7, this file's own header
## fix (2)). Mirrors game/PlayerController.gd's own _raycast_disk_surface()
## (out of this package's ownership, so duplicated rather than reached into --
## same call this file already makes for collision_box_local_centers(), see
## its own DECISION) exactly, including its surface_probe_max_blocks bound
## against a very tall or adversarial stack.
func _raycast_disk_surface(origin: Vector3) -> Dictionary:
	if not is_inside_tree():
		return {}
	var world: World3D = get_world_3d()
	if world == null:
		return {}
	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	if space_state == null:
		return {}
	var exclude: Array[RID] = []
	var attempts: int = 0
	while attempts <= ghost_tuning.surface_probe_max_blocks:
		var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			origin, origin + Vector3.DOWN * ghost_tuning.placement_ray_length
		)
		params.exclude = exclude
		var hit: Dictionary = space_state.intersect_ray(params)
		if hit.is_empty():
			return {}
		if hit["collider"] is RigidBody3D:
			exclude.append(hit["rid"] as RID)
			attempts += 1
			continue
		return hit
	return {}


func _set_footprint_quad_count(count: int) -> void:
	while _footprint_quads.size() < count:
		var quad: MeshInstance3D = _make_footprint_quad()
		add_child(quad)
		_footprint_quads.append(quad)
	while _footprint_quads.size() > count:
		var extra: MeshInstance3D = _footprint_quads.pop_back()
		extra.queue_free()


## For tests: how many footprint quads are currently shown -- 0 with nothing
## held, otherwise always 1 (Bontago-xtq.7: the whole rotated shape's own
## silhouette, not one per bottom cell -- see _rotated_shape_hull()'s own
## comment).
func footprint_quad_count() -> int:
	return _footprint_quads.size()


## For tests: where footprint quad `index` currently sits.
func footprint_quad_position(index: int) -> Vector3:
	return _footprint_quads[index].global_position


## For tests: the world-space (X, Z) convex polygon footprint quad `index` is
## currently showing -- the exact rotated silhouette of the whole held shape,
## not just its center point (see footprint_quad_position()).
func footprint_polygon_world(index: int) -> PackedVector2Array:
	return _footprint_polygons[index]


## For tests: the world-space Y span (top, bottom) the projection prism
## currently covers -- Vector2.ZERO when nothing is held or the prism
## collapsed (see _update_projection_mesh()'s own guard). `top` is always the
## held shape's own current lowest point (matches _rotated_bottom_offset()'s
## own contract); `bottom` is the footprint's own landing height.
func projection_span_y() -> Vector2:
	return _projection_span_y


## For tests: whether the projection prism mesh is currently visible (has a
## non-null mesh assigned) -- distinct from footprint_quad_count() > 0, since
## a collapsed (top <= bottom) prism still has a footprint quad but no prism.
func has_projection_mesh() -> bool:
	return _projection_mesh != null and _projection_mesh.mesh != null


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
	_apply_projection_material()


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


## Bontago-xtq.7 (this file's own header, fix (2)): the projection prism's own
## walls, at ghost_tuning.projection_alpha instead of footprint_alpha -- the
## brief calls for a noticeably fainter volume marker than the flat footprint
## decal it stands on. DECISION (game/GhostPreview.gd): reuses
## _footprint_color_for_state()'s own state colour when
## ghost_tuning.projection_uses_state_tint is true (the default -- the owner
## report's own reference screenshot, docs/original_in-game.png, tints its
## silhouette prism the same as everything else the ghost shows), just at the
## prism's own alpha; false is kept as a tuning-panel escape hatch to compare
## a state-neutral prism (always the base tint_color) without a second
## migration, the same reasoning already used for several other GhostTuning
## fields' own master-switch DECISIONs in this file/config/GhostTuning.gd.
func _apply_projection_material() -> void:
	if _projection_material == null:
		return
	if ghost_tuning.projection_uses_state_tint:
		var state_color: Color = _footprint_color_for_state()
		_projection_material.albedo_color = _with_alpha(state_color, ghost_tuning.projection_alpha)
	else:
		_projection_material.albedo_color = _with_alpha(ghost_tuning.tint_color, ghost_tuning.projection_alpha)


## For tests: the projection prism's own current tint colour (see
## current_footprint_tint_color() for the flat footprint decal's own colour).
func current_projection_tint_color() -> Color:
	return _projection_material.albedo_color if _projection_material != null else Color.WHITE


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
