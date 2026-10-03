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


func test_next_pick_backwards_reverses_the_cycle() -> void:
	for cap: int in [2, 3, 4]:
		assert_eq(TeamAssigner.next_pick(1, cap, true), MatchConfig.TEAM_PICK_RANDOM, "cap %d: 1 back to Random" % cap)
		assert_eq(TeamAssigner.next_pick(MatchConfig.TEAM_PICK_RANDOM, cap, true), cap, "cap %d: Random back to cap" % cap)
		assert_eq(TeamAssigner.next_pick(cap, cap, true), cap - 1, "cap %d" % cap)
		# Forward then backward is the identity everywhere on the ring.
		for pick: int in range(0, cap + 1):
			assert_eq(TeamAssigner.next_pick(TeamAssigner.next_pick(pick, cap), cap, true), pick, "cap %d pick %d" % [cap, pick])


func test_next_pick_clamps_a_pick_from_a_wider_lobby() -> void:
	assert_eq(TeamAssigner.next_pick(4, 2), MatchConfig.TEAM_PICK_RANDOM, "4 counts as the cap (2) when the cap shrank")
	assert_eq(TeamAssigner.next_pick(4, 2, true), 1)
	assert_eq(TeamAssigner.next_pick(-3, 3), 1, "a negative pick counts as Random")
	assert_eq(TeamAssigner.next_pick(1, 0), MatchConfig.TEAM_PICK_RANDOM, "teams off: nothing to cycle")


# --- default_picks -----------------------------------------------------------

func test_default_picks_alternate_one_two() -> void:
	assert_eq(TeamAssigner.default_picks(0), PackedInt32Array())
	assert_eq(TeamAssigner.default_picks(1), _picks([1]))
	assert_eq(TeamAssigner.default_picks(5), _picks([1, 2, 1, 2, 1]))
	assert_eq(TeamAssigner.default_picks(8), _picks([1, 2, 1, 2, 1, 2, 1, 2]))
	assert_eq(TeamAssigner.default_picks(-2), PackedInt32Array())


func test_default_picks_resolve_to_two_teams_and_never_block() -> void:
	for seats: int in range(MatchConfig.PLAYER_COUNT_MIN, MatchConfig.PLAYER_COUNT_MAX + 1):
		var picks: PackedInt32Array = TeamAssigner.default_picks(seats)
		assert_eq(TeamAssigner.blocker(picks, 4), "", "%d seats" % seats)
		var result: TeamAssigner.Result = TeamAssigner.resolve(picks, 4, 1)
		assert_eq(result.team_numbers, _picks([1, 2]), "%d seats" % seats)
		for slot: int in range(seats):
			assert_eq(result.team_ids[slot], slot % 2, "%d seats: the legacy interleave" % seats)


# --- resolve: explicit picks -------------------------------------------------

func test_explicit_picks_are_kept() -> void:
	var result: TeamAssigner.Result = TeamAssigner.resolve(_picks([1, 2, 1, 2]), 4, 7)
	assert_eq(result.team_ids, _picks([0, 1, 0, 1]))
	assert_eq(result.team_numbers, _picks([1, 2]))
	assert_eq(result.team_count(), 2)


func test_unbalanced_explicit_teams_are_allowed() -> void:
	var result: TeamAssigner.Result = TeamAssigner.resolve(_picks([1, 1, 1, 2]), 4, 7)
	assert_eq(result.team_ids, _picks([0, 0, 0, 1]), "3v1 is the owner's 'same number = same team'")
	assert_eq(result.team_numbers, _picks([1, 2]))


func test_four_single_player_teams() -> void:
	var result: TeamAssigner.Result = TeamAssigner.resolve(_picks([1, 2, 3, 4]), 4, 7)
	assert_eq(result.team_ids, _picks([0, 1, 2, 3]))
	assert_eq(result.team_numbers, _picks([1, 2, 3, 4]))


func test_numbers_compact_to_dense_ids_but_keep_their_labels() -> void:
	var result: TeamAssigner.Result = TeamAssigner.resolve(_picks([4, 2, 4, 2]), 4, 7)
	assert_eq(result.team_ids, _picks([1, 0, 1, 0]), "number 2 -> id 0, number 4 -> id 1")
	assert_eq(result.team_numbers, _picks([2, 4]), "the labels remember the lobby numbers")
	var gap: TeamAssigner.Result = TeamAssigner.resolve(_picks([1, 3, 3, 1, 4]), 4, 7)
	assert_eq(gap.team_numbers, _picks([1, 3, 4]))
	assert_eq(gap.team_ids, _picks([0, 1, 1, 0, 2]))


func test_a_pick_above_the_cap_is_clamped_to_the_cap() -> void:
	var result: TeamAssigner.Result = TeamAssigner.resolve(_picks([4, 4, 1]), 2, 7)
	assert_eq(result.team_numbers, _picks([1, 2]))
	assert_eq(result.team_ids, _picks([1, 1, 0]))
	var over_max: TeamAssigner.Result = TeamAssigner.resolve(_picks([9, 1]), 9, 7)
	assert_eq(over_max.team_numbers, _picks([1, 4]), "a cap above TEAM_PICK_MAX is treated as TEAM_PICK_MAX")


# --- resolve: Random ---------------------------------------------------------

func test_all_random_is_balanced_across_two_teams() -> void:
	for seats: int in range(MatchConfig.PLAYER_COUNT_MIN, MatchConfig.PLAYER_COUNT_MAX + 1):
		var picks: PackedInt32Array = PackedInt32Array()
		picks.resize(seats)  # all 0 = Random
		for rng_seed: int in range(SEEDS):
			var result: TeamAssigner.Result = TeamAssigner.resolve(picks, 4, rng_seed)
			_assert_well_formed(result, 4, "%d seats seed %d" % [seats, rng_seed])
			assert_eq(result.team_numbers, _picks([1, 2]), "all-Random fills teams 1..2 (K = 2): %d seats" % seats)
			var sizes: Array[int] = _sizes(result)
			assert_eq(sizes[0] + sizes[1], seats)
			assert_lte(absi(sizes[0] - sizes[1]), 1, "%d seats seed %d: sizes %s" % [seats, rng_seed, str(sizes)])


func test_four_random_players_always_split_two_v_two() -> void:
	for rng_seed: int in range(SEEDS):
		var result: TeamAssigner.Result = TeamAssigner.resolve(_picks([0, 0, 0, 0]), 4, rng_seed)
		assert_eq(_sizes(result), _arr([2, 2]), "seed %d" % rng_seed)


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


func test_a_random_never_widens_beyond_the_highest_explicit_number() -> void:
	for rng_seed: int in range(SEEDS):
		var result: TeamAssigner.Result = TeamAssigner.resolve(_picks([2, 2, 2, 0, 0, 0]), 4, rng_seed)
		assert_between(result.team_numbers[result.team_numbers.size() - 1], 1, 2, "K = 2: no team 3 or 4 appears")
		assert_eq(result.team_numbers, _picks([1, 2]))


func test_more_randoms_than_teams_stay_balanced() -> void:
	# One explicit seat on every team 1..4, then seven Randoms: sizes end 2,2,2,2 minus one.
	for rng_seed: int in range(SEEDS):
		var result: TeamAssigner.Result = TeamAssigner.resolve(_picks([1, 2, 3, 4, 0, 0, 0]), 4, rng_seed)
		_assert_well_formed(result, 4, "seed %d" % rng_seed)
		var sizes: Array[int] = _sizes(result)
		assert_eq(sizes.size(), 4)
		var total: int = 0
		var largest: int = 0
		var smallest: int = MatchConfig.PLAYER_COUNT_MAX
		for size: int in sizes:
			total += size
			largest = maxi(largest, size)
			smallest = mini(smallest, size)
		assert_eq(total, 7)
		assert_lte(largest - smallest, 1, "seed %d: sizes %s" % [rng_seed, str(sizes)])
		for slot: int in range(4):
			assert_eq(result.team_numbers[result.team_ids[slot]], slot + 1, "explicit seats keep their numbers")
	for rng_seed: int in range(SEEDS):
		var six: TeamAssigner.Result = TeamAssigner.resolve(PackedInt32Array([0, 0, 0, 0, 0, 0]), 4, rng_seed)
		assert_eq(_sizes(six), _arr([3, 3]), "6 Randoms, K = 2: 3v3 (seed %d)" % rng_seed)


func test_a_random_can_open_a_team_nobody_picked_but_ids_stay_dense() -> void:
	# [4,4,Random]: K = 4, teams 1..3 are all empty, so the Random takes one of them.
	var seen: Dictionary = {}
	for rng_seed: int in range(SEEDS):
		var result: TeamAssigner.Result = TeamAssigner.resolve(_picks([4, 4, 0]), 4, rng_seed)
		_assert_well_formed(result, 4, "seed %d" % rng_seed)
		assert_eq(result.team_count(), 2)
		assert_eq(result.team_numbers[1], 4)
		assert_between(result.team_numbers[0], 1, 3)
		assert_eq(result.team_ids, _picks([1, 1, 0]))
		seen[result.team_numbers[0]] = true
	assert_gt(seen.size(), 1, "the seed picks among the empty teams")


func test_negative_picks_count_as_random() -> void:
	for rng_seed: int in range(SEEDS):
		assert_eq(
			TeamAssigner.resolve(_picks([-1, -5, 0, 0]), 4, rng_seed).team_ids,
			TeamAssigner.resolve(_picks([0, 0, 0, 0]), 4, rng_seed).team_ids,
			"seed %d" % rng_seed
		)


func test_every_mix_of_picks_resolves_well_formed() -> void:
	var free_seats: int = 4  # seats whose pick runs through every value 0..cap
	for cap: int in [2, 3, 4]:
		var combos: int = floori(pow(cap + 1, free_seats))
		for combo: int in range(combos):
			var picks: PackedInt32Array = PackedInt32Array()
			for slot: int in range(free_seats):
				picks.append(floori(float(combo) / pow(cap + 1, slot)) % (cap + 1))
			picks.append(MatchConfig.TEAM_PICK_RANDOM)
			picks.append(MatchConfig.TEAM_PICK_RANDOM)
			var result: TeamAssigner.Result = TeamAssigner.resolve(picks, cap, combo)
			_assert_well_formed(result, cap, "cap %d picks %s" % [cap, str(picks)])
			assert_eq(result.team_ids.size(), picks.size())
			for slot: int in range(free_seats):
				if picks[slot] > 0:
					assert_eq(result.team_numbers[result.team_ids[slot]], picks[slot], "explicit pick kept: cap %d %s" % [cap, str(picks)])


# --- resolve: determinism and purity ----------------------------------------

func test_the_same_picks_and_seed_always_give_the_same_teams() -> void:
	var picks: PackedInt32Array = _picks([0, 3, 0, 0, 1, 0, 0])
	for rng_seed: int in [0, 1, 99, 123456789, -1, -987654321]:
		var first: TeamAssigner.Result = TeamAssigner.resolve(picks, 4, rng_seed)
		var second: TeamAssigner.Result = TeamAssigner.resolve(picks, 4, rng_seed)
		assert_eq(first.team_ids, second.team_ids, "seed %d" % rng_seed)
		assert_eq(first.team_numbers, second.team_numbers, "seed %d" % rng_seed)


func test_different_seeds_can_resolve_randoms_differently() -> void:
	var partitions: Dictionary = {}
	for rng_seed: int in range(SEEDS):
		var result: TeamAssigner.Result = TeamAssigner.resolve(_picks([0, 0, 0, 0]), 4, rng_seed)
		partitions[str(result.team_ids)] = true
	assert_gt(partitions.size(), 1, "the seed matters: more than one 2v2 split shows up over %d seeds" % SEEDS)


func test_resolve_leaves_the_global_rng_alone() -> void:
	seed(4242)
	var expected: int = randi()
	seed(4242)
	TeamAssigner.resolve(_picks([0, 0, 0, 0, 0]), 4, 11)
	assert_eq(randi(), expected, "resolve() draws only from its own seeded generator")


func test_resolve_does_not_modify_its_input() -> void:
	var picks: PackedInt32Array = _picks([0, 5, 0, 9])
	var copy: PackedInt32Array = picks.duplicate()
	TeamAssigner.resolve(picks, 3, 5)
	assert_eq(picks, copy)


# --- resolve: edge cases -----------------------------------------------------

func test_teams_off_is_free_for_all() -> void:
	var result: TeamAssigner.Result = TeamAssigner.resolve(_picks([1, 1, 0, 2]), 0, 3)
	assert_eq(result.team_ids, _picks([0, 1, 2, 3]), "one team per slot, like TeamMode.OFF")
	assert_eq(result.team_numbers, _picks([1, 2, 3, 4]))


func test_no_seats_resolve_to_nothing() -> void:
	var result: TeamAssigner.Result = TeamAssigner.resolve(PackedInt32Array(), 4, 3)
	assert_true(result.team_ids.is_empty())
	assert_true(result.team_numbers.is_empty())
	assert_eq(result.team_count(), 0)


func test_a_single_random_seat_resolves_to_one_team() -> void:
	var result: TeamAssigner.Result = TeamAssigner.resolve(_picks([0]), 4, 3)
	_assert_well_formed(result, 4, "single seat")
	assert_eq(result.team_ids, _picks([0]))
	assert_eq(result.team_count(), 1)


# --- blocker -----------------------------------------------------------------

func test_blocker_names_the_reason_when_everyone_is_on_one_team() -> void:
	for picks: PackedInt32Array in [_picks([1, 1]), _picks([1, 1, 1, 1]), _picks([2, 2, 2]), _picks([4, 4]), _picks([3, 3, 3, 3, 3, 3, 3, 3])]:
		assert_eq(TeamAssigner.blocker(picks, 4), TeamAssigner.BLOCKER_ONE_TEAM, str(picks))
	assert_ne(TeamAssigner.BLOCKER_ONE_TEAM, "")


func test_blocker_is_empty_when_the_seats_form_two_teams() -> void:
	for picks: PackedInt32Array in [
		_picks([1, 2]), _picks([1, 1, 2]), _picks([2, 4]), _picks([1, 2, 3, 4]),
		_picks([1, 0]), _picks([0, 0]), _picks([0, 0, 0, 0]), _picks([1, 1, 1, 0]), _picks([4, 0]),
	]:
		assert_eq(TeamAssigner.blocker(picks, 4), "", str(picks))


func test_blocker_ignores_teams_off_and_single_seats() -> void:
	assert_eq(TeamAssigner.blocker(_picks([1, 1, 1]), 0), "", "teams off: nothing to block")
	assert_eq(TeamAssigner.blocker(_picks([1]), 4), "", "fewer than two seats")
	assert_eq(TeamAssigner.blocker(PackedInt32Array(), 4), "")


func test_blocker_respects_the_cap() -> void:
	# Two picks above a 2-team cap clamp to team 2 together: still one team.
	assert_eq(TeamAssigner.blocker(_picks([3, 4]), 2), TeamAssigner.BLOCKER_ONE_TEAM)
	assert_eq(TeamAssigner.blocker(_picks([1, 4]), 2), "")


func test_blocker_agrees_with_resolve_for_every_seed() -> void:
	for picks: PackedInt32Array in [_picks([1, 1, 1]), _picks([1, 1, 0]), _picks([0, 0]), _picks([2, 2])]:
		var blocked: bool = TeamAssigner.blocker(picks, 4) != ""
		for rng_seed: int in range(10):
			assert_eq(TeamAssigner.resolve(picks, 4, rng_seed).team_count() < 2, blocked, "%s seed %d" % [str(picks), rng_seed])


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
