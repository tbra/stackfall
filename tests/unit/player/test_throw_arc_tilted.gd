extends GutTest
## ThrowArcPreview.sample_arc() on a tilted disc: the arc ends on the live tilted top surface, below
## the rest plane when thrown downhill and never through the disc when thrown uphill. The disc
## rises towards +X (a rotation about Z by +TILT_RAD lifts +X).

## The preview line interpolates its last segment to the height under the first sample past the surface,
## so on a slope the end sits within a sample step of the exact surface, far inside the tilt offsets asserted.
const EPS: float = 0.1
const TILT_RAD: float = 0.25
const FIELD_RADIUS_M: float = 12.0
const LAUNCH_HEIGHT_M: float = 6.0
const SPEED_MPS: float = 5.0

var _field: Field = null
var _arc: ThrowArcPreview = null


func before_each() -> void:
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_arc_tilted"
	map_def.field_radius = FIELD_RADIUS_M
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 32
	_field = autofree(Field.new())
	_field.map_def = map_def
	add_child_autofree(_field)
	_arc = autofree(ThrowArcPreview.new())
	add_child_autofree(_arc)


func _tilt(angle: float) -> void:
	_field.apply_replicated_pose(Vector3.ZERO, Quaternion(Vector3.BACK, angle))
	await wait_physics_frames(2)


func _throw(direction_x: float) -> PackedVector3Array:
	return _arc.sample_arc(Vector3(0.0, LAUNCH_HEIGHT_M, 0.0), Vector3(direction_x * SPEED_MPS, 0.0, 0.0), _field)


func test_downhill_arc_ends_on_the_live_surface_below_the_rest_plane() -> void:
	await _tilt(TILT_RAD)
	var points: PackedVector3Array = _throw(-1.0)
	var end: Vector3 = points[points.size() - 1]
	assert_lt(end.x, 0.0, "fixture: thrown downhill")
	assert_lt(_field.surface_height_at(end), _field.surface_y() - 0.5, "fixture: the live surface is below the rest plane there")
	assert_almost_eq(end.y, _field.surface_height_at(end), EPS, "the arc ends on the tilted surface")
	assert_lt(end.y, _field.surface_y() - 0.5, "it keeps falling past the rest plane instead of stopping at it")


func test_uphill_arc_ends_on_the_live_surface_and_never_passes_through_it() -> void:
	await _tilt(TILT_RAD)
	var points: PackedVector3Array = _throw(1.0)
	var end: Vector3 = points[points.size() - 1]
	assert_gt(end.x, 0.0, "fixture: thrown uphill")
	assert_gt(_field.surface_height_at(end), _field.surface_y() + 0.5, "fixture: the live surface is above the rest plane there")
	assert_almost_eq(end.y, _field.surface_height_at(end), EPS, "the arc ends on the tilted surface")
	for point: Vector3 in points:
		assert_gte(point.y, _field.surface_height_at(point) - EPS, "no sample lies under the disc at %s" % point)


func test_level_disc_arc_still_ends_on_the_rest_plane() -> void:
	await _tilt(0.0)
	for direction_x: float in [-1.0, 1.0]:
		var points: PackedVector3Array = _throw(direction_x)
		var end: Vector3 = points[points.size() - 1]
		assert_almost_eq(end.y, _field.surface_y(), EPS, "level disc: lands on the pivot height going %s" % direction_x)
		assert_lt(Vector2(end.x, end.z).length(), FIELD_RADIUS_M, "fixture: lands over the disc")


func test_flat_launch_uphill_lands_sooner_than_downhill() -> void:
	await _tilt(TILT_RAD)
	var uphill: PackedVector3Array = _throw(1.0)
	var downhill: PackedVector3Array = _throw(-1.0)
	assert_lt(uphill.size(), downhill.size(), "the rising surface is met earlier in the flight")
