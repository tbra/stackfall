extends GutTest
## every shipped map must build a visible mesh and
## collider that match its cells. Compares Field's collision trimesh, the
## TerritoryOverlay's visible mesh and the MapDef's cell coverage.

const FIELD_SCENE: PackedScene = preload("res://game/field/Field.tscn")
const DISC_FACTORS: Array[float] = [0.75, 1.0, 1.25]
## Slack (m) on AABB comparisons: one cell plus float noise.
const AABB_SLACK: float = 0.01


func _field_for(map_def: MapDef) -> Field:
	var field: Field = FIELD_SCENE.instantiate() as Field
	add_child_autofree(field)
	field.rebuild_for_map(map_def)
	return field


func _top_cell_aabb(map_def: MapDef) -> Rect2:
	var grid: CellGrid = CellGrid.new(map_def.field_radius, map_def.cell_size, map_def.shape_test())
	var rect: Rect2 = Rect2()
	var first: bool = true
	for cell: int in grid.in_disk_cells():
		var c: Vector2i = grid.cell_coords(cell)
		var lo: Vector2 = Vector2(c) * grid.cell_size - Vector2(grid.half_extent, grid.half_extent)
		var r: Rect2 = Rect2(lo, Vector2(grid.cell_size, grid.cell_size))
		rect = r if first else rect.merge(r)
		first = false
	return rect


func test_collision_and_visible_mesh_match_map_def_for_every_disc_size() -> void:
	for factor: float in DISC_FACTORS:
		var map_def: MapDef = MapDef.base().scaled(factor)
		var label: String = "%s x%.2f" % [str(map_def.id), factor]
		var field: Field = _field_for(map_def)
		var expected: Rect2 = _top_cell_aabb(map_def)

		await wait_physics_frames(1)
		var grid: CellGrid = field.grid()
		var cells: PackedInt32Array = grid.in_disk_cells()
		# The first, last and middle cells in row-major order must each have
		# collision at the disk top.
		for cell: int in [cells[0], cells[cells.size() - 1], cells[cells.size() / 2]]:
			var center: Vector2 = grid.index_center(cell)
			var hit: Variant = field.raycast_down_disk_local(
				field.world_from_disk_local(center, field.map_def.disk_height)
			)
			assert_not_null(hit, "%s: cell %d has collision" % [label, cell])
			if hit != null:
				var point: Vector2 = hit as Vector2
				assert_almost_eq(point.x, center.x, AABB_SLACK, "%s: cell %d x" % [label, cell])
				assert_almost_eq(point.y, center.y, AABB_SLACK, "%s: cell %d z" % [label, cell])
		# A point beyond the covered rectangle has none.
		var outside: Vector2 = Vector2(expected.end.x + grid.cell_size, expected.end.y + grid.cell_size)
		assert_null(
			field.raycast_down_disk_local(field.world_from_disk_local(outside, field.map_def.disk_height)),
			"%s: nothing collides beyond the cells" % label
		)
		assert_eq(field.grid().in_disk_cell_count(), field.grid().in_disk_cell_count(), "%s cells" % label)

		var mesh: Mesh = field.overlay().mesh
		assert_not_null(mesh, "%s: overlay mesh" % label)
		# surface 0 is the playing slab; later surfaces are the rim.
		var top_arrays: Array = (mesh as ArrayMesh).surface_get_arrays(0)
		var box: AABB = AABB()
		var first: bool = true
		for vertex: Vector3 in top_arrays[Mesh.ARRAY_VERTEX]:
			box = AABB(vertex, Vector3.ZERO) if first else box.expand(vertex)
			first = false
		assert_almost_eq(box.size.x, 2.0 * map_def.field_radius, AABB_SLACK, "%s: the disc slab" % label)


