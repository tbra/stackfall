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

@export var tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")

var orientation_index: int = 0
var free_quaternion: Quaternion = Quaternion.IDENTITY
## Extra manual raise/lower on top of tuning.hover_height (hover_raise/lower).
var manual_hover_offset: float = 0.0

var _shape: BlockShape = null
var _shape_visual: Node3D = null
var _shadow: MeshInstance3D
var _guide: MeshInstance3D


func _ready() -> void:
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
	_apply_ghost_material(_shape_visual)


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
	_shadow.global_position = hit_point + hit_normal * 0.01
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
	mesh.size = Vector3(0.03, length, 0.03)


func _apply_ghost_material(node: Node3D) -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.9, 0.55, 0.55)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_override = material


func _make_shadow_mesh() -> MeshInstance3D:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	mesh_instance.mesh = quad
	mesh_instance.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	mesh_instance.material_override = _unshaded_material(Color(0.0, 0.0, 0.0, 0.4))
	# DECISION (game/GhostPreview.gd): the shadow is a fixed 1x1 quad rather
	# than one shaped to the held block's exact footprint. M1 only needs a
	# clear landing indicator, not a pixel-accurate silhouette.
	mesh_instance.top_level = true
	return mesh_instance


func _make_guide_mesh() -> MeshInstance3D:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.03, 1.0, 0.03)
	mesh_instance.mesh = box
	mesh_instance.material_override = _unshaded_material(Color(1.0, 1.0, 1.0, 0.6))
	mesh_instance.top_level = true
	return mesh_instance


func _unshaded_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material
