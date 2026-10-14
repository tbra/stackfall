class_name HoneyCoat
## Honey coat on placed, glued blocks (Bontago-1pi.85.52). Reuses the 85.51
## HoneyCoatTuning look. The coat is a child MeshInstance3D sharing each shape
## mesh (so it never fights Block's frozen overlay slot or BlockFactory.recolor())
## and carries the generated jelly shell (Bontago-lv2; jelly is the only glue look, Bontago-1pi.85.71).
## The material is built once and shared by every coated block.
##
## Depends on: HoneyCoatTuning

const TUNING_PATH: String = "res://config/gifts/honey_coat_tuning.tres"
const COAT_NODE_NAME: String = "HoneyCoatMesh"

const JELLY_HALF_M: float = 0.5

static var _tuning: HoneyCoatTuning = null
static var _coat_material: ShaderMaterial = null
## Generated jelly shells, one per cell layout, shared by every block with that layout.
static var _blob_meshes: Dictionary = {}


## Bontago-xtq.44: drops the static texture/material cache on exit (freed before the renderer shuts down).
static func release_statics() -> void:
	_coat_material = null
	_tuning = null
	_blob_meshes.clear()


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
			_attach(mesh_instance, _cell_centres(block), false)
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


## Held-ghost version: translucent jelly shell on the ghost's mesh. `centres` = block-local cell centres. Idempotent both ways.
static func set_ghost_coated(mesh_instance: MeshInstance3D, centres: Array[Vector3], coated: bool) -> void:
	_ensure_materials()
	if mesh_instance == null:
		return
	var existing: Node = mesh_instance.get_node_or_null(COAT_NODE_NAME)
	if existing != null:
		mesh_instance.remove_child(existing)
		existing.queue_free()
	if coated:
		_attach(mesh_instance, centres, true)


static func _attach(mesh_instance: MeshInstance3D, centres: Array[Vector3], ghost: bool) -> void:
	_ensure_materials()
	var jelly: MeshInstance3D = MeshInstance3D.new()
	jelly.mesh = _jelly_mesh(centres)
	jelly.material_override = _tuning.build_jelly_material(true) if ghost else _coat_material
	jelly.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	jelly.name = COAT_NODE_NAME
	mesh_instance.add_child(jelly)


static func _ensure_materials() -> void:
	if _tuning != null and _coat_material != null:
		return
	_tuning = load(TUNING_PATH) as HoneyCoatTuning
	_coat_material = _tuning.build_jelly_material()


## Block-local cell centres, read from the block's per-cell collision shapes.
static func _cell_centres(block: Block) -> Array[Vector3]:
	var centres: Array[Vector3] = []
	for child: Node in block.get_children():
		var shape_node: CollisionShape3D = child as CollisionShape3D
		if shape_node != null:
			centres.append(shape_node.position)
	return centres


static func _jelly_mesh(centres: Array[Vector3]) -> Mesh:
	var key: String = str(centres)
	if _blob_meshes.has(key):
		return _blob_meshes[key] as Mesh
	var mesh: Mesh = HoneyBlobMeshes.shell(centres, _tuning.jelly_subdivisions, JELLY_HALF_M)
	_blob_meshes[key] = mesh
	return mesh
