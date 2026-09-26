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
	tiny_match_config.rng_seed = 4242
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
	MatchTestReset.clear_world()


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


# --- Pause menu suppression (Bontago-xtq.42 fix round 2) ----------------------
#
# This fixture's own Main instance is the cheap place to exercise game/Main.gd's
# suppress/unsuppress wiring end to end: before_each() already boots the real
# Main scene to the real main menu (its own assert_not_null(_main._main_menu)
# fixture assertion above), and start_sandbox_from_menu() is the actual
# menu-driven entry point that owns its own explicit unsuppress (unlike
# _start_sandbox()'s own _start_sandbox_match_with_args() helper above, which
# bypasses that wrapper entirely -- see game/Main.gd's own comment on why).

func test_pause_menu_is_suppressed_at_boot_on_the_main_menu() -> void:
	assert_true(_main._pause_menu.suppressed, "the pause menu must be inert while the main menu is showing -- there is no match to leave.")


func test_pause_menu_is_unsuppressed_after_sandbox_starts_from_the_menu() -> void:
	_main.start_sandbox_from_menu()

	assert_false(_main._pause_menu.suppressed, "starting a sandbox match from the main menu must make the pause menu usable.")


# --- Leaving a sandbox via the pause menu (Bontago-xtq.42 P42 review, round 3) -
#
# game/Main.gd's _on_pause_leave_requested() (ui/PauseMenu.gd's own Leave
# match, confirmed) frees _sandbox and aborts the offline match. Round 3
# regression: the previous free-after-abort order left _world_built stuck
# true forever after this call -- Match.abort_match()'s (-> LOBBY) emit
# reached _on_match_state_changed() while _sandbox was still live, which
# diverts that reaction away from _end_match_world(), the only place that
# clears _world_built back to false -- so the *next* ordinary match's
# _build_match_world() call silently built nothing at all (its own `if
# _world_built: return` guard).

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


## Bontago-xtq.43 (owner playtest report: "after I hit F5 to reset I
## controlled 2 blocks"). game/PlayerController.gd's _ready() unconditionally
## adds its ghost to GhostPreview.LOCAL_HELD_GROUP regardless of which
## controller built it, so "exactly one node in that group" is the correct
## invariant for "the local player controls exactly one held block" — this
## does not depend on knowing which controller is the stray one.
##
## Root cause traced to game/Main.gd (not owned by this package, reported
## separately): _on_match_state_changed() calls _end_match_world() on any
## `-> LOBBY` transition, and _end_match_world() unconditionally clears
## _world_built to false even when the match that just left LOBBY (via
## Match.start_match()'s internal abort_match()) is a sandbox match that
## Sandbox.gd already fully owns. The same start_match() call's following
## `LOBBY -> LOADING` transition then finds _world_built already false and
## runs _build_match_world() for real, which instantiates a second, fully
## independent HotSeat-driven PlayerController bound to the same local slot
## Sandbox's own controller already serves. start_sandbox_from_menu() guards
## only the *first* start (`_world_built = true` before the first
## start_match()); nothing re-arms that guard before a later
## sandbox_reset_field, and this test's own _start_sandbox() helper — like
## the real CLI --sandbox entry point never reconnecting the listener, but
## unlike the guarded menu button — calls _start_sandbox_match_with_args()
## directly, so the very first start already exhibits it too.
func test_sandbox_start_and_reset_field_leave_exactly_one_local_held_block() -> void:
	_start_sandbox(2)
	_run_countdown()
	assert_eq(
		get_tree().get_nodes_in_group(GhostPreview.LOCAL_HELD_GROUP).size(), 1,
		"sandbox start must not also build a HotSeat-driven world on top of Sandbox's own"
	)
	assert_null(_main._hot_seat, "Main._build_match_world() must never run for a sandbox match")

	var sandbox: Sandbox = _main._sandbox
	# A block actually lands and the active slot moves on, same fixture shape
	# as test_sandbox_reset_field_clears_blocks_and_rebuilds_for_the_same_config()
	# above, so the reset is exercised with a block already placed (not an
	# empty, just-booted field) -- one of the states the owner's report could
	# plausibly have been in.
	var reason: StringName = Match.request_place(0, Match.default_ghost_origin(0), 0, Quaternion.IDENTITY, false)
	assert_eq(reason, PlacementRules.REASON_OK, "fixture: a block actually lands before the reset")
	sandbox._cycle_active_slot()

	for reset_pass: int in range(3):
		sandbox._unhandled_input(_key_press(KEY_F5))
		_run_countdown()
		assert_eq(
			get_tree().get_nodes_in_group(GhostPreview.LOCAL_HELD_GROUP).size(), 1,
			"sandbox_reset_field pass %d must not leave a second local-held ghost controlled by a duplicate HotSeat" % reset_pass
		)
		assert_null(
			_main._hot_seat,
			"sandbox_reset_field pass %d must not (re)build a HotSeat-driven world for a sandbox match" % reset_pass
		)


## Same invariant as the test above, but the reset lands while the previous
## held block is mid-drop (thrown, not yet resolved to a placement) rather
## than already placed and settled -- a second state the owner's "after I hit
## F5" report could have been in.
func test_sandbox_reset_field_mid_throw_leaves_exactly_one_local_held_block() -> void:
	_start_sandbox(2)
	_run_countdown()
	var sandbox: Sandbox = _main._sandbox
	var controller: PlayerController = sandbox.controller()
	sandbox.ghost().update_placement(Match.default_ghost_origin(0), Vector3.UP)
	controller._aiming_throw = true

	sandbox._unhandled_input(_key_press(KEY_F5))
	_run_countdown()

	assert_eq(
		get_tree().get_nodes_in_group(GhostPreview.LOCAL_HELD_GROUP).size(), 1,
		"sandbox_reset_field mid-throw must not leave a second local-held ghost controlled by a duplicate HotSeat"
	)
	assert_null(_main._hot_seat, "Main._build_match_world() must never run for a sandbox match")


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


# --- M6 B2: block picker (MatchFeed.debug_force_next_shape) ------------------

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


func test_debug_force_next_shape_is_refused_off_host() -> void:
	_start_sandbox(2)
	_run_countdown()
	var before: BlockShape = Match.held_shape(0)

	Match.set_net_provider(FakeNet.client(0))
	Match._feed.debug_force_next_shape(0, &"domino")
	Match.set_net_provider(null)

	assert_eq(Match.held_shape(0), before, "a client must never force its own held shape")


func test_debug_force_next_shape_with_an_unknown_id_warns_and_leaves_the_held_shape() -> void:
	_start_sandbox(2)
	_run_countdown()
	var before: BlockShape = Match.held_shape(0)

	Match._feed.debug_force_next_shape(0, &"not_a_real_shape")

	assert_eq(Match.held_shape(0), before, "an unknown shape id must not change the held shape")


# --- M6 B2: sandbox_slow_motion (F10) ----------------------------------------

func test_sandbox_slow_motion_hotkey_sets_time_scale_and_toggles_back() -> void:
	_start_sandbox(2)
	_run_countdown()
	var sandbox: Sandbox = _main._sandbox

	var event: InputEventKey = _key_press(KEY_F10)
	assert_true(event.is_action_pressed(&"sandbox_slow_motion"), "F10 should map to sandbox_slow_motion")

	sandbox._unhandled_input(event)
	assert_eq(Engine.time_scale, sandbox.sandbox_config.slow_motion_scale)
	assert_true(sandbox.is_slow_motion_active())

	sandbox._unhandled_input(event)
	assert_eq(Engine.time_scale, 1.0, "a second press must toggle it back off")
	assert_false(sandbox.is_slow_motion_active())


func test_sandbox_slow_motion_resets_to_1_0_on_scene_teardown() -> void:
	_start_sandbox(2)
	_run_countdown()
	var sandbox: Sandbox = _main._sandbox
	sandbox._unhandled_input(_key_press(KEY_F10))
	assert_ne(Engine.time_scale, 1.0, "fixture: slow motion is active before teardown")

	_main.free()
	await get_tree().process_frame

	assert_eq(Engine.time_scale, 1.0, "Engine.time_scale must not leak past this scene's teardown")
	_main = null


func test_sandbox_slow_motion_resets_on_sandbox_reset_field() -> void:
	_start_sandbox(2)
	_run_countdown()
	var sandbox: Sandbox = _main._sandbox
	sandbox._unhandled_input(_key_press(KEY_F10))
	assert_ne(Engine.time_scale, 1.0, "fixture: slow motion is active before the reset")

	sandbox._unhandled_input(_key_press(KEY_F5))

	assert_eq(Engine.time_scale, 1.0, "F5 must not leave the previous match's slow motion running")
	assert_false(sandbox.is_slow_motion_active())


func test_sandbox_slow_motion_gamepad_chord_requires_the_overlay_button_held() -> void:
	_start_sandbox(2)
	_run_countdown()
	var sandbox: Sandbox = _main._sandbox

	# PADDLE1 alone is sandbox_reset_field (fixture: a block lands first so
	# the reset is observable), not sandbox_slow_motion.
	Match.request_place(0, Match.default_ghost_origin(0), 0, Quaternion.IDENTITY, false)
	assert_gt(Match.blocks_spawned(), 0, "fixture")
	sandbox._unhandled_input(_pad_press(JOY_BUTTON_PADDLE1))
	assert_eq(Match.blocks_spawned(), 0, "PADDLE1 alone must still mean sandbox_reset_field")
	assert_false(sandbox.is_slow_motion_active())

	# PADDLE1 + PADDLE4 (sandbox_toggle_overlay) held means sandbox_slow_motion.
	Input.action_press(&"sandbox_toggle_overlay")
	sandbox._unhandled_input(_pad_press(JOY_BUTTON_PADDLE1))
	Input.action_release(&"sandbox_toggle_overlay")

	assert_true(sandbox.is_slow_motion_active(), "PADDLE1 chorded with PADDLE4 must mean sandbox_slow_motion")


# --- M6 B2: sandbox_pause_physics (F11) --------------------------------------

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


func test_sandbox_pause_physics_leaves_the_panel_processing_while_paused() -> void:
	_start_sandbox(2)
	_run_countdown()
	var sandbox: Sandbox = _main._sandbox

	assert_eq(sandbox.process_mode, Node.PROCESS_MODE_ALWAYS, "Sandbox must keep processing input while paused")
	assert_eq(
		sandbox.panel().process_mode, Node.PROCESS_MODE_ALWAYS,
		"SandboxPanel must keep processing while paused"
	)

	sandbox._unhandled_input(_key_press(KEY_F11))
	assert_true(get_tree().paused, "fixture")
	# The panel's own _unhandled_input path (sandbox hotkeys) must still be
	# reachable while paused -- toggling it back off proves the node kept
	# processing input rather than the engine silently dropping it.
	sandbox._unhandled_input(_key_press(KEY_F11))
	assert_false(get_tree().paused, "the pause hotkey itself must still work while paused")


func test_sandbox_pause_physics_unpauses_on_scene_teardown() -> void:
	_start_sandbox(2)
	_run_countdown()
	var sandbox: Sandbox = _main._sandbox
	sandbox._unhandled_input(_key_press(KEY_F11))
	assert_true(get_tree().paused, "fixture: paused before teardown")

	_main.free()
	await get_tree().process_frame

	assert_false(get_tree().paused, "get_tree().paused must not leak past this scene's teardown")
	_main = null


# --- M6 B2: height record -----------------------------------------------------

func test_height_record_is_monotone_and_resets_on_sandbox_reset_field() -> void:
	_start_sandbox(2)
	_run_countdown()
	var sandbox: Sandbox = _main._sandbox
	var panel: SandboxPanel = sandbox.panel()

	panel._refresh()
	assert_eq(panel._height_record_label.text, "Height record: 0.00 m", "fixture: nothing placed yet")

	Match.request_place(0, Match.default_ghost_origin(0), 0, Quaternion.IDENTITY, false)
	# game/BlockRegistry.gd's max_height_for_slot() only counts settled blocks
	# (test_block_registry.gd's own fixture on the same rule) -- give the
	# real physics simulation (untouched by this fixture's Match.set_process
	# (false), which only pauses Match's own script) enough real ticks to
	# reach PhysicsTuning.sleep_settle_time.
	var tuning: PhysicsTuning = load("res://config/physics_tuning.tres")
	var settle_ticks: int = int(ceil(tuning.sleep_settle_time * Engine.physics_ticks_per_second)) + 5
	for _i: int in range(settle_ticks):
		await get_tree().physics_frame
	panel._refresh()
	var after_one: float = Match.registry().max_height_for_slot(0)
	assert_gt(after_one, 0.0, "fixture: a settled block has positive height")
	assert_true(panel._height_record_label.text.findn("%.2f" % after_one) >= 0)

	# The record must never drop even if a later poll reads a lower current
	# height (e.g. the active slot changed, or blocks/territory shifted).
	panel._height_record = after_one + 5.0
	panel._refresh()
	assert_true(
		panel._height_record_label.text.findn("%.2f" % (after_one + 5.0)) >= 0,
		"the running max must not be lowered by a fresh, smaller poll"
	)

	sandbox._unhandled_input(_key_press(KEY_F5))
	panel._refresh()
	assert_eq(panel._height_record_label.text, "Height record: 0.00 m", "F5 must reset the height record")
