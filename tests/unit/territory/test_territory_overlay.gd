extends GutTest
## TerritoryOverlay turns the cell raster into the ImageTexture the disk shader
## samples (spec 2.10, 3.3, docs/archive/M2_PLAN.md "Raster resolution").
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


# --- Bontago-cmc.5: the analytic circle list -------------------------------


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


# --- Bontago-mv0.20b: disk_mesh_segments live-apply --------------------------


# --- Bontago-xtq.11: mirror-like opaque disk ---------------------------------
#
# Bontago-xtq.4's disk-opacity tunables and the shader uniforms they drove
# are gone (owner, 2026-09-23: "the disc is a mirror-like surface and not
# glass, so it should be reflective but not transparent"); see
# config/territory/TerritoryVisuals.gd and shaders/territory/territory.gdshader for the removal
# DECISIONs.


# --- Bontago-xtq.14: crisp ownership edge, separate from the rim glow --------
#
# Owner playtest 2026-09-23: "the edge of the area is a bit blurry, sharpen
# it." shaders/territory/territory.gdshader's analytic circle_path() used to feather
# the ownership TINT over rim_soft_width (0.25 m, the rim glow's own width) --
# edge_softness_m below is now a separate, much smaller default so the
# boundary itself reads as crisp while the glow keeps its existing rim_*
# tunables untouched (a reference screenshot of the original game: "hard-edged shadows/
# edges").


# --- Owner 2026-10-07: the disc mirror pass is removed -----------------------


# --- Bontago-1pi.11: spatial circle bins -------------------------------------

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


## Bontago-1pi.11.23: an unchanged revision skips the texture upload.
class CountingOverlay extends TerritoryOverlay:
	var pushes: int = 0

	func push_cells(owner_bytes: PackedByteArray, state_bytes: PackedByteArray, side: int) -> void:
		pushes += 1
		super(owner_bytes, state_bytes, side)


# --- Bontago-1pi.11.67 fix2b: GPU cost of the disc shader ---------------------

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


## Bontago-1pi.11.67 fix2b: a test that switches the graphics preset records the
## original here; after_each puts it back even when an assert failed midway.
var _restore_preset_id: StringName = &""


func after_each() -> void:
	if _restore_preset_id != &"":
		Settings.set_graphics_preset(_restore_preset_id)
		_restore_preset_id = &""
