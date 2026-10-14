class_name PaintballSplash
extends Node3D
## Brief expanding translucent color shell at the Paintball impact point.
## Each peer builds it from the already replicated special-trigger event.

const LIFETIME_S: float = 0.35
const FINAL_RADIUS_M: float = 3.5

var _age: float = 0.0
var _material: StandardMaterial3D
## Set when spawned into a match world (GiftFxPresenter); see BlackHoleVisual.bind_to_match.
var bind_to_match: bool = false


func setup(color: Color, radius_m: float = FINAL_RADIUS_M) -> void:
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(color.r, color.g, color.b, 0.32)
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var mesh_node: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = radius_m
	sphere.height = radius_m * 2.0
	mesh_node.mesh = sphere
	mesh_node.material_override = _material
	add_child(mesh_node)
	scale = Vector3.ONE * 0.05


func _process(delta: float) -> void:
	if bind_to_match and not MatchPhase.is_live(MatchContext.current().state()):
		queue_free()
		return
	_age += delta
	var progress: float = minf(_age / LIFETIME_S, 1.0)
	scale = Vector3.ONE * lerpf(0.05, 1.0, progress)
	var tint: Color = _material.albedo_color
	tint.a = 0.32 * (1.0 - progress)
	_material.albedo_color = tint
	if progress >= 1.0:
		queue_free()
