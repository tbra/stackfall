extends GutTest
## Bontago-1pi.85.51: honey-coat tuning, shader and ghost overlay wiring.

const TUNING_PATH: String = "res://config/honey_coat_tuning.tres"
const SHADER_PATH: String = "res://shaders/honey_coat.gdshader"
const SLOT: int = 3


func _make_ghost() -> GhostPreview:
	var ghost: GhostPreview = GhostPreview.new()
	add_child_autofree(ghost)
	ghost.set_shape(BlockShape.load_all_shapes()[0])
	return ghost


func _meshes(ghost: GhostPreview) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for child: Node in ghost._shape_visual.get_children():
		if child is MeshInstance3D:
			found.append(child as MeshInstance3D)
	return found


func test_tuning_defaults_match_plan() -> void:
	var tuning: HoneyCoatTuning = load(TUNING_PATH) as HoneyCoatTuning
	assert_not_null(tuning)
	assert_eq(tuning.color, Color(1.0, 0.7, 0.04, 1.0))
	assert_almost_eq(tuning.thickness_m, 0.02, 0.0001)
	assert_almost_eq(tuning.ghost_alpha, 0.6, 0.0001)
	assert_almost_eq(tuning.roughness, 0.05, 0.0001)


func test_shader_loads_and_material_carries_the_tuning() -> void:
	var shader: Shader = load(SHADER_PATH) as Shader
	assert_not_null(shader)
	assert_eq(shader.get_mode(), Shader.MODE_SPATIAL)
	var tuning: HoneyCoatTuning = load(TUNING_PATH) as HoneyCoatTuning
	var material: ShaderMaterial = tuning.build_material()
	assert_eq(material.shader, shader)
	assert_eq(material.get_shader_parameter(&"honey_color"), tuning.color)
	assert_almost_eq(float(material.get_shader_parameter(&"tongue_chance")), tuning.tongue_chance, 0.0001)


## The puddle-overlay ghost tests run on the legacy PUDDLE look; the shipped default is JELLY_BEADS.
func _use_look(look: HoneyCoatTuning.Look) -> void:
	# Held in a member so the cached resource (and the look set on it) outlives this call.
	_tuning_ref = load(TUNING_PATH) as HoneyCoatTuning
	var original: HoneyCoatTuning.Look = _tuning_ref.look
	_tuning_ref.look = look
	HoneyCoat.release_statics()
	_restore_look = original


var _tuning_ref: HoneyCoatTuning = null
var _restore_look: HoneyCoatTuning.Look = HoneyCoatTuning.Look.JELLY_BEADS


func after_each() -> void:
	if _tuning_ref != null:
		_tuning_ref.look = _restore_look
		_tuning_ref = null
	HoneyCoat.release_statics()


func test_glue_ghost_gets_honey_overlay_and_loses_it() -> void:
	_use_look(HoneyCoatTuning.Look.PUDDLE)
	var ghost: GhostPreview = _make_ghost()
	var meshes: Array[MeshInstance3D] = _meshes(ghost)
	assert_gt(meshes.size(), 0)
	for mesh: MeshInstance3D in meshes:
		assert_null(mesh.material_overlay)
	ghost.set_glue_charges(2)
	for mesh: MeshInstance3D in meshes:
		assert_true(mesh.material_overlay is ShaderMaterial, "glue ghost mesh gets the honey ShaderMaterial")
		assert_eq((mesh.material_overlay as ShaderMaterial).shader, load(SHADER_PATH))
	ghost.set_glue_charges(0)
	for mesh: MeshInstance3D in meshes:
		assert_null(mesh.material_overlay, "overlay is removed at zero charges")


func test_glue_ghost_is_translucent_honey() -> void:
	_use_look(HoneyCoatTuning.Look.PUDDLE)
	var ghost: GhostPreview = _make_ghost()
	var mesh: MeshInstance3D = _meshes(ghost)[0]
	ghost.set_glue_charges(1)
	var overlay: ShaderMaterial = mesh.material_overlay as ShaderMaterial
	assert_true(bool(overlay.get_shader_parameter(&"ghost_mode")))
	var tuning: HoneyCoatTuning = load(TUNING_PATH) as HoneyCoatTuning
	assert_lt(tuning.ghost_alpha, 1.0, "translucent so the validity colour reads through")
	assert_almost_eq(float(overlay.get_shader_parameter(&"patch_coverage")), tuning.patch_coverage, 0.0001)


# --- Bontago-lv2: blob look switch ------------------------------------------------

func test_default_look_is_jelly_and_beads_and_materials_match() -> void:
	var tuning: HoneyCoatTuning = (load(TUNING_PATH) as HoneyCoatTuning).duplicate() as HoneyCoatTuning
	assert_eq(tuning.look, HoneyCoatTuning.Look.JELLY_BEADS)
	assert_true(tuning.has_jelly())
	assert_true(tuning.has_beads())
	assert_eq(tuning.build_jelly_material().shader, load(HoneyCoatTuning.JELLY_SHADER_PATH))
	assert_eq(tuning.build_beads_material().shader, load(HoneyCoatTuning.BEADS_SHADER_PATH))
	assert_lt(float(tuning.build_jelly_material(true).get_shader_parameter(&"alpha")), float(tuning.build_jelly_material().get_shader_parameter(&"alpha")))
	tuning.look = HoneyCoatTuning.Look.PUDDLE
	assert_false(tuning.has_jelly())
	assert_false(tuning.has_beads())


func test_glue_ghost_wears_jelly_and_beads_children_by_default() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.set_glue_charges(1)
	for mesh: MeshInstance3D in _meshes(ghost):
		assert_null(mesh.material_overlay, "no puddle overlay on the jelly look")
		var jelly: Node = mesh.get_node_or_null(HoneyCoat.COAT_NODE_NAME)
		assert_not_null(jelly)
		assert_not_null(jelly.get_node_or_null(HoneyCoat.BEADS_NODE_NAME))
	ghost.set_glue_charges(0)
	for mesh: MeshInstance3D in _meshes(ghost):
		assert_null(mesh.get_node_or_null(HoneyCoat.COAT_NODE_NAME))


func test_blob_meshes_skip_shared_faces_and_are_deterministic() -> void:
	var two: Array[Vector3] = [Vector3.ZERO, Vector3.UP]
	var shell: ArrayMesh = HoneyBlobMeshes.shell(two, 2, 0.5)
	# 2 cells x 5 open faces x 9 verts.
	assert_eq(shell.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), 90)
	var a: ArrayMesh = HoneyBlobMeshes.beads(two, 3, 0.05, 0.1, 0.7)
	var b: ArrayMesh = HoneyBlobMeshes.beads(two, 3, 0.05, 0.1, 0.7)
	assert_eq(a.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], b.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
