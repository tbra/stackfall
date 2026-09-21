extends GutTest
## TerritoryOverlay turns the cell raster into the ImageTexture the disk shader
## samples (spec 2.10, 3.3, docs/M2_PLAN.md "Raster resolution").
##
## The raster itself is P1's; these tests drive the overlay through a stand-in
## that answers owner_bytes()/state_bytes() with hand-built cells, so they pin
## the upload path and not the solver.

## CellGrid rounds its resolution up to an odd number (see the DECISION there),
## so a test map's cells per side is odd too.
const CELLS_PER_SIDE: int = 13
## An odd upscale factor (5) so that one dest pixel lands exactly on each cell
## center, which lets a test read a cell's bytes back unblended.
const UPSCALE: int = 5
const UPLOAD_RES: int = CELLS_PER_SIDE * UPSCALE


## A TerritoryRaster whose bytes are whatever the test says they are.
class ScriptedRaster extends TerritoryRaster:
	var owners: PackedByteArray = PackedByteArray()
	var states: PackedByteArray = PackedByteArray()

	func _init(grid: CellGrid, tuning: TerritoryTuning) -> void:
		super(grid, tuning)
		var count: int = grid.cell_count()
		owners.resize(count)
		states.resize(count)

	func set_cell(index: int, owner_byte: int, state_byte: int) -> void:
		owners[index] = owner_byte
		states[index] = state_byte

	func owner_bytes() -> PackedByteArray:
		return owners

	func state_bytes() -> PackedByteArray:
		return states


func _map() -> MapDef:
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_overlay"
	map_def.field_radius = float(CELLS_PER_SIDE) * 0.5
	map_def.cell_size = 1.0
	map_def.territory_res = UPLOAD_RES
	return map_def


func _make_overlay(map_def: MapDef) -> TerritoryOverlay:
	var overlay: TerritoryOverlay = TerritoryOverlay.new()
	overlay.configure(map_def, load("res://config/territory_visuals.tres"), load("res://config/territory_tuning.tres"))
	add_child_autofree(overlay)
	return overlay


func _make_raster(map_def: MapDef) -> ScriptedRaster:
	var grid: CellGrid = CellGrid.new(map_def.field_radius, map_def.cell_size)
	return ScriptedRaster.new(grid, load("res://config/territory_tuning.tres"))


## The upscaled pixel sitting exactly on cell (cx, cy)'s center.
func _sample(image: Image, cx: int, cy: int) -> Color:
	var middle: int = floori(float(UPSCALE - 1) * 0.5)
	return image.get_pixel(cx * UPSCALE + middle, cy * UPSCALE + middle)


func test_upload_is_territory_res_square() -> void:
	var map_def: MapDef = _map()
	var overlay: TerritoryOverlay = _make_overlay(map_def)
	var raster: ScriptedRaster = _make_raster(map_def)
	overlay.set_source(raster, PackedColorArray())

	var image: Image = overlay.last_image()
	assert_not_null(image, "set_source uploads immediately.")
	assert_eq(image.get_width(), UPLOAD_RES, "Spec 3.3: uploaded at territory_res.")
	assert_eq(image.get_height(), UPLOAD_RES)
	assert_eq(overlay.texture().get_width(), UPLOAD_RES)
	assert_eq(overlay.cells_per_side(), CELLS_PER_SIDE, "The rules stay at cell resolution.")


func test_owner_bytes_survive_the_upscale() -> void:
	var map_def: MapDef = _map()
	var overlay: TerritoryOverlay = _make_overlay(map_def)
	var raster: ScriptedRaster = _make_raster(map_def)
	var grid: CellGrid = raster.grid()

	# Two overlapping-ish blocks of territory: team 0 on the left half, team 2
	# on the right, so the R channel carries 1 and 3.
	for cy: int in range(grid.res):
		for cx: int in range(grid.res):
			var owner_byte: int = 1 if cx < floori(float(grid.res) * 0.5) else 3
			raster.set_cell(grid.cell_index(cx, cy), owner_byte, 0)
	overlay.set_source(raster, PackedColorArray())

	var image: Image = overlay.last_image()
	var left: Color = _sample(image, 2, 6)
	var right: Color = _sample(image, 9, 6)
	assert_eq(left.r8, 1, "Team 0's cells read back as R = team_id + 1.")
	assert_eq(right.r8, 3, "Team 2's cells read back as R = team_id + 1.")


func test_state_bytes_go_up_verbatim() -> void:
	var map_def: MapDef = _map()
	var overlay: TerritoryOverlay = _make_overlay(map_def)
	var raster: ScriptedRaster = _make_raster(map_def)
	var grid: CellGrid = raster.grid()

	raster.set_cell(grid.cell_index(3, 3), 0, TerritoryRaster.STATE_CONTESTED)
	raster.set_cell(grid.cell_index(8, 8), 0, TerritoryRaster.STATE_HOLE)
	raster.set_cell(
		grid.cell_index(9, 9),
		0,
		TerritoryRaster.STATE_CONTESTED | TerritoryRaster.STATE_HOLE
	)
	overlay.set_source(raster, PackedColorArray())

	# The state grid goes up unblended at cell resolution: the shader's hole
	# discard has to land on exactly the cell whose collision Field switched
	# off, and an interpolated bit field cannot answer that.
	var states: Image = overlay.state_cell_image()
	assert_eq(states.get_width(), CELLS_PER_SIDE)
	assert_eq(states.get_pixel(3, 3).r8, TerritoryRaster.STATE_CONTESTED)
	assert_eq(states.get_pixel(8, 8).r8, TerritoryRaster.STATE_HOLE)
	assert_eq(
		states.get_pixel(9, 9).r8,
		TerritoryRaster.STATE_CONTESTED | TerritoryRaster.STATE_HOLE
	)
	assert_eq(states.get_pixel(0, 0).r8, 0, "An untouched cell carries no state.")


func test_owner_ids_also_go_up_unblended_at_cell_resolution() -> void:
	var map_def: MapDef = _map()
	var overlay: TerritoryOverlay = _make_overlay(map_def)
	var raster: ScriptedRaster = _make_raster(map_def)
	var grid: CellGrid = raster.grid()
	raster.set_cell(grid.cell_index(4, 4), 1, 0)
	raster.set_cell(grid.cell_index(5, 4), 3, 0)
	overlay.set_source(raster, PackedColorArray())

	# The shader reads team ids off this second texture, because the bilinear
	# upscale invents ids between two teams: halfway between 1 and 3 is 2,
	# which would ring the border in a third player's color.
	var cells: ImageTexture = overlay.cell_texture()
	assert_not_null(cells, "The overlay uploads the raw cell grid as well.")
	assert_eq(cells.get_width(), CELLS_PER_SIDE, "Unblended, at cell resolution.")
	assert_eq(cells.get_height(), CELLS_PER_SIDE)
	assert_not_null(overlay.state_texture(), "And the state grid beside it.")
	assert_eq(overlay.owner_cell_image().get_pixel(4, 4).r8, 1)
	assert_eq(overlay.owner_cell_image().get_pixel(5, 4).r8, 3)
	assert_eq(
		overlay.texture().get_width(),
		UPLOAD_RES,
		"The filtered texture is still the territory_res upload."
	)


func test_empty_raster_bytes_upload_as_unowned() -> void:
	var map_def: MapDef = _map()
	var overlay: TerritoryOverlay = _make_overlay(map_def)
	# owner_bytes()/state_bytes() empty is what a raster reports before its
	# first solve; it must upload a blank disk, not crash.
	var raster: ScriptedRaster = _make_raster(map_def)
	raster.owners = PackedByteArray()
	raster.states = PackedByteArray()
	overlay.set_source(raster, PackedColorArray())

	var image: Image = overlay.last_image()
	assert_eq(image.get_width(), UPLOAD_RES)
	assert_eq(_sample(image, 5, 5).r8, 0, "Nothing is owned yet.")


func test_slot_colors_reach_the_shader() -> void:
	var map_def: MapDef = _map()
	var overlay: TerritoryOverlay = _make_overlay(map_def)
	var colors: PackedColorArray = PackedColorArray([
		Color(0.9, 0.25, 0.25), Color(0.25, 0.55, 0.95),
	])
	overlay.set_slot_colors(colors)

	var uniform: Variant = overlay.material().get_shader_parameter(&"slot_colors")
	assert_not_null(uniform, "The shader's slot_colors array is set, not left default.")
	var stored: Array = uniform as Array
	assert_eq(stored.size(), TerritoryOverlay.SLOT_COLOR_MAX, "All eight slots are filled.")
	var first: Color = stored[0]
	assert_almost_eq(
		first.r, colors[0].srgb_to_linear().r, 0.01,
		"Colors are converted to linear, because an array uniform cannot carry source_color."
	)


func test_uv_uniforms_map_the_disk_onto_the_texture() -> void:
	var map_def: MapDef = _map()
	var overlay: TerritoryOverlay = _make_overlay(map_def)
	var raster: ScriptedRaster = _make_raster(map_def)
	overlay.set_source(raster, PackedColorArray())

	var uv_scale: float = float(overlay.material().get_shader_parameter(&"uv_scale"))
	var uv_offset: float = float(overlay.material().get_shader_parameter(&"uv_offset"))
	# CellGrid's square is centred on the disk centre and is half_extent wide
	# either way, so -half_extent maps to UV 0, the centre to 0.5 and
	# +half_extent to UV 1.
	var half_extent: float = raster.grid().half_extent
	assert_almost_eq(-half_extent * uv_scale + uv_offset, 0.0, 0.0001)
	assert_almost_eq(uv_offset, 0.5, 0.0001)
	assert_almost_eq(half_extent * uv_scale + uv_offset, 1.0, 0.0001)


# --- Bontago-cmc.5: the analytic circle list -------------------------------


func _make_overlay_with_visuals(map_def: MapDef, visuals: TerritoryVisuals) -> TerritoryOverlay:
	var overlay: TerritoryOverlay = TerritoryOverlay.new()
	overlay.configure(map_def, visuals, load("res://config/territory_tuning.tres"))
	add_child_autofree(overlay)
	return overlay


func test_set_circles_uploads_one_texel_per_circle() -> void:
	var overlay: TerritoryOverlay = _make_overlay(_map())
	var xs: PackedFloat32Array = PackedFloat32Array([1.0, -2.0, 3.0])
	var zs: PackedFloat32Array = PackedFloat32Array([0.5, 1.5, -1.5])
	var radii: PackedFloat32Array = PackedFloat32Array([2.0, 3.0, 4.0])
	var teams: PackedInt32Array = PackedInt32Array([0, 1, 0])

	overlay.set_circles(
		xs, zs, radii, teams, PackedVector2Array(), PackedFloat32Array(), false
	)

	assert_eq(overlay.circle_count(), 3, "The shader's circle_count uniform.")
	assert_eq(overlay.circle_texture().get_width(), 3, "One texel per circle, RGBAF.")
	var texel: Color = overlay.circle_image().get_pixel(1, 0)
	assert_almost_eq(texel.r, xs[1], 0.001, "R = disk-local x")
	assert_almost_eq(texel.g, zs[1], 0.001, "G = disk-local z")
	assert_almost_eq(texel.b, radii[1], 0.001, "B = radius")
	assert_almost_eq(texel.a, float(teams[1]), 0.001, "A = team id")
	assert_true(
		bool(overlay.material().get_shader_parameter(&"circles_valid")),
		"Within max_shader_circles, the analytic path is used."
	)


func test_set_circles_uploads_goal_discs_independently() -> void:
	var overlay: TerritoryOverlay = _make_overlay(_map())
	var goal_positions: PackedVector2Array = PackedVector2Array([Vector2(4.0, -4.0)])
	var goal_radii: PackedFloat32Array = PackedFloat32Array([4.0])

	overlay.set_circles(
		PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array(), PackedInt32Array(),
		goal_positions, goal_radii, false
	)

	assert_eq(overlay.goal_count(), 1)
	assert_eq(overlay.goal_texture().get_width(), 1)
	var texel: Color = overlay.goal_image().get_pixel(0, 0)
	assert_almost_eq(texel.r, 4.0, 0.001)
	assert_almost_eq(texel.g, -4.0, 0.001)
	assert_almost_eq(texel.b, 4.0, 0.001)


func test_a_circle_list_over_the_shader_budget_falls_back_to_the_raster_path() -> void:
	var visuals: TerritoryVisuals = load("res://config/territory_visuals.tres").duplicate() as TerritoryVisuals
	visuals.max_shader_circles = 2
	var overlay: TerritoryOverlay = _make_overlay_with_visuals(_map(), visuals)

	var xs: PackedFloat32Array = PackedFloat32Array([0.0, 1.0, 2.0])
	var zs: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0])
	var radii: PackedFloat32Array = PackedFloat32Array([1.0, 1.0, 1.0])
	var teams: PackedInt32Array = PackedInt32Array([0, 0, 0])
	overlay.set_circles(xs, zs, radii, teams, PackedVector2Array(), PackedFloat32Array(), false)

	assert_eq(overlay.circle_count(), 3, "The full list still uploads, for readback.")
	assert_false(
		bool(overlay.material().get_shader_parameter(&"circles_valid")),
		"Over max_shader_circles: the shader must fall back to the raster path, spec 3.3 'Bounded cost'."
	)


func test_set_source_null_clears_the_circle_list() -> void:
	var map_def: MapDef = _map()
	var overlay: TerritoryOverlay = _make_overlay(map_def)
	overlay.set_circles(
		PackedFloat32Array([1.0]), PackedFloat32Array([1.0]), PackedFloat32Array([1.0]),
		PackedInt32Array([0]), PackedVector2Array(), PackedFloat32Array(), false
	)
	assert_eq(overlay.circle_count(), 1)

	overlay.set_source(null, PackedColorArray())

	assert_eq(overlay.circle_count(), 0, "set_source(null) must not leave a stale match's circles up.")
	assert_eq(overlay.goal_count(), 0)
	assert_false(bool(overlay.material().get_shader_parameter(&"circles_valid")))


func test_configure_starts_with_no_circles() -> void:
	var overlay: TerritoryOverlay = _make_overlay(_map())
	assert_eq(overlay.circle_count(), 0, "Before any solve, the blank disk has no circles either.")
	assert_false(bool(overlay.material().get_shader_parameter(&"circles_valid")))


func test_field_hands_its_overlay_the_source() -> void:
	var field: Field = Field.new()
	field.map_def = _map()
	add_child_autofree(field)

	var raster: ScriptedRaster = _make_raster(field.map_def)
	var grid: CellGrid = raster.grid()
	raster.set_cell(grid.cell_index(6, 6), 2, 0)
	field.set_overlay_source(raster, PackedColorArray([Color.RED, Color.BLUE]))

	var image: Image = field.overlay().last_image()
	assert_not_null(image, "Field.set_overlay_source uploads through the overlay.")
	assert_eq(_sample(image, 6, 6).r8, 2)


func test_field_hands_its_overlay_the_circle_list() -> void:
	var field: Field = Field.new()
	field.map_def = _map()
	add_child_autofree(field)

	field.set_overlay_circles(
		PackedFloat32Array([2.0]), PackedFloat32Array([3.0]), PackedFloat32Array([1.5]),
		PackedInt32Array([1]), PackedVector2Array(), PackedFloat32Array(), false
	)

	assert_eq(field.overlay().circle_count(), 1, "Field.set_overlay_circles routes to the overlay.")
	var texel: Color = field.overlay().circle_image().get_pixel(0, 0)
	assert_almost_eq(texel.a, 1.0, 0.001, "Team id survives the hand-off.")
