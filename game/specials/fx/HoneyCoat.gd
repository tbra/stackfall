class_name HoneyCoat
## Honey coat on placed, glued blocks (Bontago-1pi.85.52). Reuses the 85.51
## HoneyCoatTuning look. The coat is a child MeshInstance3D sharing each shape
## mesh (so it never fights Block's frozen overlay slot or BlockFactory.recolor())
## and carries the look chosen by HoneyCoatTuning.look: the old shader-drawn pool and tongues (PUDDLE),
## or generated jelly shell and/or glue beads (Bontago-lv2). Materials are built once and shared by every coated block.
##
## Depends on: HoneyCoatTuning

const TUNING_PATH: String = "res://config/honey_coat_tuning.tres"
const COAT_NODE_NAME: String = "HoneyCoatMesh"

const BEADS_NODE_NAME: String = "HoneyBeadsMesh"
const JELLY_HALF_M: float = 0.5

static var _tuning: HoneyCoatTuning = null
static var _coat_material: ShaderMaterial = null
static var _beads_material: ShaderMaterial = null
## Generated meshes for the blob looks, one per (kind, cell layout), shared by every block with that layout.
static var _blob_meshes: Dictionary = {}


## Bontago-xtq.44: drops the static texture/material cache on exit (freed before the renderer shuts down).
static func release_statics() -> void:
	_coat_material = null
	_beads_material = null
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


## Held-ghost version of the blob looks: translucent shell/beads on the ghost's mesh. Returns false
## for the PUDDLE look (the ghost keeps its material overlay then). `centres` = block-local cell centres. Idempotent both ways.
static func set_ghost_coated(mesh_instance: MeshInstance3D, centres: Array[Vector3], coated: bool) -> bool:
	_ensure_materials()
	if mesh_instance == null or _tuning.look == HoneyCoatTuning.Look.PUDDLE:
		return false
	var existing: Node = mesh_instance.get_node_or_null(COAT_NODE_NAME)
	if existing != null:
		mesh_instance.remove_child(existing)
		existing.queue_free()
	if coated:
		_attach(mesh_instance, centres, true)
	return true


static func _attach(mesh_instance: MeshInstance3D, centres: Array[Vector3], ghost: bool) -> void:
	_ensure_materials()
	if _tuning.look == HoneyCoatTuning.Look.PUDDLE:
		_attach_puddle(mesh_instance)
		return
	var jelly: MeshInstance3D = null
	if _tuning.has_jelly():
		jelly = _blob_node(_blob_mesh("jelly", centres), _tuning.build_jelly_material(true) if ghost else _coat_material)
		jelly.name = COAT_NODE_NAME
	var beads: MeshInstance3D = null
	if _tuning.has_beads():
		beads = _blob_node(_blob_mesh("beads", centres), _tuning.build_beads_material(true) if ghost else _beads_material)
		beads.name = BEADS_NODE_NAME if jelly != null else COAT_NODE_NAME
	if jelly != null:
		mesh_instance.add_child(jelly)
		if beads != null:
			jelly.add_child(beads)
	elif beads != null:
		mesh_instance.add_child(beads)


static func _blob_node(mesh: Mesh, material: Material) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


static func _attach_puddle(mesh_instance: MeshInstance3D) -> void:
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
	if _tuning.has_jelly():
		_coat_material = _tuning.build_jelly_material()
	else:
		_coat_material = _tuning.build_material()
	_beads_material = _tuning.build_beads_material()


## Block-local cell centres, read from the block's per-cell collision shapes.
static func _cell_centres(block: Block) -> Array[Vector3]:
	var centres: Array[Vector3] = []
	for child: Node in block.get_children():
		var shape_node: CollisionShape3D = child as CollisionShape3D
		if shape_node != null:
			centres.append(shape_node.position)
	return centres


static func _blob_mesh(kind: String, centres: Array[Vector3]) -> Mesh:
	var key: String = "%s:%s" % [kind, str(centres)]
	if _blob_meshes.has(key):
		return _blob_meshes[key] as Mesh
	var mesh: Mesh = null
	if kind == "jelly":
		mesh = HoneyBlobMeshes.shell(centres, _tuning.jelly_subdivisions, JELLY_HALF_M)
	else:
		mesh = HoneyBlobMeshes.beads(centres, _tuning.bead_count_per_cell, _tuning.bead_min_radius_m, _tuning.bead_max_radius_m, _tuning.bead_flatten)
	_blob_meshes[key] = mesh
	return mesh
