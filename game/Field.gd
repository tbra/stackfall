class_name Field
extends StaticBody3D
## The match field: a disk (spec 2.1). Static for M1 — no tilt yet, so it's a
## plain StaticBody3D. It becomes an AnimatableBody3D (SPECIALS_ONLY tilt) or
## RigidBody3D (PHYSICAL_BALANCE tilt) from M4/M6 onward.
##
## Also owns the kill plane (spec 2.1): any body that falls below
## `tuning.kill_plane_y` is freed and reported on the Events bus.

const DISK_HEIGHT: float = 1.0
## The kill plane only needs to catch blocks that fall off the disk, so it's
## sized as a wide multiple of the field radius rather than a magic constant.
const KILL_PLANE_RADIUS_FACTOR: float = 20.0

@export var map_def: MapDef = preload("res://config/maps/round_medium.tres")
@export var tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")


func _ready() -> void:
	_build_disk()
	_build_kill_plane()


func _build_disk() -> void:
	var collision: CollisionShape3D = CollisionShape3D.new()
	var cylinder_shape: CylinderShape3D = CylinderShape3D.new()
	cylinder_shape.radius = map_def.field_radius
	cylinder_shape.height = DISK_HEIGHT
	collision.shape = cylinder_shape
	collision.position = Vector3(0.0, -DISK_HEIGHT * 0.5, 0.0)
	add_child(collision)

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var cylinder_mesh: CylinderMesh = CylinderMesh.new()
	cylinder_mesh.top_radius = map_def.field_radius
	cylinder_mesh.bottom_radius = map_def.field_radius
	cylinder_mesh.height = DISK_HEIGHT
	mesh_instance.mesh = cylinder_mesh
	mesh_instance.position = collision.position
	add_child(mesh_instance)

	var material: PhysicsMaterial = PhysicsMaterial.new()
	material.friction = tuning.disk_friction
	physics_material_override = material


func _build_kill_plane() -> void:
	var area: Area3D = Area3D.new()
	area.name = &"KillPlane"
	var collision: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	var span: float = map_def.field_radius * KILL_PLANE_RADIUS_FACTOR
	box.size = Vector3(span, 1.0, span)
	collision.shape = box
	area.add_child(collision)
	area.position = Vector3(0.0, tuning.kill_plane_y, 0.0)
	add_child(area)
	area.body_entered.connect(_on_kill_plane_body_entered)


func _on_kill_plane_body_entered(body: Node3D) -> void:
	var rigid_body: RigidBody3D = body as RigidBody3D
	if rigid_body == null:
		return
	Events.block_removed.emit(rigid_body, "kill_plane")
	rigid_body.queue_free()
