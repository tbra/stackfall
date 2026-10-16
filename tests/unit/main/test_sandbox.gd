extends GutTest

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")

## game/main/Main.gd has no class_name (a scene root, not a type other code
## names -- see tests/unit/match/test_match_lifecycle.gd's matching comment), so
## the instance is held through a Variant-typed reference.
var _main: Variant = null

## DECISION: see test_match_flow.gd's own `_tiny_map` comment.
## Main.gd's `_build_sandbox_config()` (game/main/Main.gd) duplicates its own
## `match_config` export -- normally the shared round_medium.tres-backed
## match_defaults.tres -- so it, not this file's own code, is what has to
## carry the tiny map: `_main.match_config` is overridden below, the same way
## `$Field.map_def` is, both before Main ever enters the tree.
var _tiny_map: MapDef


func before_each() -> void:
	# Match ticks on real frames; these tests drive _process() by hand where a
	# state must advance, so automatic processing is off for the duration
	# (same fixture as test_match_flow.gd/test_match_lifecycle.gd).
	Match.set_process(false)
	Match.abort_match()
	assert_true(Net.is_offline(), "fixture: the real Net must start offline")
	_main = MAIN_SCENE.instantiate()
	_tiny_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	(_main.get_node("Field") as Field).map_def = _tiny_map
	var tiny_match_config: MatchConfig = (load("res://config/match/match_defaults.tres") as MatchConfig).duplicate(true)
	tiny_match_config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(tiny_match_config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	tiny_match_config.rng_seed = 4242
	_main.match_config = tiny_match_config
	add_child_autofree(_main)
	assert_not_null(_main._main_menu, "fixture: Main boots to the main menu with no command-line flags")


func after_each() -> void:
	# several sandbox_force_special tests below install a
	# forced Callable via Match.set_special_drawer() (game/sandbox/Sandbox.gd's
	# force_special_by_id()); Match._gifts.reset() (run by abort_match() right
	# below) deliberately leaves `_special_drawer` untouched -- it is an
	# injectable dependency, not per-match state (see that function's own
	# comment) -- and Match is a singleton that outlives this script. Without
	# this, a forced drawer left installed here would leak into whichever
	# test file's Match._gifts the test runner happens to load next in the
	# same process (see test_gift_claim.gd's matching after_each() cleanup).
	Match._gifts.set_special_drawer(Match._gifts._default_special_drawer)
	Match.abort_match()
	SnapshotSync.end_match()
	Match.set_process(true)
	await get_tree().process_frame
	await get_tree().process_frame
	MatchTestReset.clear_world()


func _run_countdown() -> void:
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)


## Bypasses OS.get_cmdline_user_args() (there is no setter to fake it with —
## see game/main/Main.gd's own DECISION on _start_sandbox_match_with_args()) with
## a manufactured argument list, the same seam autoload/Net.gd's
## _apply_command_line_args() uses for the same reason.
func _start_sandbox(player_count: int) -> void:
	_main._sandbox_flow_port().call(&"start_sandbox_match_with_args", PackedStringArray(["sandbox", "players=%d" % player_count]))


func _key_press(keycode: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.device = -1
	event.physical_keycode = keycode
	event.pressed = true
	return event


func test_leaving_a_sandbox_via_the_pause_menu_clears_world_built_and_the_sandbox() -> void:
	_main.start_sandbox_from_menu()
	_run_countdown()
	assert_eq(
		get_tree().get_nodes_in_group(GhostPreview.LOCAL_HELD_GROUP).size(), 1,
		"fixture: exactly one local-held ghost while the sandbox is live"
	)

	_main._on_pause_leave_requested()
	await get_tree().process_frame

	assert_null(_main._hot_seat, "leaving a sandbox must never leave a HotSeat behind")
	assert_eq(
		get_tree().get_nodes_in_group(GhostPreview.LOCAL_HELD_GROUP).size(), 0,
		"leaving a sandbox must free its PlayerController/GhostPreview subtree"
	)
	assert_false(
		_main._world_built,
		"_world_built must be cleared so the next real match's _build_match_world() actually runs"
	)
	assert_null(_main._sandbox, "the sandbox instance itself must be freed and nulled")
	assert_not_null(_main._main_menu, "leaving must show the main menu")

	# A fresh sandbox afterward must still behave exactly as a first one does
	# -- never a duplicate (or missing) HotSeat/ghost left over from the one
	# just freed above.
	_main.start_sandbox_from_menu()
	_run_countdown()

	assert_eq(
		get_tree().get_nodes_in_group(GhostPreview.LOCAL_HELD_GROUP).size(), 1,
		"a fresh sandbox after leaving must still control exactly one local-held block"
	)
	assert_null(_main._hot_seat, "a fresh sandbox must still never build a HotSeat-driven world")


# --- Flag routing / world build ----------------------------------------------

func test_sandbox_flag_builds_an_offline_world_with_n_slots() -> void:
	_start_sandbox(3)

	assert_true(Net.is_offline(), "sandbox never touches Net")
	assert_eq(Match.slot_count(), 3)
	assert_true(Match.config.sandbox, "the sandbox config flag is set")
	assert_false(Match.config.hot_seat, "sandbox is real-time, not turn-based")
	assert_eq(Match.config.ai_count, 0)
	assert_not_null(_main._sandbox, "Main built a Sandbox instance")
	assert_true(_main._sandbox is Sandbox)
	assert_not_null(_main._debug_overlay, "F3's net debug overlay is available offline too")
	assert_eq(_main._field._home_flags.size(), 3, "one home flag per sandbox slot")


func test_sandbox_never_reaches_the_lobby() -> void:
	_start_sandbox(2)
	assert_null(_main._lobby, "sandbox never opens a lobby (game/main/Main.gd's early return, like --hot-seat)")
	assert_true(Net.is_offline(), "sandbox never calls Net.host_game()/join_game()")


# --- sandbox_next_slot: the acting-slot seam ---------------------------------

func test_sandbox_next_slot_cycles_the_acting_slot_and_wraps() -> void:
	_start_sandbox(3)
	_run_countdown()
	var sandbox: Sandbox = _main._sandbox
	assert_eq(sandbox.active_slot(), 0, "Match._begin_playing() seeds slot 0 first")
	assert_eq(sandbox.controller()._active_slot, 0)

	var event: InputEventKey = _key_press(KEY_TAB)
	assert_true(event.is_action_pressed(&"sandbox_next_slot"), "Tab should map to sandbox_next_slot")

	sandbox._unhandled_input(event)
	assert_eq(sandbox.active_slot(), 1)
	assert_eq(sandbox.controller()._active_slot, 1, "PlayerController.set_sandbox_slot() actually moved the acting slot")

	sandbox._unhandled_input(event)
	sandbox._unhandled_input(event)
	assert_eq(sandbox.active_slot(), 0, "cycling 3 players wraps back to slot 0")


func test_sandbox_timer_is_disabled_by_default_so_feed_time_left_never_moves() -> void:
	_start_sandbox(2)
	_run_countdown()
	assert_false(Match.feed_timer_enabled(), "sandbox starts with the feed timer paused")
	var before: float = Match.feed_time_left(0)

	watch_signals(Events)
	for _i: int in range(int(MatchConfig.BLOCK_TIMER_MAX * Engine.physics_ticks_per_second) + 10):
		Match._process(1.0 / Engine.physics_ticks_per_second)

	assert_eq(Match.feed_time_left(0), before, "a paused timer must not decrement")
	assert_signal_not_emitted(Events, "feed_timer_expired")


## spec 1.4 "[ORIGINAL target]" cadence: with the feed timer
## paused -- sandbox's default, "unlimited blocks" -- placements must never
## lock, or a tester could place one block and then be stuck aiming a piece
## it can never release (nothing would ever count the interval down to
## unlock it, since _tick_feed() returns immediately while the timer is
## disabled). Several placements in a row, with no frames between them, must
## all succeed exactly as M2's original feed always allowed.
func test_placements_never_lock_while_the_feed_timer_is_paused() -> void:
	_start_sandbox(2)
	_run_countdown()
	assert_false(Match.feed_timer_enabled(), "fixture: sandbox starts paused")

	for _i: int in range(3):
		var reason: StringName = Match.request_place(0, Match.default_ghost_origin(0), 0, Quaternion.IDENTITY, false)
		assert_eq(reason, PlacementRules.REASON_OK)
		assert_false(Match.is_release_locked(0), "no lock while the timer is paused")
		assert_not_null(Match.held_shape(0), "the next piece is issued immediately every time")

	assert_eq(Match.registry().all_blocks().size(), 3, "every release spawned a block")


func test_sandbox_reset_field_clears_blocks_and_rebuilds_for_the_same_config() -> void:
	_start_sandbox(2)
	_run_countdown()
	var sandbox: Sandbox = _main._sandbox

	var reason: StringName = Match.request_place(0, Match.default_ghost_origin(0), 0, Quaternion.IDENTITY, false)
	assert_eq(reason, PlacementRules.REASON_OK, "fixture: a block actually lands before the reset")
	assert_gt(Match.registry().all_blocks().size(), 0)
	sandbox._cycle_active_slot()
	assert_eq(sandbox.active_slot(), 1, "fixture: move off slot 0 so the reset's re-seed is visible")

	var event: InputEventKey = _key_press(KEY_F5)
	assert_true(event.is_action_pressed(&"sandbox_reset_field"), "F5 should map to sandbox_reset_field")
	sandbox._unhandled_input(event)

	assert_eq(Match.registry().all_blocks().size(), 0, "a freshly reset match has spawned nothing yet")
	assert_eq(Match.slot_count(), 2, "the same config's player count survives the reset")
	assert_eq(sandbox.active_slot(), 0, "reset re-seeds the active slot")
	assert_eq(_main._field._home_flags.size(), 2, "flags are rebuilt for the same config")
	assert_not_null(Match.raster(), "territory is rebuilt")


## config/gifts/specials/ includes the original roster and the enabled remake gifts;
## SpecialDef.load_selectable_specials() sorts by id and leaves out disabled gifts
## (Cat), so this is the exact cycle
## order F9 must walk through -- pinned here rather than re-derived from the
## loader, so a regression in the loader's own sort shows up as a failure
## here too, not just in test_special_def.gd.
const _EXPECTED_ROSTER_ORDER: PackedStringArray = [
	"anvil", "black_hole", "bomb", "earthquake", "freeze", "glue", "jumping_bean", "magnet",
	"paintball", "propeller", "rocket", "stackfall", "volcano",
]


func test_sandbox_force_special_hotkey_cycles_the_roster_in_order_and_wraps_to_off() -> void:
	_start_sandbox(2)
	_run_countdown()
	var sandbox: Sandbox = _main._sandbox
	assert_eq(sandbox.forced_special(), &"", "off by default")

	var event: InputEventKey = _key_press(KEY_F9)
	assert_true(event.is_action_pressed(&"sandbox_force_special"), "F9 should map to sandbox_force_special")

	for expected_id: String in _EXPECTED_ROSTER_ORDER:
		sandbox._unhandled_input(event)
		assert_eq(sandbox.forced_special(), StringName(expected_id))
		if expected_id == "glue":
			# glue applies on claim as charges, not a queued piece.
			assert_gt(Match._gifts.glue_drops_left(sandbox.active_slot()), 0, "forced glue grants charges")
		else:
			assert_eq(
				(Match._gifts._pending_queues[sandbox.active_slot()] as Array)[0], StringName(expected_id),
				"the forced special must become the active slot's next piece with no crate needed"
			)
		assert_eq(Match.held_special(sandbox.active_slot()), &"", "forcing leaves the current piece alone")

	# One more press than the roster is long wraps back to "off".
	sandbox._unhandled_input(event)
	assert_eq(sandbox.forced_special(), &"", "cycling past the last roster id must wrap back to off")


func test_sandbox_force_special_installs_a_forced_drawer() -> void:
	_start_sandbox(2)
	_run_countdown()
	var sandbox: Sandbox = _main._sandbox

	sandbox.force_special_by_id(&"rocket")

	assert_eq(
		Match._gifts._special_drawer.call(), &"rocket",
		"while forced, every future draw (a real crate claim included) must return the forced id"
	)

	sandbox.force_special_by_id(&"")  # not on the roster -> ignored, stays forced
	assert_eq(sandbox.forced_special(), &"rocket", "an unknown id must not change the forced state")


func test_debug_force_next_shape_sets_the_held_shape_and_reissues_the_event() -> void:
	_start_sandbox(2)
	_run_countdown()
	var sandbox: Sandbox = _main._sandbox
	var domino: BlockShape = load("res://config/blocks/domino.tres")

	watch_signals(Events)
	sandbox.force_next_shape(&"domino")

	assert_eq(Match.held_shape(0), domino, "the block picker must force the active slot's held shape")
	assert_signal_emitted(Events, "feed_block_issued", "the picker reuses the real feed_block_issued path")


func test_debug_force_next_shape_is_refused_off_sandbox() -> void:
	_start_sandbox(2)
	_run_countdown()
	var before: BlockShape = Match.held_shape(0)

	Match.config.sandbox = false
	Match._feed.debug_force_next_shape(0, &"domino")

	assert_eq(Match.held_shape(0), before, "a non-sandbox match must refuse the block picker's seam")


func test_sandbox_pause_physics_hotkey_pauses_the_tree_and_toggles_back() -> void:
	_start_sandbox(2)
	_run_countdown()
	var sandbox: Sandbox = _main._sandbox

	var event: InputEventKey = _key_press(KEY_F11)
	assert_true(event.is_action_pressed(&"sandbox_pause_physics"), "F11 should map to sandbox_pause_physics")

	sandbox._unhandled_input(event)
	assert_true(get_tree().paused)
	assert_true(sandbox.is_physics_paused())

	sandbox._unhandled_input(event)
	assert_false(get_tree().paused, "a second press must unpause again")
	assert_false(sandbox.is_physics_paused())


## with debug mode off the F5
## reset hotkey do nothing, while slot switching (Tab) stays a play feature.
func test_debug_hotkeys_ignored_when_debug_mode_off() -> void:
	_start_sandbox(2)
	_run_countdown()
	var sandbox: Sandbox = _main._sandbox
	DebugMode.set_override_for_test(false)
	sandbox._unhandled_input(_key_press(KEY_F10))
	assert_false(sandbox._slow_motion_active, "F10 is debug-only")
	var slot_before: int = sandbox._active_slot if "_active_slot" in sandbox else -1
	sandbox._unhandled_input(_key_press(KEY_TAB))
	if slot_before >= 0:
		assert_ne(sandbox._active_slot, slot_before, "Tab still switches slots")
	DebugMode.set_override_for_test(true)
	DebugMode.clear_override_for_test()

