extends GutTest
## Bontago-1pi.11.42 (owner decision Bontago-gdb): holes are a shader effect.
## Pins the wiring of the animated void (disc uniforms, minimap hole colour,
## graphics presets) and game/BlockDissolveFx.gd (per-block instance uniform,
## cleanup, shared materials untouched).

const CELLS_PER_SIDE: int = 13

var _tuning: PhysicsTuning = load("res://config/physics_tuning.tres")
var _cube: BlockShape = load("res://config/blocks/cube.tres")
var _hole_visuals: HoleVisualTuning = load("res://config/hole_visual_tuning.tres")
var _original_preset_id: StringName


func before_each() -> void:
	_original_preset_id = Settings.current_graphics_preset().id


func after_each() -> void:
	Settings.set_graphics_preset(_original_preset_id)


func _overlay() -> TerritoryOverlay:
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_hole_visuals"
	map_def.field_radius = float(CELLS_PER_SIDE) * 0.5
	map_def.cell_size = 1.0
	map_def.territory_res = CELLS_PER_SIDE * 5
	var overlay: TerritoryOverlay = TerritoryOverlay.new()
	overlay.configure(map_def, load("res://config/territory_visuals.tres"), load("res://config/territory_tuning.tres"))
	add_child_autofree(overlay)
	return overlay


func _fx() -> BlockDissolveFx:
	var fx: BlockDissolveFx = BlockDissolveFx.new()
	add_child_autofree(fx)
	return fx


func _block() -> Block:
	var block: Block = BlockFactory.build(_cube, _tuning)
	add_child_autofree(block)
	return block


func _instance_amount(block: Block, node_name: StringName) -> float:
	var mesh: MeshInstance3D = block.get_node(NodePath(String(node_name))) as MeshInstance3D
	var value: Variant = mesh.get_instance_shader_parameter(&"dissolve_amount")
	return 0.0 if value == null else float(value)


# --- Disc void ---------------------------------------------------------------

func test_overlay_uploads_void_uniforms() -> void:
	Settings.set_graphics_preset(&"high")
	var overlay: TerritoryOverlay = _overlay()
	var material: ShaderMaterial = overlay.material()
	assert_eq(material.get_shader_parameter(&"void_deep_color"), _hole_visuals.void_deep_color)
	assert_eq(material.get_shader_parameter(&"void_rim_glow"), _hole_visuals.void_rim_glow)
	assert_eq(material.get_shader_parameter(&"void_band_count"), _hole_visuals.void_band_count)
	assert_almost_eq(float(material.get_shader_parameter(&"void_animated")), 1.0, 0.001)


func test_hole_cell_uv_matches_the_grid() -> void:
	var overlay: TerritoryOverlay = _overlay()
	var map_def: MapDef = MapDef.new()
	map_def.field_radius = float(CELLS_PER_SIDE) * 0.5
	map_def.cell_size = 1.0
	var raster: TerritoryRaster = TerritoryRaster.new(
		CellGrid.new(map_def.field_radius, map_def.cell_size), load("res://config/territory_tuning.tres")
	)
	overlay.set_source(raster, PackedColorArray())
	assert_almost_eq(
		float(overlay.material().get_shader_parameter(&"hole_cell_uv")), 1.0 / float(overlay.cells_per_side()), 0.0001
	)


func test_disc_shader_no_longer_discards_holes() -> void:
	var code: String = (load("res://shaders/territory.gdshader") as Shader).code
	assert_false(code.contains("\t\tdiscard;"), "A hole is drawn as a void, never cut out.")
	assert_true(code.contains("hole_void("), "The void branch exists.")


func test_presets_toggle_the_void_animation() -> void:
	var overlay: TerritoryOverlay = _overlay()
	Settings.set_graphics_preset(&"low")
	assert_false(overlay.void_animated())
	assert_almost_eq(float(overlay.material().get_shader_parameter(&"void_animated")), 0.0, 0.001)
	Settings.set_graphics_preset(&"high")
	assert_true(overlay.void_animated())
	assert_almost_eq(float(overlay.material().get_shader_parameter(&"void_animated")), 1.0, 0.001)


func test_minimap_shader_has_a_hole_colour() -> void:
	var code: String = (load("res://shaders/minimap_territory.gdshader") as Shader).code
	assert_true(code.contains("uniform vec4 hole_color"))


# --- Block dissolve ----------------------------------------------------------

func test_dissolve_start_fades_only_the_right_block() -> void:
	Settings.set_graphics_preset(&"high")
	var fx: BlockDissolveFx = _fx()
	var target: Block = _block()
	var other: Block = _block()
	Events.block_dissolve_started.emit(target, 1, 0.4)
	assert_eq(fx.active_count(), 1)
	fx.step(0.2)
	assert_almost_eq(fx.amount_for(target), 0.5, 0.001)
	assert_almost_eq(_instance_amount(target, &"BlockMesh"), 0.5, 0.001)
	assert_almost_eq(_instance_amount(target, &"BlockOutline"), 0.5, 0.001, "The outline fades in step.")
	assert_almost_eq(_instance_amount(other, &"BlockMesh"), 0.0, 0.001, "Other blocks are untouched.")
	fx.step(1.0)
	assert_almost_eq(fx.amount_for(target), 1.0, 0.001, "Progress clamps at 1.")


func test_shared_materials_are_not_modified() -> void:
	Settings.set_graphics_preset(&"high")
	var fx: BlockDissolveFx = _fx()
	var target: Block = _block()
	var other: Block = _block()
	var mesh: MeshInstance3D = target.get_node("BlockMesh") as MeshInstance3D
	assert_same(mesh.material_override, (other.get_node("BlockMesh") as MeshInstance3D).material_override)
	Events.block_dissolve_started.emit(target, 1, 0.4)
	fx.step(0.1)
	assert_same(mesh.material_override, (other.get_node("BlockMesh") as MeshInstance3D).material_override)
	assert_eq(mesh.get_instance_shader_parameter(&"dissolve_amount") != null, true)


func test_removal_cleans_up() -> void:
	Settings.set_graphics_preset(&"high")
	var fx: BlockDissolveFx = _fx()
	var target: Block = _block()
	Events.block_dissolve_started.emit(target, 1, 0.4)
	fx.step(0.1)
	Events.block_removed.emit(target, String(Events.REASON_KILL_PLANE))
	assert_eq(fx.active_count(), 0, "A removed block leaves the table.")
	target.queue_free()
	await get_tree().process_frame
	fx.step(0.1)
	assert_eq(fx.active_count(), 0, "A freed block never errors the next step.")


func test_zero_duration_is_fully_dissolved_at_once() -> void:
	Settings.set_graphics_preset(&"high")
	var fx: BlockDissolveFx = _fx()
	var target: Block = _block()
	Events.block_dissolve_started.emit(target, 1, 0.0)
	assert_almost_eq(fx.amount_for(target), 1.0, 0.001)


func test_low_preset_skips_the_effect() -> void:
	Settings.set_graphics_preset(&"low")
	var fx: BlockDissolveFx = _fx()
	var target: Block = _block()
	Events.block_dissolve_started.emit(target, 1, 0.4)
	assert_false(fx.is_effect_enabled())
	assert_eq(fx.active_count(), 0)
	Settings.set_graphics_preset(&"high")
	assert_true(fx.is_effect_enabled(), "Switching presets re-enables it live.")
	Events.block_dissolve_started.emit(target, 1, 0.4)
	assert_eq(fx.active_count(), 1)
	Settings.set_graphics_preset(&"low")
	assert_eq(fx.active_count(), 0, "Switching off mid-fade clears and resets.")
	assert_almost_eq(_instance_amount(target, &"BlockMesh"), 0.0, 0.001)


func test_field_scene_owns_a_dissolve_fx_node() -> void:
	var field: Node = (load("res://game/Field.tscn") as PackedScene).instantiate()
	autofree(field)
	assert_not_null(field.get_node_or_null("BlockDissolveFx") as BlockDissolveFx)
