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


# --- Smooth void territory (Bontago-1pi.11.44) --------------------------------

func _state_bytes(holes: Array[Vector2i]) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(CELLS_PER_SIDE * CELLS_PER_SIDE)
	for cell: Vector2i in holes:
		bytes[cell.y * CELLS_PER_SIDE + cell.x] = TerritoryRaster.STATE_CONTESTED | TerritoryRaster.STATE_HOLE
	return bytes


## Mirror of territory.gdshader's linear-filtered territory_hole read at a
## continuous cell-space point (texel centres at cell centres).
func _mask_at(image: Image, cell_point: Vector2, channel: int = 0) -> float:
	var f: Vector2 = cell_point - Vector2(0.5, 0.5)
	var base: Vector2i = Vector2i(floori(f.x), floori(f.y))
	var w: Vector2 = f - Vector2(base)
	var total: float = 0.0
	for dy: int in range(2):
		for dx: int in range(2):
			var tx: int = clampi(base.x + dx, 0, CELLS_PER_SIDE - 1)
			var ty: int = clampi(base.y + dy, 0, CELLS_PER_SIDE - 1)
			var weight: float = (w.x if dx == 1 else 1.0 - w.x) * (w.y if dy == 1 else 1.0 - w.y)
			total += image.get_pixel(tx, ty)[channel] * weight
	return total


## Mirror of void_signed_distance() with a 1 m cell: g is the smooth overlap field.
func _void_d(image: Image, p: Vector2, g: float) -> float:
	var mask: float = _mask_at(image, p)
	var contested: float = _mask_at(image, p, 1)
	var blob: float = mask - 0.5 if contested < 0.05 else -1000000.0
	return maxf(minf(g, mask - 0.2), blob)


func test_hole_mask_texture_follows_open_and_close() -> void:
	var overlay: TerritoryOverlay = _overlay()
	var cell: Vector2i = Vector2i(5, 6)
	overlay.push_cells(PackedByteArray(), _state_bytes([cell]), CELLS_PER_SIDE)
	var image: Image = overlay.hole_mask_image()
	assert_almost_eq(image.get_pixel(cell.x, cell.y).r, 1.0, 0.01)
	assert_almost_eq(image.get_pixel(cell.x + 1, cell.y).r, 0.0, 0.01)
	assert_eq(overlay.material().get_shader_parameter(&"territory_hole"), overlay.hole_mask_texture())
	overlay.push_cells(PackedByteArray(), _state_bytes([]), CELLS_PER_SIDE)
	assert_almost_eq(overlay.hole_mask_image().get_pixel(cell.x, cell.y).r, 0.0, 0.01, "A closed hole clears.")


func test_contested_only_cell_is_not_a_void() -> void:
	var overlay: TerritoryOverlay = _overlay()
	var bytes: PackedByteArray = _state_bytes([])
	bytes[3] = TerritoryRaster.STATE_CONTESTED
	overlay.push_cells(PackedByteArray(), bytes, CELLS_PER_SIDE)
	assert_almost_eq(overlay.hole_mask_image().get_pixel(3, 0).r, 0.0, 0.01, "Contested before hole_delay stays hidden.")


func test_void_edge_follows_a_curved_boundary_not_cell_squares() -> void:
	var overlay: TerritoryOverlay = _overlay()
	var holes: Array[Vector2i] = []
	for y: int in range(3, 10):
		for x: int in range(3, 10):
			holes.append(Vector2i(x, y))
	overlay.push_cells(PackedByteArray(), _state_bytes(holes), CELLS_PER_SIDE)
	var image: Image = overlay.hole_mask_image()
	# A circle of radius 3.3 cells about (6.5, 6.5): g = radius - distance.
	var centre: Vector2 = Vector2(6.5, 6.5)
	var seen_in: bool = false
	var seen_out: bool = false
	for step: int in range(0, 20):
		var p: Vector2 = Vector2(9.0 + float(step) / 20.0, 6.5)
		var inside: bool = _void_d(image, p, 3.3 - p.distance_to(centre)) > 0.0
		seen_in = seen_in or inside
		seen_out = seen_out or not inside
	assert_true(seen_in and seen_out, "One hole cell is partly void, partly floor: the edge is the circle, not the cell.")
	var far_corner: Vector2 = Vector2(9.95, 6.95)
	var cell_centre: Vector2 = Vector2(9.5, 6.5)
	assert_lt(_void_d(image, far_corner, 3.3 - far_corner.distance_to(centre)), 0.0)
	assert_gt(_void_d(image, cell_centre, 3.3 - cell_centre.distance_to(centre)), 0.0)


func test_isolated_hole_without_overlap_is_a_rounded_blob() -> void:
	var overlay: TerritoryOverlay = _overlay()
	var bytes: PackedByteArray = _state_bytes([])
	bytes[6 * CELLS_PER_SIDE + 6] = TerritoryRaster.STATE_HOLE
	overlay.push_cells(PackedByteArray(), bytes, CELLS_PER_SIDE)
	var image: Image = overlay.hole_mask_image()
	var no_overlap: float = -1000000.0
	assert_gt(_void_d(image, Vector2(6.5, 6.5), no_overlap), 0.0, "Centre of a forced hole is void.")
	assert_lt(_void_d(image, Vector2(6.02, 6.02), no_overlap), 0.0, "The cell corner is rounded off.")


func test_shader_wires_the_overlap_void_layer() -> void:
	var code: String = (load("res://shaders/territory.gdshader") as Shader).code
	assert_true(code.contains("uniform sampler2D territory_hole"))
	assert_true(code.contains("void_g = argmax_mode"), "circle_path publishes the smooth overlap field.")
	assert_true(code.contains("void_signed_distance("))


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
	assert_null(target.get_node_or_null("BlockOutline"), "The outline is a next_pass now, fading with BlockMesh.")
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
