extends GutTest
## SlotCursors: the last ghost per slot and the host's AFK auto-drop pose, through its public API.

const SLOT: int = 1
const OTHER_SLOT: int = 2
const HEIGHT_EPSILON: float = 0.0001
const AGE_EPSILON: float = 0.0001
const STORED_ORIGIN: Vector3 = Vector3(3.0, 4.0, -5.0)
const STORED_ORIENTATION: int = 7
const STORED_QUAT: Quaternion = Quaternion(0.0, 0.7071068, 0.0, 0.7071068)
const HOME: Vector3 = Vector3(10.0, 0.5, -2.0)

## A host whose home flag for every slot is HOME.
class HomeHostPort extends FakeHostPort:
	func default_ghost_origin(slot_id: int) -> Vector3:
		super(slot_id)
		return HOME

var _now: float = 100.0
var _ghost: GhostTuning = preload("res://config/blocks/tuning/ghost_tuning.tres")
var _beacon: BeaconVisualTuning = preload("res://config/territory/beacon_visual_tuning.tres")
var _physics: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")
var _cursors: SlotCursors


func before_each() -> void:
	_now = 100.0
	_cursors = SlotCursors.new(func() -> float: return _now, _ghost, _beacon, _physics)
	_cursors.bind(HomeHostPort.new())


func _store_default(slot_id: int = SLOT) -> void:
	_cursors.store(slot_id, STORED_ORIGIN, STORED_ORIENTATION, STORED_QUAT)


func test_for_slot_is_empty_before_any_store() -> void:
	assert_true(_cursors.for_slot(SLOT).is_empty())


func test_for_slot_returns_the_stored_cursor_with_zero_age() -> void:
	_store_default()
	var cursor: Dictionary = _cursors.for_slot(SLOT)
	assert_eq(cursor["origin"], STORED_ORIGIN)
	assert_eq(cursor["orientation_index"], STORED_ORIENTATION)
	assert_eq(cursor["free_quat"], STORED_QUAT)
	assert_almost_eq(float(cursor["age"]), 0.0, AGE_EPSILON)


func test_age_is_seconds_since_the_store() -> void:
	_store_default()
	_now += 2.5
	assert_almost_eq(float(_cursors.for_slot(SLOT)["age"]), 2.5, AGE_EPSILON)
	_now += 1.0
	assert_almost_eq(float(_cursors.for_slot(SLOT)["age"]), 3.5, AGE_EPSILON)


func test_a_second_store_replaces_the_cursor_and_restarts_the_age() -> void:
	_store_default()
	_now += 5.0
	_cursors.store(SLOT, Vector3.ONE, 2, Quaternion.IDENTITY)
	var cursor: Dictionary = _cursors.for_slot(SLOT)
	assert_eq(cursor["origin"], Vector3.ONE)
	assert_eq(cursor["orientation_index"], 2)
	assert_eq(cursor["free_quat"], Quaternion.IDENTITY)
	assert_almost_eq(float(cursor["age"]), 0.0, AGE_EPSILON)


func test_slots_are_independent() -> void:
	_store_default(SLOT)
	assert_true(_cursors.for_slot(OTHER_SLOT).is_empty())
	_cursors.store(OTHER_SLOT, Vector3.ONE, 1, Quaternion.IDENTITY)
	_cursors.clear(SLOT)
	assert_true(_cursors.for_slot(SLOT).is_empty())
	assert_eq(_cursors.for_slot(OTHER_SLOT)["origin"], Vector3.ONE)


func test_clear_removes_the_cursor() -> void:
	_store_default()
	_cursors.clear(SLOT)
	assert_true(_cursors.for_slot(SLOT).is_empty())


func test_clear_of_a_slot_with_no_cursor_is_harmless() -> void:
	_cursors.clear(SLOT)
	assert_true(_cursors.for_slot(SLOT).is_empty())


func test_reset_drops_every_cursor() -> void:
	_store_default(SLOT)
	_store_default(OTHER_SLOT)
	_cursors.reset()
	assert_true(_cursors.for_slot(SLOT).is_empty())
	assert_true(_cursors.for_slot(OTHER_SLOT).is_empty())


func test_reset_then_store_starts_a_fresh_age() -> void:
	_store_default()
	_now += 9.0
	_cursors.reset()
	_store_default()
	assert_almost_eq(float(_cursors.for_slot(SLOT)["age"]), 0.0, AGE_EPSILON)


func test_bind_keeps_the_stored_cursors() -> void:
	_store_default()
	_now += 1.0
	_cursors.bind(HomeHostPort.new())
	var cursor: Dictionary = _cursors.for_slot(SLOT)
	assert_eq(cursor["origin"], STORED_ORIGIN)
	assert_almost_eq(float(cursor["age"]), 1.0, AGE_EPSILON)


func test_auto_drop_pose_is_the_stored_cursor_when_present() -> void:
	_store_default()
	var pose: Dictionary = _cursors.auto_drop_pose(SLOT)
	assert_eq(pose["origin"], STORED_ORIGIN, "a stored cursor is not raised")
	assert_eq(pose["orientation_index"], STORED_ORIENTATION)
	assert_eq(pose["free_quat"], STORED_QUAT)


func test_auto_drop_pose_falls_back_to_the_raised_home_without_a_cursor() -> void:
	var pose: Dictionary = _cursors.auto_drop_pose(SLOT)
	var expected_height: float = _ghost.home_spawn_pivot_height(_beacon, _physics)
	var origin: Vector3 = pose["origin"]
	assert_almost_eq(origin.x, HOME.x, HEIGHT_EPSILON)
	assert_almost_eq(origin.z, HOME.z, HEIGHT_EPSILON)
	assert_almost_eq(origin.y - HOME.y, expected_height, HEIGHT_EPSILON)
	assert_eq(pose["orientation_index"], 0)
	assert_eq(pose["free_quat"], Quaternion.IDENTITY)


func test_auto_drop_pose_falls_back_again_after_clear_and_reset() -> void:
	_store_default()
	_cursors.clear(SLOT)
	assert_ne(_cursors.auto_drop_pose(SLOT)["origin"], STORED_ORIGIN)
	_store_default()
	_cursors.reset()
	assert_eq(_cursors.auto_drop_pose(SLOT)["orientation_index"], 0)
	assert_ne(_cursors.auto_drop_pose(SLOT)["origin"], STORED_ORIGIN)


func test_fallback_asks_the_bound_host_for_the_slots_home() -> void:
	var host: HomeHostPort = HomeHostPort.new()
	_cursors.bind(host)
	_cursors.auto_drop_pose(OTHER_SLOT)
	assert_eq(host.calls_to(&"default_ghost_origin"), [[OTHER_SLOT]] as Array[Array])
