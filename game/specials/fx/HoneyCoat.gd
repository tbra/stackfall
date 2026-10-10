class_name HoneyCoat
## Honey coat on placed, glued blocks (Bontago-1pi.85.52). Reuses the 85.51
## HoneyCoatTuning look. The coat is a child MeshInstance3D sharing each shape
## mesh (so it never fights Block's frozen overlay slot or BlockFactory.recolor())
## and carries the shader-drawn pool and tongues. Materials are built once and shared by every coated block.
##
## Depends on: HoneyCoatTuning

const TUNING_PATH: String = "res://config/honey_coat_tuning.tres"
const COAT_NODE_NAME: String = "HoneyCoatMesh"

static var _tuning: HoneyCoatTuning = null
static var _coat_material: ShaderMaterial = null


## Bontago-xtq.44: drops the static texture/material cache on exit (freed before the renderer shuts down).
static func release_statics() -> void:
	_coat_material = null
	_tuning = null


## Adds or removes the coat on every shape mesh of `block`. Idempotent.
static func set_coated(block: Block, coated: bool) -> void:
	if block == null or not is_instance_valid(block):
		return
	for child: Node in block.get_children():
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		if mesh_instance == null:
			continue
		var existing: Node = mesh_instance.get_node_or_null(COAT_NODE_NAME)
		if coated and existing == null:
			_attach(mesh_instance)
		elif not coated and existing != null:
			mesh_instance.remove_child(existing)
			existing.queue_free()


static func is_coated(block: Block) -> bool:
	if block == null or not is_instance_valid(block):
		return false
	for child: Node in block.get_children():
		if child is MeshInstance3D and child.get_node_or_null(COAT_NODE_NAME) != null:
			return true
	return false


static func _attach(mesh_instance: MeshInstance3D) -> void:
	_ensure_materials()
	var coat: MeshInstance3D = MeshInstance3D.new()
	coat.name = COAT_NODE_NAME
	coat.mesh = mesh_instance.mesh
	coat.material_override = _coat_material
	coat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.add_child(coat)
	coat.set_instance_shader_parameter(&"lattice_origin", mesh_instance.mesh.get_aabb().position if mesh_instance.mesh != null else Vector3.ZERO)


static func _ensure_materials() -> void:
	if _tuning != null and _coat_material != null:
		return
	_tuning = load(TUNING_PATH) as HoneyCoatTuning
	_coat_material = _tuning.build_material()
