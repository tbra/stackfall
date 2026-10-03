class_name TeamAssigner
extends RefCounted
## Pure team resolution for the lobby rework (Bontago-1pi.53, docs/LOBBY_REWORK_PLAN.md
## section 3). Every seat carries a team pick: 1..cap = an explicit lobby team
## number (same number = same team) or MatchConfig.TEAM_PICK_RANDOM. At match
## start the host turns the per-slot picks into dense team ids (0..n-1, what
## every downstream loop over range(team_count()) needs) plus the lobby number
## each id was, so "Team 3 wins" still matches what the lobby showed.
##
## No scene tree, no global RNG: Random seats are resolved from a seed the
## caller supplies (MatchConfig.rng_seed, or a host randi() when that is -1), so
## the same picks and seed always give the same teams and a test can pin them.
##
## DECISION (owner question 2 of the plan, recommendation taken): Random is a
## BALANCED FILL. K = clampi(max(2, highest explicit number), 2, cap); the Random
## seats, in a seeded shuffled order, each join the least-populated team of
## 1..K (ties broken by the seed). All-Random therefore gives an even split
## (4 players -> 2v2, 8 -> 4v4) and Random never builds a team nobody chose
## beyond K. The alternative (each Random seat drawing uniformly from 1..cap)
## can produce one team or all singles.

## Both the floor of K and the length of the default 1,2,1,2... seeding.
const DEFAULT_TEAM_COUNT: int = 2
## Shown by the lobby (Start disabled) when teams are on and no two seats differ.
const BLOCKER_ONE_TEAM: String = "Everyone is on the same team. Choose at least two different team numbers (or Random)."


## Outcome of resolve(): `team_ids[slot]` is the dense team id of that slot
## (0..team_numbers.size()-1, each used at least once); `team_numbers[id]` is the
## lobby number (1..cap) that team was.
class Result:
	extends RefCounted
	var team_ids: PackedInt32Array = PackedInt32Array()
	var team_numbers: PackedInt32Array = PackedInt32Array()

	func team_count() -> int:
		return team_numbers.size()


## Resolves per-slot picks into dense team ids.
## `picks`: one entry per slot (humans and bots alike): 1..cap explicit,
## MatchConfig.TEAM_PICK_RANDOM (0) or any negative value = Random; a number above
## `cap` is clamped to `cap`. `cap`: MatchConfig.team_pick_cap() (2..4), or <= 0
## when teams are off, which resolves to free-for-all (every slot its own team,
## numbers 1..n, exactly what MatchConfig does for TeamMode.OFF).
## `rng_seed`: used as is, a negative seed is a valid deterministic seed (the
## caller substitutes a host randi() for MatchConfig.rng_seed == -1).
static func resolve(picks: PackedInt32Array, cap: int, rng_seed: int) -> Result:
	var result: Result = Result.new()
	var seat_count: int = picks.size()
	if seat_count == 0:
		return result
	if cap <= 0:
		for slot: int in range(seat_count):
			result.team_ids.append(slot)
			result.team_numbers.append(slot + 1)
		return result
	cap = mini(cap, MatchConfig.TEAM_PICK_MAX)

	# Explicit picks first: they fix K and the starting populations.
	var assigned: PackedInt32Array = PackedInt32Array()
	assigned.resize(seat_count)
	var random_seats: Array[int] = []
	var highest: int = 0
	for slot: int in range(seat_count):
		var pick: int = picks[slot]
		if pick >= 1:
			assigned[slot] = mini(pick, cap)
			highest = maxi(highest, assigned[slot])
		else:
			assigned[slot] = MatchConfig.TEAM_PICK_RANDOM
			random_seats.append(slot)
	var fill_count: int = mini(maxi(DEFAULT_TEAM_COUNT, highest), cap)

	# population[n] = seats on lobby team n so far (index 0 unused).
	var population: PackedInt32Array = PackedInt32Array()
	population.resize(cap + 1)
	for slot: int in range(seat_count):
		if assigned[slot] != MatchConfig.TEAM_PICK_RANDOM:
			population[assigned[slot]] += 1

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = rng_seed
	# Seeded Fisher-Yates over the Random seats (Array.shuffle() uses the global RNG).
	for i: int in range(random_seats.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: int = random_seats[i]
		random_seats[i] = random_seats[j]
		random_seats[j] = swap
	for slot: int in random_seats:
		var lowest: int = population[1]
		for number: int in range(2, fill_count + 1):
			lowest = mini(lowest, population[number])
		var candidates: Array[int] = []
		for number: int in range(1, fill_count + 1):
			if population[number] == lowest:
				candidates.append(number)
		var chosen: int = candidates[rng.randi_range(0, candidates.size() - 1)]
		assigned[slot] = chosen
		population[chosen] += 1

	# Compact the numbers in use, ascending, to dense ids.
	var used: Array[int] = []
	for number: int in range(1, cap + 1):
		if population[number] > 0:
			used.append(number)
	for slot: int in range(seat_count):
		result.team_ids.append(used.find(assigned[slot]))
	for number: int in used:
		result.team_numbers.append(number)
	return result


## "" when the picks may start a match, else the reason (BLOCKER_ONE_TEAM) the
## host's Start must be disabled with: teams are on and everything lands on one
## team. With teams off (cap <= 0) or fewer than two seats nothing blocks. A Random
## seat never blocks: resolve() always puts the first Random seat on an empty team
## when one exists (K >= 2), so any Random pick yields at least two teams.
static func blocker(picks: PackedInt32Array, cap: int) -> String:
	if cap <= 0 or picks.size() < DEFAULT_TEAM_COUNT:
		return ""
	# The seed is irrelevant: the number of teams does not depend on tie-breaks.
	if resolve(picks, cap, 0).team_count() < DEFAULT_TEAM_COUNT:
		return BLOCKER_ONE_TEAM
	return ""


## The next pick when a seat's team button is clicked: 1 > 2 > ... > cap > Random
## > 1 (backwards reverses). `current` outside 0..cap is clamped into it first
## (a pick kept from a wider lobby, then the cap shrank). cap <= 0 (teams off)
## has nothing to cycle and returns Random.
static func next_pick(current: int, cap: int, backwards: bool = false) -> int:
	if cap <= 0:
		return MatchConfig.TEAM_PICK_RANDOM
	var from_pick: int = clampi(current, MatchConfig.TEAM_PICK_RANDOM, cap)
	# The ring is Random (0) then 1..cap: size cap + 1, index == pick.
	var step: int = -1 if backwards else 1
	return posmod(from_pick + step, cap + 1)


## The starting picks 1,2,1,2... for `seat_count` seats (what switching Teams on seeds).
static func default_picks(seat_count: int) -> PackedInt32Array:
	var picks: PackedInt32Array = PackedInt32Array()
	for slot: int in range(maxi(seat_count, 0)):
		picks.append(slot % DEFAULT_TEAM_COUNT + 1)
	return picks
