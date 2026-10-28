extends "res://tests/unit/match/match_world_test.gd"
## On a tilted disc a ghost raised high over the field is judged where it drops: at the world-vertical
## drop point, not where the disc-normal column through it would land. preview_placement and
## request_place agree on that verdict.

const TILT_Z_RAD: float = 0.2
const RAISE_M: float = 10.0
const SCAN_STEP: float = 0.25
const SCAN_ROWS: Array[float] = [-6.0, -3.0, 0.0, 3.0, 6.0]
const SCAN_RANGE: float = 18.0


func after_each() -> void:
	Match._net_provider = null
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _start_tilted() -> void:
	var config: MatchConfig = _tiny_map_config()
	config.player_count = 2
	config.block_timer = 6.0
	config.rng_seed = 13579
	Match.start_match(config)
	_run_countdown()
	_field.apply_replicated_pose(Vector3(0.0, 0.2, 0.0), Quaternion(Vector3.BACK, TILT_Z_RAD))
	await wait_physics_frames(2)


func _verdict_at(local: Vector2) -> PlacementRules.Result:
	return PlacementRules.validate_point(local, Match.raster(), Match.team_of(0))


## The disc point straight below world (x, z), disk-local.
func _drop_local(x: float, z: float) -> Vector2:
	var ground: Vector3 = Vector3(x, _field.surface_height_at(Vector3(x, 0.0, z)), z)
	var local: Vector3 = _field.to_local(ground)
	return Vector2(local.x, local.z)


func _raised(x: float, z: float) -> Vector3:
	return Vector3(x, _field.surface_height_at(Vector3(x, 0.0, z)) + RAISE_M, z)


## First scanned world (x, z) whose vertical drop verdict is `wanted` while the raised origin's own
## disk-local xz (the disc-normal column's neighbourhood) is judged differently.
func _find_split(wanted: PlacementRules.Result) -> Vector2:
	for z: float in SCAN_ROWS:
		var x: float = -SCAN_RANGE
		while x < SCAN_RANGE:
			var raised_local: Vector3 = _field.to_local(_raised(x, z))
			if _verdict_at(_drop_local(x, z)) == wanted and _verdict_at(Vector2(raised_local.x, raised_local.z)) != wanted:
				return Vector2(x, z)
			x += SCAN_STEP
	return Vector2(INF, INF)


func test_preview_judges_the_world_vertical_drop_point() -> void:
	await _start_tilted()
	var checked: int = 0
	for wanted: PlacementRules.Result in [PlacementRules.Result.VALID, PlacementRules.Result.OUTSIDE_TERRITORY]:
		var spot: Vector2 = _find_split(wanted)
		assert_ne(spot, Vector2(INF, INF), "fixture: a raised point whose drop and disc-normal verdicts differ (%s)" % wanted)
		if spot.x == INF:
			continue
		assert_eq(Match.preview_placement(0, _raised(spot.x, spot.y), 0, Quaternion.IDENTITY), wanted)
		checked += 1
	assert_eq(checked, 2)


func test_request_place_agrees_with_preview_at_the_drop_point() -> void:
	await _start_tilted()
	var valid: Vector2 = _find_split(PlacementRules.Result.VALID)
	assert_ne(valid, Vector2(INF, INF), "fixture: raised over the outside, dropping into territory")
	var outside: Vector2 = _find_split(PlacementRules.Result.OUTSIDE_TERRITORY)
	assert_ne(outside, Vector2(INF, INF), "fixture: raised over territory, dropping outside it")

	var refused: StringName = Match.request_place(0, _raised(outside.x, outside.y), 0, Quaternion.IDENTITY, false)
	assert_eq(refused, PlacementRules.REASON_OUTSIDE_TERRITORY)
	assert_eq(_blocks_root.get_child_count(), 0)

	var accepted: StringName = Match.request_place(0, _raised(valid.x, valid.y), 0, Quaternion.IDENTITY, false)
	assert_eq(accepted, PlacementRules.REASON_OK)
	assert_eq(_blocks_root.get_child_count(), 1)
