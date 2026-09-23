extends GutTest
## `godot --headless --path . -- --headless-host --bots=<n>` (docs/M5_PLAN.md
## P5, Bontago-d5c.6): the cmdline parsers (`_bots_arg()`/`_seconds_arg()`)
## and `_start_headless_bot_match_with_args()`'s own direct
## register_world()/start_match() build, which reuses the ordinary networked
## `_build_match_world()` (Events.match_state_changed is already connected by
## the time `_ready()` reaches this call -- see that function's own doc) so
## its bot-controller wiring serves this path too.
##
## Same fixture shape as tests/unit/test_match_lifecycle.gd (the real Main
## scene, a tiny map override so round_medium.tres's own collision build
## doesn't pay its ~6300-cell cost per test), including that file's own
## `_host()` (a real Net.host_game() with an incrementing port, no clients):
## unlike this file's original version, `_start_headless_bot_match_with_args()`
## now refuses to build a match unless Net actually became the HOST (review
## finding 1, Bontago-d5c.6) -- exactly what a real `--headless-host --bots=N`
## command line has already done, via Net.apply_command_line(), by the time
## `_ready()` reaches that call. `test_offline_with_bots_is_refused_and_logs_
## an_error()` below covers the case this guards against: --headless-host's
## own host_game() call failing to bind and leaving Net at OFFLINE.

const MAIN_SCENE: PackedScene = preload("res://game/Main.tscn")

## game/Main.gd has no class_name (a scene root, not a type other code
## names -- see test_match_lifecycle.gd's matching comment), so the instance
## is held through a Variant-typed reference.
var _main: Variant = null

var _tiny_map: MapDef

## Well clear of test_net_session.gd's 47800+ and test_match_lifecycle.gd's
## 47900+ ranges (this file's own comment on those files), incrementing per
## test the same way, so a port the OS has not released yet can never
## collide with the next one.
static var _next_port: int = 48300


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
	assert_true(Net.is_offline(), "fixture: the real Net must start offline")
	_main = MAIN_SCENE.instantiate()
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	(_main.get_node("Field") as Field).map_def = _tiny_map
	var tiny_match_config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true)
	tiny_match_config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(tiny_match_config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	tiny_match_config.rng_seed = 90210
	_main.match_config = tiny_match_config
	add_child_autofree(_main)
	assert_not_null(_main._main_menu, "fixture: Main boots to the main menu with no command-line flags")


func after_each() -> void:
	Net.leave()
	Match.abort_match()
	SnapshotSync.end_match()
	Match.set_process(true)
	await get_tree().process_frame
	await get_tree().process_frame


func _take_port() -> int:
	var port: int = _next_port
	_next_port += 1
	return port


## What a real `--headless-host --bots=<n>` command line has already done by
## the time `_ready()` reaches `_start_headless_bot_match_with_args()`
## (Net.apply_command_line() -> host_game()) -- test_match_lifecycle.gd's own
## `_host()` doc: "opens a listen server with no clients", so nothing here
## touches the network beyond binding a port.
func _host() -> void:
	assert_eq(Net.host_game(_take_port(), "Hostie"), OK)
	assert_true(_main._net_is_hosting())


func _bot_controller_count() -> int:
	var total: int = 0
	for child: Node in _main.get_children():
		if child is BotController:
			total += 1
	return total


## Two frames, so queue_free()d nodes are actually gone before the next
## assertion (test_match_lifecycle.gd's own `_settle()` doc: "a Lobby or
## MainMenu awaiting its free still holds its Events connections for that
## frame").
func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


# --- _bots_arg / _seconds_arg parsing -----------------------------------------

func test_bots_arg_parses_the_flag() -> void:
	assert_eq(_main._bots_arg(PackedStringArray(["--bots=8"])), 8)


func test_bots_arg_defaults_to_zero_with_no_flag() -> void:
	assert_eq(_main._bots_arg(PackedStringArray([])), 0, "feature off by default")
	assert_eq(_main._bots_arg(PackedStringArray(["--headless-host"])), 0)


func test_seconds_arg_parses_the_flag() -> void:
	assert_eq(_main._seconds_arg(PackedStringArray(["--seconds=30"])), 30.0)


func test_seconds_arg_defaults_to_zero_unbounded_with_no_flag() -> void:
	assert_eq(_main._seconds_arg(PackedStringArray([])), 0.0)


# --- _start_headless_bot_match_with_args --------------------------------------

func test_bots_zero_is_a_no_op() -> void:
	_main._start_headless_bot_match_with_args(PackedStringArray([]))

	assert_eq(Match.state(), Match.State.LOBBY, "no --bots= means no match starts")
	assert_false(_main._world_built)


# --- Review finding 1: refuse a bot match with nobody actually hosting -------

func test_offline_with_bots_is_refused_and_logs_an_error() -> void:
	assert_true(Net.is_offline(), "fixture: no _host() call in this test -- host_game() never ran")
	assert_false(_main._net_is_hosting())

	_main._start_headless_bot_match_with_args(PackedStringArray(["--bots=4"]))
	await _settle()

	assert_eq(Match.state(), Match.State.LOBBY, "refused: Net never became the host")
	assert_false(_main._world_built)
	assert_eq(_bot_controller_count(), 0, "no bots are spawned when the match never starts")
	assert_push_error("never became the host", "refusal must be logged, not silent")


func test_net_is_hosting_reflects_net_mode() -> void:
	assert_false(_main._net_is_hosting(), "offline is not the same as actually hosting")
	_host()
	assert_true(_main._net_is_hosting())


func test_all_bot_match_reaches_playing_with_n_bot_slots_and_no_hot_seat() -> void:
	_host()
	_main._start_headless_bot_match_with_args(PackedStringArray(["--bots=4"]))
	await _settle()

	assert_eq(Match.state(), Match.State.COUNTDOWN, "start_match() always begins at COUNTDOWN")
	assert_eq(Match.slot_count(), 4, "config.player_count == bots with no --players= override")
	assert_eq(Match.config.ai_count, 4)
	for i: int in range(4):
		assert_true(Match.slot(i).is_bot, "slot %d must be a bot" % i)

	assert_eq(_bot_controller_count(), 4, "one BotController per bot slot")
	assert_null(_main._hot_seat, "an all-bot match has no local human slot to bind a HotSeat/PlayerController to")

	# Advance past the countdown so the match is actually PLAYING, not merely
	# counting down (the literal "8-bot match reaches PLAYING" acceptance
	# shape, scaled down to 4 for a fast unit test).
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)
	assert_eq(Match.state(), Match.State.PLAYING)


func test_players_override_leaves_idle_human_seats_and_still_builds_a_hot_seat() -> void:
	_host()
	_main._start_headless_bot_match_with_args(PackedStringArray(["--bots=2", "--players=3"]))
	await _settle()

	assert_eq(Match.slot_count(), 3)
	assert_eq(Match.config.ai_count, 2)
	assert_false(Match.slot(0).is_bot, "slot 0 stays a human seat when --players= raises the total")
	assert_true(Match.slot(1).is_bot)
	assert_true(Match.slot(2).is_bot)
	assert_eq(_bot_controller_count(), 2)
	assert_not_null(_main._hot_seat, "a human seat exists, so HotSeat binds Net.local_slot() (0) as usual")


func test_end_match_world_frees_the_bot_controllers() -> void:
	_host()
	_main._start_headless_bot_match_with_args(PackedStringArray(["--bots=4"]))
	await _settle()
	var bots: Array = []
	for child: Node in _main.get_children():
		if child is BotController:
			bots.append(child)
	assert_eq(bots.size(), 4, "fixture: 4 bots exist before teardown")

	_main._end_match_world()
	await _settle()

	assert_eq(_bot_controller_count(), 0, "no BotController remains after teardown")
	# Untyped `Variant` on purpose: a freed instance can no longer be assigned
	# to a typed `Node` loop variable (a bare "Trying to assign invalid
	# previously freed instance" engine error, not a GDScript exception) --
	# is_instance_valid() itself works fine on the raw Variant either way.
	for bot: Variant in bots:
		assert_false(is_instance_valid(bot), "each bot must actually be freed, not merely detached")


# --- Review finding 2: HEADLESS_BOTS progress line ----------------------------

func test_headless_bots_diagnostics_counts_placements_and_formats_lines() -> void:
	_host()
	_main._start_headless_bot_match_with_args(PackedStringArray(["--bots=4"]))
	await _settle()

	assert_eq(_main._headless_bots_placements, 0, "fixture: no blocks placed yet")
	Events.block_placed.emit(null, &"cube")
	Events.block_placed.emit(null, &"cube")
	assert_eq(_main._headless_bots_placements, 2, "each Events.block_placed increments the counter")

	var periodic: String = _main._headless_bots_periodic_line()
	assert_true(periodic.begins_with("HEADLESS_BOTS t="), "periodic line: %s" % periodic)
	assert_true(periodic.contains(" state=%s " % _main._headless_bots_state_name()), "carries Match's own state name: %s" % periodic)
	assert_true(periodic.ends_with("placements=2"), "periodic line: %s" % periodic)

	var done: String = _main._headless_bots_done_line()
	assert_true(done.begins_with("HEADLESS_BOTS done t="), "done line: %s" % done)
	assert_true(done.ends_with("placements=2"), "done line: %s" % done)


func test_end_match_world_stops_headless_bots_diagnostics() -> void:
	_host()
	_main._start_headless_bot_match_with_args(PackedStringArray(["--bots=4"]))
	await _settle()

	_main._end_match_world()
	await _settle()

	assert_false(
		Events.block_placed.is_connected(_main._on_headless_bots_block_placed),
		"teardown disconnects the placements counter"
	)
	assert_null(_main._headless_bots_report_timer, "teardown frees the report timer")
