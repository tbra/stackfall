extends GutTest
## MatchConfig.sanitize()/to_dict()/from_dict() (spec 2.8, 3.6).


func test_to_dict_from_dict_round_trips_every_field() -> void:
	var config: MatchConfig = MatchConfig.new()
	config.disc_size_step = 4
	config.player_count = 6
	config.ai_count = 2
	config.ai_difficulty = MatchConfig.AiDifficulty.HARD
	config.team_mode = MatchConfig.TeamMode.TEAMS_2
	config.block_timer = 9.5
	config.gravity_multiplier = 1.2
	config.goal_flag_count = 3
	config.gifts_enabled = false
	config.special_frequency = 70
	config.enabled_specials = [&"rocket", &"bomb"]
	config.tilt_mode = MatchConfig.TiltMode.PHYSICAL_BALANCE
	config.hole_mode = MatchConfig.HoleMode.PERMANENT
	config.match_timer_minutes = 20
	config.sudden_death = true
	config.per_player_timer = false
	config.hot_seat = false
	config.player_colors = PackedColorArray([Color.RED, Color.BLUE])
	config.rng_seed = 42

	var data: Dictionary = config.to_dict()
	var restored: MatchConfig = MatchConfig.from_dict(data)

	assert_eq(restored.disc_size_step, config.disc_size_step)
	assert_eq(restored.player_count, config.player_count)
	assert_eq(restored.ai_count, config.ai_count)
	assert_eq(restored.ai_difficulty, config.ai_difficulty)
	assert_eq(restored.team_mode, config.team_mode)
	assert_almost_eq(restored.block_timer, config.block_timer, 0.001)
	assert_almost_eq(restored.gravity_multiplier, config.gravity_multiplier, 0.001)
	assert_eq(restored.goal_flag_count, config.goal_flag_count)
	assert_eq(restored.gifts_enabled, config.gifts_enabled)
	assert_eq(restored.special_frequency, config.special_frequency)
	assert_eq(restored.enabled_specials, config.enabled_specials)
	assert_eq(restored.tilt_mode, config.tilt_mode)
	assert_eq(restored.hole_mode, config.hole_mode)
	assert_eq(restored.match_timer_minutes, config.match_timer_minutes)
	assert_eq(restored.sudden_death, config.sudden_death)
	assert_eq(restored.per_player_timer, config.per_player_timer)
	assert_eq(restored.hot_seat, config.hot_seat)
	assert_eq(restored.player_colors.size(), config.player_colors.size())
	for i: int in range(config.player_colors.size()):
		assert_eq(restored.player_colors[i], config.player_colors[i])
	assert_eq(restored.rng_seed, config.rng_seed)


func test_sanitize_clamps_every_range() -> void:
	var config: MatchConfig = MatchConfig.new()
	config.player_count = 99
	config.block_timer = -5.0
	config.gravity_multiplier = 100.0
	config.goal_flag_count = 0
	config.special_frequency = -10
	config.match_timer_minutes = -3

	config.sanitize()

	assert_eq(config.player_count, MatchConfig.PLAYER_COUNT_MAX)
	assert_eq(config.block_timer, MatchConfig.BLOCK_TIMER_MIN)
	assert_eq(config.gravity_multiplier, MatchConfig.GRAVITY_MAX)
	assert_eq(config.goal_flag_count, MatchConfig.GOAL_FLAG_MIN)
	assert_eq(config.special_frequency, MatchConfig.SPECIAL_FREQUENCY_MIN)
	assert_eq(config.match_timer_minutes, 0)


## Bots don't need a connected peer behind them (M5): the requested ai_count
## fills the remaining seats up to the spec 2.8 max instead of being zeroed.
func test_clamp_to_connected_peers_fills_remaining_seats_with_bots() -> void:
	var config: MatchConfig = MatchConfig.new()
	config.ai_count = 7

	config.clamp_to_connected_peers(1)

	assert_eq(config.player_count, 8, "1 human + 7 bots fills every seat")
	assert_eq(config.ai_count, 7)


## Spec 2.8 "Teams: Off / 2 / 3 / 4": every real team mode, for every
## player_count in 2..8. Assignment interleaves (slot_id % team_count),
## team_count() never exceeds player_count (mini() guard: TEAMS_4 with 2
## players still returns 2 teams, never 4 with two of them permanently
## empty), and every team from 0 until team_count() has at least one slot.
func test_team_of_slot_interleaves_for_every_team_mode_and_player_count() -> void:
	var modes_and_sizes: Array[Array] = [
		[MatchConfig.TeamMode.TEAMS_2, 2],
		[MatchConfig.TeamMode.TEAMS_3, 3],
		[MatchConfig.TeamMode.TEAMS_4, 4],
	]
	for entry: Array in modes_and_sizes:
		var mode: MatchConfig.TeamMode = entry[0]
		var team_size: int = entry[1]
		for player_count: int in range(MatchConfig.PLAYER_COUNT_MIN, MatchConfig.PLAYER_COUNT_MAX + 1):
			var config: MatchConfig = MatchConfig.new()
			config.team_mode = mode
			config.player_count = player_count
			var expected_team_count: int = mini(team_size, player_count)
			assert_eq(
				config.team_count(), expected_team_count,
				"mode=%d player_count=%d team_count()" % [mode, player_count]
			)
			var seen_teams: Dictionary = {}
			for slot_id: int in range(player_count):
				var team_id: int = config.team_of_slot(slot_id)
				assert_eq(
					team_id, posmod(slot_id, expected_team_count),
					"mode=%d player_count=%d slot=%d interleaves" % [mode, player_count, slot_id]
				)
				assert_between(team_id, 0, expected_team_count - 1)
				seen_teams[team_id] = true
			assert_eq(
				seen_teams.size(), expected_team_count,
				"mode=%d player_count=%d: no team is ever empty" % [mode, player_count]
			)


# --- HoleMode.TEMPORARY, the default again (Bontago-cmc.7) --------------------
# docs/TERRITORY_V2_PLAN.md's HoleMode.OFF (the v2 no-overlap mode) was the
# default for a while; SPEC.md's 2026-09-20 evidence audit ("Decisions made —
# current target": "restore overlap holes as the fidelity target... The
# no-overlap v2 mode is optional, not the default") reverted it back to
# TEMPORARY, matching the installed original's own tutorial text
# (docs/ORIGINAL_INSTALL_EVIDENCE.md: overlap sinking).

## Bontago-59o.18: RANDOM picks one of the three locked skies for every roll
## (negative included) and never the running cycle; the result round-trips and
## every peer derives the same locked id from the replicated fields.
func test_random_sky_resolves_to_a_locked_id_never_the_running_cycle() -> void:
	var seen: Dictionary = {}
	for roll: int in range(-3, MatchConfig.SKY_THEME_IDS.size() * 2):
		var config: MatchConfig = MatchConfig.new()
		config.sky_theme_mode = MatchConfig.SkyThemeMode.RANDOM
		config.resolve_sky_theme(roll)
		assert_true(MatchConfig.SKY_THEME_IDS.has(config.sky_theme_resolved), "roll %d" % roll)
		assert_false(config.is_sky_cycle_running())
		var restored: MatchConfig = MatchConfig.from_dict(config.to_dict())
		assert_eq(restored.locked_sky_id(), config.sky_theme_resolved, "the client derives the host's locked id")
		seen[config.sky_theme_resolved] = true
	assert_eq(seen.size(), MatchConfig.SKY_THEME_IDS.size(), "every locked sky is reachable by a roll")


func test_legacy_dict_gravity_is_rescaled_but_versioned_dict_is_not() -> void:
	var legacy: MatchConfig = MatchConfig.from_dict({"gravity_multiplier": 1.4})
	assert_almost_eq(legacy.gravity_multiplier, 1.0, 0.0001)
	var current: MatchConfig = MatchConfig.from_dict(MatchConfig.new().to_dict())
	assert_eq(current.gravity_multiplier, 1.0)


# --- Lobby rework: per-slot teams, per-bot difficulty (Bontago-1pi.53, P1) ----

## A resolved three-team, six-seat config (lobby numbers 1/3/4): the shape the
## host's TeamAssigner writes at Start.
func _resolved_config() -> MatchConfig:
	var config: MatchConfig = MatchConfig.new()
	config.team_mode = MatchConfig.TeamMode.TEAMS_4
	config.player_count = 6
	config.slot_team_ids = PackedInt32Array([0, 1, 0, 2, 1, 2])
	config.team_numbers = PackedInt32Array([1, 3, 4])
	return config


func test_old_dict_without_the_new_keys_keeps_the_interleave() -> void:
	# What a saved lobby / peer from before this change sends: no new keys at all.
	var old_dict: Dictionary = {
		"player_count": 6, "ai_count": 2, "ai_difficulty": MatchConfig.AiDifficulty.HARD,
		"team_mode": MatchConfig.TeamMode.TEAMS_2,
	}
	var config: MatchConfig = MatchConfig.from_dict(old_dict)
	config.sanitize()
	assert_false(config.teams_resolved())
	assert_eq(config.team_count(), 2)
	for slot: int in range(6):
		assert_eq(config.team_of_slot(slot), slot % 2, "slot %d keeps the legacy interleave" % slot)
		assert_eq(config.team_number_for(config.team_of_slot(slot)), slot % 2 + 1, "legacy label is id + 1")
	for slot: int in range(6):
		assert_eq(config.ai_difficulty_for_slot(slot), MatchConfig.AiDifficulty.HARD, "one difficulty for every bot")
	assert_eq(config.territory_colors(), config.player_colors, "legacy territory colour is player_colors[team]")


func _assert_team_arrays_dropped(config: MatchConfig, label: String) -> void:
	config.sanitize()
	assert_true(config.slot_team_ids.is_empty(), "%s: slot_team_ids dropped" % label)
	assert_true(config.team_numbers.is_empty(), "%s: team_numbers dropped" % label)
	assert_false(config.teams_resolved(), label)
	# ...and the config is back on the legacy interleave.
	assert_eq(config.team_count(), mini(config.team_pick_cap(), config.player_count) if config.teams_enabled() else config.player_count, label)


func test_sanitize_drops_inconsistent_team_arrays() -> void:
	var config: MatchConfig = _resolved_config()
	config.player_count = 5  # array covers 6 slots
	_assert_team_arrays_dropped(config, "size != player_count")

	config = _resolved_config()
	config.slot_team_ids = PackedInt32Array([0, 1, 0, 3, 1, 2])  # id 3 has no number
	_assert_team_arrays_dropped(config, "id out of range")

	config = _resolved_config()
	config.slot_team_ids = PackedInt32Array([0, 1, 0, -1, 1, 2])
	_assert_team_arrays_dropped(config, "negative id")

	config = _resolved_config()
	config.slot_team_ids = PackedInt32Array([0, 1, 0, 1, 1, 0])  # team 2 unused: ids not dense
	_assert_team_arrays_dropped(config, "unused team id")

	config = _resolved_config()
	config.team_numbers = PackedInt32Array([3, 1, 4])
	_assert_team_arrays_dropped(config, "numbers not ascending")

	config = _resolved_config()
	config.team_numbers = PackedInt32Array([1, 1, 4])
	_assert_team_arrays_dropped(config, "duplicate numbers")

	config = _resolved_config()
	config.team_numbers = PackedInt32Array([1, 3, 5])
	_assert_team_arrays_dropped(config, "number above TEAM_PICK_MAX")

	config = _resolved_config()
	config.team_numbers = PackedInt32Array([0, 3, 4])
	_assert_team_arrays_dropped(config, "number below 1")

	config = _resolved_config()
	config.team_mode = MatchConfig.TeamMode.TEAMS_3  # cap 3, but number 4 is used
	_assert_team_arrays_dropped(config, "number above the mode's cap")

	config = _resolved_config()
	config.team_mode = MatchConfig.TeamMode.OFF
	_assert_team_arrays_dropped(config, "teams off")

	config = _resolved_config()
	config.team_numbers = PackedInt32Array()
	_assert_team_arrays_dropped(config, "ids without numbers")

	config = _resolved_config()
	config.slot_team_ids = PackedInt32Array()
	_assert_team_arrays_dropped(config, "numbers without ids")


func test_from_dict_accepts_json_style_arrays() -> void:
	# The Steam lobby tee is JSON: arrays come back as Arrays of floats.
	var json: JSON = JSON.new()
	var text: String = JSON.stringify({
		"team_mode": MatchConfig.TeamMode.TEAMS_4, "player_count": 4,
		"slot_team_ids": PackedInt32Array([0, 1, 0, 1]), "team_numbers": PackedInt32Array([2, 4]),
		"slot_ai_difficulties": PackedInt32Array([1, 1, 2, 0]),
	})
	assert_eq(json.parse(text), OK)
	var parsed: Variant = json.data
	assert_true(parsed is Dictionary)
	var config: MatchConfig = MatchConfig.from_dict(parsed as Dictionary)
	config.sanitize()
	assert_eq(config.slot_team_ids, PackedInt32Array([0, 1, 0, 1]))
	assert_eq(config.team_numbers, PackedInt32Array([2, 4]))
	assert_eq(config.slot_ai_difficulties, PackedInt32Array([1, 1, 2, 0]))
	assert_eq(config.team_number_for(1), 4)
	# Plain Arrays and 64-bit packed arrays (RPC) read the same.
	var from_array: MatchConfig = MatchConfig.from_dict({"slot_team_ids": [0, 1.0, 1]})
	assert_eq(from_array.slot_team_ids, PackedInt32Array([0, 1, 1]))
	var from_int64: MatchConfig = MatchConfig.from_dict({"team_numbers": PackedInt64Array([1, 2])})
	assert_eq(from_int64.team_numbers, PackedInt32Array([1, 2]))


func test_from_dict_degrades_foreign_values_to_the_legacy_behaviour() -> void:
	var bad_values: Array[Variant] = [
		"0,1,0,1", 7, 1.5, true, {"a": 1}, [0, "1", 1], [0, null], [0, 1, 0, 1, 0, 1, 0, 1, 0], PackedStringArray(["0"]),
	]
	for bad: Variant in bad_values:
		var config: MatchConfig = MatchConfig.from_dict({
			"team_mode": MatchConfig.TeamMode.TEAMS_2, "player_count": 4,
			"slot_team_ids": bad, "team_numbers": bad, "slot_ai_difficulties": bad,
		})
		config.sanitize()
		assert_true(config.slot_team_ids.is_empty(), "slot_team_ids from %s" % str(bad))
		assert_true(config.team_numbers.is_empty(), "team_numbers from %s" % str(bad))
		assert_true(config.slot_ai_difficulties.is_empty(), "slot_ai_difficulties from %s" % str(bad))
		assert_eq(config.team_of_slot(3), 1, "still the legacy interleave")

