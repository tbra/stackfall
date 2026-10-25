extends GutTest
## `--loop-matches` restarts a headless bot match on END with a
## fresh seed and prints one HEADLESS_MATCH summary line per finished match.

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")

var _main: Variant = null


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
	_main = MAIN_SCENE.instantiate()
	var tiny_map: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	tiny_map.field_radius = 20.0
	(_main.get_node("Field") as Field).map_def = tiny_map
	var cfg: MatchConfig = (load("res://config/match/match_defaults.tres") as MatchConfig).duplicate(true)
	cfg.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(cfg as TinyMapMatchConfig).set_tiny_map(tiny_map)
	cfg.rng_seed = 90210
	_main.match_config = cfg
	add_child_autofree(_main)


func after_each() -> void:
	Net.leave()
	Match.abort_match()
	SnapshotSync.end_match()
	Match.set_process(true)
	await get_tree().process_frame
	await get_tree().process_frame


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _bot_count() -> int:
	var total: int = 0
	for child: Node in _main.get_children():
		if child is BotController:
			total += 1
	return total


func test_end_restarts_with_fresh_seed_and_clean_teardown() -> void:
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "Hostie"), OK)
	_main._start_headless_bot_match_with_args(PackedStringArray(["--bots=2", "--loop-matches"]))
	await _settle()
	assert_eq(_main._headless_loop_index, 1)
	assert_eq(_main._headless_loop_seed, 90210, "match 1 keeps the configured seed")
	Events.block_placed.emit(null, &"x")
	assert_eq(_main._headless_bots_placements, 1)
	var orphans_before: int = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) as int

	Match._lifecycle._finish_match(0)
	assert_true(_main._headless_loop_restart_pending, "END schedules a restart")
	assert_true((_main._headless_bots_flow_port().call(&"_headless_match_summary_line") as String).begins_with("HEADLESS_MATCH index=1 "))
	await _settle()

	assert_eq(_main._headless_loop_index, 2, "a second match started")
	assert_ne(_main._headless_loop_seed, 90210, "fresh seed for match 2")
	assert_ne(Match.state(), Match.State.END)
	assert_ne(Match.state(), Match.State.LOBBY)
	assert_eq(_bot_count(), 2, "old bots freed, exactly one new set")
	var connections: int = 0
	for c: Dictionary in Events.block_placed.get_connections():
		if (c["callable"] as Callable).get_object() == _main:
			connections += 1
	assert_eq(connections, 1, "one block_placed connection after restart")
	var timers: int = 0
	for child: Node in _main.get_children():
		if child is Timer and not child.is_queued_for_deletion():
			timers += 1
	assert_eq(timers, 1, "exactly one report timer")
	assert_eq(_main._headless_bots_placements, 0, "placements reset")
	assert_lt(_main._headless_bots_flow_port().call(&"_headless_bots_elapsed_s"), 5.0, "elapsed reset")
	assert_eq(
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) as int, orphans_before,
		"restart leaves no orphan nodes"
	)


func test_without_flag_end_does_not_restart() -> void:
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "Hostie"), OK)
	_main._start_headless_bot_match_with_args(PackedStringArray(["--bots=2"]))
	await _settle()
	Match._lifecycle._finish_match(0)
	await _settle()
	assert_eq(Match.state(), Match.State.END)
	assert_eq(_main._headless_loop_index, 1)


func _summary_line(timed_out: bool) -> String:
	return _main._headless_bots_flow_port().call(&"_headless_match_summary_line", timed_out) as String


## The ` appetite=slot:value,...` token lists every bot once, after `stats=` and before the optional ` timeout=1`.
func test_summary_line_reports_each_bots_appetite_before_the_timeout_token() -> void:
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "Hostie"), OK)
	_main._start_headless_bot_match_with_args(PackedStringArray(["--bots=2"]))
	await _settle()
	var line: String = _summary_line(false)
	var at: int = line.find(" appetite=")
	assert_gt(at, line.find(" stats="), "appetite comes after stats")
	var entries: PackedStringArray = line.substr(at + " appetite=".length()).split(" ")[0].split(",")
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

	var timed: String = _summary_line(true)
	assert_true(timed.ends_with(" timeout=1"))
	assert_lt(timed.find(" appetite="), timed.find(" timeout=1"), "appetite precedes timeout=1")
	assert_gt(timed.find(" appetite="), 0)


## tools/bot_h2h.py splits the stats token on "/" into exactly four fields; the new token must not leak into it.
func test_the_appetite_token_stays_out_of_the_stats_token() -> void:
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "Hostie"), OK)
	_main._start_headless_bot_match_with_args(PackedStringArray(["--bots=2"]))
	await _settle()
	var line: String = _summary_line(false)
	var stats: String = line.substr(line.find(" stats=") + " stats=".length()).split(" ")[0]
	for entry: String in stats.split(","):
		assert_eq(entry.split(":")[1].split("/").size(), 4, "stats entry '%s' keeps four fields" % entry)
