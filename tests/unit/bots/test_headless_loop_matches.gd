extends GutTest
## `--loop-matches` restarts a headless bot match on END with a fresh seed and prints one
## HEADLESS_MATCH summary line per finished match. Observed through Match, Events, the scene tree and
## the printed log lines; a match is ended the way a real one ends (an Elimination round timer
## running out).

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")
const FIXED_SEED: int = 90210
const BASE_ARGS: Array[String] = ["--bots=2", "--mode=elimination", "--round-timer=1"]
const MATCH_TAG: String = "HEADLESS_MATCH "

var _main: Variant = null
var _capture: PrintCapture = null


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
	_capture = PrintCapture.start()
	_main = _new_main(FIXED_SEED)


func after_each() -> void:
	_capture.stop()
	Net.leave()
	Match.abort_match()
	SnapshotSync.end_match()
	Match.set_process(true)
	await get_tree().process_frame
	await get_tree().process_frame


func _new_main(rng_seed: int) -> Node:
	var main: Node = MAIN_SCENE.instantiate()
	var tiny_map: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	tiny_map.field_radius = 20.0
	(main.get_node("Field") as Field).map_def = tiny_map
	var cfg: MatchConfig = (load("res://config/match/match_defaults.tres") as MatchConfig).duplicate(true)
	cfg.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(cfg as TinyMapMatchConfig).set_tiny_map(tiny_map)
	cfg.rng_seed = rng_seed
	main.match_config = cfg
	add_child_autofree(main)
	return main


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _start(extra: Array[String] = []) -> void:
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "Hostie"), OK)
	_main._start_headless_bot_match_with_args(PackedStringArray(BASE_ARGS + extra))
	await _settle()


## Ends the running match through its round timer (no private Match state touched).
func _play_to_end() -> void:
	var tick: float = 1.0 / Engine.physics_ticks_per_second
	var guard: int = 0
	while Match.state() != Match.State.PLAYING and guard < 20:
		Match._process(tick)
		guard += 1
	assert_eq(Match.state(), Match.State.PLAYING, "fixture: the bot match reaches PLAYING")
	Match._process(Match.config.round_timer_minutes * 60.0 + 1.0)
	assert_eq(Match.state(), Match.State.END, "fixture: the round timer ends the match")


func _summary_lines() -> PackedStringArray:
	return _capture.lines_starting_with(MATCH_TAG)


func _field(line: String, key: String) -> String:
	for token: String in line.split(" "):
		if token.begins_with(key + "="):
			return token.substr(key.length() + 1)
	return ""


func _count(type_name: StringName) -> int:
	return MainNodes.count(_main, type_name)


## Starts a loop from the current Main and returns each of `matches` matches' seeds as the game ran
## them (Match.config.rng_seed while that match is running).
func _loop_seeds(matches: int, extra: Array[String]) -> Array[int]:
	var seeds: Array[int] = []
	await _start(extra)
	for i: int in range(matches):
		seeds.append(Match.config.rng_seed)
		if i < matches - 1:
			_play_to_end()
			await _settle()
	return seeds


## A fresh Main and session, for a second run in the same test.
func _reset_session() -> void:
	Net.leave()
	Match.abort_match()
	SnapshotSync.end_match()
	_main.queue_free()
	await _settle()
	_main = _new_main(FIXED_SEED)


func test_end_restarts_with_fresh_seed_and_clean_teardown() -> void:
	await _start(["--loop-matches"])
	assert_eq(Match.config.rng_seed, FIXED_SEED, "match 1 keeps the configured seed")
	var bots_before: int = _count(&"BotController")
	var timers_before: int = _count(&"Timer")
	assert_eq(bots_before, 2)
	var orphans_before: int = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) as int
	Events.block_placed.emit(null, &"x")

	_play_to_end()
	await _settle()

	assert_ne(Match.state(), Match.State.END, "a second match started")
	assert_ne(Match.state(), Match.State.LOBBY)
	assert_gt(Match.config.rng_seed, 0, "match 2 draws a fresh positive seed")
	assert_ne(Match.config.rng_seed, FIXED_SEED, "fresh seed for match 2")
	assert_eq(_count(&"BotController"), bots_before, "old bots freed, exactly one new set")
	assert_eq(_count(&"Timer"), timers_before, "the restart neither leaks nor doubles a report timer")
	assert_eq(
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) as int, orphans_before,
		"restart leaves no orphan nodes"
	)
	var lines: PackedStringArray = _summary_lines()
	assert_eq(lines.size(), 1, "one HEADLESS_MATCH line for the one finished match")
	assert_eq(_field(lines[0], "index"), "1")
	assert_eq(_field(lines[0], "seed"), str(FIXED_SEED))
	assert_gte(_field(lines[0], "placements").to_int(), 1, "the block placed during match 1 is counted")


## Match 1 prints its own count `base`; match 2 gets 3 more placements and must print exactly
## `base + 3` (a count carried over from match 1 or a doubled listener would differ).
func test_the_next_match_line_counts_its_own_placements_and_elapsed_time() -> void:
	await _start(["--loop-matches"])
	_play_to_end()
	await _settle()
	for _i: int in range(3):
		Events.block_placed.emit(null, &"x")
	_play_to_end()
	await _settle()
	var lines: PackedStringArray = _summary_lines()
	assert_eq(lines.size(), 2)
	assert_eq(_field(lines[1], "index"), "2", "the second match is numbered 2")
	assert_eq(_field(lines[1], "placements").to_int(), _field(lines[0], "placements").to_int() + 3, "placements are counted per match, once each")
	assert_lt(_field(lines[1], "duration").to_float(), 5.0, "elapsed time reset for match 2")


func test_without_flag_end_does_not_restart_and_still_logs_the_match() -> void:
	await _start()
	_play_to_end()
	await _settle()
	assert_eq(Match.state(), Match.State.END, "no restart without --loop-matches")
	assert_eq(Match.config.rng_seed, FIXED_SEED)
	var lines: PackedStringArray = _summary_lines()
	assert_eq(lines.size(), 1, "a single match still prints its HEADLESS_MATCH line on END")
	assert_eq(_field(lines[0], "index"), "1")


# --- loop seeds, pinned through behaviour -------------------------------------


func test_a_negative_configured_seed_becomes_a_positive_one_in_a_loop() -> void:
	_main.queue_free()
	await _settle()
	_main = _new_main(-1)
	await _start(["--loop-matches"])
	assert_gt(Match.config.rng_seed, 0)


func test_with_match_seed_the_loop_seeds_are_deterministic_and_distinct() -> void:
	var first: Array[int] = await _loop_seeds(3, ["--loop-matches", "--match-seed=77"])
	await _reset_session()
	var second: Array[int] = await _loop_seeds(3, ["--loop-matches", "--match-seed=77"])
	assert_eq(first[0], 77, "match 1 uses the given seed")
	assert_eq(first, second, "the same --match-seed gives the same seed for every loop match")
	assert_ne(first[1], first[0], "match 2 differs from match 1")
	assert_ne(first[2], first[1], "match 3 differs from match 2")
	assert_ne(first[2], first[0])


func test_a_different_match_seed_gives_different_later_seeds() -> void:
	var a: Array[int] = await _loop_seeds(2, ["--loop-matches", "--match-seed=77"])
	await _reset_session()
	var b: Array[int] = await _loop_seeds(2, ["--loop-matches", "--match-seed=78"])
	assert_eq(b[0], 78)
	assert_ne(a[1], b[1], "the derived seed depends on the base seed")


func test_without_match_seed_later_loop_seeds_are_drawn_fresh() -> void:
	var a: Array[int] = await _loop_seeds(2, ["--loop-matches"])
	await _reset_session()
	var b: Array[int] = await _loop_seeds(2, ["--loop-matches"])
	assert_eq(a[0], FIXED_SEED)
	assert_gt(a[1], 0)
	assert_gt(b[1], 0)
	assert_ne(a[1], b[1], "two runs draw different seeds for match 2")


func test_the_logged_seed_is_the_one_each_match_ran_with() -> void:
	var seeds: Array[int] = await _loop_seeds(2, ["--loop-matches", "--match-seed=77"])
	_play_to_end()
	await _settle()
	var lines: PackedStringArray = _summary_lines()
	assert_eq(lines.size(), 2)
	assert_eq(_field(lines[0], "seed"), str(seeds[0]))
	assert_eq(_field(lines[1], "seed"), str(seeds[1]))


# --- the summary line ---------------------------------------------------------


func _first_summary_line() -> String:
	_play_to_end()
	var lines: PackedStringArray = _summary_lines()
	assert_eq(lines.size(), 1)
	return lines[0] if lines.size() == 1 else ""


## The ` appetite=slot:value,...` token lists every bot once, after `stats=`; a finished match has no timeout token.
func test_summary_line_reports_each_bots_appetite_after_the_stats_token() -> void:
	await _start()
	var line: String = _first_summary_line()
	assert_gt(line.find(" appetite="), line.find(" stats="), "appetite comes after stats")
	var entries: PackedStringArray = _field(line, "appetite").split(",")
	assert_eq(entries.size(), 2, "one entry per bot")
	var slots: Dictionary = {}
	for entry: String in entries:
		var parts: PackedStringArray = entry.split(":")
		assert_eq(parts.size(), 2, "entry '%s' is slot:value" % entry)
		if parts.size() == 2:
			assert_true(parts[1].is_valid_float())
			assert_between(parts[1].to_float(), 0.0, 1.0)
			slots[parts[0].to_int()] = true
	assert_eq(slots.size(), 2, "two different bot slots")
	assert_false(line.contains("timeout=1"), "no timeout token on a finished match")


## tools/bot_h2h.py splits the stats token on "/" into exactly four fields; the appetite token must not leak into it.
func test_the_appetite_token_stays_out_of_the_stats_token() -> void:
	await _start()
	var line: String = _first_summary_line()
	for entry: String in _field(line, "stats").split(","):
		assert_eq(entry.split(":")[1].split("/").size(), 4, "stats entry '%s' keeps four fields" % entry)
