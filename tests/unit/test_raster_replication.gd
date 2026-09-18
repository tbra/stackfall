extends GutTest
## TerritoryRaster.apply_replicated_state / apply_replicated_diff — the
## client's mirror raster (docs/M3a_PLAN.md, "The client's raster is a mirror,
## not a solve").
##
## The contract these tests defend: a mirror fed the host's owner_bytes() and
## state_bytes() answers team_at(), is_contested(), is_hole_index() and
## therefore PlacementRules.validate() **bit-for-bit** the way the host does.
## Group indices deliberately do not survive (the win check is host-only), so
## nothing here compares group_at() between the two.

var _tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")


func _make_grid() -> CellGrid:
	# Small enough that a test can read every cell, large enough that circles
	# of the tuning's real radii overlap into contested bands.
	return CellGrid.new(12.0, 1.0)


func _make_raster() -> TerritoryRaster:
	return TerritoryRaster.new(_make_grid(), _tuning)


## A host raster with two teams whose circles overlap, solved long enough for
## the contested band to have become holes. That covers all four cell states
## the wire carries: unowned, owned, contested and hole.
func _solved_host_raster() -> TerritoryRaster:
	var raster: TerritoryRaster = _make_raster()
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.for_home(Vector2(-2.0, 0.0), 0, 0, _tuning),
		InfluenceCircle.for_home(Vector2(2.0, 0.0), 1, 1, _tuning),
	]
	var groups: TerritoryGroups = TerritoryGroups.new()
	groups.add_group(0, PackedInt32Array([0]))
	groups.add_group(1, PackedInt32Array([1]))

	var step: float = 1.0 / _tuning.solve_hz
	var elapsed: float = 0.0
	while elapsed < _tuning.hole_delay + step:
		raster.update(circles, groups, step, true)
		elapsed += step
	return raster


func _assert_mirrors(host: TerritoryRaster, mirror: TerritoryRaster) -> void:
	var grid: CellGrid = host.grid()
	var mismatches: int = 0
	for index: int in range(grid.cell_count()):
		var coords: Vector2i = grid.cell_coords(index)
		if host.team_at(coords.x, coords.y) != mirror.team_at(coords.x, coords.y):
			mismatches += 1
		elif host.is_contested(coords.x, coords.y) != mirror.is_contested(coords.x, coords.y):
			mismatches += 1
		elif host.is_hole_index(index) != mirror.is_hole_index(index):
			mismatches += 1
	assert_eq(mismatches, 0, "Every cell of the mirror must answer as the host's raster does.")


func test_a_keyframe_reproduces_owner_contested_and_hole_state() -> void:
	var host: TerritoryRaster = _solved_host_raster()
	var mirror: TerritoryRaster = _make_raster()

	mirror.apply_replicated_state(host.owner_bytes(), host.state_bytes())

	_assert_mirrors(host, mirror)


func test_the_solved_fixture_actually_contains_all_four_cell_states() -> void:
	# Without this the mirror tests could pass against an empty raster.
	var host: TerritoryRaster = _solved_host_raster()
	var grid: CellGrid = host.grid()
	var owned: int = 0
	var contested: int = 0
	var holes: int = 0
	var unowned: int = 0
	for index: int in range(grid.cell_count()):
		var coords: Vector2i = grid.cell_coords(index)
		if host.is_hole_index(index):
			holes += 1
		if host.is_contested(coords.x, coords.y):
			contested += 1
		elif host.team_at(coords.x, coords.y) >= 0:
			owned += 1
		else:
			unowned += 1
	assert_gt(owned, 0, "fixture should own cells")
	assert_gt(contested, 0, "fixture should contest cells")
	assert_gt(holes, 0, "fixture should have opened holes")
	assert_gt(unowned, 0, "fixture should leave cells unowned")


func test_a_keyframe_reproduces_team_share() -> void:
	var host: TerritoryRaster = _solved_host_raster()
	var mirror: TerritoryRaster = _make_raster()

	mirror.apply_replicated_state(host.owner_bytes(), host.state_bytes())

	assert_almost_eq(mirror.team_share(0), host.team_share(0), 0.0001)
	assert_almost_eq(mirror.team_share(1), host.team_share(1), 0.0001)
	assert_gt(host.team_share(0), 0.0, "the fixture should give team 0 real territory")


func test_validate_answers_identically_on_host_and_mirror() -> void:
	var host: TerritoryRaster = _solved_host_raster()
	var mirror: TerritoryRaster = _make_raster()
	mirror.apply_replicated_state(host.owner_bytes(), host.state_bytes())

	var grid: CellGrid = host.grid()
	var cells: Array[Vector3i] = [Vector3i.ZERO]
	var basis: Basis = Basis.IDENTITY
	var checked: int = 0
	var mismatches: int = 0
	for cy: int in range(0, grid.res, 3):
		for cx: int in range(0, grid.res, 3):
			var point: Vector2 = grid.cell_center(cx, cy)
			var host_result: PlacementRules.Result = PlacementRules.validate(
				PlacementRules.footprint_cells(cells, basis, point, 1.0, grid), host, 0
			)
			var mirror_result: PlacementRules.Result = PlacementRules.validate(
				PlacementRules.footprint_cells(cells, basis, point, 1.0, grid), mirror, 0
			)
			checked += 1
			if host_result != mirror_result:
				mismatches += 1
	assert_gt(checked, 10, "the sweep should actually test something")
	assert_eq(mismatches, 0, "PlacementRules.validate must agree on host and mirror.")


func test_a_keyframe_reports_the_holes_it_opened() -> void:
	var host: TerritoryRaster = _solved_host_raster()
	var mirror: TerritoryRaster = _make_raster()

	mirror.apply_replicated_state(host.owner_bytes(), host.state_bytes())

	var host_holes: int = 0
	for index: int in range(host.grid().cell_count()):
		if host.is_hole_index(index):
			host_holes += 1
	assert_eq(
		mirror.holes_opened().size(),
		host_holes,
		"A keyframe onto an empty mirror opens every hole it carries, so Field can build them."
	)
	assert_eq(mirror.holes_closed().size(), 0)


func test_a_diff_only_touches_the_cells_it_names() -> void:
	var host: TerritoryRaster = _solved_host_raster()
	var mirror: TerritoryRaster = _make_raster()
	mirror.apply_replicated_state(host.owner_bytes(), host.state_bytes())

	var grid: CellGrid = mirror.grid()
	var untouched: int = grid.cell_index(grid.res / 2, grid.res / 2)
	var untouched_coords: Vector2i = grid.cell_coords(untouched)
	var before_team: int = mirror.team_at(untouched_coords.x, untouched_coords.y)

	var target: int = grid.cell_index(0, 0)
	mirror.apply_replicated_diff(
		PackedInt32Array([target]), PackedByteArray([3]), PackedByteArray([0])
	)

	var target_coords: Vector2i = grid.cell_coords(target)
	assert_eq(mirror.team_at(target_coords.x, target_coords.y), 2, "owner byte 3 means team 2")
	assert_eq(mirror.team_at(untouched_coords.x, untouched_coords.y), before_team)


func test_a_diff_reports_a_hole_opening_and_closing() -> void:
	var mirror: TerritoryRaster = _make_raster()
	var grid: CellGrid = mirror.grid()
	var target: int = grid.cell_index(grid.res / 2, grid.res / 2)

	mirror.apply_replicated_diff(
		PackedInt32Array([target]),
		PackedByteArray([0]),
		PackedByteArray([TerritoryRaster.STATE_CONTESTED | TerritoryRaster.STATE_HOLE])
	)
	assert_eq(mirror.holes_opened(), PackedInt32Array([target]))
	assert_eq(mirror.holes_closed().size(), 0)
	assert_true(mirror.is_hole_index(target))

	mirror.apply_replicated_diff(
		PackedInt32Array([target]), PackedByteArray([1]), PackedByteArray([0])
	)
	assert_eq(mirror.holes_closed(), PackedInt32Array([target]))
	assert_eq(mirror.holes_opened().size(), 0)
	assert_false(mirror.is_hole_index(target))


func test_a_stale_mirror_converges_on_the_next_keyframe() -> void:
	var host: TerritoryRaster = _solved_host_raster()
	var mirror: TerritoryRaster = _make_raster()

	# A diff applied to a mirror that missed an earlier one: deliberately
	# wrong everywhere the diff does not reach.
	var grid: CellGrid = mirror.grid()
	var junk_cells: PackedInt32Array = PackedInt32Array()
	var junk_owners: PackedByteArray = PackedByteArray()
	var junk_states: PackedByteArray = PackedByteArray()
	for index: int in range(0, grid.cell_count(), 7):
		junk_cells.append(index)
		junk_owners.append(5)
		junk_states.append(TerritoryRaster.STATE_HOLE)
	mirror.apply_replicated_diff(junk_cells, junk_owners, junk_states)

	mirror.apply_replicated_state(host.owner_bytes(), host.state_bytes())

	_assert_mirrors(host, mirror)
	assert_almost_eq(mirror.team_share(1), host.team_share(1), 0.0001)


func test_a_payload_of_the_wrong_length_is_ignored() -> void:
	var host: TerritoryRaster = _solved_host_raster()
	var mirror: TerritoryRaster = _make_raster()
	mirror.apply_replicated_state(host.owner_bytes(), host.state_bytes())

	mirror.apply_replicated_state(PackedByteArray([1, 2, 3]), PackedByteArray([0, 0, 0]))
	_assert_mirrors(host, mirror)

	mirror.apply_replicated_diff(
		PackedInt32Array([0, 1]), PackedByteArray([1]), PackedByteArray([0, 0])
	)
	_assert_mirrors(host, mirror)


func test_an_out_of_range_diff_cell_is_skipped_not_fatal() -> void:
	var mirror: TerritoryRaster = _make_raster()
	var count: int = mirror.grid().cell_count()

	mirror.apply_replicated_diff(
		PackedInt32Array([-1, count + 10, 0]),
		PackedByteArray([2, 2, 2]),
		PackedByteArray([0, 0, 0])
	)

	var coords: Vector2i = mirror.grid().cell_coords(0)
	assert_eq(mirror.team_at(coords.x, coords.y), 1, "the in-range cell still applies")
