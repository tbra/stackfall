extends GutTest
## Bontago-1pi.11.60: the per-block outline is a next_pass on the block's mesh
## material (no separate BlockOutline node), and Block._integrate_forces()
## skips its rebound work for frozen bodies.

const CUBE_PATH: String = "res://config/blocks/cube.tres"
const COLOR_A: Color = Color(0.9, 0.2, 0.2)
const COLOR_B: Color = Color(0.2, 0.4, 0.9)
const SETTLE_FRAMES: int = 5
const TOLERANCE: float = 0.0001

var _tuning: PhysicsTuning = load("res://config/physics_tuning.tres")
var _visual: BlockVisualTuning = load("res://config/block_visual_tuning.tres")


func _mesh_children(block: Block) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child: Node in block.get_children():
		if child is MeshInstance3D:
			result.append(child as MeshInstance3D)
	return result


func test_block_has_no_separate_outline_node() -> void:
	var block: Block = autofree(BlockFactory.build(load(CUBE_PATH), _tuning, 0, COLOR_A))
	assert_null(block.get_node_or_null("BlockOutline"))
	assert_eq(_mesh_children(block).size(), 1, "one MeshInstance3D per block")


func test_material_carries_configured_outline_next_pass() -> void:
	var block: Block = autofree(BlockFactory.build(load(CUBE_PATH), _tuning, 0, COLOR_A))
	var material: ShaderMaterial = _mesh_children(block)[0].material_override as ShaderMaterial
	var outline: ShaderMaterial = material.next_pass as ShaderMaterial
	assert_not_null(outline)
	assert_eq(outline.shader.resource_path, "res://shaders/block_outline.gdshader")
	assert_almost_eq(float(outline.get_shader_parameter(&"outline_width_px")), _visual.outline_width_px, TOLERANCE)
	assert_almost_eq(float(outline.get_shader_parameter(&"outline_far_width_px")), _visual.outline_far_width_px, TOLERANCE)
	assert_true((outline.get_shader_parameter(&"outline_color") as Color).is_equal_approx(_visual.outline_color))
	assert_almost_eq(float(outline.get_shader_parameter(&"outline_tint_amount")), _visual.outline_tint_amount, TOLERANCE)


func test_outline_tint_follows_owner_colour_and_recolor() -> void:
	var block: Block = autofree(BlockFactory.build(load(CUBE_PATH), _tuning, 0, COLOR_A))
	var mesh: MeshInstance3D = _mesh_children(block)[0]
	var first: ShaderMaterial = (mesh.material_override as ShaderMaterial).next_pass as ShaderMaterial
	assert_eq(first.get_shader_parameter(&"tint_color"), COLOR_A)
	BlockFactory.recolor(block, COLOR_B)
	var second: ShaderMaterial = (mesh.material_override as ShaderMaterial).next_pass as ShaderMaterial
	assert_eq(second.get_shader_parameter(&"tint_color"), COLOR_B)


func _count_next_pass(root: Node3D) -> int:
	var total: int = 0
	for child: Node in root.get_children():
		var mesh: MeshInstance3D = child as MeshInstance3D
		if mesh != null and mesh.material_override != null and mesh.material_override.next_pass != null:
			total += 1
	return total


func test_ghost_visual_has_no_outline_pass() -> void:
	var visual: Node3D = autofree(BlockFactory.build_visual_only(load(CUBE_PATH), _tuning))
	for child: Node in visual.get_children():
		var mesh: MeshInstance3D = child as MeshInstance3D
		if mesh != null and mesh.material_override != null:
			assert_null(mesh.material_override.next_pass)


func test_frozen_block_skips_rebound_work_and_awake_runs_it() -> void:
	var awake: Block = BlockFactory.build(load(CUBE_PATH), _tuning, 0, COLOR_A)
	var frozen: Block = BlockFactory.build(load(CUBE_PATH), _tuning, 0, COLOR_A)
	frozen.freeze = true
	add_child(awake)
	add_child(frozen)
	await wait_physics_frames(SETTLE_FRAMES)
	assert_eq(frozen.rebound_work_runs, 0, "frozen body skips the rebound work")
	assert_gt(awake.rebound_work_runs, 0, "awake body still runs it")
	awake.free()
	frozen.free()
