extends GutTest
## Bontago-mv0.8: the unlisted `godot --path . -- --sandbox [--players=N]`
## debug entry point. Flag routing and offline world build (game/Main.gd),
## active-slot cycling (game/PlayerController.gd's set_sandbox_slot() seam),
## the disabled/toggleable feed timer (autoload/Match.gd's
## _feed_timer_enabled), sandbox_reset_field and sandbox_spawn_tower — both
## through Match's normal, rules-checked entry points, never a rule of their
## own (game/Sandbox.gd) — and the F8 overlay toggle.
##
## Drives the real Main scene and the real Net/Match autoloads, the same
## fixture shape as tests/unit/test_match_lifecycle.gd, because the point is
## the sandbox route hooked into Main correctly (register_world() before
## start_match(), place_flags()/set_overlay_source() after) — a single-system
## test could not see that ordering.

const MAIN_SCENE: PackedScene = preload("res://game/Main.tscn")

## game/Main.gd has no class_name (a scene root, not a type other code
## names -- see tests/unit/test_match_lifecycle.gd's matching comment), so
## the instance is held through a Variant-typed reference.
var _main: Variant = null

## DECISION (Bontago-mv0.3): see test_match_flow.gd's own `_tiny_map` comment.
## Main.gd's `_build_sandbox_config()` (game/Main.gd) duplicates its own
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
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	(_main.get_node("Field") as Field).map_def = _tiny_map
	var tiny_match_config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true)
	tiny_match_config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(tiny_match_config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	_main.match_config = tiny_match_config
	add_child_autofree(_main)
	assert_not_null(_main._main_menu, "fixture: Main boots to the main menu with no command-line flags")


func after_each() -> void:
	# Bontago-1en.24: several sandbox_force_special tests below install a
	# forced Callable via Match.set_special_drawer() (game/Sandbox.gd's
	# force_special_by_id()); Match._gifts.reset() (run by abort_match() right
	# below) deliberately leaves `_special_drawer` untouched -- it is an
	# injectable dependency, not per-match state (see that function's own
	# comment) -- and Match is a singleton that outlives this script. Without
	# this, a forced drawer left installed here would leak into whichever
	# test file's Match._gifts the test runner happens to load next in the
	# same process (see test_gift_claim.gd's matching after_each() cleanup).
	Match._gifts.set_special_drawer(Match._gifts._default_special_drawer)
	Match.abort_match()
	Match.set_process(true)
	await get_tree().process_frame
	await get_tree().process_frame


func _run_countdown() -> void:
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)


## Bypasses OS.get_cmdline_user_args() (there is no setter to fake it with —
## see game/Main.gd's own DECISION on _start_sandbox_match_with_args()) with
## a manufactured argument list, the same seam autoload/Net.gd's
## _apply_command_line_args() uses for the same reason.
func _start_sandbox(player_count: int) -> void:
	_main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=%d" % player_count]))


func _key_press(keycode: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.device = -1
	event.physical_keycode = keycode
	event.pressed = true
	return event


func _pad_press(button: JoyButton) -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button
	event.pressed = true
	return event


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


func test_sandbox_defaults_to_the_configured_player_count_with_no_players_arg() -> void:
	_main._start_sandbox_match_with_args(PackedStringArray(["sandbox"]))
	assert_eq(Match.slot_count(), _main.sandbox_config.default_player_count)


func test_sandbox_allows_a_single_player() -> void:
	# Spec 2.8's normal floor is 2 (MatchConfig.PLAYER_COUNT_MIN); sandbox is
	# the one path that goes below it (config/MatchConfig.gd's `sandbox` flag).
	_start_sandbox(1)
	assert_eq(Match.slot_count(), 1)


func test_sandbox_never_reaches_the_lobby() -> void:
	_start_sandbox(2)
	assert_null(_main._lobby, "sandbox never opens a lobby (game/Main.gd's early return, like --hot-seat)")
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


func test_sandbox_next_slot_gamepad_binding_also_cycles() -> void:
	_start_sandbox(2)
	_run_countdown()
	var sandbox: Sandbox = _main._sandbox

	var event: InputEventJoypadButton = _pad_press(JOY_BUTTON_BACK)
	assert_true(event.is_action_pressed(&"sandbox_next_slot"), "gamepad Back should map to sandbox_next_slot")

	sandbox._unhandled_input(event)

	assert_eq(sandbox.active_slot(), 1)


# --- sandbox_toggle_timer: no auto-drop until re-enabled ---------------------

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


## Bontago-mv0.10 (spec 2.4 "[ORIGINAL target]" cadence): with the feed timer
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

	assert_eq(Match.blocks_spawned(), 3)


## Re-enabling the timer (F6) also re-enables the real placement cadence, so
## a tester can deliberately exercise the interval lock in sandbox too.
func test_placements_lock_once_the_feed_timer_is_re_enabled() -> void:
	_start_sandbox(2)
	_run_countdown()
	Match.set_feed_timer_enabled(true)

	var reason: StringName = Match.request_place(0, Match.default_ghost_origin(0), 0, Quaternion.IDENTITY, false)

	assert_eq(reason, PlacementRules.REASON_OK)
	assert_true(Match.is_release_locked(0), "F6 turns the real cadence -- and its lock -- back on")


## Bontago-mv0.10 follow-up: the debug panel's timer line names the lock
## state explicitly (spec 2.5's "distinct timer-locked state" -- the ghost's
## own grey tint is the in-world version of the same fact).
func test_sandbox_panel_shows_the_lock_state() -> void:
	_start_sandbox(2)
	_run_countdown()
	var sandbox: Sandbox = _main._sandbox
	sandbox.panel()._refresh()
	assert_true(
		sandbox.panel()._timer_label.text.findn("[unlocked]") >= 0,
		"unlocked before any release: %s" % sandbox.panel()._timer_label.text
	)

	Match.set_feed_timer_enabled(true)
	Match.request_place(0, Match.default_ghost_origin(0), 0, Quaternion.IDENTITY, false)
	sandbox.panel()._refresh()

	assert_true(
		sandbox.panel()._timer_label.text.findn("[locked]") >= 0,
		"locked after an early release: %s" % sandbox.panel()._timer_label.text
	)


func test_sandbox_toggle_timer_hotkey_reenables_auto_drop() -> void:
	_start_sandbox(2)
	_run_countdown()
	var sandbox: Sandbox = _main._sandbox

	var event: InputEventKey = _key_press(KEY_F6)
	assert_true(event.is_action_pressed(&"sandbox_toggle_timer"), "F6 should map to sandbox_toggle_timer")
	sandbox._unhandled_input(event)
	assert_true(Match.feed_timer_enabled(), "F6 flips the paused timer back on")

	watch_signals(Events)
	for _i: int in range(int(MatchConfig.BLOCK_TIMER_MAX * Engine.physics_ticks_per_second) + 10):
		Match._process(1.0 / Engine.physics_ticks_per_second)
	assert_signal_emitted(Events, "feed_timer_expired", "re-enabled, the timer now expires and auto-drops as usual")

	# A second press pauses it again -- the hotkey is a toggle, not a one-shot.
	sandbox._unhandled_input(event)
	assert_false(Match.feed_timer_enabled())


# --- sandbox_reset_field: F5 --------------------------------------------------

func test_sandbox_reset_field_clears_blocks_and_rebuilds_for_the_same_config() -> void:
	_start_sandbox(2)
	_run_countdown()
	var sandbox: Sandbox = _main._sandbox

	var reason: StringName = Match.request_place(0, Match.default_ghost_origin(0), 0, Quaternion.IDENTITY, false)
	assert_eq(reason, PlacementRules.REASON_OK, "fixture: a block actually lands before the reset")
	assert_gt(Match.blocks_spawned(), 0)
	sandbox._cycle_active_slot()
	assert_eq(sandbox.active_slot(), 1, "fixture: move off slot 0 so the reset's re-seed is visible")

	var event: InputEventKey = _key_press(KEY_F5)
	assert_true(event.is_action_pressed(&"sandbox_reset_field"), "F5 should map to sandbox_reset_field")
	sandbox._unhandled_input(event)

	assert_eq(Match.blocks_spawned(), 0, "a freshly reset match has spawned nothing yet")
	assert_eq(Match.slot_count(), 2, "the same config's player count survives the reset")
	assert_eq(sandbox.active_slot(), 0, "reset re-seeds the active slot")
	assert_eq(_main._field._home_flags.size(), 2, "flags are rebuilt for the same config")
	assert_not_null(Match.raster(), "territory is rebuilt")


# --- sandbox_spawn_tower: F7 --------------------------------------------------

func test_sandbox_spawn_tower_places_the_configured_block_count_via_request_place() -> void:
	_start_sandbox(2)
	_run_countdown()
	var sandbox: Sandbox = _main._sandbox
	sandbox.ghost().update_placement(Match.default_ghost_origin(0), Vector3.UP)

	var placed: Array = []
	var collect: Callable = func(block: Block, _shape_id: StringName) -> void: placed.append(block)
	Events.block_placed.connect(collect)

	var event: InputEventKey = _key_press(KEY_F7)
	assert_true(event.is_action_pressed(&"sandbox_spawn_tower"), "F7 should map to sandbox_spawn_tower")
	sandbox._unhandled_input(event)

	Events.block_placed.disconnect(collect)
	assert_eq(
		placed.size(), sandbox.sandbox_config.tower_block_count,
		"F7 must place exactly tower_block_count blocks, each through Match.request_place()"
	)
	assert_eq(Match.blocks_spawned(), sandbox.sandbox_config.tower_block_count)


# --- sandbox_toggle_overlay: F8 -----------------------------------------------

func test_sandbox_toggle_overlay_flips_the_fields_territory_overlay() -> void:
	_start_sandbox(2)
	var sandbox: Sandbox = _main._sandbox
	var overlay: TerritoryOverlay = _main._field.overlay()
	var initial: bool = overlay.visible

	var event: InputEventKey = _key_press(KEY_F8)
	assert_true(event.is_action_pressed(&"sandbox_toggle_overlay"), "F8 should map to sandbox_toggle_overlay")
	sandbox._unhandled_input(event)

	assert_eq(overlay.visible, not initial)

	sandbox._unhandled_input(event)
	assert_eq(overlay.visible, initial, "the hotkey toggles both ways")


# --- sandbox_force_special: F9 (Bontago-1en.24) -------------------------------

## config/specials/ ships exactly these 7 .tres today (anvil, bomb,
## earthquake, jumping_bean, propeller, rocket, volcano);
## SpecialDef.load_all_specials() sorts by id, so this is the exact cycle
## order F9 must walk through -- pinned here rather than re-derived from the
## loader, so a regression in the loader's own sort shows up as a failure
## here too, not just in test_special_def.gd.
const _EXPECTED_ROSTER_ORDER: PackedStringArray = [
	"anvil", "bomb", "earthquake", "jumping_bean", "propeller", "rocket", "volcano",
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
		assert_eq(
			Match.held_special(sandbox.active_slot()), StringName(expected_id),
			"the forced special must be seeded into the active slot's queue with no crate needed"
		)
		Match.pop_pending_special(sandbox.active_slot())

	# One more press than the roster is long wraps back to "off".
	sandbox._unhandled_input(event)
	assert_eq(sandbox.forced_special(), &"", "cycling past the last roster id must wrap back to off")


func test_sandbox_force_special_gamepad_binding_also_cycles() -> void:
	_start_sandbox(2)
	_run_countdown()
	var sandbox: Sandbox = _main._sandbox

	var event: InputEventJoypadButton = _pad_press(JOY_BUTTON_TOUCHPAD)
	assert_true(event.is_action_pressed(&"sandbox_force_special"), "gamepad Touchpad should map to sandbox_force_special")

	sandbox._unhandled_input(event)

	assert_eq(sandbox.forced_special(), StringName(_EXPECTED_ROSTER_ORDER[0]))


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


func test_sandbox_force_special_off_restores_the_default_drawer() -> void:
	_start_sandbox(2)
	_run_countdown()
	var sandbox: Sandbox = _main._sandbox
	sandbox.force_special_by_id(&"rocket")
	assert_eq(Match._gifts._special_drawer.call(), &"rocket", "fixture")

	# Cycle all the way back around to "off" -- bounded to one full period
	# (every roster id plus "off" itself), regardless of which id the fixture
	# above happened to start from.
	for _i: int in range(_EXPECTED_ROSTER_ORDER.size() + 1):
		if sandbox.forced_special() == &"":
			break
		sandbox._cycle_forced_special()
	assert_eq(sandbox.forced_special(), &"", "fixture: cycled back to off")

	assert_ne(
		Match._gifts._special_drawer.call(), &"rocket",
		"turning forcing back off must reinstall the normal drawer, not leave the forced one active"
	)


## GiftConfig.max_pending_specials caps debug_queue_special() exactly like a
## real claim; a full queue must not be silently overfilled, and the panel
## must be able to show why nothing new appeared.
func test_sandbox_force_special_queue_full_sets_the_panel_flag_without_queuing() -> void:
	_start_sandbox(2)
	_run_countdown()
	var sandbox: Sandbox = _main._sandbox
	Match._gifts._gift_config = Match._gifts._gift_config.duplicate() as GiftConfig
	Match._gifts._gift_config.max_pending_specials = 1
	assert_true(Match.debug_queue_special(0, &"filler"), "fixture: fill the queue to its cap")

	sandbox.force_special_by_id(&"anvil")

	assert_true(sandbox.forced_special_queue_full(), "F9 must report the queue as full when it is")
	assert_eq(Match.pending_special_count(0), 1, "a full queue must not grow past the cap")
	assert_eq(Match.held_special(0), &"filler", "the existing queue entry must be untouched")


func test_sandbox_panel_shows_the_forced_special_and_off_states() -> void:
	_start_sandbox(2)
	_run_countdown()
	var sandbox: Sandbox = _main._sandbox
	sandbox.panel()._refresh()
	assert_eq(sandbox.panel()._forced_special_label.text, "Forced special: off")

	sandbox.force_special_by_id(&"volcano")
	sandbox.panel()._refresh()
	assert_true(
		sandbox.panel()._forced_special_label.text.findn("volcano") >= 0,
		"panel must show the forced id: %s" % sandbox.panel()._forced_special_label.text
	)


## M4 P2e: game/GhostPreview.gd's own current_state() reports STATE_THROW
## while show_throw_hint(true) is active; the panel's Ghost: label must show
## "throw" instead of a stale validity reason for that gesture.
func test_sandbox_panel_ghost_label_shows_throw_state() -> void:
	_start_sandbox(2)
	_run_countdown()
	var sandbox: Sandbox = _main._sandbox
	sandbox.ghost().show_throw_hint(true)

	sandbox.panel()._refresh()

	assert_eq(sandbox.panel()._validity_label.text, "Ghost: throw")
	sandbox.ghost().show_throw_hint(false)


# --- `--force-special=<id>` (Bontago-1en.24) ----------------------------------

func test_force_special_cli_arg_sets_the_forced_special_at_startup() -> void:
	_main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2", "force-special=anvil"]))

	assert_eq(_main._sandbox.forced_special(), &"anvil")
	assert_eq(Match.held_special(0), &"anvil", "the CLI flag must seed the active slot immediately, like F9 does")


func test_force_special_by_id_with_an_unknown_id_warns_and_stays_off() -> void:
	_start_sandbox(2)
	_run_countdown()
	var sandbox: Sandbox = _main._sandbox

	sandbox.force_special_by_id(&"not_a_real_special")

	assert_eq(sandbox.forced_special(), &"", "an unknown id must leave forcing off, not crash or force a garbage id")
