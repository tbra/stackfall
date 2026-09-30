extends GutTest
## Bontago-sen.5: the minimap must follow the rendered camera every frame.


func _make_minimap() -> Minimap:
	var minimap: Minimap = Minimap.new()
	add_child_autofree(minimap)
	minimap.set_map_def(MapDef.new())
	return minimap


func test_process_runs_after_camera_rig() -> void:
	var minimap: Minimap = _make_minimap()
	var rig: CameraRig = load("res://game/CameraRig.tscn").instantiate()
	add_child_autofree(rig)
	assert_gt(minimap.process_priority, rig.process_priority)


func test_process_step_matches_current_camera_yaw() -> void:
	var minimap: Minimap = _make_minimap()
	var camera: Camera3D = Camera3D.new()
	add_child_autofree(camera)
	camera.current = true
	camera.rotation.y = 0.7
	minimap._process(0.016)
	var forward: Vector3 = -camera.global_transform.basis.z
	assert_almost_eq(minimap._camera_forward.x, Vector2(forward.x, forward.z).normalized().x, 0.0001)
	assert_almost_eq(minimap._camera_forward.y, Vector2(forward.x, forward.z).normalized().y, 0.0001)


func test_cached_image_is_rotated_to_current_basis_between_rebuilds() -> void:
	var minimap: Minimap = _make_minimap()
	var center: Vector2 = Vector2(80.0, 80.0)
	assert_true(minimap.image_to_current_transform(center).is_equal_approx(Transform2D.IDENTITY))
	# Quarter turn: forward (0,1) -> (1,0), right (1,0) -> (0,-1); no image rebuild.
	minimap.set_camera_basis(Vector2(0.0, -1.0), Vector2(1.0, 0.0))
	var xf: Transform2D = minimap.image_to_current_transform(center)
	assert_false(xf.is_equal_approx(Transform2D.IDENTITY))
	assert_almost_eq(xf * center, center, Vector2(0.001, 0.001))
	# Old "ahead" is now to the camera's left after turning toward +x.
	var up: Vector2 = xf * (center + Vector2(0.0, -50.0))
	assert_almost_eq(up.x, center.x - 50.0, 0.001)
	assert_almost_eq(up.y, center.y, 0.001)
	minimap.render_now()
	assert_true(minimap.image_to_current_transform(center).is_equal_approx(Transform2D.IDENTITY))


func _make_raster(map_def: MapDef) -> TerritoryRaster:
	var tuning: TerritoryTuning = load("res://config/territory_tuning.tres")
	var grid: CellGrid = CellGrid.new(map_def.field_radius, map_def.cell_size)
	return TerritoryRaster.new(grid, tuning)


## Bontago-1pi.11.9: the refresh timer rebuilt the GDScript pixel loop at 8 Hz
## even on a settled board (a ~60 ms hitch); it must rebuild only on change.
func test_refresh_timer_skips_rebuild_when_inputs_unchanged() -> void:
	var minimap: Minimap = _make_minimap()
	var map_def: MapDef = MapDef.new()
	var raster: TerritoryRaster = _make_raster(map_def)
	var colors: PackedColorArray = PackedColorArray([Color.RED])
	minimap.set_match_state(raster, colors, PackedVector2Array([Vector2.ZERO]))
	minimap.render_now()
	assert_false(minimap._image_inputs_changed(), "fresh build: nothing to rebuild")
	minimap.set_camera_basis(Vector2(0.0, -1.0), Vector2(1.0, 0.0))
	assert_false(minimap._image_inputs_changed(), "camera rotation alone is handled by the draw transform")
	var before: int = minimap._built_raster_hash
	minimap._on_refresh_timeout()
	assert_eq(minimap._built_raster_hash, before)
	assert_eq(minimap._image_right, Vector2(1.0, 0.0), "no rebuild means the image basis is untouched")


func test_refresh_timer_rebuilds_when_ownership_or_colors_change() -> void:
	var minimap: Minimap = _make_minimap()
	var map_def: MapDef = MapDef.new()
	var tuning: TerritoryTuning = load("res://config/territory_tuning.tres")
	var raster: TerritoryRaster = _make_raster(map_def)
	minimap.set_match_state(raster, PackedColorArray([Color.RED]), PackedVector2Array([Vector2.ZERO]))
	minimap.render_now()
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.new(Vector2.ZERO, tuning.home_radius, 0, 0, true, -1)
	]
	raster.update(circles, TerritorySolver.new(tuning).solve(circles), 0.1, true, false)
	assert_true(minimap._image_inputs_changed(), "owner ids changed")
	minimap.set_camera_basis(Vector2(0.0, -1.0), Vector2(1.0, 0.0))
	minimap._on_refresh_timeout()
	assert_eq(minimap._image_right, Vector2(0.0, -1.0), "timer rebuilt the image in the new basis")
	assert_false(minimap._image_inputs_changed())
	minimap.set_match_state(raster, PackedColorArray([Color.BLUE]), PackedVector2Array([Vector2.ZERO]))
	assert_true(minimap._image_inputs_changed(), "team colors changed")


## Bontago-1pi.11.11: the rebuild uploads the raster as native-copied textures
## and the shader colours them; the per-pixel reference stays a test seam.
func test_raster_images_match_team_hole_and_disk_lookups() -> void:
	var map_def: MapDef = MapDef.new()
	var tuning: TerritoryTuning = load("res://config/territory_tuning.tres")
	var raster: TerritoryRaster = _make_raster(map_def)
	var solver: TerritorySolver = TerritorySolver.new(tuning)
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.new(Vector2.ZERO, tuning.home_radius, 1, 1, true, -1)
	]
	raster.update(circles, solver.solve(circles), 0.1, true, false)
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


func test_rebuild_feeds_shader_and_reference_image_uses_boosted_colour() -> void:
	var minimap: Minimap = _make_minimap()
	var map_def: MapDef = MapDef.new()
	var tuning: TerritoryTuning = load("res://config/territory_tuning.tres")
	var raster: TerritoryRaster = _make_raster(map_def)
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.new(Vector2.ZERO, tuning.home_radius, 0, 0, true, -1)
	]
	raster.update(circles, TerritorySolver.new(tuning).solve(circles), 0.1, true, false)
	minimap.set_match_state(raster, PackedColorArray([Color.RED]), PackedVector2Array([Vector2.ZERO]))
	minimap.render_now()
	var material: ShaderMaterial = minimap._territory_material
	assert_eq(int(material.get_shader_parameter("slot_count")), 1)
	assert_eq(material.get_shader_parameter("grid_res"), raster.grid().res)
	var colors: PackedVector4Array = material.get_shader_parameter("slot_colors")
	var image: Image = minimap.debug_image()
	var size_px: int = image.get_width()
	var expected: Color = image.get_pixel(size_px / 2, size_px / 2)
	assert_eq(colors[0], Vector4(expected.r, expected.g, expected.b, expected.a))
	assert_eq(image.get_pixel(1, 1).a, 0.0)


func test_rebuild_path_has_no_per_pixel_loop() -> void:
	var source: String = FileAccess.get_file_as_string("res://ui/Minimap.gd")
	var start: int = source.find("func _rebuild_image()")
	var end: int = source.find("func _territory_color")
	var body: String = source.substr(start, end - start)
	assert_false(body.contains("set_pixel"))
	assert_false(body.contains("for py"))


func test_rebuild_cost_is_small() -> void:
	var minimap: Minimap = _make_minimap()
	var raster: TerritoryRaster = _make_raster(MapDef.new())
	minimap.set_match_state(raster, PackedColorArray([Color.RED]), PackedVector2Array([Vector2.ZERO]))
	minimap.render_now()
	var start: int = Time.get_ticks_usec()
	for i: int in range(20):
		minimap._rebuild_image()
	var per_ms: float = float(Time.get_ticks_usec() - start) / 20000.0
	gut.p("minimap _rebuild_image: %.3f ms" % per_ms)
	assert_lt(per_ms, 5.0, "texture upload path, not a per-pixel loop")


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


func test_goal_controls_come_from_raster() -> void:
	var raster: TerritoryRaster = _make_raster(MapDef.new())
	var minimap: Minimap = _make_minimap()
	minimap.set_goal_positions(PackedVector2Array([Vector2.ZERO]))
	minimap.set_match_state(raster, PackedColorArray([Color.RED]), PackedVector2Array())
	assert_eq(minimap._goal_controls.size(), 1)
	assert_eq(minimap._goal_controls[0], GoalControl.owner_at(raster, Vector2.ZERO))


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
