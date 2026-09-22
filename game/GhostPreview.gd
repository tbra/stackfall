class_name GhostPreview
extends Node3D
## The non-physics held block (spec 2.5): floats at a height PlayerController
## reports (the disk surface plus hover_height plus the wheel's manual
## offset, Bontago-mv0.17 item 5 — never whatever is directly underneath the
## cursor), with a small drop-shadow quad at the cursor's own disk-plane spot
## plus a projected footprint (one quad per bottom cell of the rotated held
## shape, item 6) showing exactly what each part of it would land on.
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
var _shadow: MeshInstance3D
## Bontago-mv0.17 item 6: one quad per bottom cell of the *rotated* held
## shape, resized to match every time the shape/rotation/position changes
## (_update_footprint()). Replaces the old single vertical guide line.
var _footprint_quads: Array[MeshInstance3D] = []
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

	_shadow = _make_shadow_mesh()
	add_child(_shadow)


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
## 2026-09-22]): PlayerController calls this with (yaw, 0.0) while rotate_drag
## (MMB) is held, driving free_quaternion continuously -- already the exact
## field submit_cursor/submit_place send unmodified over the wire, so no new
## replication path was needed.
func apply_free_rotation_delta(yaw: float, pitch: float) -> void:
	var delta: Quaternion = Quaternion(Vector3.UP, yaw) * Quaternion(Vector3.RIGHT, pitch)
	free_quaternion = (delta * free_quaternion).normalized()
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
## that height (item 3's rotated-bounds pivot), then refreshes the shadow and
## the footprint projection (item 6).
func update_placement(surface_point: Vector3, surface_normal: Vector3) -> void:
	var hover: float = tuning.hover_height + manual_hover_offset
	var anchor: Vector3 = surface_point + surface_normal * hover
	var bottom_offset: float = _rotated_bottom_offset()
	global_position = Vector3(anchor.x, anchor.y - bottom_offset, anchor.z)
	_shadow.global_position = surface_point + surface_normal * ghost_tuning.shadow_offset
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
	global_position = origin
	var hover: float = tuning.hover_height + manual_hover_offset
	_shadow.global_position = origin - Vector3.UP * hover + Vector3.UP * ghost_tuning.shadow_offset
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

## This node's own origin plus every distinct (x, z) column the *rotated*
## held shape occupies, in world space -- one entry per bottom cell of the
## rotated shape, deduplicated so a shape stacked in the (now-rotated)
## vertical axis gets exactly one footprint quad per column, not one per
## cell.
func _rotated_footprint_columns() -> Array[Vector2]:
	var columns: Array[Vector2] = []
	if _shape == null or _shape.cells.is_empty():
		return columns
	var pivot: Vector3 = _shape.bottom_center()
	var seen: Dictionary = {}
	for cell: Vector3i in _shape.cells:
		var local: Vector3 = (Vector3(cell) - pivot) * tuning.cube_size
		var rotated: Vector3 = basis * local
		var key: Vector2i = Vector2i(roundi(rotated.x / tuning.cube_size), roundi(rotated.z / tuning.cube_size))
		if seen.has(key):
			continue
		seen[key] = true
		columns.append(Vector2(rotated.x, rotated.z))
	return columns


## Rebuilds the footprint quad pool to match the current shape/rotation and
## raycasts straight down through each column (blocks included -- unlike
## PlayerController's disk-only probe, this is meant to land on a tower) to
## show exactly what each part of the held shape would rest on.
func _update_footprint() -> void:
	var columns: Array[Vector2] = _rotated_footprint_columns()
	_set_footprint_quad_count(columns.size())
	for i: int in range(columns.size()):
		var world_x: float = global_position.x + columns[i].x
		var world_z: float = global_position.z + columns[i].y
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
			(child as MeshInstance3D).material_override = _material


# --- Reject / auto-drop animation (spec 2.2, 2.5) ---------------------------

## Spec 2.2: "released [in a contested area] ... is thrown off the map with a
## visible reject animation" (docs/M2_PLAN.md owner decision 2: every invalid
## release burns the block, decided by Match.request_place — this is just the
## ghost-side cue: a bright flash plus a small arc kick on the held shape's
## own local offset, since PlayerController re-homes the ghost's world
## position every frame and a position tween on it would be overwritten
## immediately).
func play_reject_animation() -> void:
	_flash_material(ghost_tuning.reject_flash_color, ghost_tuning.reject_flash_duration)
	if _shape_visual == null:
		return
	if _reject_tween != null and _reject_tween.is_valid():
		_reject_tween.kill()
	_shape_visual.position = Vector3.ZERO
	var kick: Vector3 = Vector3(ghost_tuning.reject_arc_sideways, ghost_tuning.reject_arc_height, 0.0)
	var half_duration: float = ghost_tuning.reject_arc_duration * 0.5
	_reject_tween = create_tween()
	_reject_tween.tween_property(_shape_visual, ^"position", kick, half_duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_reject_tween.tween_property(_shape_visual, ^"position", Vector3.ZERO, half_duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


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

func _make_shadow_mesh() -> MeshInstance3D:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var quad: QuadMesh = QuadMesh.new()
	quad.size = ghost_tuning.shadow_size
	mesh_instance.mesh = quad
	mesh_instance.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	mesh_instance.material_override = _unshaded_material(ghost_tuning.shadow_color)
	# DECISION (game/GhostPreview.gd): the shadow is a fixed 1x1 quad rather
	# than one shaped to the held block's exact footprint. M1 only needs a
	# clear landing indicator, not a pixel-accurate silhouette.
	mesh_instance.top_level = true
	return mesh_instance


## Bontago-mv0.17 item 6: one flat quad per bottom cell of the rotated held
## shape (replaces _make_guide_mesh()'s old vertical line), sized like one
## cell's own footprint and tinted by the shared _footprint_material so every
## quad repaints together when validity/lock state changes.
func _make_footprint_quad() -> MeshInstance3D:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var quad: QuadMesh = QuadMesh.new()
	quad.size = ghost_tuning.shadow_size
	mesh_instance.mesh = quad
	mesh_instance.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	mesh_instance.material_override = _footprint_material
	mesh_instance.top_level = true
	return mesh_instance


func _unshaded_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


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
