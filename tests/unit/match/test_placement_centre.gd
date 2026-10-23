extends "res://tests/unit/match/match_world_test.gd"
## Placement legality is judged under the rotated footprint's centre, while the spawned body keeps
## its pivot as origin (spec 2.5 "Placement legality"): placement, throw preview and the host
## verdict agree for a tilted piece.

const SCAN_STEP: float = 0.25
const SCAN_ROWS: Array[float] = [-6.0, -3.0, 0.0, 3.0, 6.0]


func after_each() -> void:
	Match._net_provider = null
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _config() -> MatchConfig:
	var config: MatchConfig = _tiny_map_config()
	config.player_count = 2
	config.block_timer = 6.0
	config.rng_seed = 24680
	return config


## Slot 0 holds a pillar rolled onto its side along x: its centre sits 1.5 cubes to -x of the pivot.
func _start_with_lying_pillar() -> Quaternion:
	Match.start_match(_config())
	_run_countdown()
	Match._feed._held_shapes[0] = load("res://config/blocks/pillar.tres") as BlockShape
	return Quaternion(Vector3.BACK, PI * 0.5)


func _pivot_world(x: float, z: float) -> Vector3:
	return _field.to_global(Vector3(x, 5.0, z))


func _centre_x_shift(quat: Quaternion) -> float:
	var shape: BlockShape = Match.held_shape(0)
	return PlacementPoint.centre_offset(shape, Basis(quat), Match._physics_tuning.cube_size).x


func _verdict_at(x: float, z: float) -> PlacementRules.Result:
	return PlacementRules.validate_point(Vector2(x, z), Match.raster(), Match.team_of(0))


## First scanned pivot where the centre verdict is `centre_wanted` and the pivot's own is not.
func _find_disagreement(shift_x: float, centre_wanted: PlacementRules.Result) -> Vector2:
	var x: float = -16.0
	for z: float in SCAN_ROWS:
		x = -16.0
		while x < 16.0:
			if _verdict_at(x + shift_x, z) == centre_wanted and _verdict_at(x, z) != centre_wanted:
				return Vector2(x, z)
			x += SCAN_STEP
	return Vector2(INF, INF)


func test_preview_matches_the_centre_verdict_for_a_tilted_piece() -> void:
	var quat: Quaternion = _start_with_lying_pillar()
	var shift_x: float = _centre_x_shift(quat)
	assert_gt(absf(shift_x), 1.0, "the rolled pillar's centre really is off the pivot")
	var differing: int = 0
	for z: float in SCAN_ROWS:
		var x: float = -16.0
		while x < 16.0:
			var preview: PlacementRules.Result = Match.preview_placement(0, _pivot_world(x, z), 0, quat)
			var expected: PlacementRules.Result = _verdict_at(x + shift_x, z)
			if _field.raycast_down_disk_local(_pivot_world(x + shift_x, z)) != null:
				assert_eq(preview, expected, "preview at pivot (%.2f, %.2f)" % [x, z])
			if expected != _verdict_at(x, z):
				differing += 1
			x += SCAN_STEP
	assert_gt(differing, 0, "the scan crosses a territory edge, so pivot and centre verdicts differ somewhere")


func test_host_places_a_tilted_piece_whose_centre_is_in_territory_and_spawns_at_the_pivot() -> void:
	var quat: Quaternion = _start_with_lying_pillar()
	var shift_x: float = _centre_x_shift(quat)
	var spot: Vector2 = _find_disagreement(shift_x, PlacementRules.Result.VALID)
	assert_ne(spot, Vector2(INF, INF), "fixture: a pivot outside territory with its centre inside")
	var origin: Vector3 = _pivot_world(spot.x, spot.y)

	assert_eq(Match.preview_placement(0, origin, 0, quat), PlacementRules.Result.VALID)
	var reason: StringName = Match.request_place(0, origin, 0, quat, false)

	assert_eq(reason, PlacementRules.REASON_OK)
	assert_eq(_blocks_root.get_child_count(), 1)
	var block: Node3D = _blocks_root.get_child(0) as Node3D
	var local: Vector3 = _field.to_local(block.global_position)
	assert_almost_eq(local.x, spot.x, 0.001, "body origin stays the pivot (no double offset)")
	assert_almost_eq(local.z, spot.y, 0.001)


func test_host_refuses_a_tilted_piece_whose_pivot_is_in_territory_but_centre_is_not() -> void:
	var quat: Quaternion = _start_with_lying_pillar()
	var shift_x: float = _centre_x_shift(quat)
	var found: Vector2 = Vector2(INF, INF)
	for z: float in SCAN_ROWS:
		var x: float = -16.0
		while x < 16.0 and found.x == INF:
			if _verdict_at(x, z) == PlacementRules.Result.VALID and _verdict_at(x + shift_x, z) == PlacementRules.Result.OUTSIDE_TERRITORY:
				found = Vector2(x, z)
			x += SCAN_STEP
	assert_ne(found, Vector2(INF, INF), "fixture: a pivot inside territory with its centre outside")
	var origin: Vector3 = _pivot_world(found.x, found.y)
	var seq_before: int = Match.feed_seq(0)

	assert_eq(Match.preview_placement(0, origin, 0, quat), PlacementRules.Result.OUTSIDE_TERRITORY)
	var reason: StringName = Match.request_place(0, origin, 0, quat, false)

	assert_eq(reason, PlacementRules.REASON_OUTSIDE_TERRITORY)
	assert_eq(_blocks_root.get_child_count(), 0)
	assert_eq(Match.feed_seq(0), seq_before)


func test_auto_drop_relocation_lands_the_centre_on_the_valid_point() -> void:
	var quat: Quaternion = _start_with_lying_pillar()
	var shift_x: float = _centre_x_shift(quat)
	var spot: Vector2 = _find_disagreement(shift_x, PlacementRules.Result.OUTSIDE_TERRITORY)
	assert_ne(spot, Vector2(INF, INF))
	var origin: Vector3 = _pivot_world(spot.x, spot.y)
	var relocated: Array[Vector2] = []
	Events.placement_relocated.connect(func(_slot: int, point: Vector2) -> void: relocated.append(point))

	var reason: StringName = Match.request_place(0, origin, 0, quat, true)

	assert_eq(reason, PlacementRules.REASON_OK)
	assert_eq(relocated.size(), 1)
	var centre: Vector2 = relocated[0]
	assert_eq(_verdict_at(centre.x, centre.y), PlacementRules.Result.VALID, "the reported cursor point is a valid centre")
	var block: Node3D = _blocks_root.get_child(0) as Node3D
	var local: Vector3 = _field.to_local(block.global_position)
	assert_almost_eq(local.x, centre.x - shift_x, 0.001, "pivot = centre minus the shift, applied once")
	assert_almost_eq(local.z, centre.y, 0.001)
