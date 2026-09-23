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
## doesn't pay its ~6300-cell cost per test) -- offline throughout, since
## this path (unlike that file's own `_host()`/`_start()`) never needs a real
## ENet session: register_world()/start_match() work exactly as they do for
## --hot-seat/--sandbox while Net stays offline (Net.is_host()'s own
## contract: "True on the host and offline").

const MAIN_SCENE: PackedScene = preload("res://game/Main.tscn")

## game/Main.gd has no class_name (a scene root, not a type other code
## names -- see test_match_lifecycle.gd's matching comment), so the instance
## is held through a Variant-typed reference.
var _main: Variant = null

var _tiny_map: MapDef


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


func test_all_bot_match_reaches_playing_with_n_bot_slots_and_no_hot_seat() -> void:
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
