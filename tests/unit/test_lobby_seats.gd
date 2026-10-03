extends GutTest
## core/rules/LobbySeats.gd (Bontago-1pi.53, package P2): the pure lobby seat model.
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

func test_the_palette_has_a_colour_for_every_seat() -> void:
	assert_eq(LobbySeats.palette_size(), MatchConfig.PLAYER_COUNT_MAX,
		"eight seats, eight colours: unique colours can always be honoured")
	assert_eq(LobbySeats.palette_size(), MatchConfig.default_player_colors().size())
	assert_eq(LobbySeats.palette_color(0), MatchConfig.default_player_colors()[0])
	assert_eq(LobbySeats.palette_color(99), MatchConfig.default_player_colors()[LobbySeats.palette_size() - 1],
		"an out-of-range index clamps")


func test_keys_tell_humans_from_bots() -> void:
	assert_eq(_human(7), 7, "a human is keyed by its peer id")
	assert_eq(_bot(0), -1)
	assert_eq(_bot(2), -3)
	assert_true(LobbySeats.is_bot_key(_bot(0)))
	assert_false(LobbySeats.is_bot_key(_human(1)))
	assert_false(LobbySeats.is_bot_key(LobbySeats.KEY_NONE))
	assert_eq(LobbySeats.bot_ordinal(_bot(4)), 4)


func test_empty_is_a_table_with_two_lists() -> void:
	var seats: Dictionary = LobbySeats.empty()
	assert_eq(LobbySeats.seat_count(seats), 0)
	assert_eq(LobbySeats.human_count(seats), 0)
	assert_eq(LobbySeats.bot_count(seats), 0)
	assert_true(seats.has(LobbySeats.KEY_HUMANS))
	assert_true(seats.has(LobbySeats.KEY_BOTS))


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


func test_reconcile_uses_the_given_default_difficulty_for_new_bots() -> void:
	var seats: Dictionary = LobbySeats.reconcile({}, _peers([1]), 2, HARD, CAP_FOUR)
	assert_eq(LobbySeats.difficulty_of(seats, _bot(0)), HARD)
	assert_eq(LobbySeats.difficulty_of(seats, _bot(1)), HARD)
	var clamped: Dictionary = LobbySeats.reconcile({}, _peers([1]), 1, 99, CAP_FOUR)
	assert_eq(LobbySeats.difficulty_of(clamped, _bot(0)), HARD, "an out-of-range default clamps")


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


func test_reconcile_keeps_the_others_picks_when_a_peer_leaves() -> void:
	var seats: Dictionary = _seats([1, 2, 3], 1)
	assert_true(LobbySeats.set_color(seats, _human(3), 7))
	_set_team_of(seats, _human(3), 3)
	var after: Dictionary = LobbySeats.reconcile(seats, _peers([1, 3]), 1, NORMAL, CAP_FOUR)
	assert_eq(LobbySeats.human_count(after), 2)
	assert_false(LobbySeats.has_seat(after, _human(2)), "the leaver's seat is gone")
	assert_eq(LobbySeats.color_of(after, _human(3)), 7)
	assert_eq(LobbySeats.team_of(after, _human(3)), 3)
	assert_eq(LobbySeats.color_of(after, _bot(0)), 3, "the bot is untouched")
	# The leaver's colour (1) is free again: the next newcomer takes it.
	var rejoined: Dictionary = LobbySeats.reconcile(after, _peers([1, 3, 9]), 1, NORMAL, CAP_FOUR)
	assert_eq(LobbySeats.color_of(rejoined, _human(9)), 1)


func test_reconcile_follows_the_peer_order_it_is_given() -> void:
	var seats: Dictionary = _seats([5, 2, 8], 0)
	assert_eq(LobbySeats.seat_keys(seats), _ints([_human(5), _human(2), _human(8)]))
	var reordered: Dictionary = LobbySeats.reconcile(seats, _peers([8, 5, 2]), 0, NORMAL, CAP_FOUR)
	assert_eq(LobbySeats.seat_keys(reordered), _ints([_human(8), _human(5), _human(2)]),
		"humans follow the caller's (slot) order")
	assert_eq(LobbySeats.color_of(reordered, _human(5)), 0, "reordering keeps each seat's colour")
	assert_eq(LobbySeats.color_of(reordered, _human(8)), 2)


func test_reconcile_resizes_the_bot_list_keeping_the_bots_that_stay() -> void:
	var seats: Dictionary = _seats([1], 3)
	assert_true(LobbySeats.set_difficulty(seats, _bot(0), EASY))
	assert_true(LobbySeats.set_difficulty(seats, _bot(1), HARD))
	var fewer: Dictionary = LobbySeats.reconcile(seats, _peers([1]), 2, NORMAL, CAP_FOUR)
	assert_eq(LobbySeats.bot_count(fewer), 2, "trailing bots are cut")
	assert_eq(LobbySeats.difficulty_of(fewer, _bot(0)), EASY)
	assert_eq(LobbySeats.difficulty_of(fewer, _bot(1)), HARD)
	var more: Dictionary = LobbySeats.reconcile(fewer, _peers([1]), 4, HARD, CAP_FOUR)
	assert_eq(LobbySeats.bot_count(more), 4)
	assert_eq(LobbySeats.difficulty_of(more, _bot(0)), EASY, "existing bots keep their difficulty")
	assert_eq(LobbySeats.difficulty_of(more, _bot(2)), HARD, "new bots take the default")
	_assert_unique_valid_colors(more, "after resizing the bots")


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


func test_reconcile_skips_invalid_and_duplicate_peer_ids() -> void:
	var seats: Dictionary = LobbySeats.reconcile({}, _peers([1, 0, -3, 1, 2]), 0, NORMAL, CAP_FOUR)
	assert_eq(LobbySeats.seat_keys(seats), _ints([_human(1), _human(2)]))


func test_reconcile_does_not_modify_its_input() -> void:
	var seats: Dictionary = _seats([1, 2], 1)
	var before: String = JSON.stringify(seats)
	var after: Dictionary = LobbySeats.reconcile(seats, _peers([2, 3]), 3, HARD, 2)
	assert_eq(JSON.stringify(seats), before, "the previous table is left as it was")
	assert_ne(JSON.stringify(after), before)


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


func test_reconcile_clamps_picks_to_the_cap_only_while_teams_are_on() -> void:
	var seats: Dictionary = _seats([1, 2, 3, 4], 0)
	_set_team_of(seats, _human(1), 4)
	_set_team_of(seats, _human(2), 3)
	_set_team_of(seats, _human(3), 0)
	var legacy: Dictionary = LobbySeats.reconcile(seats, _peers([1, 2, 3, 4]), 0, NORMAL, 2)
	assert_eq(LobbySeats.team_of(legacy, _human(1)), 2, "a 4 becomes 2 under a two-team cap")
	assert_eq(LobbySeats.team_of(legacy, _human(2)), 2)
	assert_eq(LobbySeats.team_of(legacy, _human(3)), MatchConfig.TEAM_PICK_RANDOM, "Random stays Random")
	var hidden: Dictionary = LobbySeats.reconcile(seats, _peers([1, 2, 3, 4]), 0, NORMAL, 0)
	assert_eq(LobbySeats.team_of(hidden, _human(1)), 4, "teams off keeps the picks (hidden)")
	assert_eq(LobbySeats.team_of(hidden, _human(2)), 3)


func test_a_new_seat_joins_the_smaller_of_teams_one_and_two() -> void:
	var seats: Dictionary = _seats([1, 2, 3], 0)
	_set_team_of(seats, _human(1), 2)
	_set_team_of(seats, _human(2), 2)
	_set_team_of(seats, _human(3), 3)
	var after: Dictionary = LobbySeats.reconcile(seats, _peers([1, 2, 3, 4]), 0, NORMAL, CAP_FOUR)
	assert_eq(LobbySeats.team_of(after, _human(4)), 1, "team 1 is empty, team 2 has two")
	var balanced: Dictionary = LobbySeats.reconcile(after, _peers([1, 2, 3, 4, 5]), 0, NORMAL, CAP_FOUR)
	assert_eq(LobbySeats.team_of(balanced, _human(5)), 1, "1 vs 2 players: team 1 is still the smaller")
	var tie: Dictionary = LobbySeats.reconcile(balanced, _peers([1, 2, 3, 4, 5, 6]), 0, NORMAL, CAP_FOUR)
	assert_eq(LobbySeats.team_of(tie, _human(6)), 1, "2 vs 2 ties to team 1")


func test_a_missing_or_stale_table_degrades_to_defaults() -> void:
	for junk: Variant in [null, 5, "seats", [], {"humans": "x", "bots": 7}, {"humans": [1, "a", null]}]:
		var seats: Dictionary = LobbySeats.reconcile(junk, _peers([1, 2]), 1, NORMAL, CAP_FOUR)
		assert_eq(LobbySeats.seat_count(seats), 3, "defaults from %s" % str(junk))
		assert_eq(_colors(seats), _ints([0, 1, 2]))
		assert_eq(_teams(seats), _ints([1, 2, 1]))


func test_the_table_survives_a_json_round_trip() -> void:
	var seats: Dictionary = _seats([1, 2, 3, 4], 3)
	assert_true(LobbySeats.set_color(seats, _human(2), 7))
	_set_team_of(seats, _human(4), 0)
	assert_true(LobbySeats.set_difficulty(seats, _bot(1), HARD))
	var wire: Variant = JSON.parse_string(JSON.stringify(seats))
	var back: Dictionary = LobbySeats.reconcile(wire, _peers([1, 2, 3, 4]), 3, NORMAL, CAP_FOUR)
	assert_eq(_colors(back), _colors(seats), "colours survive JSON floats")
	assert_eq(_teams(back), _teams(seats))
	assert_eq(LobbySeats.difficulty_of(back, _bot(1)), HARD)
	assert_eq(JSON.stringify(back), JSON.stringify(seats), "an identical reconcile is a no-op")


func test_normalize_drops_junk_entries_and_marks_bad_fields_unset() -> void:
	var raw: Dictionary = {
		"humans": [
			{"peer_id": 4.0, "color": 2.0, "team": 3.0},
			{"peer_id": 4, "color": 1, "team": 1},
			{"peer_id": "5", "color": 1},
			{"peer_id": -2},
			{"peer_id": 6, "color": 8, "team": 5},
			{"color": 1},
			"junk",
		],
		"bots": [{"color": -1, "team": 9, "difficulty": 3}, 12],
	}
	var seats: Dictionary = LobbySeats.normalize(raw)
	assert_eq(LobbySeats.seat_keys(seats), _ints([_human(4), _human(6), _bot(0), _bot(1)]),
		"duplicate, non-numeric, negative and missing peer ids are dropped")
	assert_eq(LobbySeats.color_of(seats, _human(4)), 2, "JSON floats become ints")
	assert_eq(LobbySeats.team_of(seats, _human(4)), 3)
	assert_eq(LobbySeats.color_of(seats, _human(6)), LobbySeats.UNSET, "an out-of-range colour is unset")
	assert_eq(LobbySeats.team_of(seats, _human(6)), LobbySeats.UNSET, "an out-of-range team is unset")
	assert_eq(LobbySeats.difficulty_of(seats, _bot(0)), LobbySeats.UNSET)
	assert_eq(LobbySeats.color_of(seats, _bot(1)), LobbySeats.UNSET, "a junk bot entry is an all-unset bot")
	assert_eq(LobbySeats.normalize(null).size(), LobbySeats.empty().size())


# --- colours ------------------------------------------------------------------

func test_set_color_swaps_with_the_seat_that_holds_it() -> void:
	var seats: Dictionary = _seats([1, 2], 1)  # colours 0, 1, 2
	assert_true(LobbySeats.set_color(seats, _human(1), 2))
	assert_eq(_colors(seats), _ints([2, 1, 0]), "the bot's colour 2 and the human's 0 swapped")
	assert_true(LobbySeats.set_color(seats, _human(2), 5))
	assert_eq(_colors(seats), _ints([2, 5, 0]), "a free colour is simply taken")
	_assert_unique_valid_colors(seats, "after swaps")


func test_set_color_keeps_eight_seats_unique_for_every_pick() -> void:
	var seats: Dictionary = _seats([1, 2, 3, 4], 4)
	assert_eq(LobbySeats.seat_count(seats), 8)
	for key: int in LobbySeats.seat_keys(seats):
		for color: int in range(LobbySeats.palette_size()):
			LobbySeats.set_color(seats, key, color)
			_assert_unique_valid_colors(seats, "key %d -> colour %d" % [key, color])
			assert_eq(LobbySeats.color_of(seats, key), color, "the seat gets what it asked for")


func test_set_color_refuses_what_it_cannot_do() -> void:
	var seats: Dictionary = _seats([1, 2], 0)
	assert_false(LobbySeats.set_color(seats, _human(1), 0), "already that colour")
	assert_false(LobbySeats.set_color(seats, _human(1), -1))
	assert_false(LobbySeats.set_color(seats, _human(1), LobbySeats.palette_size()))
	assert_false(LobbySeats.set_color(seats, _human(99), 3), "unknown peer")
	assert_false(LobbySeats.set_color(seats, _bot(0), 3), "unknown bot")
	assert_false(LobbySeats.set_color(seats, LobbySeats.KEY_NONE, 3))
	assert_eq(_colors(seats), _ints([0, 1]), "a refused request changes nothing")


func test_cycle_color_steps_with_wrap_and_swaps() -> void:
	var seats: Dictionary = _seats([1, 2], 0)  # 0, 1
	assert_true(LobbySeats.cycle_color(seats, _human(1)))
	assert_eq(_colors(seats), _ints([1, 0]), "next colour is held by seat 2: swap")
	assert_true(LobbySeats.cycle_color(seats, _human(1), true))
	assert_eq(_colors(seats), _ints([0, 1]), "previous colour swaps back")
	assert_true(LobbySeats.cycle_color(seats, _human(1), true))
	assert_eq(LobbySeats.color_of(seats, _human(1)), LobbySeats.palette_size() - 1, "backwards from 0 wraps to the last")
	assert_true(LobbySeats.cycle_color(seats, _human(1)))
	assert_eq(LobbySeats.color_of(seats, _human(1)), 0, "forwards from the last wraps to 0")
	assert_false(LobbySeats.cycle_color(seats, _human(42)), "unknown seat")
	_assert_unique_valid_colors(seats, "after cycling")


# --- teams --------------------------------------------------------------------

func test_set_team_validates_against_the_cap() -> void:
	var seats: Dictionary = _seats([1, 2], 0)
	assert_true(LobbySeats.set_team(seats, _human(1), 2, 2))
	assert_false(LobbySeats.set_team(seats, _human(1), 3, 2), "3 is above a two-team cap")
	assert_true(LobbySeats.set_team(seats, _human(1), MatchConfig.TEAM_PICK_RANDOM, 2), "Random is always allowed")
	assert_false(LobbySeats.set_team(seats, _human(1), -1, 2))
	assert_false(LobbySeats.set_team(seats, _human(1), 1, 0), "teams off accepts nothing")
	assert_false(LobbySeats.set_team(seats, _human(99), 1, 2), "unknown seat")
	assert_false(LobbySeats.set_team(seats, _human(1), MatchConfig.TEAM_PICK_RANDOM, 2), "no change")
	assert_true(LobbySeats.set_team(seats, _human(1), 4), "the default cap is the model maximum")
	assert_false(LobbySeats.set_team(seats, _human(1), 5), "above the model maximum")
	assert_eq(LobbySeats.team_of(seats, _human(1)), 4)


func test_cycle_team_walks_one_to_cap_then_random() -> void:
	var seats: Dictionary = _seats([1, 2], 0)  # picks 1, 2
	var walked: Array[int] = []
	for step: int in range(6):
		assert_true(LobbySeats.cycle_team(seats, _human(1), CAP_FOUR))
		walked.append(LobbySeats.team_of(seats, _human(1)))
	assert_eq(walked, _ints([2, 3, 4, 0, 1, 2]), "1 > 2 > 3 > 4 > Random > 1")
	var legacy: Array[int] = []
	for step: int in range(4):
		LobbySeats.cycle_team(seats, _human(2), 2)
		legacy.append(LobbySeats.team_of(seats, _human(2)))
	assert_eq(legacy, _ints([0, 1, 2, 0]), "a two-team cap cycles 1 > 2 > Random")
	assert_true(LobbySeats.cycle_team(seats, _human(2), CAP_FOUR, true), "right click goes backwards")
	assert_eq(LobbySeats.team_of(seats, _human(2)), 4, "backwards from Random wraps to the cap")
	assert_false(LobbySeats.cycle_team(seats, _human(2), 0), "teams off: nothing to cycle")
	assert_false(LobbySeats.cycle_team(seats, _human(77), CAP_FOUR), "unknown seat")


func test_seed_team_picks_restores_one_two_one_two_in_seat_order() -> void:
	var seats: Dictionary = _seats([1, 2, 3], 2)
	_set_team_of(seats, _human(1), 3)
	_set_team_of(seats, _bot(1), 0)
	assert_true(LobbySeats.seed_team_picks(seats))
	assert_eq(_teams(seats), _ints([1, 2, 1, 2, 1]), "humans then bots: 1,2,1,2,1")
	assert_false(LobbySeats.seed_team_picks(seats), "already seeded")


# --- difficulty and bots ------------------------------------------------------

func test_set_difficulty_is_for_bots_and_validates_the_range() -> void:
	var seats: Dictionary = _seats([1], 2)
	assert_true(LobbySeats.set_difficulty(seats, _bot(1), HARD))
	assert_eq(LobbySeats.difficulty_of(seats, _bot(1)), HARD)
	assert_eq(LobbySeats.difficulty_of(seats, _bot(0)), NORMAL, "the other bot is untouched")
	assert_false(LobbySeats.set_difficulty(seats, _bot(1), HARD), "no change")
	assert_false(LobbySeats.set_difficulty(seats, _bot(1), 3))
	assert_false(LobbySeats.set_difficulty(seats, _bot(1), -1))
	assert_false(LobbySeats.set_difficulty(seats, _human(1), EASY), "a human has no difficulty")
	assert_false(LobbySeats.set_difficulty(seats, _bot(5), EASY), "unknown bot")
	assert_eq(LobbySeats.difficulty_of(seats, _bot(1)), HARD, "refused requests change nothing")


func test_add_bot_takes_the_lowest_free_colour_and_the_smaller_team() -> void:
	var seats: Dictionary = _seats([1, 2, 3], 0)  # teams 1,2,1
	var key: int = LobbySeats.add_bot(seats, HARD)
	assert_eq(key, _bot(0))
	assert_eq(LobbySeats.color_of(seats, key), 3)
	assert_eq(LobbySeats.team_of(seats, key), 2, "team 2 has fewer seats than team 1")
	assert_eq(LobbySeats.difficulty_of(seats, key), HARD)
	var next_key: int = LobbySeats.add_bot(seats)
	assert_eq(next_key, _bot(1))
	assert_eq(LobbySeats.difficulty_of(seats, next_key), NORMAL, "the default difficulty is Normal")
	assert_eq(LobbySeats.team_of(seats, next_key), 1, "2 vs 2 ties to team 1")
	assert_eq(LobbySeats.seat_count(seats), 5)
	_assert_unique_valid_colors(seats, "after adding bots")


func test_add_bot_fills_the_freed_colour_and_stops_at_eight_seats() -> void:
	var seats: Dictionary = _seats([1, 2], 0)
	assert_true(LobbySeats.set_color(seats, _human(1), 7))
	for i: int in range(6):
		assert_ne(LobbySeats.add_bot(seats), LobbySeats.KEY_NONE, "bot %d fits" % i)
	assert_eq(LobbySeats.seat_count(seats), 8)
	assert_eq(LobbySeats.add_bot(seats), LobbySeats.KEY_NONE, "no ninth seat")
	assert_eq(LobbySeats.seat_count(seats), 8)
	_assert_unique_valid_colors(seats, "a full lobby")
	assert_eq(LobbySeats.color_of(seats, _bot(0)), 0, "colour 0 was freed by the colour change and is reused")


func test_add_bot_works_on_an_empty_table() -> void:
	var seats: Dictionary = LobbySeats.empty()
	assert_eq(LobbySeats.add_bot(seats), _bot(0))
	assert_eq(LobbySeats.color_of(seats, _bot(0)), 0)
	var bare: Dictionary = {}
	assert_eq(LobbySeats.add_bot(bare), _bot(0), "even a bare dictionary gets its lists")


func test_remove_bot_compacts_and_frees_the_colour() -> void:
	var seats: Dictionary = _seats([1], 3)
	assert_true(LobbySeats.set_difficulty(seats, _bot(1), EASY))
	assert_true(LobbySeats.set_difficulty(seats, _bot(2), HARD))
	_set_team_of(seats, _bot(2), 0)
	var removed_color: int = LobbySeats.color_of(seats, _bot(0))
	assert_true(LobbySeats.remove_bot(seats, _bot(0)))
	assert_eq(LobbySeats.bot_count(seats), 2, "the list shrank")
	assert_eq(LobbySeats.difficulty_of(seats, _bot(0)), EASY, "bot 2 moved down to ordinal 0 with its picks")
	assert_eq(LobbySeats.difficulty_of(seats, _bot(1)), HARD)
	assert_eq(LobbySeats.team_of(seats, _bot(1)), MatchConfig.TEAM_PICK_RANDOM)
	assert_eq(LobbySeats.color_of(seats, _bot(0)), 2, "its colour moved with it")
	assert_eq(LobbySeats.color_of(seats, _human(1)), 0, "humans are unaffected")
	var replacement: int = LobbySeats.add_bot(seats)
	assert_eq(LobbySeats.color_of(seats, replacement), removed_color, "the removed bot's colour is free again")


func test_remove_bot_refuses_humans_and_unknown_keys() -> void:
	var seats: Dictionary = _seats([1, 2], 1)
	assert_false(LobbySeats.remove_bot(seats, _human(2)), "humans leave by disconnecting")
	assert_false(LobbySeats.remove_bot(seats, _bot(1)), "no such bot")
	assert_false(LobbySeats.remove_bot(seats, LobbySeats.KEY_NONE))
	assert_eq(LobbySeats.seat_count(seats), 3)
	assert_true(LobbySeats.remove_bot(seats, _bot(0)))
	assert_false(LobbySeats.remove_bot(seats, _bot(0)), "already gone")


func test_removing_and_reconciling_agree_on_the_bot_list() -> void:
	var seats: Dictionary = _seats([1, 2], 3)
	assert_true(LobbySeats.set_difficulty(seats, _bot(2), HARD))
	assert_true(LobbySeats.remove_bot(seats, _bot(1)))
	var after: Dictionary = LobbySeats.reconcile(seats, _peers([1, 2]), 2, NORMAL, CAP_FOUR)
	assert_eq(LobbySeats.bot_count(after), 2, "ai_count - 1 keeps the compacted list")
	assert_eq(LobbySeats.difficulty_of(after, _bot(1)), HARD)
	assert_eq(JSON.stringify(after), JSON.stringify(seats))


# --- a client edits its own seat ----------------------------------------------

func test_apply_human_pref_changes_only_the_named_seat() -> void:
	var seats: Dictionary = _seats([1, 2], 1)
	assert_true(LobbySeats.apply_human_pref(seats, 2, 5, 3, CAP_FOUR))
	assert_eq(LobbySeats.color_of(seats, _human(2)), 5)
	assert_eq(LobbySeats.team_of(seats, _human(2)), 3)
	assert_eq(LobbySeats.color_of(seats, _human(1)), 0, "the other human is untouched")
	assert_eq(LobbySeats.team_of(seats, _human(1)), 1)
	assert_eq(LobbySeats.difficulty_of(seats, _bot(0)), NORMAL)


func test_apply_human_pref_unchanged_fields_stay() -> void:
	var seats: Dictionary = _seats([1, 2], 0)
	assert_true(LobbySeats.apply_human_pref(seats, 2, LobbySeats.UNCHANGED, 0, CAP_FOUR))
	assert_eq(LobbySeats.team_of(seats, _human(2)), 0)
	assert_eq(LobbySeats.color_of(seats, _human(2)), 1, "colour left alone")
	assert_true(LobbySeats.apply_human_pref(seats, 2, 4, LobbySeats.UNCHANGED, CAP_FOUR))
	assert_eq(LobbySeats.color_of(seats, _human(2)), 4)
	assert_eq(LobbySeats.team_of(seats, _human(2)), 0, "team left alone")
	assert_false(LobbySeats.apply_human_pref(seats, 2, LobbySeats.UNCHANGED, LobbySeats.UNCHANGED, CAP_FOUR),
		"nothing requested, nothing changed")
	assert_false(LobbySeats.apply_human_pref(seats, 2, 4, 0, CAP_FOUR), "the same values: no change")


func test_apply_human_pref_swaps_colours_with_another_seat() -> void:
	var seats: Dictionary = _seats([1, 2], 1)  # 0, 1, 2
	assert_true(LobbySeats.apply_human_pref(seats, 2, 2, LobbySeats.UNCHANGED, CAP_FOUR))
	assert_eq(_colors(seats), _ints([0, 2, 1]), "the bot that held colour 2 got the human's old colour")


func test_apply_human_pref_is_all_or_nothing() -> void:
	var seats: Dictionary = _seats([1, 2], 0)
	var before: String = JSON.stringify(seats)
	assert_false(LobbySeats.apply_human_pref(seats, 2, 5, 9, CAP_FOUR), "bad team refuses the valid colour too")
	assert_false(LobbySeats.apply_human_pref(seats, 2, 99, 2, CAP_FOUR), "bad colour refuses the valid team too")
	assert_false(LobbySeats.apply_human_pref(seats, 2, 5, -5, CAP_FOUR), "only -1 means unchanged")
	assert_false(LobbySeats.apply_human_pref(seats, 2, -5, 2, CAP_FOUR))
	assert_false(LobbySeats.apply_human_pref(seats, 2, 5, 3, 2), "3 is above a two-team cap: refused, not clamped")
	assert_false(LobbySeats.apply_human_pref(seats, 2, 5, 1, 0), "a team pick while teams are off")
	assert_eq(JSON.stringify(seats), before, "no partial application")


func test_apply_human_pref_refuses_seats_that_are_not_humans() -> void:
	var seats: Dictionary = _seats([1, 2], 1)
	var before: String = JSON.stringify(seats)
	assert_false(LobbySeats.apply_human_pref(seats, 9, 3, 1, CAP_FOUR), "a peer with no seat (spectator)")
	assert_false(LobbySeats.apply_human_pref(seats, 0, 3, 1, CAP_FOUR))
	assert_false(LobbySeats.apply_human_pref(seats, -1, 3, 1, CAP_FOUR), "a bot key is not a peer id")
	assert_eq(JSON.stringify(seats), before)
	assert_true(LobbySeats.apply_human_pref(seats, 2, LobbySeats.UNCHANGED, 1, CAP_FOUR), "a real seat still works")
	assert_eq(LobbySeats.team_of(seats, _human(2)), 1)


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


func test_layout_without_net_slots_numbers_humans_in_seat_order() -> void:
	var seats: Dictionary = _seats([7, 3], 1)
	var plan: LobbySeats.Layout = LobbySeats.layout(seats)
	assert_eq(plan.slot_keys, _ints([_human(7), _human(3), _bot(0)]))


func test_layout_keeps_a_vacant_slot_below_the_player_minimum() -> void:
	var plan: LobbySeats.Layout = LobbySeats.layout(_seats([1], 0), _slots([Vector2i(1, 0)]))
	assert_true(plan.is_valid())
	assert_eq(plan.player_count, MatchConfig.PLAYER_COUNT_MIN)
	assert_eq(plan.ai_count, 0)
	assert_eq(plan.slot_keys, _ints([_human(1), LobbySeats.KEY_NONE]))


func test_layout_ignores_spectators() -> void:
	var seats: Dictionary = _seats([1, 2, 3], 0)
	var plan: LobbySeats.Layout = LobbySeats.layout(seats, _slots([Vector2i(1, 0), Vector2i(2, -1), Vector2i(3, 1)]))
	assert_true(plan.is_valid())
	assert_eq(plan.slot_keys, _ints([_human(1), _human(3)]), "a peer with slot -1 holds no seat")
	var missing: LobbySeats.Layout = LobbySeats.layout(seats, _slots([Vector2i(1, 0), Vector2i(3, 1)]))
	assert_eq(missing.slot_keys, _ints([_human(1), _human(3)]), "nor does a peer Net does not list")


func test_layout_reports_a_human_slot_that_clashes_with_the_bots() -> void:
	# Net slots never compact: peer 30 sits in slot 3 after the peer in slot 2 left,
	# so the two bots would be slots 2 and 3 and collide with it (plan R4).
	var seats: Dictionary = _seats([10, 20, 30], 2)
	var plan: LobbySeats.Layout = LobbySeats.layout(seats, _slots([Vector2i(10, 0), Vector2i(20, 1), Vector2i(30, 7)]))
	assert_false(plan.is_valid())
	assert_eq(plan.error, LobbySeats.BLOCKER_SLOT_CONFLICT)
	var twice: LobbySeats.Layout = LobbySeats.layout(_seats([1, 2], 0), _slots([Vector2i(1, 0), Vector2i(2, 0)]))
	assert_eq(twice.error, LobbySeats.BLOCKER_SLOT_CONFLICT, "two peers in one slot")
	var hole: LobbySeats.Layout = LobbySeats.layout(_seats([1, 2], 0), _slots([Vector2i(1, 0), Vector2i(2, 2)]))
	assert_eq(hole.error, LobbySeats.BLOCKER_SLOT_CONFLICT, "a hole below a human leaves it past the last slot")


func test_layout_reports_too_many_seats() -> void:
	var raw: Dictionary = {
		"humans": [{"peer_id": 1}, {"peer_id": 2}, {"peer_id": 3}, {"peer_id": 4}, {"peer_id": 5}],
		"bots": [{}, {}, {}, {}],
	}
	var plan: LobbySeats.Layout = LobbySeats.layout(raw)
	assert_eq(plan.error, LobbySeats.BLOCKER_TOO_MANY_SEATS)


func test_team_picks_by_slot_follow_the_layout() -> void:
	var seats: Dictionary = _seats([10, 20], 2)  # picks 1,2,1,2
	_set_team_of(seats, _human(20), 4)
	_set_team_of(seats, _bot(0), 0)
	var picks: PackedInt32Array = LobbySeats.team_picks_by_slot(seats, _slots([Vector2i(10, 0), Vector2i(20, 1)]))
	assert_eq(picks, PackedInt32Array([1, 4, 0, 2]), "slot order: humans at their slots, then the bots")
	var swapped: PackedInt32Array = LobbySeats.team_picks_by_slot(seats, _slots([Vector2i(20, 0), Vector2i(10, 1)]))
	assert_eq(swapped, PackedInt32Array([4, 1, 0, 2]), "the real Net slots decide the order")
	var vacant: PackedInt32Array = LobbySeats.team_picks_by_slot(_seats([1], 0), _slots([Vector2i(1, 0)]))
	assert_eq(vacant, PackedInt32Array([1, MatchConfig.TEAM_PICK_RANDOM]), "a vacant slot is a Random pick")
	var broken: PackedInt32Array = LobbySeats.team_picks_by_slot(_seats([1, 2], 0), _slots([Vector2i(1, 0), Vector2i(2, 0)]))
	assert_true(broken.is_empty(), "no picks for a layout that cannot be built")


# --- start blocker ------------------------------------------------------------

func test_start_blocker_rejects_teams_on_with_one_team() -> void:
	var seats: Dictionary = _seats([1, 2, 3], 1)
	for key: int in LobbySeats.seat_keys(seats):
		_set_team_of(seats, key, 1)
	assert_eq(LobbySeats.start_blocker(seats, {}, CAP_FOUR), TeamAssigner.BLOCKER_ONE_TEAM,
		"everyone explicitly on team 1")
	assert_eq(LobbySeats.start_blocker(seats, {}, 0), "", "teams off: nothing to block")
	_set_team_of(seats, _bot(0), 2)
	assert_eq(LobbySeats.start_blocker(seats, {}, CAP_FOUR), "", "a second team unblocks")
	_set_team_of(seats, _bot(0), 1)
	_set_team_of(seats, _human(3), 0)
	assert_eq(LobbySeats.start_blocker(seats, {}, CAP_FOUR), "", "a Random seat always makes a second team")


func test_start_blocker_accepts_the_default_picks_and_an_all_random_lobby() -> void:
	assert_eq(LobbySeats.start_blocker(_seats([1, 2], 0), {}, CAP_FOUR), "", "1,2")
	var random_lobby: Dictionary = _seats([1, 2, 3, 4], 0)
	for key: int in LobbySeats.seat_keys(random_lobby):
		_set_team_of(random_lobby, key, 0)
	assert_eq(LobbySeats.start_blocker(random_lobby, {}, CAP_FOUR), "")
	assert_eq(LobbySeats.start_blocker(_seats([1], 0), {}, CAP_FOUR), "", "a single seat is not blocked (no min-seat gate)")


func test_start_blocker_reports_a_seat_layout_that_cannot_start() -> void:
	var seats: Dictionary = _seats([1, 2], 1)
	assert_eq(LobbySeats.start_blocker(seats, _slots([Vector2i(1, 0), Vector2i(2, 5)]), 0), LobbySeats.BLOCKER_SLOT_CONFLICT)
	assert_eq(LobbySeats.start_blocker(seats, _slots([Vector2i(1, 0), Vector2i(2, 1)]), 0), "")


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

func test_flatten_maps_humans_to_real_slots_and_bots_to_the_trailing_slots() -> void:
	var seats: Dictionary = _seats([10, 20, 30], 2)
	assert_true(LobbySeats.set_color(seats, _human(30), 7))
	assert_true(LobbySeats.set_difficulty(seats, _bot(0), EASY))
	assert_true(LobbySeats.set_difficulty(seats, _bot(1), HARD))
	var config: MatchConfig = _team_config()
	var reason: String = LobbySeats.flatten_to_config(seats, _slots([Vector2i(10, 0), Vector2i(20, 1), Vector2i(30, 2)]), config, SEED)
	assert_eq(reason, "")
	assert_eq(config.player_count, 5)
	assert_eq(config.ai_count, 2)
	var palette: PackedColorArray = MatchConfig.default_player_colors()
	assert_eq(config.player_colors[0], palette[0], "slot 0 = peer 10's colour")
	assert_eq(config.player_colors[1], palette[1])
	assert_eq(config.player_colors[2], palette[7], "slot 2 = peer 30's chosen colour")
	assert_eq(config.player_colors[3], palette[LobbySeats.color_of(seats, _bot(0))], "slot 3 = bot 1's colour")
	assert_eq(config.player_colors[4], palette[LobbySeats.color_of(seats, _bot(1))])
	assert_eq(config.player_colors.size(), MatchConfig.PLAYER_COUNT_MAX)
	assert_eq(config.slot_ai_difficulties, PackedInt32Array([NORMAL, NORMAL, NORMAL, EASY, HARD]),
		"bots' difficulties sit at their slots; human slots hold the default")
	assert_eq(config.ai_difficulty_for_slot(3), MatchConfig.AiDifficulty.EASY)
	assert_eq(config.ai_difficulty_for_slot(4), MatchConfig.AiDifficulty.HARD)


func test_flatten_player_colors_stay_a_permutation_of_the_palette() -> void:
	var seats: Dictionary = _seats([1, 2], 1)
	LobbySeats.set_color(seats, _human(1), 5)
	LobbySeats.set_color(seats, _bot(0), 6)
	var config: MatchConfig = MatchConfig.new()
	assert_eq(LobbySeats.flatten_to_config(seats, {}, config, SEED), "")
	var palette: PackedColorArray = MatchConfig.default_player_colors()
	var seen: Dictionary = {}
	for color: Color in config.player_colors:
		assert_true(palette.has(color), "only palette colours")
		seen[color] = true
	assert_eq(seen.size(), palette.size(), "every colour exactly once, so seats can never share one")
	assert_eq(config.player_colors[0], palette[5])
	assert_eq(config.player_colors[1], palette[1])
	assert_eq(config.player_colors[2], palette[6])
	# Flattening twice from the same table gives the same colours (the palette is the
	# canonical one, not the config's already-permuted player_colors).
	var again: MatchConfig = MatchConfig.new()
	again.player_colors = config.player_colors
	assert_eq(LobbySeats.flatten_to_config(seats, {}, again, SEED), "")
	assert_eq(again.player_colors, config.player_colors)


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


func test_flatten_survives_the_wire_round_trip_with_teams_resolved() -> void:
	var seats: Dictionary = _seats([1, 2, 3], 3)
	var config: MatchConfig = _team_config()
	assert_eq(LobbySeats.flatten_to_config(seats, {}, config, SEED), "")
	var wire: Variant = bytes_to_var(var_to_bytes(config.to_dict()))
	var received: MatchConfig = MatchConfig.from_dict(wire as Dictionary)
	received.sanitize()
	assert_true(received.teams_resolved())
	assert_eq(received.slot_team_ids, config.slot_team_ids)
	assert_eq(received.slot_ai_difficulties, config.slot_ai_difficulties)
	assert_eq(received.player_colors, config.player_colors)


func test_flatten_player_count_follows_the_seats_not_the_stale_config() -> void:
	var seats: Dictionary = _seats([1, 2], 1)
	var config: MatchConfig = _team_config()
	config.player_count = 8
	config.ai_count = 6
	assert_eq(LobbySeats.flatten_to_config(seats, {}, config, SEED), "")
	assert_eq(config.player_count, 3)
	assert_eq(config.ai_count, 1)
	assert_eq(config.slot_team_ids.size(), 3)


func test_flatten_gives_a_lone_host_a_vacant_random_slot() -> void:
	var seats: Dictionary = _seats([1], 0)
	var config: MatchConfig = _team_config()
	assert_eq(LobbySeats.flatten_to_config(seats, _slots([Vector2i(1, 0)]), config, SEED), "")
	assert_eq(config.player_count, MatchConfig.PLAYER_COUNT_MIN)
	assert_eq(config.ai_count, 0)
	assert_true(config.slot_ai_difficulties.is_empty(), "no bots, no per-slot difficulties")
	assert_eq(config.slot_team_ids.size(), 2)
	assert_eq(config.team_numbers.size(), 2, "the vacant slot is Random and lands on the empty team")
	config.sanitize()
	assert_true(config.teams_resolved())


func test_flatten_with_teams_off_clears_stale_team_arrays() -> void:
	var seats: Dictionary = _seats([1, 2, 3], 0)
	var config: MatchConfig = MatchConfig.new()
	config.team_mode = MatchConfig.TeamMode.OFF
	config.slot_team_ids = PackedInt32Array([0, 0, 1])
	config.team_numbers = PackedInt32Array([1, 2])
	assert_eq(LobbySeats.flatten_to_config(seats, {}, config, SEED), "")
	assert_true(config.slot_team_ids.is_empty())
	assert_true(config.team_numbers.is_empty())
	assert_false(config.teams_resolved())
	assert_eq(config.team_of_slot(2), 2, "free for all")
	assert_eq(config.player_count, 3)


func test_flatten_honours_a_two_team_cap_from_a_legacy_lobby() -> void:
	var seats: Dictionary = _seats([1, 2, 3, 4], 0)
	_set_team_of(seats, _human(1), 4)
	_set_team_of(seats, _human(3), 3)
	_set_team_of(seats, _human(4), 1)  # picks 4,2,3,1
	var config: MatchConfig = _team_config(MatchConfig.TeamMode.TEAMS_2)
	assert_eq(LobbySeats.flatten_to_config(seats, {}, config, SEED), "")
	assert_eq(config.slot_team_ids, PackedInt32Array([1, 1, 1, 0]), "4 and 3 clamp into team 2 under a two-team cap")
	assert_eq(config.team_numbers, PackedInt32Array([1, 2]))
	var one_team: Dictionary = _seats([1, 2], 0)
	_set_team_of(one_team, _human(1), 4)
	assert_eq(LobbySeats.start_blocker(one_team, {}, 2), TeamAssigner.BLOCKER_ONE_TEAM,
		"picks 4 and 2 are both team 2 under a two-team cap")


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


func test_flatten_reports_layout_errors_without_touching_the_config() -> void:
	var seats: Dictionary = _seats([1, 2], 1)
	var config: MatchConfig = _team_config()
	var before: String = JSON.stringify(config.to_dict())
	var reason: String = LobbySeats.flatten_to_config(seats, _slots([Vector2i(1, 0), Vector2i(2, 2)]), config, SEED)
	assert_eq(reason, LobbySeats.BLOCKER_SLOT_CONFLICT)
	assert_eq(JSON.stringify(config.to_dict()), before)


func test_flatten_ignores_spectators_for_the_seat_counts() -> void:
	var seats: Dictionary = _seats([1, 2, 3], 1)
	var config: MatchConfig = MatchConfig.new()
	var slots: Dictionary = _slots([Vector2i(1, 0), Vector2i(2, -1), Vector2i(3, 1)])
	assert_eq(LobbySeats.flatten_to_config(seats, slots, config, SEED), "")
	assert_eq(config.player_count, 3, "two seated humans and one bot")
	assert_eq(config.ai_count, 1)


func test_flatten_balanced_random_fill_is_deterministic_per_seed() -> void:
	var seats: Dictionary = _seats([1, 2, 3, 4], 0)
	for key: int in LobbySeats.seat_keys(seats):
		_set_team_of(seats, key, 0)
	var first: MatchConfig = _team_config()
	var second: MatchConfig = _team_config()
	assert_eq(LobbySeats.flatten_to_config(seats, {}, first, SEED), "")
	assert_eq(LobbySeats.flatten_to_config(seats, {}, second, SEED), "")
	assert_eq(first.slot_team_ids, second.slot_team_ids, "same seed, same teams")
	assert_eq(first.team_numbers, PackedInt32Array([1, 2]), "all Random with 4 seats: two teams")
	var sizes: Array[int] = [0, 0]
	for team_id: int in first.slot_team_ids:
		sizes[team_id] += 1
	assert_eq(sizes, _ints([2, 2]), "balanced: 2v2")
	var distinct: Dictionary = {}
	for seed_value: int in range(1, 30):
		var other: MatchConfig = _team_config()
		assert_eq(LobbySeats.flatten_to_config(seats, {}, other, seed_value), "")
		distinct[str(other.slot_team_ids)] = true
		var other_sizes: Array[int] = [0, 0]
		for team_id: int in other.slot_team_ids:
			other_sizes[team_id] += 1
		assert_eq(other_sizes, _ints([2, 2]), "seed %d stays balanced" % seed_value)
	assert_gt(distinct.size(), 1, "different seeds can give different splits")


func test_flatten_seeds_the_assigner_with_the_caller_seed_plus_the_team_offset() -> void:
	var seats: Dictionary = _seats([1, 2, 3, 4, 5, 6], 0)
	for key: int in LobbySeats.seat_keys(seats):
		_set_team_of(seats, key, 0)
	var config: MatchConfig = _team_config()
	assert_eq(LobbySeats.flatten_to_config(seats, {}, config, SEED), "")
	var expected: TeamAssigner.Result = TeamAssigner.resolve(PackedInt32Array([0, 0, 0, 0, 0, 0]), CAP_FOUR, SEED + LobbySeats.TEAM_RNG_OFFSET)
	assert_eq(config.slot_team_ids, expected.team_ids)
	assert_eq(config.team_numbers, expected.team_numbers)


func test_resolve_seed_prefers_the_match_seed() -> void:
	var config: MatchConfig = MatchConfig.new()
	config.rng_seed = 77
	assert_eq(LobbySeats.resolve_seed(config, 5), 77)
	config.rng_seed = 0
	assert_eq(LobbySeats.resolve_seed(config, 5), 0, "seed 0 is a real seed")
	config.rng_seed = -1
	assert_eq(LobbySeats.resolve_seed(config, 5), 5, "-1 takes the host's fresh seed")


func test_flatten_three_against_one_and_sparse_team_numbers() -> void:
	var seats: Dictionary = _seats([1, 2, 3, 4], 0)
	for key: int in LobbySeats.seat_keys(seats):
		_set_team_of(seats, key, 2)
	_set_team_of(seats, _human(4), 3)
	var config: MatchConfig = _team_config()
	assert_eq(LobbySeats.flatten_to_config(seats, {}, config, SEED), "")
	assert_eq(config.slot_team_ids, PackedInt32Array([0, 0, 0, 1]), "3v1")
	assert_eq(config.team_numbers, PackedInt32Array([2, 3]), "labels keep the lobby numbers")
	assert_eq(config.team_number_for(1), 3)


func test_flatten_random_seat_joins_the_smaller_chosen_team() -> void:
	var seats: Dictionary = _seats([1, 2, 3], 0)
	_set_team_of(seats, _human(1), 1)
	_set_team_of(seats, _human(2), 1)
	_set_team_of(seats, _human(3), 0)
	var config: MatchConfig = _team_config()
	assert_eq(LobbySeats.flatten_to_config(seats, {}, config, SEED), "")
	assert_eq(config.slot_team_ids, PackedInt32Array([0, 0, 1]), "the Random seat fills the empty team 2")
	assert_eq(config.team_numbers, PackedInt32Array([1, 2]))


func test_flatten_does_not_modify_the_seat_table() -> void:
	var seats: Dictionary = _seats([1, 2], 2)
	var before: String = JSON.stringify(seats)
	var config: MatchConfig = _team_config()
	assert_eq(LobbySeats.flatten_to_config(seats, {}, config, SEED), "")
	assert_eq(JSON.stringify(seats), before)


func test_flatten_repairs_an_unreconciled_table() -> void:
	var raw: Dictionary = {
		"humans": [{"peer_id": 1, "color": 2, "team": 1}, {"peer_id": 2, "color": 2}],
		"bots": [{}],
	}
	var config: MatchConfig = _team_config()
	assert_eq(LobbySeats.flatten_to_config(raw, {}, config, SEED), "")
	assert_eq(config.player_count, 3)
	var seen: Dictionary = {}
	for color: Color in config.player_colors:
		seen[color] = true
	assert_eq(seen.size(), MatchConfig.PLAYER_COUNT_MAX, "a duplicate colour was repaired")
	assert_true(config.teams_resolved())
	assert_eq(config.slot_ai_difficulties.size(), 3)
	assert_eq(config.ai_difficulty_for_slot(2), config.ai_difficulty, "a bot with no difficulty gets the config default")


# --- wire budget --------------------------------------------------------------

func test_an_eight_seat_table_is_small_next_to_the_steam_lobby_data_budget() -> void:
	var seats: Dictionary = _seats([2000000001, 2000000002, 2000000003, 2000000004], 4)
	for key: int in LobbySeats.seat_keys(seats):
		LobbySeats.set_team(seats, key, 4)
	var net_config: NetConfig = load("res://config/net_config.tres") as NetConfig
	var size: int = JSON.stringify(seats).to_utf8_buffer().size()
	assert_lt(size, net_config.steam_lobby_data_max_bytes / 8,
		"the seat table (%d bytes) leaves room for the config and roster in 8192 bytes" % size)
