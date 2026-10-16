extends GutTest
## TerritoryRaster.apply_replicated_state / apply_replicated_diff — the
## client's mirror raster (it is a mirror, not a solve).
##
## The contract these tests defend: a mirror fed the host's owner_bytes() and
## state_bytes() answers team_at(), is_contested(), is_hole_index() and
## therefore PlacementRules.validate_point() **bit-for-bit** the way the host does.
## Group indices deliberately do not survive (the win check is host-only), so
## nothing here compares group_at() between the two.

var _tuning: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")


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


## The host skips solves on a clean board, so its raster bytes do not change
## and MatchNet.replicate_territory() finds no changed cells. The mirror must
## still pick up the next real change as a diff.
func test_mirror_still_receives_updates_after_host_clean_ticks_skip() -> void:
	var host: TerritoryRaster = _solved_host_raster()
	var mirror: TerritoryRaster = _make_raster()
	mirror.apply_replicated_state(host.owner_bytes(), host.state_bytes())
	var sent_owners: PackedByteArray = host.owner_bytes().duplicate()
	var sent_states: PackedByteArray = host.state_bytes().duplicate()

	# Clean ticks: the host does not touch the raster at all.
	assert_eq(host.owner_bytes(), sent_owners, "Skipped ticks leave the owner bytes unchanged (nothing to replicate).")
	assert_eq(host.state_bytes(), sent_states)

	# A real change (third home nearby) solves again and must reach the mirror as a diff.
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.for_home(Vector2(-2.0, 0.0), 0, 0, _tuning),
		InfluenceCircle.for_home(Vector2(2.0, 0.0), 1, 1, _tuning),
		InfluenceCircle.for_home(Vector2(0.0, 7.0), 2, 2, _tuning),
	]
	var groups: TerritoryGroups = TerritoryGroups.new()
	groups.add_group(0, PackedInt32Array([0]))
	groups.add_group(1, PackedInt32Array([1]))
	groups.add_group(2, PackedInt32Array([2]))
	host.update(circles, groups, 1.0 / _tuning.solve_hz, true)
	var changed: PackedInt32Array = PackedInt32Array()
	var owners: PackedByteArray = host.owner_bytes()
	var states: PackedByteArray = host.state_bytes()
	for index: int in range(owners.size()):
		if owners[index] != sent_owners[index] or states[index] != sent_states[index]:
			changed.append(index)
	assert_gt(changed.size(), 0, "fixture: the new solve changed cells.")
	var picked_owners: PackedByteArray = PackedByteArray()
	var picked_states: PackedByteArray = PackedByteArray()
	for index: int in changed:
		picked_owners.append(owners[index])
		picked_states.append(states[index])
	mirror.apply_replicated_diff(changed, picked_owners, picked_states)
	_assert_mirrors(host, mirror)
