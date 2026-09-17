class_name GhostPreview
extends Node3D
## The non-physics held block (spec 2.5): follows wherever PlayerController's
## raycast says to go, hovering `hover_height` above the first thing it would
## touch, with a projected drop shadow and a vertical guide line.
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

const STATE_VALID: StringName = &"valid"
const STATE_INVALID: StringName = &"invalid"
const STATE_HOLE: StringName = &"hole"

const HATCH_TEXTURE_SIZE: int = 32

@export var tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
@export var ghost_tuning: GhostTuning = preload("res://config/ghost_tuning.tres")

var orientation_index: int = 0
var free_quaternion: Quaternion = Quaternion.IDENTITY
## Extra manual raise/lower on top of tuning.hover_height (hover_raise/lower).
var manual_hover_offset: float = 0.0

var _shape: BlockShape = null
var _shape_visual: Node3D = null
var _shadow: MeshInstance3D
var _guide: MeshInstance3D

var _material: StandardMaterial3D
var _hatch_texture: ImageTexture
var _player_color: Color = Color.WHITE
var _last_result: PlacementRules.Result = PlacementRules.Result.VALID

var _flash_tween: Tween
var _reject_tween: Tween


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_material.uv1_triplanar = true
	_hatch_texture = _build_hatch_texture()
	_apply_validity_material()

	_shadow = _make_shadow_mesh()
	add_child(_shadow)
	_guide = _make_guide_mesh()
	add_child(_guide)


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


func apply_free_rotation_delta(yaw: float, pitch: float) -> void:
	var delta: Quaternion = Quaternion(Vector3.UP, yaw) * Quaternion(Vector3.RIGHT, pitch)
	free_quaternion = (delta * free_quaternion).normalized()
	_apply_rotation()


func _apply_rotation() -> void:
	var base_basis: Basis = BlockOrientations.get_basis(orientation_index)
	basis = Basis(free_quaternion) * base_basis


## Called every frame by PlayerController with where the placement raycast
## hit. Positions the ghost above that point and updates the shadow/guide.
func update_placement(hit_point: Vector3, hit_normal: Vector3) -> void:
	var hover: float = tuning.hover_height + manual_hover_offset
	global_position = hit_point + hit_normal * hover
	_shadow.global_position = hit_point + hit_normal * ghost_tuning.shadow_offset
	_update_guide(hit_point)


func _update_guide(hit_point: Vector3) -> void:
	var to_ghost: Vector3 = global_position - hit_point
	var length: float = to_ghost.length()
	_guide.visible = length > 0.001
	if not _guide.visible:
		return
	_guide.global_position = hit_point + to_ghost * 0.5
	var y_axis: Vector3 = to_ghost.normalized()
	var x_axis: Vector3 = y_axis.cross(Vector3.FORWARD)
	if x_axis.length() < 0.001:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	_guide.global_transform.basis = Basis(x_axis, y_axis, z_axis)
	var mesh: BoxMesh = _guide.mesh as BoxMesh
	mesh.size = Vector3(ghost_tuning.guide_thickness, length, ghost_tuning.guide_thickness)


# --- Placement validity tint (spec 2.2, 2.5) --------------------------------

## The active slot's colour, used for the VALID tint. Setting it re-applies
## the material immediately if the ghost is currently showing VALID, so a
## hot-seat turn change re-colours the ghost without waiting for the next
## preview_placement() poll.
func set_player_color(color: Color) -> void:
	_player_color = color
	if _last_result == PlacementRules.Result.VALID:
		_apply_validity_material()


## Maps Match.preview_placement()'s advisory result onto the three tint
## states spec 2.5 calls for. Safe to call every frame.
func apply_validity(result: PlacementRules.Result) -> void:
	_last_result = result
	_apply_validity_material()


## For tests: which of the three tint states the ghost is currently showing.
func current_state() -> StringName:
	match _last_result:
		PlacementRules.Result.VALID:
			return STATE_VALID
		PlacementRules.Result.HOLE:
			return STATE_HOLE
		_:
			return STATE_INVALID


## For tests: the material colour currently applied to the held shape.
func current_tint_color() -> Color:
	return _material.albedo_color if _material != null else Color.WHITE


func _apply_validity_material() -> void:
	if _material == null:
		return
	match _last_result:
		PlacementRules.Result.VALID:
			_material.albedo_texture = null
			_material.albedo_color = Color(_player_color.r, _player_color.g, _player_color.b, ghost_tuning.tint_color.a)
		PlacementRules.Result.HOLE:
			_material.albedo_texture = _hatch_texture
			_material.uv1_scale = Vector3(ghost_tuning.hatch_scale, ghost_tuning.hatch_scale, 1.0)
			_material.albedo_color = ghost_tuning.hole_tint_color
		_:
			_material.albedo_texture = null
			_material.albedo_color = ghost_tuning.invalid_tint_color


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


func _make_guide_mesh() -> MeshInstance3D:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(ghost_tuning.guide_thickness, 1.0, ghost_tuning.guide_thickness)
	mesh_instance.mesh = box
	mesh_instance.material_override = _unshaded_material(ghost_tuning.guide_color)
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
