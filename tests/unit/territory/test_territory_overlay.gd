extends GutTest
## TerritoryOverlay turns the cell raster into the ImageTexture the disk shader
## samples (spec 1.10, 3.3).
##
## The raster itself is tested in test_territory_raster.gd; these tests drive the
## overlay through a stand-in that answers owner_bytes()/state_bytes() with
## hand-built cells, so they pin the upload path and not the solver.

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
		_mark_changed()

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
	overlay.configure(map_def, load("res://config/territory/territory_visuals.tres"), load("res://config/territory/territory_tuning.tres"))
	add_child_autofree(overlay)
	return overlay


func _make_raster(map_def: MapDef) -> ScriptedRaster:
	var grid: CellGrid = CellGrid.new(map_def.field_radius, map_def.cell_size)
	return ScriptedRaster.new(grid, load("res://config/territory/territory_tuning.tres"))


## The upscaled pixel sitting exactly on cell (cx, cy)'s center.
func _sample(image: Image, cx: int, cy: int) -> Color:
	var middle: int = floori(float(UPSCALE - 1) * 0.5)
	return image.get_pixel(cx * UPSCALE + middle, cy * UPSCALE + middle)


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


func test_the_shader_reads_owner_ids_from_the_unblended_cell_grid() -> void:
	var map_def: MapDef = _map()
	var overlay: TerritoryOverlay = _make_overlay(map_def)
	var raster: ScriptedRaster = _make_raster(map_def)
	var grid: CellGrid = raster.grid()
	raster.set_cell(grid.cell_index(4, 4), 1, 0)
	raster.set_cell(grid.cell_index(5, 4), 3, 0)
	overlay.set_source(raster, PackedColorArray())

	# The shader reads team ids off territory_cells, because the bilinear upscale
	# invents ids between two teams: halfway between 1 and 3 is 2, which would
	# ring the border in a third player's color. So it must be bound at cell
	# resolution, not the territory_res texture.
	var cells: ImageTexture = overlay.material().get_shader_parameter(&"territory_cells") as ImageTexture
	assert_not_null(cells, "The overlay binds the raw cell grid as well.")
	assert_eq(cells.get_width(), CELLS_PER_SIDE, "Unblended, at cell resolution.")
	assert_eq(cells.get_height(), CELLS_PER_SIDE)
	var states: ImageTexture = overlay.material().get_shader_parameter(&"territory_state") as ImageTexture
	assert_not_null(states, "And the state grid beside it.")
	assert_eq(states.get_width(), CELLS_PER_SIDE)
	assert_eq(
		overlay.texture().get_width(),
		UPLOAD_RES,
		"The filtered texture is still the territory_res upload."
	)
	assert_eq(
		(overlay.material().get_shader_parameter(&"territory_tex") as ImageTexture).get_width(),
		UPLOAD_RES,
		"territory_tex stays the filtered upload."
	)


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


func test_refresh_visual_uniforms_keeps_slot_colors() -> void:
	# A visuals refresh (the F4 panel, a graphics change) must re-push the team
	# colors rather than reset every slot to the goal-flag color.
	var overlay: TerritoryOverlay = _make_overlay(_map())
	var colors: PackedColorArray = PackedColorArray([
		Color(0.9, 0.25, 0.25), Color(0.25, 0.55, 0.95),
	])
	overlay.set_slot_colors(colors)
	overlay.refresh_visual_uniforms()
	var stored: Array = overlay.material().get_shader_parameter(&"slot_colors") as Array
	var second: Color = stored[1]
	assert_almost_eq(second.b, colors[1].srgb_to_linear().b, 0.01, "Slot 1 keeps its team color.")


# --- the analytic circle list and the Field hand-off ---------

func _make_overlay_with_visuals(map_def: MapDef, visuals: TerritoryVisuals) -> TerritoryOverlay:
	var overlay: TerritoryOverlay = TerritoryOverlay.new()
	overlay.configure(map_def, visuals, load("res://config/territory/territory_tuning.tres"))
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
	var goal_positions: PackedVector2Array = PackedVector2Array([Vector2(4.0, -4.0), Vector2(-4.0, 4.0)])
	var goal_radii: PackedFloat32Array = PackedFloat32Array([4.0, 3.0])

	overlay.set_circles(
		PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array(), PackedInt32Array(),
		goal_positions, goal_radii, false
	)

	assert_eq(overlay.circle_count(), 0, "Goal discs upload without any territory circle.")
	assert_eq(overlay.goal_count(), 2)
	assert_eq(int(overlay.material().get_shader_parameter(&"goal_count")), 2, "The shader's goal_count uniform.")
	var goal_tex: ImageTexture = overlay.material().get_shader_parameter(&"goal_tex") as ImageTexture
	assert_not_null(goal_tex, "The shader's goal_tex is bound.")
	assert_eq(goal_tex.get_width(), 2, "One texel per goal disc.")


func test_goal_discs_past_the_texel_cap_are_dropped() -> void:
	var overlay: TerritoryOverlay = _make_overlay(_map())
	var goal_positions: PackedVector2Array = PackedVector2Array()
	var goal_radii: PackedFloat32Array = PackedFloat32Array()
	for i: int in range(TerritoryOverlay.GOAL_TEXELS_MAX + 3):
		goal_positions.append(Vector2(float(i), 0.0))
		goal_radii.append(1.0)

	overlay.set_circles(
		PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array(), PackedInt32Array(),
		goal_positions, goal_radii, false
	)

	assert_eq(overlay.goal_count(), TerritoryOverlay.GOAL_TEXELS_MAX, "The goal list is capped, never overrun.")
	var goal_tex: ImageTexture = overlay.material().get_shader_parameter(&"goal_tex") as ImageTexture
	assert_eq(goal_tex.get_width(), TerritoryOverlay.GOAL_TEXELS_MAX)


func test_a_circle_list_over_the_shader_budget_falls_back_to_the_raster_path() -> void:
	var visuals: TerritoryVisuals = load("res://config/territory/territory_visuals.tres").duplicate() as TerritoryVisuals
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
		"Over max_shader_circles: the shader must fall back to the raster path, spec 2.5 'Bounded cost'."
	)


func test_set_source_null_clears_the_circle_list() -> void:
	var map_def: MapDef = _map()
	var overlay: TerritoryOverlay = _make_overlay(map_def)
	overlay.set_circles(
		PackedFloat32Array([1.0]), PackedFloat32Array([1.0]), PackedFloat32Array([1.0]),
		PackedInt32Array([0]), PackedVector2Array([Vector2.ONE]), PackedFloat32Array([1.0]), false
	)
	assert_eq(overlay.circle_count(), 1)
	assert_eq(overlay.goal_count(), 1)

	overlay.set_source(null, PackedColorArray())

	assert_eq(overlay.circle_count(), 0, "set_source(null) must not leave a stale match's circles up.")
	assert_eq(overlay.goal_count(), 0)
	assert_false(bool(overlay.material().get_shader_parameter(&"circles_valid")))


func test_field_hands_its_overlay_the_source() -> void:
	var field: Field = Field.new()
	field.map_def = _map()
	add_child_autofree(field)

	var raster: ScriptedRaster = _make_raster(field.map_def)
	var grid: CellGrid = raster.grid()
	raster.set_cell(grid.cell_index(6, 6), 2, 0)
	var colors: PackedColorArray = PackedColorArray([Color.RED, Color.BLUE])
	field.set_overlay_source(raster, colors)

	var image: Image = field.overlay().last_image()
	assert_not_null(image, "Field.set_overlay_source uploads through the overlay.")
	assert_eq(_sample(image, 6, 6).r8, 2)
	var stored: Array = field.overlay().material().get_shader_parameter(&"slot_colors") as Array
	var first: Color = stored[0]
	assert_almost_eq(first.r, colors[0].srgb_to_linear().r, 0.01, "The slot colors travel with the source.")


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


# --- spatial circle bins -------------------------------------

## Reads bin k's (start, count) header and its circle indices back out of the
## flat RGF image, the same row-major walk the shader does.
func _bin_indices(image: Image, k: int) -> PackedInt32Array:
	var width: int = TerritoryOverlay.CIRCLE_BIN_TEX_WIDTH
	var header: Color = image.get_pixel(k % width, k / width)
	var start: int = int(round(header.r))
	var count: int = int(round(header.g))
	var out: PackedInt32Array = PackedInt32Array()
	for j: int in range(count):
		var ref_k: int = start + j
		out.append(int(round(image.get_pixel(ref_k % width, ref_k / width).r)))
	return out


func test_circle_bins_list_every_circle_that_can_reach_a_pixel() -> void:
	var map_def: MapDef = _map()
	var overlay: TerritoryOverlay = _make_overlay(map_def)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1611
	var xs: PackedFloat32Array = PackedFloat32Array()
	var zs: PackedFloat32Array = PackedFloat32Array()
	var radii: PackedFloat32Array = PackedFloat32Array()
	var teams: PackedInt32Array = PackedInt32Array()
	var circle_total: int = 120
	var r: float = map_def.field_radius
	for i: int in range(circle_total):
		xs.append(rng.randf_range(-r, r))
		zs.append(rng.randf_range(-r, r))
		radii.append(rng.randf_range(0.2, 2.5))
		teams.append(i % 4)

	overlay.set_circles(xs, zs, radii, teams, PackedVector2Array(), PackedFloat32Array(), false)

	assert_true(overlay.circle_bins_valid(), "A normal circle list is binned.")
	assert_true(
		bool(overlay.material().get_shader_parameter(&"circle_bins_valid")),
		"The shader is told to use the bins."
	)
	var image: Image = overlay.circle_bin_image()
	var grid: int = TerritoryOverlay.CIRCLE_BIN_GRID
	var half: float = overlay.circle_bin_half_extent()
	var margin: float = overlay.circle_bin_margin()
	var cell: float = 2.0 * half / float(grid)
	var misses: int = 0
	var unordered: int = 0
	var samples: int = 97
	for sz: int in range(samples):
		for sx: int in range(samples):
			var point: Vector2 = Vector2(
				-r + 2.0 * r * float(sx) / float(samples - 1),
				-r + 2.0 * r * float(sz) / float(samples - 1)
			)
			var col: int = int(floor((point.x + half) / cell))
			var row: int = int(floor((point.y + half) / cell))
			var listed: PackedInt32Array = _bin_indices(image, row * grid + col)
			for j: int in range(1, listed.size()):
				if listed[j] <= listed[j - 1]:
					unordered += 1
			for i: int in range(circle_total):
				var value: float = radii[i] - point.distance_to(Vector2(xs[i], zs[i]))
				if value >= -margin and not listed.has(i):
					misses += 1
	assert_eq(misses, 0, "Every circle within radius + margin of a sample point is in that point's bin.")
	assert_eq(unordered, 0, "Bin lists keep circle_tex's ascending (team-sorted) order.")


# --- hole void field -----------------------------------------

## The void field is skipped while no cell is a hole; any hole cell turns it on.
func test_void_present_follows_hole_cells_in_the_upload() -> void:
	var overlay: TerritoryOverlay = _make_overlay(_map())
	var cell_total: int = CELLS_PER_SIDE * CELLS_PER_SIDE
	var owners: PackedByteArray = PackedByteArray()
	owners.resize(cell_total)
	var states: PackedByteArray = PackedByteArray()
	states.resize(cell_total)
	states[7] = TerritoryOverlay.STATE_CONTESTED
	overlay.push_cells(owners, states, CELLS_PER_SIDE)
	assert_false(bool(overlay.material().get_shader_parameter(&"void_present")),
		"contested cells alone draw no void, so the shader may skip the void field.")
	states[7] = TerritoryOverlay.STATE_HOLE | TerritoryOverlay.STATE_CONTESTED
	overlay.push_cells(owners, states, CELLS_PER_SIDE)
	assert_true(bool(overlay.material().get_shader_parameter(&"void_present")), "a hole cell needs the void field.")
	states[7] = 0
	overlay.push_cells(owners, states, CELLS_PER_SIDE)
	assert_false(bool(overlay.material().get_shader_parameter(&"void_present")), "a closed hole drops it again.")
