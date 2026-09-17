extends GutTest
## Spec 2.2's connected-territory rule and spec 3.3's union-find-over-a-spatial-
## hash implementation.
##
## "Your territory is the union of all circles connected, directly or through
## other circles, to your home circle. Circles that aren't connected to your
## home give no territory. If a tower is cut off, its influence is gone."
## "Teams: territories of teammates never create holes between them. They merge
## for the win check."

const MAP_RADIUS: float = 45.0
const HOME_R: float = 6.0

var _tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")


func _solver(tuning: TerritoryTuning = _tuning) -> TerritorySolver:
	return TerritorySolver.new(tuning)


func _block(x: float, z: float, radius: float, team: int, slot: int = -1) -> InfluenceCircle:
	return InfluenceCircle.new(Vector2(x, z), radius, team, slot if slot >= 0 else team, false, 0)


func _home(x: float, z: float, team: int, slot: int = -1) -> InfluenceCircle:
	return InfluenceCircle.new(
		Vector2(x, z), HOME_R, team, slot if slot >= 0 else team, true, -1
	)


## -- Anchoring ---------------------------------------------------------------

func test_a_lone_home_circle_is_a_group_on_its_own() -> void:
	var solver: TerritorySolver = _solver()
	var circles: Array[InfluenceCircle] = [_home(0.0, 0.0, 0)]
	var groups: TerritoryGroups = solver.solve(circles)
	assert_eq(groups.group_count(), 1, "A home circle is always a group seed.")
	assert_eq(groups.team_of(0), 0)
	assert_eq(groups.circles_of(0), PackedInt32Array([0]))
	assert_true(solver.is_circle_connected(0))
	assert_eq(solver.group_of_circle(0), 0)


func test_a_block_circle_with_no_home_gives_no_territory() -> void:
	var solver: TerritorySolver = _solver()
	var circles: Array[InfluenceCircle] = [_block(0.0, 0.0, 5.0, 0)]
	var groups: TerritoryGroups = solver.solve(circles)
	assert_eq(groups.group_count(), 0)
	assert_false(solver.is_circle_connected(0))
	assert_eq(solver.group_of_circle(0), TerritoryGroups.NO_GROUP)


func test_an_unanchored_chain_gives_no_territory() -> void:
	## Three circles that all overlap each other, none of them a home.
	var solver: TerritorySolver = _solver()
	var circles: Array[InfluenceCircle] = [
		_block(0.0, 0.0, 4.0, 0), _block(6.0, 0.0, 4.0, 0), _block(12.0, 0.0, 4.0, 0)
	]
	assert_eq(solver.solve(circles).group_count(), 0)


## -- Overlap and connectivity ------------------------------------------------

func test_two_overlapping_same_team_circles_form_one_group() -> void:
	var solver: TerritorySolver = _solver()
	var circles: Array[InfluenceCircle] = [_home(0.0, 0.0, 0), _block(5.0, 0.0, 2.0, 0)]
	var groups: TerritoryGroups = solver.solve(circles)
	assert_eq(groups.group_count(), 1)
	assert_eq(groups.circles_of(0), PackedInt32Array([0, 1]))


func test_two_disjoint_anchored_groups_stay_separate() -> void:
	var solver: TerritorySolver = _solver()
	var circles: Array[InfluenceCircle] = [_home(-25.0, 0.0, 0), _home(25.0, 0.0, 1)]
	var groups: TerritoryGroups = solver.solve(circles)
	assert_eq(groups.group_count(), 2)
	assert_ne(solver.group_of_circle(0), solver.group_of_circle(1))


func test_a_chain_connects_through_its_middle() -> void:
	## home(r6) -- A(r3) -- B(r3): home and B are 13 m apart and do not touch
	## (6 + 3 = 9), but both reach A.
	var solver: TerritorySolver = _solver()
	var circles: Array[InfluenceCircle] = [
		_home(0.0, 0.0, 0), _block(8.0, 0.0, 3.0, 0), _block(13.0, 0.0, 3.0, 0)
	]
	assert_false(circles[0].overlaps(circles[2]), "The ends must not touch directly.")
	var groups: TerritoryGroups = solver.solve(circles)
	assert_eq(groups.group_count(), 1, "A and C are one territory through B.")
	assert_eq(groups.circles_of(0), PackedInt32Array([0, 1, 2]))


func test_touching_exactly_at_the_summed_radii_connects() -> void:
	var solver: TerritorySolver = _solver()
	var circles: Array[InfluenceCircle] = [_home(0.0, 0.0, 0), _block(9.0, 0.0, 3.0, 0)]
	assert_eq(solver.solve(circles).group_count(), 1)
	assert_true(solver.is_circle_connected(1))


func test_a_circle_a_hair_too_far_does_not_connect() -> void:
	var solver: TerritorySolver = _solver()
	var circles: Array[InfluenceCircle] = [_home(0.0, 0.0, 0), _block(9.05, 0.0, 3.0, 0)]
	assert_eq(solver.solve(circles).group_count(), 1)
	assert_false(solver.is_circle_connected(1))


func test_connectivity_works_across_the_spatial_hash_diagonally() -> void:
	## A big circle spanning many hash cells must still find a small neighbour
	## that shares only one of them.
	var solver: TerritorySolver = _solver()
	var circles: Array[InfluenceCircle] = [
		_home(0.0, 0.0, 0), _block(0.0, 0.0, 20.0, 0), _block(14.0, 14.0, 1.0, 0)
	]
	var groups: TerritoryGroups = solver.solve(circles)
	assert_eq(groups.group_count(), 1)
	assert_eq(groups.circles_of(0).size(), 3)


## -- The cut-off rule (M2 acceptance criterion) ------------------------------

func test_a_cut_off_tower_loses_its_influence() -> void:
	var solver: TerritorySolver = _solver()
	var linked: Array[InfluenceCircle] = [
		_home(0.0, 0.0, 0), _block(8.0, 0.0, 3.0, 0), _block(13.0, 0.0, 3.0, 0)
	]
	assert_eq(solver.solve(linked).circles_of(0).size(), 3, "Connected to start with.")

	## Remove the middle block: the far tower is now cut off.
	var cut: Array[InfluenceCircle] = [linked[0], linked[2]]
	var groups: TerritoryGroups = solver.solve(cut)
	assert_eq(groups.group_count(), 1, "Only the home's own group survives.")
	assert_eq(groups.circles_of(0), PackedInt32Array([0]))
	assert_false(solver.is_circle_connected(1), "The cut-off tower contributes nothing.")
	assert_eq(solver.group_of_circle(1), TerritoryGroups.NO_GROUP)


## -- Teams -------------------------------------------------------------------

func test_teammates_merge_into_one_group() -> void:
	## Two slots on team 0 whose homes do not reach each other, bridged by one
	## teammate block.
	var solver: TerritorySolver = _solver()
	var circles: Array[InfluenceCircle] = [
		_home(-8.0, 0.0, 0, 0), _home(8.0, 0.0, 0, 1), _block(0.0, 0.0, 6.0, 0, 0)
	]
	assert_false(circles[0].overlaps(circles[1]), "The two homes do not touch.")
	var groups: TerritoryGroups = solver.solve(circles)
	assert_eq(groups.group_count(), 1, "Teammates merge into one territory.")
	assert_eq(groups.team_of(0), 0)
	assert_eq(groups.circles_of(0).size(), 3)


func test_different_teams_never_merge_even_when_overlapping() -> void:
	var solver: TerritorySolver = _solver()
	var circles: Array[InfluenceCircle] = [_home(-4.0, 0.0, 0), _home(4.0, 0.0, 1)]
	assert_true(circles[0].overlaps(circles[1]), "These circles do overlap.")
	var groups: TerritoryGroups = solver.solve(circles)
	assert_eq(groups.group_count(), 2, "Overlap across teams is contest, not merge.")
	assert_ne(groups.team_of(0), groups.team_of(1))


func test_an_enemy_block_does_not_bridge_two_of_my_towers() -> void:
	var solver: TerritorySolver = _solver()
	var circles: Array[InfluenceCircle] = [
		_home(-10.0, 0.0, 0), _block(0.0, 0.0, 6.0, 1), _block(10.0, 0.0, 3.0, 0)
	]
	var groups: TerritoryGroups = solver.solve(circles)
	assert_false(solver.is_circle_connected(2), "Team 0's far block is still cut off.")
	assert_eq(groups.group_count(), 1, "The enemy block has no home of its own.")


func test_groups_of_team_lists_every_group_a_team_holds() -> void:
	var solver: TerritorySolver = _solver()
	var circles: Array[InfluenceCircle] = [
		_home(-30.0, 0.0, 0, 0), _home(30.0, 0.0, 0, 1), _home(0.0, 30.0, 1, 2)
	]
	var groups: TerritoryGroups = solver.solve(circles)
	assert_eq(groups.group_count(), 3)
	assert_eq(groups.groups_of_team(0).size(), 2, "One team, two disconnected groups.")
	assert_eq(groups.groups_of_team(1).size(), 1)
	assert_eq(groups.groups_of_team(7).size(), 0)


## -- Output shape ------------------------------------------------------------

func test_circle_indices_are_ascending_and_index_the_input() -> void:
	var solver: TerritorySolver = _solver()
	var circles: Array[InfluenceCircle] = [
		_block(9.0, 0.0, 3.0, 0), _block(4.0, 0.0, 2.0, 0), _home(0.0, 0.0, 0)
	]
	var groups: TerritoryGroups = solver.solve(circles)
	var members: PackedInt32Array = groups.circles_of(0)
	assert_eq(members, PackedInt32Array([0, 1, 2]))
	for member: int in members:
		assert_eq(circles[member].team_id, groups.team_of(0))


func test_solving_again_replaces_the_previous_answer() -> void:
	var solver: TerritorySolver = _solver()
	var first: Array[InfluenceCircle] = [_home(0.0, 0.0, 0), _block(5.0, 0.0, 2.0, 0)]
	solver.solve(first)
	assert_true(solver.is_circle_connected(1))
	var second: Array[InfluenceCircle] = [_home(0.0, 0.0, 0)]
	solver.solve(second)
	assert_eq(solver.group_of_circle(1), TerritoryGroups.NO_GROUP,
		"Stale state from the previous solve must not leak through.")


func test_an_empty_input_solves_to_nothing() -> void:
	var solver: TerritorySolver = _solver()
	var circles: Array[InfluenceCircle] = []
	assert_eq(solver.solve(circles).group_count(), 0)


## -- max_circles safety valve ------------------------------------------------

func test_max_circles_keeps_the_homes_and_the_largest_blocks() -> void:
	var tuning: TerritoryTuning = _tuning.duplicate() as TerritoryTuning
	tuning.max_circles = 3
	var solver: TerritorySolver = _solver(tuning)
	var circles: Array[InfluenceCircle] = [
		_home(0.0, 0.0, 0),
		_block(1.0, 0.0, 1.0, 0),
		_block(1.0, 0.0, 5.0, 0),
		_block(1.0, 0.0, 2.0, 0),
		_block(1.0, 0.0, 4.0, 0),
	]
	var groups: TerritoryGroups = solver.solve(circles)
	assert_eq(groups.group_count(), 1)
	assert_eq(groups.circles_of(0), PackedInt32Array([0, 2, 4]),
		"The home plus the two widest blocks survive the cap.")


func test_max_circles_shares_the_budget_between_teams() -> void:
	var tuning: TerritoryTuning = _tuning.duplicate() as TerritoryTuning
	tuning.max_circles = 4
	var solver: TerritorySolver = _solver(tuning)
	var circles: Array[InfluenceCircle] = [
		_home(-10.0, 0.0, 0),
		_home(10.0, 0.0, 1),
		_block(-9.0, 0.0, 9.0, 0),
		_block(-9.0, 0.0, 8.0, 0),
		_block(9.0, 0.0, 1.0, 1),
		_block(9.0, 0.0, 0.5, 1),
	]
	solver.solve(circles)
	assert_true(solver.is_circle_connected(2), "Team 0 keeps its widest block.")
	assert_true(solver.is_circle_connected(4),
		"Team 1 keeps one too, even though both of its blocks are smaller.")
	assert_false(solver.is_circle_connected(3))
	assert_false(solver.is_circle_connected(5))


## -- The spatial hash has to actually help -----------------------------------

func test_the_spatial_hash_does_not_degenerate_into_all_pairs() -> void:
	var solver: TerritorySolver = _solver()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 424242
	var circles: Array[InfluenceCircle] = []
	for i: int in range(200):
		var angle: float = rng.randf() * TAU
		var distance: float = sqrt(rng.randf()) * (MAP_RADIUS - 3.0)
		circles.append(_block(cos(angle) * distance, sin(angle) * distance, 2.0, i % 4))
	solver.solve(circles)
	var all_pairs: int = 200 * 199 / 2
	assert_lt(solver.last_pair_count(), all_pairs / 4,
		"200 small circles spread over the disk must not cost all-pairs (%d)." % all_pairs)
	assert_gt(solver.last_pair_count(), 0, "It must still find neighbours.")


func test_six_hundred_circles_solve_without_blowing_up() -> void:
	## The host solves at TerritoryTuning.solve_hz (10 Hz). ~600 circles is the
	## far end of a full 8-player match. No hard threshold here; the number is
	## printed and tests/bench/bench_territory.tscn holds the real budget.
	var solver: TerritorySolver = _solver()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 991
	var circles: Array[InfluenceCircle] = []
	for slot: int in range(8):
		var angle: float = TAU * float(slot) / 8.0
		circles.append(
			_home(cos(angle) * MAP_RADIUS * 0.85, sin(angle) * MAP_RADIUS * 0.85, slot, slot)
		)
	for i: int in range(600):
		var angle: float = rng.randf() * TAU
		var distance: float = sqrt(rng.randf()) * (MAP_RADIUS - 2.0)
		var height: float = rng.randf() * 12.0
		circles.append(_block(
			cos(angle) * distance,
			sin(angle) * distance,
			InfluenceCircle.radius_for_height(height, _tuning, MAP_RADIUS),
			i % 8
		))

	var started: int = Time.get_ticks_usec()
	var groups: TerritoryGroups = solver.solve(circles)
	var elapsed_ms: float = float(Time.get_ticks_usec() - started) / 1000.0

	gut.p("600-circle solve: %.2f ms, %d groups, %d candidate pairs"
		% [elapsed_ms, groups.group_count(), solver.last_pair_count()])
	assert_gt(groups.group_count(), 0, "Eight homes must produce at least one group.")
	assert_lt(solver.last_pair_count(), circles.size() * circles.size(),
		"The hash must stay below all-pairs even at this density.")
