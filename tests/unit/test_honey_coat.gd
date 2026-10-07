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
	assert_eq(tuning.color, Color(0.98, 0.7, 0.06, 0.93))
	assert_almost_eq(tuning.thickness_m, 0.03, 0.0001)
	assert_almost_eq(tuning.drip_scale, 6.0, 0.0001)
	assert_almost_eq(tuning.drip_speed, 0.35, 0.0001)
	assert_almost_eq(tuning.drip_depth, 0.25, 0.0001)
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


func test_glue_ghost_hangs_drips_below_the_bottom_edge_and_clears_them() -> void:
	var ghost: GhostPreview = _make_ghost()
	var mesh: MeshInstance3D = _meshes(ghost)[0]
	ghost.set_glue_charges(1)
	var holder: Node = mesh.get_node_or_null("HoneyDrips")
	assert_not_null(holder, "glued ghost gets a drip holder")
	assert_gt(holder.get_child_count(), 0)
	var lowest: float = mesh.mesh.get_aabb().position.y
	for drip: Node in holder.get_children():
		assert_almost_eq((drip as Node3D).position.y, lowest, 0.01, "drips hang from the bottom plane")
	ghost.set_glue_charges(0)
	assert_null(mesh.get_node_or_null("HoneyDrips"))
