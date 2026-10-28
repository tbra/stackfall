extends "res://tests/unit/match/match_world_test.gd"
## Match.request_throw on a tilted disc: a low release point is lifted to gift_aim_min_height_m above
## the LIVE surface under it (downhill that is below the rest plane, uphill above it), not above the
## pivot height.

const TILT_X_RAD: float = 0.12
const TILT_Z_RAD: float = 0.12
const LOW_RELEASE_M: float = 0.2
const HEIGHT_EPS: float = 0.05
const MIN_OFFSET_M: float = 0.5
## Level aim: the spawn height depends only on the surface under the release point (the cursor).
const AIM: Vector3 = Vector3(0.0, 0.0, -1.0)

var _special_tuning: SpecialTuning = preload("res://config/gifts/special_tuning.tres")


func after_each() -> void:
	Match._net_provider = null
	Match.abort_match()
	for child: Node in _blocks_root.get_children():
		child.free()
	Match.set_process(true)
	MatchTestReset.clear_world()
	await get_tree().process_frame


func _config() -> MatchConfig:
	var config: MatchConfig = _tiny_map_config()
	config.player_count = 2
	config.block_timer = 6.0
	config.rng_seed = 13579
	config.experiments_enabled = true
	config.qol = QolExperiments.new()
	config.qol.gift_loads_next = true
	return config


func _hold_gift(slot_id: int) -> void:
	Match._gifts._ensure_capacity(slot_id)
	Match._gifts._held_specials[slot_id] = &"test_special"
	Match._feed._held_is_gift[slot_id] = true
	var def: SpecialDef = SpecialDef.new()
	def.id = &"test_special"
	def.throwable = true
	def.arm_delay = 999.0
	def.arm_impulse = 999.0
	def.fuse_timeout_s = 999.0
	Match._placement._special_defs_config = Match.config
	Match._placement._special_defs_by_id[def.id] = def


func _tilt(sign_factor: float) -> void:
	var tilt: Quaternion = (Basis(Vector3.RIGHT, TILT_X_RAD * sign_factor) * Basis(Vector3.BACK, TILT_Z_RAD * sign_factor)).get_rotation_quaternion()
	_field.apply_replicated_pose(Vector3.ZERO, tilt)
	await wait_physics_frames(2)


## Throws from a point LOW_RELEASE_M over the disc at slot 0's home and returns the spawned block.
func _throw_low_at_home() -> Block:
	var home: Vector2 = Match.slot(0).home_position
	var release: Vector3 = _field.world_from_disk_local(home, LOW_RELEASE_M)
	var reason: StringName = Match.request_throw(0, release, 0, Quaternion.IDENTITY, AIM)
	assert_eq(reason, PlacementRules.REASON_OK)
	assert_eq(_blocks_root.get_child_count(), 1)
	return _blocks_root.get_child(0) as Block if _blocks_root.get_child_count() > 0 else null


func _assert_spawns_above_live_surface(sign_factor: float) -> void:
	Match.start_match(_config())
	_run_countdown()
	_hold_gift(0)
	await _tilt(sign_factor)
	var home: Vector2 = Match.slot(0).home_position
	var release: Vector3 = _field.world_from_disk_local(home, LOW_RELEASE_M)
	var live_surface: float = _field.surface_height_at(release)
	assert_gt(absf(live_surface - _field.surface_y()), MIN_OFFSET_M, "fixture: the surface under home is off the rest plane")
	var block: Block = _throw_low_at_home()
	if block == null:
		return
	assert_almost_eq(
		block.global_position.y, live_surface + _special_tuning.gift_aim_min_height_m, HEIGHT_EPS,
		"spawns at the minimum height over the live surface, not over the pivot")


func test_throw_from_a_low_release_spawns_min_height_over_the_live_surface_one_tilt() -> void:
	await _assert_spawns_above_live_surface(1.0)


func test_throw_from_a_low_release_spawns_min_height_over_the_live_surface_opposite_tilt() -> void:
	await _assert_spawns_above_live_surface(-1.0)


func test_level_disc_spawns_min_height_over_the_pivot_height() -> void:
	Match.start_match(_config())
	_run_countdown()
	_hold_gift(0)
	await _tilt(0.0)
	var block: Block = _throw_low_at_home()
	if block == null:
		return
	assert_almost_eq(block.global_position.y, _field.surface_y() + _special_tuning.gift_aim_min_height_m, HEIGHT_EPS)
