extends GutTest
## FieldBody.surface_height_at(): the world Y of the disc's live top plane under a point's XZ. On a
## tilted disc it must match the real collision surface a downward physics ray finds
## (Field.raycast_disk_surface, the query the ghost uses), not the pivot height surface_y().

const EPS: float = 0.001
const RAY_START_Y: float = 40.0
const RAY_LENGTH_M: float = 80.0
const MAX_SKIPS: int = 0
const TILT_X_RAD: float = 0.12
const TILT_Z_RAD: float = -0.18
const POSE_OFFSET: Vector3 = Vector3(0.3, 0.4, -0.2)
const SAMPLE_XZ: Array[Vector2] = [
	Vector2(0.0, 0.0), Vector2(3.0, 0.5), Vector2(-3.5, 2.0), Vector2(2.0, -4.0), Vector2(-4.0, -3.0),
]

var _field: Field = null


func before_each() -> void:
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_surface_height"
	map_def.field_radius = 6.0
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 32
	_field = autofree(Field.new())
	_field.map_def = map_def
	add_child_autofree(_field)


func _tilt(offset: Vector3) -> void:
	var tilt: Quaternion = (Basis(Vector3.RIGHT, TILT_X_RAD) * Basis(Vector3.BACK, TILT_Z_RAD)).get_rotation_quaternion()
	_field.apply_replicated_pose(offset, tilt)
	await wait_physics_frames(2)


func _ray_hit_y(xz: Vector2) -> float:
	var space: PhysicsDirectSpaceState3D = _field.get_world_3d().direct_space_state
	var hit: Dictionary = Field.raycast_disk_surface(space, Vector3(xz.x, RAY_START_Y, xz.y), RAY_LENGTH_M, MAX_SKIPS)
	assert_false(hit.is_empty(), "fixture: the ray finds the disc at %s" % xz)
	return (hit["position"] as Vector3).y if not hit.is_empty() else NAN


func test_level_disc_reports_the_pivot_height_everywhere() -> void:
	for xz: Vector2 in SAMPLE_XZ:
		assert_almost_eq(_field.surface_height_at(Vector3(xz.x, 7.0, xz.y)), _field.surface_y(), EPS, "level at %s" % xz)


func test_level_disc_at_a_raised_pose_reports_the_raised_height() -> void:
	_field.apply_replicated_pose(Vector3(0.0, 0.75, 0.0), Quaternion.IDENTITY)
	await wait_physics_frames(2)
	for xz: Vector2 in SAMPLE_XZ:
		assert_almost_eq(_field.surface_height_at(Vector3(xz.x, 0.0, xz.y)), 0.75, EPS, "raised level at %s" % xz)
		assert_almost_eq(_field.surface_height_at(Vector3(xz.x, 0.0, xz.y)), _ray_hit_y(xz), EPS, "ray agrees at %s" % xz)


func test_tilted_disc_matches_the_physics_ray_hit_at_five_points() -> void:
	await _tilt(POSE_OFFSET)
	var spread: float = 0.0
	for xz: Vector2 in SAMPLE_XZ:
		var reported: float = _field.surface_height_at(Vector3(xz.x, 3.0, xz.y))
		assert_almost_eq(reported, _ray_hit_y(xz), EPS, "tilted surface under %s" % xz)
		spread = maxf(spread, absf(reported - _field.surface_y()))
	assert_gt(spread, 0.5, "fixture: the tilt really lifts or drops the surface away from the pivot height")


func test_the_query_height_of_the_point_does_not_matter() -> void:
	await _tilt(POSE_OFFSET)
	var low: float = _field.surface_height_at(Vector3(2.0, -50.0, -1.0))
	var high: float = _field.surface_height_at(Vector3(2.0, 50.0, -1.0))
	assert_almost_eq(low, high, EPS)


func test_surface_height_is_the_height_of_disk_local_points_lifted_by_zero() -> void:
	await _tilt(POSE_OFFSET)
	for xz: Vector2 in SAMPLE_XZ:
		var on_disc: Vector3 = _field.world_from_disk_local(xz, 0.0)
		assert_almost_eq(_field.surface_height_at(on_disc), on_disc.y, EPS, "disk-local top point %s" % xz)
