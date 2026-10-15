extends GutTest
## core/rules/TeamAssigner.gd (Bontago-1pi.53): resolves per-seat lobby team picks
## (1..cap explicit, 0 = Random) into dense team ids at match start. Pure, so
## every test here is plain data in, data out.

const SEEDS: int = 40


func _picks(values: Array[int]) -> PackedInt32Array:
	return PackedInt32Array(values)


func _arr(values: Array[int]) -> Array[int]:
	return values


## Seats per dense team id.
func _sizes(result: TeamAssigner.Result) -> Array[int]:
	var sizes: Array[int] = []
	sizes.resize(result.team_numbers.size())
	sizes.fill(0)
	for team_id: int in result.team_ids:
		sizes[team_id] += 1
	return sizes


## The invariants every Result must hold: dense ids, ascending numbers, no empty team.
func _assert_well_formed(result: TeamAssigner.Result, cap: int, label: String) -> void:
	var count: int = result.team_numbers.size()
	var previous: int = 0
	for number: int in result.team_numbers:
		assert_gt(number, previous, "%s: numbers strictly ascending" % label)
		assert_between(number, 1, cap, "%s: number within 1..cap" % label)
		previous = number
	var used: Array[int] = []
	used.resize(count)
	used.fill(0)
	for team_id: int in result.team_ids:
		assert_between(team_id, 0, count - 1, "%s: id dense" % label)
		if team_id >= 0 and team_id < count:
			used[team_id] += 1
	assert_false(used.has(0), "%s: every team has a seat" % label)


# --- next_pick ---------------------------------------------------------------

func test_next_pick_cycles_numbers_then_random_then_wraps() -> void:
	for cap: int in [2, 3, 4]:
		var expected: Array[int] = []
		for number: int in range(1, cap + 1):
			expected.append(number)
		expected.append(MatchConfig.TEAM_PICK_RANDOM)
		var current: int = 1
		for step: int in range(expected.size()):
			assert_eq(current, expected[step], "cap %d, step %d" % [cap, step])
			current = TeamAssigner.next_pick(current, cap)
		assert_eq(current, 1, "cap %d: wrapped back to 1 after Random" % cap)


# --- default_picks -----------------------------------------------------------

# --- resolve: explicit picks -------------------------------------------------

func test_numbers_compact_to_dense_ids_but_keep_their_labels() -> void:
	var result: TeamAssigner.Result = TeamAssigner.resolve(_picks([4, 2, 4, 2]), 4, 7)
	assert_eq(result.team_ids, _picks([1, 0, 1, 0]), "number 2 -> id 0, number 4 -> id 1")
	assert_eq(result.team_numbers, _picks([2, 4]), "the labels remember the lobby numbers")
	var gap: TeamAssigner.Result = TeamAssigner.resolve(_picks([1, 3, 3, 1, 4]), 4, 7)
	assert_eq(gap.team_numbers, _picks([1, 3, 4]))
	assert_eq(gap.team_ids, _picks([0, 1, 1, 0, 2]))


# --- resolve: Random ---------------------------------------------------------

func test_eight_random_players_split_four_v_four() -> void:
	for rng_seed: int in range(SEEDS):
		var result: TeamAssigner.Result = TeamAssigner.resolve(PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0]), 4, rng_seed)
		assert_eq(_sizes(result), _arr([4, 4]), "seed %d" % rng_seed)


func test_random_seats_join_the_emptier_team() -> void:
	for rng_seed: int in range(SEEDS):
		var result: TeamAssigner.Result = TeamAssigner.resolve(_picks([1, 1, 0, 0]), 4, rng_seed)
		assert_eq(result.team_ids, _picks([0, 0, 1, 1]), "seed %d: team 2 is empty so both Randoms go there" % rng_seed)
		assert_eq(result.team_numbers, _picks([1, 2]))
		var one_random: TeamAssigner.Result = TeamAssigner.resolve(_picks([1, 1, 1, 0]), 4, rng_seed)
		assert_eq(one_random.team_ids, _picks([0, 0, 0, 1]), "seed %d: a lone Random never joins the full team" % rng_seed)


func test_a_high_explicit_number_widens_the_random_pool() -> void:
	# K = highest explicit number (3): the two Randoms fill the empty teams 1 and 2.
	var seen_orders: Dictionary = {}
	for rng_seed: int in range(SEEDS):
		var result: TeamAssigner.Result = TeamAssigner.resolve(_picks([3, 0, 0]), 4, rng_seed)
		_assert_well_formed(result, 4, "seed %d" % rng_seed)
		assert_eq(result.team_numbers, _picks([1, 2, 3]), "seed %d" % rng_seed)
		assert_eq(result.team_ids[0], 2, "the explicit seat stays on team 3")
		assert_ne(result.team_ids[1], result.team_ids[2], "seed %d: the Randoms land on different teams" % rng_seed)
		seen_orders[result.team_ids[1]] = true
	assert_eq(seen_orders.size(), 2, "the tie-break depends on the seed (both orders occur)")


# --- resolve: determinism and purity ----------------------------------------

func test_the_same_picks_and_seed_always_give_the_same_teams() -> void:
	var picks: PackedInt32Array = _picks([0, 3, 0, 0, 1, 0, 0])
	for rng_seed: int in [0, 1, 99, 123456789, -1, -987654321]:
		var first: TeamAssigner.Result = TeamAssigner.resolve(picks, 4, rng_seed)
		var second: TeamAssigner.Result = TeamAssigner.resolve(picks, 4, rng_seed)
		assert_eq(first.team_ids, second.team_ids, "seed %d" % rng_seed)
		assert_eq(first.team_numbers, second.team_numbers, "seed %d" % rng_seed)


# --- resolve: edge cases -----------------------------------------------------

# --- blocker -----------------------------------------------------------------

func test_blocker_names_the_reason_when_everyone_is_on_one_team() -> void:
	for picks: PackedInt32Array in [_picks([1, 1]), _picks([1, 1, 1, 1]), _picks([2, 2, 2]), _picks([4, 4]), _picks([3, 3, 3, 3, 3, 3, 3, 3])]:
		assert_eq(TeamAssigner.blocker(picks, 4), TeamAssigner.BLOCKER_ONE_TEAM, str(picks))
	assert_ne(TeamAssigner.BLOCKER_ONE_TEAM, "")


# --- the hand-off to MatchConfig ---------------------------------------------

func test_a_result_written_into_a_config_survives_sanitize_and_drives_the_teams() -> void:
	var picks: PackedInt32Array = _picks([3, 0, 1, 0, 3, 0])
	for rng_seed: int in range(SEEDS):
		var config: MatchConfig = MatchConfig.new()
		config.team_mode = MatchConfig.TeamMode.TEAMS_4
		config.player_count = picks.size()
		var result: TeamAssigner.Result = TeamAssigner.resolve(picks, config.team_pick_cap(), rng_seed)
		config.slot_team_ids = result.team_ids
		config.team_numbers = result.team_numbers
		config.sanitize()
		assert_true(config.teams_resolved(), "seed %d: a resolver result is always sanitize-consistent" % rng_seed)
		assert_eq(config.team_count(), result.team_count())
		for slot: int in range(picks.size()):
			assert_eq(config.team_of_slot(slot), result.team_ids[slot])
			if picks[slot] > 0:
				assert_eq(config.team_number_for(config.team_of_slot(slot)), picks[slot], "label = the picked lobby number")
		var wire: MatchConfig = MatchConfig.from_dict(config.to_dict())
		wire.sanitize()
		assert_eq(wire.slot_team_ids, config.slot_team_ids)
		assert_eq(wire.team_numbers, config.team_numbers)
