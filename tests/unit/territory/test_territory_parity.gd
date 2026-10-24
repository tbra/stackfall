extends GutTest
## Parity recipe for the territory cleanup: fixed scenes go through the production
## solve path (TerritorySolveJob.run: cull, solver, raster fill, render list) and
## reduce to one digest each. The digests are goldens captured on unchanged main; a
## refactor of the solve path must leave every one of them identical.
##
## Deterministic by construction: no scene tree, physics or wall clock; seeds fixed
## per scene; default TerritoryTuning; heights are float32-exact, as the game gets
## them from a Vector3 y.
##
## Capture command (prints every `DIGEST <scene> <value>` line, then copy the values
## into GOLDENS):
##   powershell -NoProfile -File tools/run_gut.ps1 test_territory_parity
## Floor: run it in separate Godot processes; every run must pass with these goldens.

const FIELD_RADIUS: float = 20.0
const CELL: float = 1.0
const WAIT_TIMEOUT_MS: int = 10000
const HOME_A: Vector2 = Vector2(-9.0, 0.0)
const HOME_B: Vector2 = Vector2(9.0, 0.0)
const SPREAD: float = 15.0
const BLOCKS_PER_TEAM: int = 60
const MAX_BLOCK_HEIGHT: float = 9.0
const WORKER_SCENE_EXTRA_BLOCKS: int = 40

const GOLDENS: Dictionary = {
	"random_holes_off": 453237604,
	"random_holes_on": 3767949615,
	"towers": 570184075,
	"island_and_chain": 1201541940,
	"cap_and_zero": 899915127,
	"worker_large": 923401234,
}

var _tuning: TerritoryTuning = TerritoryTuning.new()


# --- scene builders -------------------------------------------------------------------

## A float32-exact height, as the game reads it from a Vector3.
func _f32(value: float) -> float:
	return PackedFloat32Array([value])[0]


func _home(position: Vector2, team: int) -> InfluenceCircle:
	return InfluenceCircle.for_home(position, team, team, _tuning)


func _block(position: Vector2, height: float, team: int, body_id: int) -> InfluenceCircle:
	var h: float = _f32(height)
	var radius: float = InfluenceCircle.radius_for_height(h, _tuning, FIELD_RADIUS)
	return InfluenceCircle.new(position, radius, team, team, false, body_id)


func _random_scene(seed_value: int, per_team: int) -> Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var circles: Array[InfluenceCircle] = []
	circles.append(_home(HOME_A, 0))
	circles.append(_home(HOME_B, 1))
	var body_id: int = 100
	for team: int in range(2):
		var anchor: Vector2 = HOME_A if team == 0 else HOME_B
		for _i: int in range(per_team):
			var spot: Vector2 = anchor + Vector2(
				rng.randf_range(-SPREAD, SPREAD), rng.randf_range(-SPREAD, SPREAD)
			)
			var height: float = rng.randf_range(0.0, MAX_BLOCK_HEIGHT)
			circles.append(_block(spot, height, team, body_id))
			body_id += 1
	return circles


func _towers_scene() -> Array:
	var circles: Array[InfluenceCircle] = []
	circles.append(_home(HOME_A, 0))
	circles.append(_home(HOME_B, 1))
	var body_id: int = 200
	# Tall tower with small cones stacked under it.
	var tower: Vector2 = Vector2(-5.0, 4.0)
	circles.append(_block(tower, 6.0, 0, body_id))
	body_id += 1
	for i: int in range(6):
		var offset: Vector2 = Vector2(0.4 * float(i) - 1.0, 0.3 * float(i % 3))
		circles.append(_block(tower + offset, 0.5 + 0.3 * float(i), 0, body_id))
		body_id += 1
	# Equal-radius ties: same height, same and different centres.
	circles.append(_block(Vector2(-6.0, -5.0), 2.0, 0, body_id))
	circles.append(_block(Vector2(-6.0, -5.0), 2.0, 0, body_id + 1))
	circles.append(_block(Vector2(-6.5, -5.0), 2.0, 0, body_id + 2))
	body_id += 3
	# Another team's tower over its own small cone, and an other-team cone inside
	# team 0's tower (never culled across teams).
	circles.append(_block(Vector2(6.0, 3.0), 5.0, 1, body_id))
	circles.append(_block(Vector2(6.2, 3.1), 1.0, 1, body_id + 1))
	circles.append(_block(tower + Vector2(0.5, 0.0), 0.5, 1, body_id + 2))
	body_id += 3
	# Exactly tangent-inside: a capped circle (radius 12) and a base-only circle
	# (radius 1.5) whose centre sits at distance 12 - 1.5 (dyadic, so diff^2 == d^2).
	var big: InfluenceCircle = _block(Vector2(-14.0, 0.0), 100.0, 0, body_id)
	circles.append(big)
	var tangent_gap: float = big.radius - InfluenceCircle.radius_for_height(0.0, _tuning, FIELD_RADIUS)
	circles.append(_block(big.center + Vector2(tangent_gap, 0.0), 0.0, 0, body_id + 1))
	# Just outside the tangent position: kept.
	circles.append(_block(big.center + Vector2(0.0, tangent_gap + 0.01), 0.0, 0, body_id + 2))
	return circles


func _island_scene() -> Array:
	# The test_territory_polish layout: a cut-off island with a contained pair next
	# to a chain to home with a contained pair.
	var circles: Array[InfluenceCircle] = []
	circles.append(_home(Vector2(-8.0, 0.0), 0))
	circles.append(_home(Vector2(8.0, 0.0), 1))
	circles.append(_block(Vector2(-5.0, 0.0), 2.0, 0, 0))
	circles.append(_block(Vector2(-5.0, 0.5), 0.0, 0, 1))
	circles.append(_block(Vector2(0.0, 12.0), 3.0, 0, 2))
	circles.append(_block(Vector2(0.2, 12.0), 0.0, 0, 3))
	circles.append(_block(Vector2(1.5, 13.0), 0.5, 0, 4))
	circles.append(_block(Vector2(-2.0, 2.0), 2.5, 0, 5))
	circles.append(_block(Vector2(-2.1, 2.0), 0.0, 0, 6))
	circles.append(_block(Vector2(6.0, -4.0), 1.5, 1, 7))
	return circles


func _cap_scene() -> Array:
	var circles: Array[InfluenceCircle] = []
	circles.append(_home(HOME_A, 0))
	circles.append(_home(HOME_B, 1))
	circles.append(_block(Vector2(-3.0, 0.0), 50.0, 0, 0))
	circles.append(_block(Vector2(-3.0, 8.0), 30.0, 0, 1))
	circles.append(_block(Vector2(-3.0, -8.0), 0.0, 0, 2))
	circles.append(_block(Vector2(4.0, 0.0), 0.0, 1, 3))
	circles.append(_block(Vector2(4.0, 3.0), 40.0, 1, 4))
	circles.append(_block(Vector2(4.0, -3.0), 0.0, 1, 5))
	return circles


## name -> [circles, holes_enabled]. Built fresh on every call.
func _scenes() -> Dictionary:
	return {
		"random_holes_off": [_random_scene(1133, BLOCKS_PER_TEAM), false],
		"random_holes_on": [_random_scene(1133, BLOCKS_PER_TEAM), true],
		"towers": [_towers_scene(), false],
		"island_and_chain": [_island_scene(), false],
		"cap_and_zero": [_cap_scene(), false],
		"worker_large": [
			_random_scene(4177, WORKER_SCENE_EXTRA_BLOCKS + _tuning.async_solve_min_circles), true
		],
	}


# --- the production path --------------------------------------------------------------

## The only place that knows the job's input fields.
func _solve(circles: Array[InfluenceCircle], holes: bool) -> TerritorySolveJob:
	var job: TerritorySolveJob = TerritorySolveJob.new()
	job.circles = circles
	job.holes_enabled = holes
	job.solver_tuning = _tuning.duplicate() as TerritoryTuning
	job.fill_raster = TerritoryRaster.new(CellGrid.new(FIELD_RADIUS, CELL), _tuning)
	return job


func _run_inline(scene: Array) -> TerritorySolveJob:
	var circles: Array[InfluenceCircle] = scene[0]
	var job: TerritorySolveJob = _solve(circles, scene[1])
	job.run()
	return job


func _run_on_worker(scene: Array) -> TerritorySolveJob:
	var circles: Array[InfluenceCircle] = scene[0]
	var job: TerritorySolveJob = _solve(circles, scene[1])
	job.task_id = WorkerThreadPool.add_task(job.run)
	var start: int = Time.get_ticks_msec()
	while not WorkerThreadPool.is_task_completed(job.task_id) and Time.get_ticks_msec() - start < WAIT_TIMEOUT_MS:
		OS.delay_msec(1)
	WorkerThreadPool.wait_for_task_completion(job.task_id)
	return job


func _digest(job: TerritorySolveJob) -> int:
	var groups: Array = []
	for g: int in range(job.groups.group_count()):
		var members: Array = Array(job.groups.circles_of(g))
		members.sort()
		groups.append([job.groups.team_of(g), members])
	var circles: Array = []
	for circle: InfluenceCircle in job.out_circles:
		circles.append([circle.center, circle.radius, circle.team_id, circle.body_id])
	return [
		job.fill_raster.owner_bytes(),
		job.fill_raster.state_bytes(),
		groups,
		job.render["xs"], job.render["zs"], job.render["radii"], job.render["teams"],
		circles,
	].hash()


func _body_ids(job: TerritorySolveJob) -> Array:
	var ids: Array = []
	for circle: InfluenceCircle in job.out_circles:
		ids.append(circle.body_id)
	return ids


# --- tests ----------------------------------------------------------------------------

func test_scenes_are_not_trivial() -> void:
	var scenes: Dictionary = _scenes()
	for scene_name: String in scenes:
		var job: TerritorySolveJob = _run_inline(scenes[scene_name])
		assert_gt(job.groups.group_count(), 1, "%s: both teams form a group" % scene_name)
		assert_gt((job.render["xs"] as PackedFloat32Array).size(), 2, "%s: circles reach the render list" % scene_name)


func test_worker_scene_is_above_the_async_threshold() -> void:
	var circles: Array = (_scenes()["worker_large"] as Array)[0]
	assert_gt(circles.size(), _tuning.async_solve_min_circles)


func test_cull_scenes_actually_cull() -> void:
	var scenes: Dictionary = _scenes()
	for scene_name: String in ["towers", "island_and_chain", "random_holes_off"]:
		var circles: Array = (scenes[scene_name] as Array)[0]
		var job: TerritorySolveJob = _run_inline(scenes[scene_name])
		assert_lt(job.out_circles.size(), circles.size(), "%s: contained circles are dropped" % scene_name)


func test_tangent_circle_is_dropped_and_outside_one_is_kept() -> void:
	var scene: Array = _scenes()["towers"]
	var all: Array = scene[0]
	var tangent_id: int = (all[all.size() - 2] as InfluenceCircle).body_id
	var outside_id: int = (all[all.size() - 1] as InfluenceCircle).body_id
	var ids: Array = _body_ids(_run_inline(scene))
	assert_false(ids.has(tangent_id), "A circle exactly tangent inside a larger one is culled.")
	assert_true(ids.has(outside_id), "A circle just outside the tangent position is kept.")


func test_inline_and_worker_digests_agree_and_match_goldens() -> void:
	var scenes: Dictionary = _scenes()
	for scene_name: String in scenes:
		var inline_digest: int = _digest(_run_inline(scenes[scene_name]))
		var worker_digest: int = _digest(_run_on_worker(scenes[scene_name]))
		print("DIGEST %s %d" % [scene_name, inline_digest])
		assert_eq(worker_digest, inline_digest, "%s: worker equals inline" % scene_name)
		assert_eq(inline_digest, GOLDENS[scene_name], "%s: golden" % scene_name)


func test_repeat_runs_in_one_process_are_identical() -> void:
	var scenes: Dictionary = _scenes()
	for scene_name: String in scenes:
		assert_eq(_digest(_run_inline(scenes[scene_name])), _digest(_run_inline(scenes[scene_name])), "%s: repeatable" % scene_name)


func test_digest_changes_when_the_scene_changes() -> void:
	var scene: Array = _scenes()["random_holes_off"]
	var before: int = _digest(_run_inline(scene))
	var circles: Array[InfluenceCircle] = scene[0]
	circles[0].center += Vector2(1.0, 0.0)
	assert_ne(before, _digest(_run_inline(scene)), "The digest reacts to a moved home circle.")



# --- raster behaviour pinned by mutation survivors ------------------------------------
# Absolute expectations on the TerritoryRaster public surface: the fills, the hole timers
# and the replication writers. Cell (20, 20) is the cell whose centre is (0, 0) (odd grid).

const MID: int = 20
const SHORT_DELTA: float = 0.1


func _new_raster() -> TerritoryRaster:
	return TerritoryRaster.new(CellGrid.new(FIELD_RADIUS, CELL), _tuning)


func _disc(x: float, y: float, radius: float, team: int) -> InfluenceCircle:
	return InfluenceCircle.new(Vector2(x, y), radius, team, team, false, 0)


## One group per circle, in order, each owned by that circle's team.
func _one_group_each(circles: Array[InfluenceCircle]) -> TerritoryGroups:
	var groups: TerritoryGroups = TerritoryGroups.new()
	for i: int in range(circles.size()):
		groups.add_group(circles[i].team_id, PackedInt32Array([i]))
	return groups


func _fill(raster: TerritoryRaster, circles: Array[InfluenceCircle], holes: bool) -> void:
	raster.fill_ownership(circles, _one_group_each(circles), holes)


func _owned_cell_count(raster: TerritoryRaster, team: int) -> int:
	var count: int = 0
	var grid: CellGrid = raster.grid()
	for cy: int in range(grid.res):
		for cx: int in range(grid.res):
			if grid.is_in_disk(cx, cy) and raster.team_at(cx, cy) == team:
				count += 1
	return count


func _keyframe_bytes(raster: TerritoryRaster) -> Array[PackedByteArray]:
	var count: int = raster.grid().cell_count()
	var owners: PackedByteArray = PackedByteArray()
	owners.resize(count)
	var states: PackedByteArray = PackedByteArray()
	states.resize(count)
	return [owners, states]


func _cell(raster: TerritoryRaster, cx: int, cy: int) -> int:
	return raster.grid().cell_index(cx, cy)


func test_fresh_and_reset_raster_report_unowned_cells_as_minus_one() -> void:
	var raster: TerritoryRaster = _new_raster()
	assert_eq(raster.team_at(MID, MID), -1, "A fresh raster owns nothing.")
	_fill(raster, [_disc(0.0, 0.0, 3.0, 1)] as Array[InfluenceCircle], false)
	assert_eq(raster.team_at(MID, MID), 1)
	raster.reset()
	assert_eq(raster.team_at(MID, MID), -1, "reset() unowns every cell as -1.")
	assert_eq(raster.group_at(MID, MID), TerritoryGroups.NO_GROUP)


func test_is_hole_index_is_false_outside_the_grid() -> void:
	var raster: TerritoryRaster = _new_raster()
	raster.force_hole_cell(MID, MID, 1.0, true)
	assert_true(raster.is_hole_index(_cell(raster, MID, MID)))
	assert_false(raster.is_hole_index(raster.grid().cell_count()), "One past the last cell is off the grid.")
	assert_false(raster.is_hole_index(-1))


func test_team_share_of_a_team_with_no_cells_is_zero() -> void:
	var raster: TerritoryRaster = _new_raster()
	_fill(raster, [_disc(0.0, 0.0, 3.0, 0)] as Array[InfluenceCircle], false)
	assert_eq(raster.team_share(7), 0.0)


func test_team_share_equals_owned_cells_over_disk_cells_in_both_fills() -> void:
	for holes: bool in [false, true]:
		var raster: TerritoryRaster = _new_raster()
		_fill(raster, [_disc(0.0, 0.0, 3.0, 0)] as Array[InfluenceCircle], holes)
		var owned: int = _owned_cell_count(raster, 0)
		assert_gt(owned, 0, "holes=%s: the disc owns cells" % holes)
		assert_almost_eq(
			raster.team_share(0), float(owned) / float(raster.grid().in_disk_cell_count()), 0.000001,
			"holes=%s: share counts every owned cell exactly once" % holes
		)


func test_zero_radius_circle_owns_nothing_in_both_fills() -> void:
	for holes: bool in [false, true]:
		var raster: TerritoryRaster = _new_raster()
		_fill(raster, [_disc(0.0, 0.0, 0.0, 0)] as Array[InfluenceCircle], holes)
		assert_eq(raster.team_at(MID, MID), -1, "holes=%s: a radius-0 circle claims no cell" % holes)
		assert_eq(raster.team_share(0), 0.0)


func test_circle_owns_the_cell_exactly_one_radius_away_in_both_fills() -> void:
	# Centre (0, 0), radius 3: the cell centres (0, 3) etc. sit exactly on the rim.
	for holes: bool in [false, true]:
		var raster: TerritoryRaster = _new_raster()
		_fill(raster, [_disc(0.0, 0.0, 3.0, 0)] as Array[InfluenceCircle], holes)
		assert_eq(raster.team_at(MID, MID + 3), 0, "holes=%s: rim cell below" % holes)
		assert_eq(raster.team_at(MID, MID - 3), 0, "holes=%s: rim cell above" % holes)
		assert_eq(raster.team_at(MID + 3, MID), 0, "holes=%s: rim cell right" % holes)
		assert_eq(raster.team_at(MID - 3, MID), 0, "holes=%s: rim cell left" % holes)
		assert_eq(raster.team_at(MID, MID + 4), -1, "holes=%s: beyond the rim" % holes)


func test_goal_zone_reaches_the_last_column() -> void:
	var raster: TerritoryRaster = _new_raster()
	var last: int = raster.grid().res - 1
	raster.set_goal_zones(PackedVector2Array([Vector2(19.0, 0.0)]), 2.5)
	assert_true(raster.is_goal_zone(last, MID), "The rim column inside the radius is in the zone.")
	assert_true(raster.is_goal_zone(last - 1, MID))
	assert_false(raster.is_goal_zone(last - 5, MID), "Five cells in is outside radius 2.5.")


func test_adopt_fill_without_holes_does_not_advance_hole_timers() -> void:
	var raster: TerritoryRaster = _new_raster()
	raster.force_hole_cell(MID, MID, 0.5, false)
	_fill(raster, [] as Array[InfluenceCircle], false)
	raster.adopt_fill(raster, 10.0, false, false)
	assert_true(raster.is_hole(MID, MID), "With holes off the timers are not advanced, so the punched hole stays.")
	assert_eq(raster.holes_closed().size(), 0)
	raster.advance_time(10.0, false)
	assert_false(raster.is_hole(MID, MID), "advance_time() does advance them, closing it.")


func test_advance_time_clears_the_previous_step_lists() -> void:
	var raster: TerritoryRaster = _new_raster()
	raster.force_hole_cell(MID, MID, 5.0, false)
	assert_eq(raster.holes_opened().size(), 1)
	raster.advance_time(SHORT_DELTA, false)
	assert_eq(raster.holes_opened().size(), 0, "The opened list is per step.")
	assert_eq(raster.holes_closed().size(), 0)


func test_a_cell_contested_again_after_going_quiet_still_opens_its_hole() -> void:
	var raster: TerritoryRaster = _new_raster()
	var meeting: Array[InfluenceCircle] = [_disc(-3.0, 0.0, 6.0, 0), _disc(3.0, 0.0, 6.0, 1)]
	var apart: Array[InfluenceCircle] = [_disc(-3.0, 0.0, 6.0, 0), _disc(15.0, 0.0, 4.0, 1)]
	_fill(raster, meeting, true)
	raster.adopt_fill(raster, SHORT_DELTA, true, false)
	assert_true(raster.is_contested(MID, MID))
	assert_false(raster.is_hole(MID, MID), "Not yet: hole_delay has not passed.")
	_fill(raster, apart, true)
	raster.adopt_fill(raster, 1.0, true, false)
	assert_false(raster.is_contested(MID, MID))
	_fill(raster, meeting, true)
	raster.adopt_fill(raster, _tuning.hole_delay + 0.05, true, false)
	assert_true(raster.is_hole(MID, MID), "The second contest runs its own timer to a hole.")


func test_keyframe_decodes_every_state_bit() -> void:
	var raster: TerritoryRaster = _new_raster()
	var bytes: Array[PackedByteArray] = _keyframe_bytes(raster)
	var owned: int = _cell(raster, MID, MID)
	var contested: int = _cell(raster, MID + 1, MID)
	var hole: int = _cell(raster, MID + 2, MID)
	var zone: int = _cell(raster, MID + 3, MID)
	bytes[0][owned] = 2
	bytes[0][contested] = 1
	bytes[1][contested] = TerritoryRaster.STATE_CONTESTED
	bytes[0][hole] = 1
	bytes[1][hole] = TerritoryRaster.STATE_HOLE
	bytes[0][zone] = 1
	bytes[1][zone] = TerritoryRaster.STATE_GOAL_ZONE
	raster.apply_replicated_state(bytes[0], bytes[1])

	assert_eq(raster.team_at(MID, MID), 1)
	assert_eq(raster.group_at(MID, MID), TerritoryRaster.REPLICATED_GROUP)
	assert_false(raster.is_contested(MID, MID))
	assert_false(raster.is_hole(MID, MID))
	assert_false(raster.is_goal_zone(MID, MID))

	assert_true(raster.is_contested(MID + 1, MID))
	assert_eq(raster.team_at(MID + 1, MID), -1, "A contested cell has no owner even with an owner byte.")
	assert_false(raster.is_hole(MID + 1, MID))

	assert_true(raster.is_hole(MID + 2, MID))
	assert_eq(raster.team_at(MID + 2, MID), -1, "A hole reads unowned.")
	assert_false(raster.is_contested(MID + 2, MID))

	assert_true(raster.is_goal_zone(MID + 3, MID))
	assert_false(raster.is_hole(MID + 3, MID))
	assert_eq(raster.team_at(MID + 3, MID), 0)

	assert_false(raster.is_goal_zone(MID + 4, MID))
	assert_eq(raster.group_at(MID + 4, MID), TerritoryGroups.NO_GROUP)
	assert_eq(Array(raster.holes_opened()), [hole], "Only the cell that became a hole is reported opened.")
	assert_eq(raster.holes_closed().size(), 0)

	bytes[1][hole] = 0
	raster.apply_replicated_state(bytes[0], bytes[1])
	assert_eq(raster.holes_opened().size(), 0)
	assert_eq(Array(raster.holes_closed()), [hole], "A cell that stopped being a hole is reported closed.")
	assert_false(raster.is_hole(MID + 2, MID))
	assert_eq(raster.team_at(MID + 2, MID), 0)


func test_keyframe_of_the_wrong_length_is_ignored_whichever_array_is_short() -> void:
	var raster: TerritoryRaster = _new_raster()
	var bytes: Array[PackedByteArray] = _keyframe_bytes(raster)
	bytes[0][_cell(raster, MID, MID)] = 1
	var short: PackedByteArray = PackedByteArray([1])
	raster.apply_replicated_state(short, bytes[1])
	assert_eq(raster.team_at(MID, MID), -1, "Short owners: nothing applied.")
	raster.apply_replicated_state(bytes[0], short)
	assert_eq(raster.team_at(MID, MID), -1, "Short states: nothing applied.")
	raster.apply_replicated_state(bytes[0], bytes[1])
	assert_eq(raster.team_at(MID, MID), 0, "The right length applies.")


func test_replicated_team_share_counts_only_in_disk_cells() -> void:
	var raster: TerritoryRaster = _new_raster()
	var bytes: Array[PackedByteArray] = _keyframe_bytes(raster)
	for cx: int in range(MID, MID + 4):
		bytes[0][_cell(raster, cx, MID)] = 1
	bytes[0][_cell(raster, 0, 0)] = 1
	assert_false(raster.grid().is_in_disk(0, 0), "The corner is off the disk.")
	raster.apply_replicated_state(bytes[0], bytes[1])
	assert_almost_eq(
		raster.team_share(0), 4.0 / float(raster.grid().in_disk_cell_count()), 0.000001,
		"Four in-disk cells; the off-disk corner never counts."
	)


func test_diff_applies_every_named_cell_and_ignores_bad_input() -> void:
	var raster: TerritoryRaster = _new_raster()
	var first: int = _cell(raster, MID, MID)
	var last: int = _cell(raster, MID + 1, MID)
	raster.apply_replicated_diff(
		PackedInt32Array([first, last]), PackedByteArray([1, 2]), PackedByteArray([0, 0])
	)
	assert_eq(raster.team_at(MID, MID), 0)
	assert_eq(raster.team_at(MID + 1, MID), 1, "The last named cell is applied too.")

	raster.apply_replicated_diff(
		PackedInt32Array([first, last]), PackedByteArray([2]), PackedByteArray([0, 0])
	)
	raster.apply_replicated_diff(
		PackedInt32Array([first, last]), PackedByteArray([2, 2]), PackedByteArray([0])
	)
	assert_eq(raster.team_at(MID, MID), 0, "Mismatched payload lengths change nothing.")

	raster.apply_replicated_diff(
		PackedInt32Array([-1, raster.grid().cell_count(), first]),
		PackedByteArray([3, 3, 3]), PackedByteArray([0, 0, 0])
	)
	assert_eq(raster.team_at(MID, MID), 2, "Out-of-range indices are skipped, the rest applied.")


func test_diff_reports_only_its_own_hole_changes() -> void:
	var raster: TerritoryRaster = _new_raster()
	var cell: int = _cell(raster, MID, MID)
	raster.apply_replicated_diff(
		PackedInt32Array([cell]), PackedByteArray([1]), PackedByteArray([TerritoryRaster.STATE_HOLE])
	)
	assert_eq(Array(raster.holes_opened()), [cell])
	raster.apply_replicated_diff(PackedInt32Array([cell]), PackedByteArray([1]), PackedByteArray([0]))
	assert_eq(raster.holes_opened().size(), 0, "The opened list is per diff.")
	assert_eq(Array(raster.holes_closed()), [cell])
	raster.apply_replicated_diff(PackedInt32Array([cell]), PackedByteArray([1]), PackedByteArray([0]))
	assert_eq(raster.holes_closed().size(), 0, "The closed list is per diff.")
