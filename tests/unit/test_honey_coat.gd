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
	assert_almost_eq(tuning.drip_speed, 0.2, 0.0001)
	assert_almost_eq(tuning.roughness, 0.05, 0.0001)


func test_shader_loads_and_material_carries_the_tuning() -> void:
	var shader: Shader = load(SHADER_PATH) as Shader
	assert_not_null(shader)
	assert_eq(shader.get_mode(), Shader.MODE_SPATIAL)
	var tuning: HoneyCoatTuning = load(TUNING_PATH) as HoneyCoatTuning
	var material: ShaderMaterial = tuning.build_material(true)
	assert_eq(material.shader, shader)
	assert_eq(material.get_shader_parameter(&"honey_color"), tuning.color)
	assert_almost_eq(float(material.get_shader_parameter(&"drip_speed")), tuning.drip_speed, 0.0001)
	var frozen: ShaderMaterial = tuning.build_material(false)
	assert_almost_eq(float(frozen.get_shader_parameter(&"drip_speed")), 0.0, 0.0001)


func test_glue_ghost_gets_honey_overlay_and_loses_it() -> void:
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


func test_glue_ghost_is_a_faint_tint_without_drips() -> void:
	var ghost: GhostPreview = _make_ghost()
	var mesh: MeshInstance3D = _meshes(ghost)[0]
	ghost.set_glue_charges(1)
	assert_null(mesh.get_node_or_null("HoneyDrips"), "the translucent ghost gets no drips (they flickered)")
	var overlay: ShaderMaterial = mesh.material_overlay as ShaderMaterial
	assert_true(bool(overlay.get_shader_parameter(&"ghost_mode")))
	assert_false(bool(overlay.get_shader_parameter(&"drip_mesh")))
	var tuning: HoneyCoatTuning = load(TUNING_PATH) as HoneyCoatTuning
	assert_lt(tuning.ghost_alpha, 1.0, "translucent so the validity colour reads through")
	assert_almost_eq(float(overlay.get_shader_parameter(&"patch_coverage")), tuning.patch_coverage, 0.0001)


func test_placed_drips_hang_from_the_bottom_edge() -> void:
	var tuning: HoneyCoatTuning = load(TUNING_PATH) as HoneyCoatTuning
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	mesh_instance.mesh = box
	add_child_autofree(mesh_instance)
	var count: int = tuning.attach_drips(mesh_instance, tuning.build_drip_material(false))
	assert_gt(count, 0)
	assert_true(count <= tuning.max_drips)
	var lowest: float = box.get_aabb().position.y
	for drip: Node in mesh_instance.get_node("HoneyDrips").get_children():
		assert_almost_eq((drip as Node3D).position.y, lowest, 0.01)
