extends GutTest
## GhostPreview over a tilted disc: the hover is straight up (world Y), the footprint quad lies on the live
## disc plane, and the projection walls stop on the live disc under each piece, not on one flat plane at
## the centroid height.

const EPS: float = 0.001
const TILT_X_RAD: float = 0.0
const TILT_Z_RAD: float = 0.2
const RIM_X_M: float = -11.0
const HOVER_STEP_M: float = 1.0
const WALL_HOVER_M: float = 2.0
const VERTS_PER_WALL: int = 4
const FIRST_BOTTOM_VERTEX: int = 2

var _field: Field = null
var _ghost: GhostPreview = null


func before_each() -> void:
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_ghost_tilted"
	map_def.field_radius = 12.0
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 32
	_field = autofree(Field.new())
	_field.map_def = map_def
	add_child_autofree(_field)
	var tilt: Quaternion = (Basis(Vector3.RIGHT, TILT_X_RAD) * Basis(Vector3.BACK, TILT_Z_RAD)).get_rotation_quaternion()
	_field.apply_replicated_pose(Vector3.ZERO, tilt)
	_ghost = autofree(GhostPreview.new())
	add_child_autofree(_ghost)
	_ghost.set_shape(load("res://config/blocks/bar3.tres"))
	await wait_physics_frames(2)


## The ghost is posed from the cursor's hit on the live disc at world (x, z).
func _place(x: float, z: float) -> void:
	var hit: Vector3 = Vector3(x, _field.surface_height_at(Vector3(x, 0.0, z)), z)
	_ghost.update_placement(hit)


func test_one_metre_of_hover_moves_the_ghost_exactly_one_metre_up() -> void:
	_place(4.0, 0.0)
	var before: Vector3 = _ghost.global_position
	_ghost.manual_hover_offset += HOVER_STEP_M
	_place(4.0, 0.0)
	var moved: Vector3 = _ghost.global_position - before
	assert_almost_eq(moved.x, 0.0, EPS, "no sideways drift on a tilted disc")
	assert_almost_eq(moved.y, HOVER_STEP_M, EPS)
	assert_almost_eq(moved.z, 0.0, EPS, "no sideways drift on a tilted disc")


func test_footprint_quad_lies_on_the_live_disc_plus_offset() -> void:
	for x: float in [-4.0, 0.0, 4.0]:
		_place(x, 1.0)
		var quads: Array[MeshInstance3D] = GhostParts.footprint_quads(_ghost)
		assert_eq(quads.size(), 1, "fixture: one footprint quad")
		var mesh: ArrayMesh = quads[0].mesh as ArrayMesh
		var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		assert_gt(verts.size(), 2, "fixture: the quad has vertices")
		var lowest: float = INF
		var highest: float = -INF
		for vertex: Vector3 in verts:
			var world: Vector3 = quads[0].global_transform * vertex
			var disc_y: float = _field.surface_height_at(world)
			assert_almost_eq(world.y, disc_y + _ghost.ghost_tuning.footprint_offset, EPS, "quad vertex on the live disc at x=%s" % x)
			lowest = minf(lowest, world.y)
			highest = maxf(highest, world.y)
		assert_gt(highest - lowest, 0.1, "fixture: the quad really follows the slope")


func test_projection_walls_stop_on_the_live_disc_under_each_piece() -> void:
	_ghost.manual_hover_offset = WALL_HOVER_M
	_place(0.0, 0.0)
	var verts: PackedVector3Array = GhostParts.prism_vertices(_ghost)
	assert_gt(verts.size(), 0, "fixture: a hovering shape has projection walls")
	var offset: float = _ghost.ghost_tuning.footprint_offset
	var disc_lowest: float = INF
	var disc_highest: float = -INF
	var wall_lowest: float = INF
	var wall_highest: float = -INF
	for i: int in range(verts.size()):
		if i % VERTS_PER_WALL < FIRST_BOTTOM_VERTEX:
			continue
		var disc_y: float = _field.surface_height_at(verts[i]) + offset
		disc_lowest = minf(disc_lowest, disc_y)
		disc_highest = maxf(disc_highest, disc_y)
		wall_lowest = minf(wall_lowest, verts[i].y)
		wall_highest = maxf(wall_highest, verts[i].y)
	assert_gt(disc_highest - disc_lowest, 0.3, "fixture: the disc under the hull really slopes")
	# A wall bottom is flat per piece, so it sits between the disc heights under the hull, and the
	# downhill and uphill walls reach the disc's lowest and highest points (end walls are exact).
	assert_almost_eq(wall_lowest, disc_lowest, EPS, "the downhill wall ends on the live disc, not the centroid height")
	assert_almost_eq(wall_highest, disc_highest, EPS, "the uphill wall ends on the live disc")


func test_cursor_ray_reaches_the_live_disc_on_the_downhill_rim() -> void:
	# tilt about +Z by 0.2 rad drops the -X rim well below the cursor ray's old end at world y = 0
	var live_y: float = _field.surface_height_at(Vector3(RIM_X_M, 0.0, 0.0))
	assert_lt(live_y, -1.0, "fixture: the rim is below world y = 0")
	var origin: Vector3 = Vector3(RIM_X_M, _ghost.ghost_tuning.cursor_ray_height, 0.0)
	var hit: Dictionary = _ghost.raycast_disk_surface(origin)
	assert_false(hit.is_empty(), "the ray finds the downhill disc")
	assert_almost_eq((hit["position"] as Vector3).y, live_y, EPS, "hit is the live disc surface")
