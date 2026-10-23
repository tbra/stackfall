extends GutTest

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")
const CAMERA_RIG_SCENE: PackedScene = preload("res://game/player/CameraRig.tscn")
## Physics frames a dropped block gets to come to rest and freeze.
const REST_FRAME_LIMIT: int = 900

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
	DebugMode.clear_override_for_test()
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


## Every live Sandbox node under Main: after a rebuild the old one may still be
## queued for deletion until the frame ends.
func _sandbox_nodes() -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in _main.get_children():
		if child is Sandbox and not child.is_queued_for_deletion():
			found.append(child)
	return found


func _hud_count() -> int:
	var live: int = 0
	for hud: Node in _main.find_children("*", "HUD", true, false):
		if not hud.is_queued_for_deletion():
			live += 1
	return live


func _f5(sandbox: Sandbox) -> void:
	sandbox._unhandled_input(_key_press(KEY_F5))


func _key_press(keycode: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.device = -1
	event.physical_keycode = keycode
	event.pressed = true
	return event


func test_leaving_a_sandbox_leaves_no_local_player_no_extras_node_and_the_launch_camera() -> void:
	var fresh: CameraRig = autofree(CAMERA_RIG_SCENE.instantiate() as CameraRig)
	add_child(fresh)
	_main.start_sandbox_from_menu()
	_run_countdown()
	assert_eq(
		get_tree().get_nodes_in_group(GhostPreview.LOCAL_HELD_GROUP).size(), 1,
		"fixture: exactly one local-held ghost while the sandbox is live"
	)
	var rig: CameraRig = _main._camera_rig as CameraRig
	rig.zoom_continuous(40.0)
	rig.set_follow_position(Vector3(12.0, 3.0, -7.0))
	assert_ne(rig.get_distance(), fresh.get_distance(), "fixture: the player zoomed away from the launch view")

	_main._on_pause_leave_requested()
	await get_tree().process_frame

	assert_null(_main._hot_seat, "leaving a sandbox must leave no local player behind")
	assert_eq(
		get_tree().get_nodes_in_group(GhostPreview.LOCAL_HELD_GROUP).size(), 0,
		"leaving a sandbox must free its PlayerController/GhostPreview subtree"
	)
	assert_eq(_sandbox_nodes().size(), 0, "no extras node survives the leave")
	assert_null(_main._sandbox, "the sandbox instance itself must be freed and nulled")
	assert_not_null(_main._main_menu, "leaving must show the main menu")
	# ROOT CAUSE pin (Main._on_pause_leave_requested): a controller freed late
	# wrote its follow position back over the reset, so the menu showed a stale camera.
	assert_almost_eq(rig.get_distance(), fresh.get_distance(), 0.0001, "the menu shows the launch zoom")
	assert_almost_eq(rig.get_pitch(), fresh.get_pitch(), 0.0001, "the menu shows the launch pitch")
	assert_almost_eq(rig.get_yaw(), fresh.get_yaw(), 0.0001, "the menu shows the launch yaw")
	assert_eq(rig.get_target(), fresh.get_target(), "the menu shows the launch pivot")

	# A fresh sandbox afterward must behave exactly as a first one does.
	_main.start_sandbox_from_menu()
	_run_countdown()
	await get_tree().process_frame

	assert_eq(
		get_tree().get_nodes_in_group(GhostPreview.LOCAL_HELD_GROUP).size(), 1,
		"a fresh sandbox after leaving must still control exactly one local-held block"
	)
	assert_eq(_sandbox_nodes().size(), 1)


# --- Flag routing / world build ----------------------------------------------

func test_sandbox_flag_builds_an_offline_world_with_n_slots() -> void:
	_start_sandbox(3)

	assert_true(Net.is_offline(), "sandbox never touches Net")
	assert_eq(Match.slot_count(), 3)
	assert_true(Match.config.sandbox, "the sandbox config flag is set")
	assert_true(Match.config.sandbox, "relaxed rules, one meaning")
	assert_eq(Match.config.ai_count, 0)
	assert_not_null(_main._sandbox, "Main built a Sandbox instance")
	assert_true(_main._sandbox is Sandbox)
	assert_not_null(_main._debug_overlay, "F3's net debug overlay is available offline too")
	assert_eq(_main._field.home_flags().size(), 3, "one home flag per sandbox slot")


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
	assert_eq(_main._hot_seat.controller()._active_slot, 0)

	var event: InputEventKey = _key_press(KEY_TAB)
	assert_true(event.is_action_pressed(&"sandbox_next_slot"), "Tab should map to sandbox_next_slot")

	sandbox._unhandled_input(event)
	assert_eq(sandbox.active_slot(), 1)
	assert_eq(_main._hot_seat.controller()._active_slot, 1, "PlayerController.set_sandbox_slot() actually moved the acting slot")

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
	sandbox = _main._sandbox  # F5 rebuilds the world: Main now holds the new node
	assert_eq(sandbox.active_slot(), 0, "reset re-seeds the active slot")
	assert_eq(_main._field.home_flags().size(), 2, "flags are rebuilt for the same config")
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


# --- F5 rebuilds the world through the one match path ------------------------

func test_f5_rebuilds_the_world_exactly_once() -> void:
	DebugMode.set_override_for_test(true)
	_start_sandbox(2)
	_run_countdown()
	var old_sandbox: Sandbox = _main._sandbox
	var old_player: Node = _main._hot_seat
	watch_signals(Events)

	_f5(old_sandbox)
	await get_tree().process_frame

	assert_signal_emit_count(Events, "match_scope_reset", 1, "one rebuild, one scope reset")
	assert_ne(_main._sandbox, old_sandbox, "F5 attaches a new sandbox")
	assert_false(is_instance_valid(old_sandbox), "the old sandbox is gone after a frame")
	assert_false(is_instance_valid(old_player), "the old local player is gone after a frame")
	assert_eq(_sandbox_nodes().size(), 1, "exactly one Sandbox")
	assert_eq(get_tree().get_nodes_in_group(GhostPreview.LOCAL_HELD_GROUP).size(), 1, "exactly one local player")
	assert_eq(_hud_count(), 1, "exactly one HUD")
	assert_eq(Match.slot_count(), 2)
	assert_true(Match.config.sandbox, "the rebuild keeps the sandbox config")
	assert_eq(_main._field.home_flags().size(), 2)


func test_f5_twice_in_a_row_still_leaves_one_of_everything() -> void:
	DebugMode.set_override_for_test(true)
	_start_sandbox(2)
	_run_countdown()
	_f5(_main._sandbox)
	_f5(_main._sandbox)
	await get_tree().process_frame
	assert_eq(_sandbox_nodes().size(), 1)
	assert_eq(get_tree().get_nodes_in_group(GhostPreview.LOCAL_HELD_GROUP).size(), 1)
	assert_eq(_hud_count(), 1)


func test_a_forced_special_chosen_before_f5_is_still_forced_after() -> void:
	DebugMode.set_override_for_test(true)
	_start_sandbox(2)
	_run_countdown()
	_main._sandbox._unhandled_input(_key_press(KEY_F9))
	var forced: StringName = _main._sandbox.forced_special()
	assert_ne(forced, &"", "fixture: F9 forced a special")

	_f5(_main._sandbox)
	await get_tree().process_frame

	assert_eq(_main._sandbox.forced_special(), forced, "the new sandbox is still forcing the same special")
	assert_eq(Match._gifts._special_drawer.call(), forced, "every future draw still returns it")


func test_slow_motion_and_physics_pause_are_off_after_f5() -> void:
	DebugMode.set_override_for_test(true)
	_start_sandbox(2)
	_run_countdown()
	_main._sandbox._unhandled_input(_key_press(KEY_F10))
	_main._sandbox._unhandled_input(_key_press(KEY_F11))
	assert_true(_main._sandbox.is_slow_motion_active(), "fixture: slow motion on")
	assert_true(get_tree().paused, "fixture: physics paused")

	_f5(_main._sandbox)
	await get_tree().process_frame

	assert_eq(Engine.time_scale, 1.0)
	assert_false(get_tree().paused)
	assert_false(_main._sandbox.is_slow_motion_active())
	assert_false(_main._sandbox.is_physics_paused())


## The old node's exit must not clobber state the new node sets before the
## frame ends (old and new coexist until then).
func test_the_old_sandbox_leaving_does_not_clobber_the_new_ones_tools() -> void:
	DebugMode.set_override_for_test(true)
	_start_sandbox(2)
	_run_countdown()
	_f5(_main._sandbox)
	var fresh: Sandbox = _main._sandbox
	fresh._unhandled_input(_key_press(KEY_F10))
	fresh._unhandled_input(_key_press(KEY_F11))
	var slowed: float = Engine.time_scale

	await get_tree().process_frame

	assert_true(fresh.is_slow_motion_active())
	assert_eq(Engine.time_scale, slowed, "slow motion set on the new sandbox survives the old one's removal")
	assert_lt(Engine.time_scale, 1.0)
	assert_true(get_tree().paused, "so does the physics pause")
	fresh._unhandled_input(_key_press(KEY_F11))


func test_the_scoreboard_stays_suppressed_before_and_after_f5() -> void:
	DebugMode.set_override_for_test(true)
	_start_sandbox(2)
	_run_countdown()
	assert_true(_main._ensure_scoreboard().suppressed, "suppressed in a sandbox")

	_f5(_main._sandbox)
	await get_tree().process_frame

	assert_true(_main._ensure_scoreboard().suppressed, "still suppressed after a rebuild")


func test_tab_still_cycles_slots_after_f5_and_the_hud_follows() -> void:
	DebugMode.set_override_for_test(true)
	_start_sandbox(3)
	_run_countdown()
	_f5(_main._sandbox)
	await get_tree().process_frame
	_run_countdown()
	var sandbox: Sandbox = _main._sandbox
	assert_eq(sandbox.active_slot(), 0, "the rebuild re-seeds slot 0")

	sandbox._unhandled_input(_key_press(KEY_TAB))

	assert_eq(sandbox.active_slot(), 1)
	assert_eq(_main._hot_seat.controller()._active_slot, 1, "the controller follows")
	assert_eq(_main._hot_seat.hud()._active_slot, 1, "the HUD follows")
	sandbox._unhandled_input(_key_press(KEY_TAB))
	sandbox._unhandled_input(_key_press(KEY_TAB))
	assert_eq(sandbox.active_slot(), 0, "wraps")
	assert_eq(_main._hot_seat.hud()._active_slot, 0)


## A sandbox F5 resets the camera like any rebuild.
func test_f5_resets_the_camera_like_any_rebuild() -> void:
	DebugMode.set_override_for_test(true)
	_start_sandbox(2)
	_run_countdown()
	var rig: CameraRig = _main._camera_rig as CameraRig
	var start_distance: float = rig.get_distance()
	var start_yaw: float = rig.get_yaw()
	rig.zoom_continuous(40.0)
	rig._yaw += 1.3
	assert_ne(rig.get_distance(), start_distance, "fixture: the player zoomed")

	_f5(_main._sandbox)
	await get_tree().process_frame
	_run_countdown()

	assert_almost_eq(rig.get_distance(), start_distance, 0.0001, "zoom is back at the match-start value")
	assert_almost_eq(rig.get_yaw(), start_yaw, 0.0001, "yaw is back at the match-start value")


# --- Stable blocks freeze in the sandbox ---------------------------

func test_a_resting_block_freezes_to_static_in_the_sandbox() -> void:
	_start_sandbox(2)
	_run_countdown()
	var manager: StableBlockManager = _main._stable_block_manager
	assert_not_null(manager, "the one world builder makes the stable-block manager for the sandbox too")
	var quick: PhysicsTuning = manager.tuning.duplicate(true) as PhysicsTuning
	quick.stable_freeze_delay_s = 0.5
	manager.tuning = quick
	assert_eq(Match.request_place(0, Match.default_ghost_origin(0), 0, Quaternion.IDENTITY, false), PlacementRules.REASON_OK)
	var block: Block = Match.registry().all_blocks()[0] as Block

	var frames: int = 0
	while not block.is_freeze_static() and frames < REST_FRAME_LIMIT:
		await get_tree().physics_frame
		frames += 1

	assert_true(block.is_freeze_static(), "a block at rest freezes to static, sandbox included")

