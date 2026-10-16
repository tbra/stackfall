extends GutTest
## the minimap must follow the rendered camera every frame.


func _make_minimap() -> Minimap:
	var minimap: Minimap = Minimap.new()
	add_child_autofree(minimap)
	minimap.set_map_def(MapDef.new())
	return minimap


func _make_raster(map_def: MapDef) -> TerritoryRaster:
	var tuning: TerritoryTuning = load("res://config/territory/territory_tuning.tres")
	var grid: CellGrid = CellGrid.new(map_def.field_radius, map_def.cell_size)
	return TerritoryRaster.new(grid, tuning)


func test_refresh_timer_rebuilds_when_ownership_or_colors_change() -> void:
	var minimap: Minimap = _make_minimap()
	var map_def: MapDef = MapDef.new()
	var tuning: TerritoryTuning = load("res://config/territory/territory_tuning.tres")
	var raster: TerritoryRaster = _make_raster(map_def)
	minimap.set_match_state(raster, PackedColorArray([Color.RED]), PackedVector2Array([Vector2.ZERO]))
	minimap.render_now()
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.new(Vector2.ZERO, tuning.home_radius, 0, 0, true, -1)
	]
	raster.fill_ownership(circles, TerritorySolver.new(tuning).solve(circles), true)
	raster.adopt_fill(raster, 0.1, true, false)
	assert_true(minimap._image_inputs_changed(), "owner ids changed")
	minimap.set_camera_basis(Vector2(0.0, -1.0), Vector2(1.0, 0.0))
	minimap._on_refresh_timeout()
	assert_eq(minimap._image_right, Vector2(0.0, -1.0), "timer rebuilt the image in the new basis")
	assert_false(minimap._image_inputs_changed())
	minimap.set_match_state(raster, PackedColorArray([Color.BLUE]), PackedVector2Array([Vector2.ZERO]))
	assert_true(minimap._image_inputs_changed(), "team colors changed")


## the rebuild uploads the raster as native-copied textures
## and the shader colours them; the per-pixel reference stays a test seam.
func test_raster_images_match_team_hole_and_disk_lookups() -> void:
	var map_def: MapDef = MapDef.new()
	var tuning: TerritoryTuning = load("res://config/territory/territory_tuning.tres")
	var raster: TerritoryRaster = _make_raster(map_def)
	var solver: TerritorySolver = TerritorySolver.new(tuning)
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.new(Vector2.ZERO, tuning.home_radius, 1, 1, true, -1)
	]
	raster.fill_ownership(circles, solver.solve(circles), true)
	raster.adopt_fill(raster, 0.1, true, false)
	var grid: CellGrid = raster.grid()
	var team_image: Image = raster.team_id_image()
	var hole_image: Image = raster.hole_image()
	var disk_image: Image = raster.in_disk_image()
	assert_eq(team_image.get_width(), grid.res)
	var mid: int = grid.res / 2
	for cell: Vector2i in [Vector2i(mid, mid), Vector2i(0, 0), Vector2i(mid, 1), Vector2i(mid + 3, mid - 2)]:
		var team: int = raster.team_at(cell.x, cell.y)
		var r: int = int(round(team_image.get_pixel(cell.x, cell.y).r * 255.0))
		assert_eq(r if r < 255 else -1, team, "team id at %s" % cell)
		assert_eq(disk_image.get_pixel(cell.x, cell.y).r > 0.001, grid.is_in_disk(cell.x, cell.y))
		assert_eq(hole_image.get_pixel(cell.x, cell.y).r > 0.001, raster.is_hole(cell.x, cell.y))
	assert_eq(int(round(team_image.get_pixel(mid, mid).r * 255.0)), 1)


func _goal_minimap(goals: PackedVector2Array) -> Minimap:
	var minimap: Minimap = _make_minimap()
	minimap.set_goal_positions(goals)
	minimap.set_match_state(null, PackedColorArray([Color.RED, Color.BLUE]), PackedVector2Array())
	return minimap


func test_one_goal_marker_per_goal_and_neutral_without_control() -> void:
	var goals: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(5.0, 0.0), Vector2(-5.0, 0.0)])
	var minimap: Minimap = _goal_minimap(goals)
	var markers: Array[Dictionary] = minimap.goal_marker_draw_data()
	assert_eq(markers.size(), 3)
	for marker: Dictionary in markers:
		assert_eq(marker["color"], minimap.tuning.minimap_goal_neutral_color)


func test_goal_colour_follows_controller() -> void:
	var minimap: Minimap = _goal_minimap(PackedVector2Array([Vector2.ZERO, Vector2(4.0, 0.0), Vector2(-4.0, 0.0)]))
	minimap._goal_controls = PackedInt32Array([1, GoalControl.CONTESTED, 0])
	assert_eq(minimap.goal_marker_color(0), Color.BLUE)
	assert_eq(minimap.goal_marker_color(1), minimap.tuning.minimap_goal_contested_color)
	assert_eq(minimap.goal_marker_color(2), Color.RED)


func test_goal_marker_position_rotates_with_camera() -> void:
	var minimap: Minimap = _goal_minimap(PackedVector2Array([Vector2(3.0, 0.0)]))
	var size_px: float = float(minimap.tuning.minimap_size_px)
	var px_per_m: float = size_px / (minimap.half_extent() * 2.0)
	var center: Vector2 = Vector2(size_px, size_px) * 0.5
	var north_up: Vector2 = minimap.goal_marker_draw_data()[0]["pixel"]
	assert_almost_eq(north_up, center + Vector2(3.0 * px_per_m, 0.0), Vector2(0.01, 0.01))
	# Camera looking along +x: the goal is straight ahead, so it moves up.
	minimap.set_camera_basis(Vector2(0.0, -1.0), Vector2(1.0, 0.0))
	var rotated: Vector2 = minimap.goal_marker_draw_data()[0]["pixel"]
	assert_almost_eq(rotated, center + Vector2(0.0, -3.0 * px_per_m), Vector2(0.01, 0.01))
