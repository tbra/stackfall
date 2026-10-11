extends GutTest
## Bontago-1pi.85.51: honey-coat tuning, shader and ghost overlay wiring.

const TUNING_PATH: String = "res://config/honey_coat_tuning.tres"


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
	assert_almost_eq(tuning.ghost_alpha, 0.6, 0.0001)


func after_each() -> void:
	HoneyCoat.release_statics()


## Bontago-1pi.85.71: jelly is the only glue look.
func test_jelly_material_uses_the_jelly_shader_and_ghost_is_fainter() -> void:
	var tuning: HoneyCoatTuning = load(TUNING_PATH) as HoneyCoatTuning
	var material: ShaderMaterial = tuning.build_jelly_material()
	assert_eq(material.shader, load(HoneyCoatTuning.JELLY_SHADER_PATH))
	assert_eq(material.get_shader_parameter(&"honey_color"), tuning.color)
	assert_lt(float(tuning.build_jelly_material(true).get_shader_parameter(&"alpha")), float(material.get_shader_parameter(&"alpha")))


func test_glue_ghost_wears_a_jelly_child_and_loses_it() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.set_glue_charges(1)
	assert_gt(_meshes(ghost).size(), 0)
	for mesh: MeshInstance3D in _meshes(ghost):
		assert_null(mesh.material_overlay, "no material overlay, the jelly is a child shell")
		assert_not_null(mesh.get_node_or_null(HoneyCoat.COAT_NODE_NAME))
		assert_eq(mesh.get_child_count(), 1, "jelly only, no bead mesh")
	ghost.set_glue_charges(0)
	for mesh: MeshInstance3D in _meshes(ghost):
		assert_null(mesh.get_node_or_null(HoneyCoat.COAT_NODE_NAME))


func test_jelly_shell_skips_shared_faces() -> void:
	var two: Array[Vector3] = [Vector3.ZERO, Vector3.UP]
	var shell: ArrayMesh = HoneyBlobMeshes.shell(two, 2, 0.5)
	# 2 cells x 5 open faces x 9 verts.
	assert_eq(shell.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), 90)
