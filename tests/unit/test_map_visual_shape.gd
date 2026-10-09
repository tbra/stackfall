extends GutTest
## Bontago-1pi.60: every shipped map must build a visible mesh and
## collider that match its cells. Compares Field's collision trimesh, the
## TerritoryOverlay's visible mesh and the MapDef's cell coverage.

const FIELD_SCENE: PackedScene = preload("res://game/Field.tscn")
const SHAPES: Array[int] = [0]
const SIZES: Array[int] = [0, 1, 2]
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


func test_collision_and_visible_mesh_match_map_def_for_every_shipped_map() -> void:
	for shape: int in SHAPES:
		for size: int in SIZES:
			var map_def: MapDef = MapDef.for_variant_and_size(shape, size as MapDef.MapSize)
			var label: String = "%s/%d" % [str(map_def.id), size]
			var field: Field = _field_for(map_def)
			var expected: Rect2 = _top_cell_aabb(map_def)

			var faces: PackedVector3Array = field._disk_shape.get_faces()
			assert_gt(faces.size(), 0, "%s: collider has faces" % label)
			var lo: Vector2 = Vector2(INF, INF)
			var hi: Vector2 = Vector2(-INF, -INF)
			for v: Vector3 in faces:
				lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.z))
				hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.z))
			assert_almost_eq(lo.x, expected.position.x, AABB_SLACK, "%s collider min x" % label)
			assert_almost_eq(hi.y, expected.end.y, AABB_SLACK, "%s collider max z" % label)
			assert_eq(field.cell_count(), field.grid().in_disk_cell_count(), "%s cells" % label)

			var mesh: Mesh = field.overlay().mesh
			assert_not_null(mesh, "%s: overlay mesh" % label)
			# Bontago-mp0.150.1: surface 0 is the playing slab; later surfaces are the rim.
			var top_arrays: Array = (mesh as ArrayMesh).surface_get_arrays(0)
			var box: AABB = AABB()
			var first: bool = true
			for vertex: Vector3 in top_arrays[Mesh.ARRAY_VERTEX]:
				box = AABB(vertex, Vector3.ZERO) if first else box.expand(vertex)
				first = false
			assert_almost_eq(box.size.x, 2.0 * map_def.field_radius, AABB_SLACK, "%s: the disc slab" % label)


