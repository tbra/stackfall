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
