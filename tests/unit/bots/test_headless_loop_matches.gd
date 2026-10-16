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
