extends GutTest
## core/rules/LobbySeats.gd (package P2): the pure lobby seat model.
## Plain data in, data out: seats are a Dictionary, peers are ints, slots are a
## {peer_id: slot} dictionary. No Net, no scene tree.

const NORMAL: int = MatchConfig.AiDifficulty.NORMAL
const HARD: int = MatchConfig.AiDifficulty.HARD
const EASY: int = MatchConfig.AiDifficulty.EASY
const CAP_FOUR: int = 4
const SEED: int = 12345


# --- helpers ------------------------------------------------------------------

func _ints(values: Array[int]) -> Array[int]:
	return values


func _peers(values: Array[int]) -> PackedInt32Array:
	return PackedInt32Array(values)


## A reconciled table: `peers` humans (in that order) then `bots` bots.
func _seats(peers: Array[int], bots: int, cap: int = CAP_FOUR) -> Dictionary:
	return LobbySeats.reconcile({}, _peers(peers), bots, NORMAL, cap)


func _human(peer_id: int) -> int:
	return LobbySeats.human_key(peer_id)


func _bot(ordinal: int) -> int:
	return LobbySeats.bot_key(ordinal)


func _colors(seats: Dictionary) -> Array[int]:
	var colors: Array[int] = []
	for key: int in LobbySeats.seat_keys(seats):
		colors.append(LobbySeats.color_of(seats, key))
	return colors


func _teams(seats: Dictionary) -> Array[int]:
	var picks: Array[int] = []
	for key: int in LobbySeats.seat_keys(seats):
		picks.append(LobbySeats.team_of(seats, key))
	return picks


func _assert_unique_valid_colors(seats: Dictionary, label: String) -> void:
	var seen: Dictionary = {}
	for color: int in _colors(seats):
		assert_between(color, 0, LobbySeats.palette_size() - 1, "%s: colour in the palette" % label)
		assert_false(seen.has(color), "%s: colour %d appears once" % [label, color])
		seen[color] = true


func _team_config(mode: MatchConfig.TeamMode = MatchConfig.TeamMode.TEAMS_4) -> MatchConfig:
	var config: MatchConfig = MatchConfig.new()
	config.team_mode = mode
	return config


func _slots(pairs: Array[Vector2i]) -> Dictionary:
	var slots: Dictionary = {}
	for pair: Vector2i in pairs:
		slots[pair.x] = pair.y
	return slots


## Puts `key` on `pick`; a seat that already holds it is fine (set_team reports no change).
func _set_team_of(seats: Dictionary, key: int, pick: int) -> void:
	LobbySeats.set_team(seats, key, pick, CAP_FOUR)
	assert_eq(LobbySeats.team_of(seats, key), pick, "team %d on key %d" % [pick, key])


# --- model basics -------------------------------------------------------------

# --- reconcile ----------------------------------------------------------------

func test_reconcile_builds_default_seats_humans_then_bots() -> void:
	var seats: Dictionary = _seats([1, 2, 3], 2)
	assert_eq(LobbySeats.seat_keys(seats), _ints([_human(1), _human(2), _human(3), _bot(0), _bot(1)]),
		"seat order: humans in peer order, then bots")
	assert_eq(_colors(seats), _ints([0, 1, 2, 3, 4]), "lowest free colours, in seat order")
	assert_eq(_teams(seats), _ints([1, 2, 1, 2, 1]), "default picks 1,2,1,2...")
	assert_eq(LobbySeats.difficulty_of(seats, _bot(0)), NORMAL)
	assert_eq(LobbySeats.difficulty_of(seats, _bot(1)), NORMAL)
	assert_eq(LobbySeats.difficulty_of(seats, _human(1)), LobbySeats.UNSET, "a human has no difficulty")
	assert_eq(LobbySeats.human_count(seats), 3)
	assert_eq(LobbySeats.bot_count(seats), 2)


func test_reconcile_keeps_everyones_picks_when_a_peer_joins() -> void:
	var seats: Dictionary = _seats([1, 2, 3], 1)
	assert_true(LobbySeats.set_color(seats, _human(2), 6))
	_set_team_of(seats, _human(3), 4)
	assert_true(LobbySeats.set_difficulty(seats, _bot(0), HARD))
	var after: Dictionary = LobbySeats.reconcile(seats, _peers([1, 2, 3, 4]), 1, NORMAL, CAP_FOUR)
	assert_eq(LobbySeats.color_of(after, _human(1)), 0)
	assert_eq(LobbySeats.color_of(after, _human(2)), 6, "peer 2 keeps its chosen colour")
	assert_eq(LobbySeats.team_of(after, _human(3)), 4, "peer 3 keeps its team")
	assert_eq(LobbySeats.difficulty_of(after, _bot(0)), HARD, "the bot keeps its difficulty")
	assert_eq(LobbySeats.color_of(after, _bot(0)), 3, "the bot keeps its colour")
	assert_eq(LobbySeats.color_of(after, _human(4)), 1,
		"the newcomer takes the lowest free colour (1: peer 2 moved off it)")
	assert_eq(LobbySeats.seat_keys(after), _ints([_human(1), _human(2), _human(3), _human(4), _bot(0)]))
	_assert_unique_valid_colors(after, "after a join")


func test_reconcile_never_exceeds_eight_seats() -> void:
	var seats: Dictionary = _seats([1, 2, 3, 4, 5], 6)
	assert_eq(LobbySeats.human_count(seats), 5)
	assert_eq(LobbySeats.bot_count(seats), 3, "bots are trimmed to the room humans leave")
	assert_eq(LobbySeats.seat_count(seats), MatchConfig.PLAYER_COUNT_MAX)
	_assert_unique_valid_colors(seats, "a full lobby")
	var crowd: Dictionary = _seats([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 2)
	assert_eq(LobbySeats.human_count(crowd), 8, "peers beyond eight are not seated")
	assert_eq(LobbySeats.bot_count(crowd), 0)
	var negative: Dictionary = _seats([1], -4)
	assert_eq(LobbySeats.bot_count(negative), 0, "a negative bot count is none")


func test_reconcile_repairs_duplicate_and_missing_colours() -> void:
	var raw: Dictionary = {
		"humans": [
			{"peer_id": 1, "color": 3, "team": 1},
			{"peer_id": 2, "color": 3, "team": 2},
			{"peer_id": 3, "team": 1},
		],
		"bots": [{"color": 99, "team": 2, "difficulty": 1}],
	}
	var seats: Dictionary = LobbySeats.reconcile(raw, _peers([1, 2, 3]), 1, NORMAL, CAP_FOUR)
	assert_eq(LobbySeats.color_of(seats, _human(1)), 3, "the first seat keeps a contested colour")
	assert_ne(LobbySeats.color_of(seats, _human(2)), 3)
	_assert_unique_valid_colors(seats, "repaired")
	assert_eq(_colors(seats), _ints([3, 0, 1, 2]), "the rest take the lowest free colours in seat order")


# --- colours ------------------------------------------------------------------

func test_set_color_swaps_with_the_seat_that_holds_it() -> void:
	var seats: Dictionary = _seats([1, 2], 1)  # colours 0, 1, 2
	assert_true(LobbySeats.set_color(seats, _human(1), 2))
	assert_eq(_colors(seats), _ints([2, 1, 0]), "the bot's colour 2 and the human's 0 swapped")
	assert_true(LobbySeats.set_color(seats, _human(2), 5))
	assert_eq(_colors(seats), _ints([2, 5, 0]), "a free colour is simply taken")
	_assert_unique_valid_colors(seats, "after swaps")


# --- teams --------------------------------------------------------------------

# --- difficulty and bots ------------------------------------------------------

# --- a client edits its own seat ----------------------------------------------

# --- slots --------------------------------------------------------------------

func test_layout_gives_humans_their_slots_and_bots_the_trailing_slots() -> void:
	var seats: Dictionary = _seats([10, 20, 30], 2)
	var plan: LobbySeats.Layout = LobbySeats.layout(seats, _slots([Vector2i(10, 0), Vector2i(20, 1), Vector2i(30, 2)]))
	assert_true(plan.is_valid())
	assert_eq(plan.player_count, 5)
	assert_eq(plan.ai_count, 2)
	assert_eq(plan.slot_keys, _ints([_human(10), _human(20), _human(30), _bot(0), _bot(1)]))
	assert_eq(plan.slot_of(_human(30)), 2)
	assert_eq(plan.slot_of(_bot(1)), 4)
	assert_eq(plan.slot_of(LobbySeats.KEY_NONE), -1)
	assert_eq(plan.slot_of(_human(99)), -1)


# --- start blocker ------------------------------------------------------------

func test_start_blocker_is_green_exactly_when_flatten_succeeds() -> void:
	var cases: Array[Dictionary] = [
		{"peers": [1, 2], "bots": 0, "picks": [1, 1], "slots": {1: 0, 2: 1}},
		{"peers": [1, 2], "bots": 0, "picks": [1, 2], "slots": {1: 0, 2: 1}},
		{"peers": [1, 2], "bots": 2, "picks": [1, 1, 1, 1], "slots": {1: 0, 2: 1}},
		{"peers": [1, 2], "bots": 1, "picks": [1, 2, 1], "slots": {1: 0, 2: 4}},
		{"peers": [1, 2], "bots": 1, "picks": [2, 2, 0], "slots": {1: 0, 2: 1}},
	]
	for scenario: Dictionary in cases:
		var peers: Array[int] = []
		for peer: int in scenario["peers"] as Array:
			peers.append(peer)
		var seats: Dictionary = _seats(peers, int(scenario["bots"]))
		var keys: Array[int] = LobbySeats.seat_keys(seats)
		var picks: Array = scenario["picks"]
		for index: int in range(keys.size()):
			_set_team_of(seats, keys[index], int(picks[index]))
		var slots: Dictionary = scenario["slots"]
		var config: MatchConfig = _team_config()
		var reason: String = LobbySeats.start_blocker(seats, slots, config.team_pick_cap())
		var flatten_reason: String = LobbySeats.flatten_to_config(seats, slots, config, SEED)
		assert_eq(flatten_reason, reason, "flatten and the blocker agree for %s" % str(scenario))


# --- flatten_to_config --------------------------------------------------------

func test_flatten_resolves_teams_into_arrays_sized_to_the_final_player_count() -> void:
	var seats: Dictionary = _seats([10, 20, 30], 2)  # picks 1,2,1,2,1
	_set_team_of(seats, _human(30), 3)
	var config: MatchConfig = _team_config()
	var slots: Dictionary = _slots([Vector2i(10, 0), Vector2i(20, 1), Vector2i(30, 2)])
	assert_eq(LobbySeats.flatten_to_config(seats, slots, config, SEED), "")
	assert_eq(config.slot_team_ids.size(), config.player_count, "one id per slot")
	assert_eq(config.slot_team_ids, PackedInt32Array([0, 1, 2, 1, 0]), "picks 1,2,3,2,1 -> dense ids")
	assert_eq(config.team_numbers, PackedInt32Array([1, 2, 3]))
	assert_true(config.teams_resolved())
	assert_eq(config.team_count(), 3)
	assert_eq(config.team_of_slot(2), 2)
	assert_eq(config.team_number_for(2), 3)
	# F1 (P1 review): the resolved arrays must survive the host's sanitize() ...
	config.sanitize()
	assert_true(config.teams_resolved(), "sanitize keeps the team arrays")
	assert_eq(config.slot_team_ids, PackedInt32Array([0, 1, 2, 1, 0]))
	assert_eq(config.slot_ai_difficulties.size(), 5)
	# ... and re-applying the connected-peer clamp for the seated humans is a no-op.
	var player_count: int = config.player_count
	var ai_count: int = config.ai_count
	config.clamp_to_connected_peers(3)
	assert_eq(config.player_count, player_count, "clamp_to_connected_peers changes nothing after flatten")
	assert_eq(config.ai_count, ai_count)
	config.sanitize()
	assert_true(config.teams_resolved(), "still resolved after the clamp and a second sanitize")


func test_flatten_blocks_a_single_team_and_leaves_the_config_untouched() -> void:
	var seats: Dictionary = _seats([1, 2, 3], 1)
	for key: int in LobbySeats.seat_keys(seats):
		_set_team_of(seats, key, 2)
	var config: MatchConfig = _team_config()
	config.player_count = 6
	config.ai_count = 3
	config.slot_team_ids = PackedInt32Array([0, 1, 0, 1, 0, 1])
	config.team_numbers = PackedInt32Array([1, 2])
	var before: String = JSON.stringify(config.to_dict())
	var reason: String = LobbySeats.flatten_to_config(seats, {}, config, SEED)
	assert_eq(reason, TeamAssigner.BLOCKER_ONE_TEAM, "F4: a one-team start is refused")
	assert_eq(JSON.stringify(config.to_dict()), before, "a refused flatten does not touch the config")


# --- wire budget --------------------------------------------------------------
