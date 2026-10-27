extends GutTest
## `godot --headless --path . -- --headless-host --bots=<n>`: the command-line entry builds a real
## networked bot match through the ordinary world build, with no human to press Start, and refuses
## to do so when Net never became the host. Observed through Match, Net, the scene tree (MainNodes)
## and the printed log lines.
##
## Same fixture shape as tests/unit/match/test_match_lifecycle.gd: the real Main scene with a tiny
## map override so round_medium.tres's collision build does not cost ~6300 cells per test.

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")

## game/main/Main.gd has no class_name (a scene root), so the instance is held through a Variant.
var _main: Variant = null
var _tiny_map: MapDef
var _capture: PrintCapture = null


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
	assert_true(Net.is_offline(), "fixture: the real Net must start offline")
	_capture = PrintCapture.start()
	_main = MAIN_SCENE.instantiate()
	_tiny_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	(_main.get_node("Field") as Field).map_def = _tiny_map
	var tiny_match_config: MatchConfig = (load("res://config/match/match_defaults.tres") as MatchConfig).duplicate(true)
	tiny_match_config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(tiny_match_config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	tiny_match_config.rng_seed = 90210
	_main.match_config = tiny_match_config
	add_child_autofree(_main)
	assert_not_null(MainNodes.main_menu(_main), "fixture: Main boots to the main menu with no command-line flags")


func after_each() -> void:
	_capture.stop()
	Net.leave()
	Match.abort_match()
	SnapshotSync.end_match()
	Match.set_process(true)
	await get_tree().process_frame
	await get_tree().process_frame


## What a real `--headless-host` command line has already done by the time Main reaches the bot
## match start: a listen server with no clients.
func _host() -> void:
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "Hostie"), OK)
	assert_eq(Net.mode(), Net.Mode.HOST)


func _bot_controller_count() -> int:
	return MainNodes.count(_main, &"BotController")


## Two frames, so queue_free()d nodes are actually gone before the next assertion.
func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func test_the_headless_bots_flow_script_loads_on_first_bot_match_only() -> void:
	var path: String = Main.HEADLESS_BOTS_FLOW_SCRIPT_PATH
	if ResourceLoader.has_cached(path):
		pending("an earlier script in this process already cached the flow script; run this script alone")
		return
	_host()
	_main._start_headless_bot_match_with_args(PackedStringArray(["--bots=2"]))
	await _settle()
	assert_true(ResourceLoader.has_cached(path), "the first bot match loads it")
	assert_eq(_bot_controller_count(), 2, "and the loaded flow built the match")



func test_bots_zero_is_a_no_op() -> void:
	_main._start_headless_bot_match_with_args(PackedStringArray([]))

	assert_eq(Match.state(), Match.State.LOBBY, "no --bots= means no match starts")
	assert_false(MainNodes.world_is_built(_main))


func test_offline_with_bots_is_refused_and_logs_an_error() -> void:
	assert_true(Net.is_offline(), "fixture: nobody is hosting")

	_main._start_headless_bot_match_with_args(PackedStringArray(["--bots=2"]))
	await _settle()

	assert_push_error("refusing to start a bot match with no host")
	assert_eq(Match.state(), Match.State.LOBBY, "no match starts without a host")
	assert_false(MainNodes.world_is_built(_main))
	assert_eq(_bot_controller_count(), 0)


func test_all_bot_match_reaches_playing_with_n_bot_slots_and_no_local_player() -> void:
	_host()
	_main._start_headless_bot_match_with_args(PackedStringArray(["--bots=4"]))
	await _settle()

	assert_eq(Match.state(), Match.State.COUNTDOWN, "start_match() always begins at COUNTDOWN")
	assert_eq(Match.slot_count(), 4, "config.player_count == bots with no --players= override")
	assert_eq(Match.config.ai_count, 4)
	for i: int in range(4):
		assert_true(Match.slot(i).is_bot, "slot %d must be a bot" % i)

	assert_eq(_bot_controller_count(), 4, "one BotController per bot slot")
	assert_null(MainNodes.local_player(_main), "an all-bot match has no local human slot to bind a LocalPlayer to")
	assert_true(MainNodes.world_is_built(_main), "the ordinary networked world build ran")

	# Advance past the countdown so the match is actually PLAYING, not merely counting down.
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)
	assert_eq(Match.state(), Match.State.PLAYING)


func test_players_override_leaves_idle_human_seats_and_still_builds_a_local_player() -> void:
	_host()
	_main._start_headless_bot_match_with_args(PackedStringArray(["--bots=2", "--players=3"]))
	await _settle()

	assert_eq(Match.slot_count(), 3)
	assert_eq(Match.config.ai_count, 2)
	assert_false(Match.slot(0).is_bot, "slot 0 stays a human seat when --players= raises the total")
	assert_true(Match.slot(1).is_bot)
	assert_true(Match.slot(2).is_bot)
	assert_eq(_bot_controller_count(), 2)
	assert_not_null(MainNodes.local_player(_main), "a human seat exists, so LocalPlayer binds Net.local_slot() (0) as usual")


func test_a_headless_bot_match_skips_the_countdown_and_is_not_a_sandbox() -> void:
	_host()
	_main._start_headless_bot_match_with_args(PackedStringArray(["--bots=2"]))
	await _settle()

	assert_false(Match.config.sandbox, "the real feed/territory/win loop runs")
	assert_eq(Match.config.countdown_seconds, 0.0, "no human to wait for")


func test_the_match_ends_with_its_world_and_frees_the_bot_controllers() -> void:
	_host()
	_main._start_headless_bot_match_with_args(PackedStringArray(["--bots=4"]))
	await _settle()
	var bots: Array = []
	for child: Node in _main.find_children("*", "BotController", true, false):
		bots.append(child)
	assert_eq(bots.size(), 4, "fixture: 4 bots exist before teardown")

	Match.abort_match()
	await _settle()

	assert_eq(_bot_controller_count(), 0, "no BotController remains after teardown")
	assert_false(MainNodes.world_is_built(_main), "the world is torn down with the match")
	# Untyped `Variant` on purpose: a freed instance cannot be assigned to a typed `Node` loop variable.
	for bot: Variant in bots:
		assert_false(is_instance_valid(bot), "each bot must actually be freed, not merely detached")


# --- HEADLESS_BOTS / HEADLESS_MATCH output -------------------------------------


func test_a_single_match_prints_its_summary_on_end_without_loop_matches() -> void:
	_host()
	_main._start_headless_bot_match_with_args(PackedStringArray(["--bots=2", "--mode=elimination", "--round-timer=1"]))
	await _settle()
	assert_eq(_capture.lines_starting_with("HEADLESS_MATCH ").size(), 0, "nothing is printed while the match runs")
	var tick: float = 1.0 / Engine.physics_ticks_per_second
	for _i: int in range(20):
		if Match.state() != Match.State.PLAYING:
			Match._process(tick)
	assert_eq(Match.state(), Match.State.PLAYING)
	Match._process(Match.config.round_timer_minutes * 60.0 + 1.0)
	assert_eq(Match.state(), Match.State.END)

	var lines: PackedStringArray = _capture.lines_starting_with("HEADLESS_MATCH ")
	assert_eq(lines.size(), 1)
	assert_true(lines[0].begins_with("HEADLESS_MATCH index=1 "))
	assert_true(lines[0].contains(" seed=90210 "))
	assert_true(lines[0].contains(" teams=0,1 "), "one team id per slot")
