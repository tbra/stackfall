class_name BlackHoleVisual
extends Node3D
## Placeholder black hole look (a dark sphere); the cel vortex is a follow-up
## bead. Built on every peer from the replicated special_triggered event.

const SPHERE_COLOR: Color = Color(0.02, 0.0, 0.05)

var _remaining_s: float = 0.0


func setup(radius_m: float, lifetime_s: float) -> void:
	_remaining_s = lifetime_s
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = SPHERE_COLOR
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = radius_m
	sphere.height = radius_m * 2.0
	var mesh_node: MeshInstance3D = MeshInstance3D.new()
	mesh_node.mesh = sphere
	mesh_node.material_override = material
	add_child(mesh_node)


func _process(delta: float) -> void:
	_remaining_s -= delta
	if _remaining_s <= 0.0:
		queue_free()
