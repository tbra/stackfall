extends GutTest
## docs/M6_PLAN.md package B3 (spec 2.7 "Tutorial"): ui/Tutorial.gd's own
## five-step state machine, driven the same "drive Main from the Main Menu"
## way tests/unit/test_sandbox_placement.gd's own Part 2 drives
## start_sandbox_from_menu() -- a real game/Main.tscn, a tiny MapDef so the
## fixture is fast, no Lobby/Net state touched.
##
## Each step's own completion condition is driven directly (Events emits, a
## ghost orientation write, Input.action_press/release, a synthetic
## InputEventAction for ui_cancel) rather than through the real placement/
## territory/gift pipeline -- this file means to pin ui/Tutorial.gd's own
## step-advance logic, not re-prove core/'s rules (already covered by their
## own test files).

const MAIN_SCENE: PackedScene = preload("res://game/Main.tscn")

var _main: Variant = null
var _tutorial: Tutorial = null
var _tiny_map: MapDef


func _setup_menu() -> void:
	Match.set_process(false)
	Net.leave()
	Match.abort_match()
	SnapshotSync.end_match()

	_main = MAIN_SCENE.instantiate()

	_tiny_map = MapDef.new()
	_tiny_map.id = &"tutorial_tiny"
	_tiny_map.field_radius = 20.0
	_tiny_map.cell_size = 2.0

	var tiny_config: MatchConfig = (
		load("res://config/match_defaults.tres") as MatchConfig
	).duplicate(true)
	tiny_config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(tiny_config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	tiny_config.rng_seed = 24681
	_main.match_config = tiny_config

	add_child_autofree(_main)
	assert_not_null(_main._main_menu, "fixture: Main boots to the main menu with no command-line flags")


func _teardown_menu() -> void:
	Net.leave()
	Match.abort_match()
	SnapshotSync.end_match()
	Match.set_process(true)
	await get_tree().process_frame
	await get_tree().process_frame


func _run_countdown() -> void:
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)


func _start_tutorial() -> void:
	_main.start_tutorial_from_menu()
	_run_countdown()
	_tutorial = _main._tutorial


## Advances past "placing" (step 1) and "rotating" (step 2) so a test that
## only cares about a later step doesn't have to repeat both drives itself.
func _advance_to_territory_step() -> void:
	Events.block_placed.emit(null, &"cube")
	_tutorial.ghost().set_orientation_index(1)
	_tutorial._process(0.016)


func _advance_to_specials_step() -> void:
	_advance_to_territory_step()
	Events.territory_share_changed.emit(PackedFloat32Array([1.0]))


func _advance_to_camera_step() -> void:
	_advance_to_specials_step()
	Events.special_consumed.emit(0, (_tutorial.tutorial_config.demo_special_id))


# --- Fixture / entry point ---------------------------------------------------

func test_start_tutorial_from_menu_builds_a_playing_one_player_sandbox_match() -> void:
	_setup_menu()
	assert_null(_main._lobby, "fixture: no Lobby exists before the Tutorial button is reached.")

	_start_tutorial()

	assert_eq(Match.state(), Match.State.PLAYING)
	assert_true(Match.config.sandbox, "spec 2.7: the tutorial waives territory limits like Sandbox.")
	assert_eq(Match.config.player_count, 1, "there is only ever one tutorial participant.")
	assert_null(_main._lobby, "the Main-Menu tutorial path never builds a Lobby.")
	assert_true(Net.is_offline(), "the Main-Menu tutorial path never touches Net's host/join state.")
	assert_null(_main._main_menu, "the menu is cleared once the tutorial world exists.")
	assert_not_null(_tutorial, "start_tutorial_from_menu() must build the Tutorial scene.")
	assert_eq(_tutorial.current_step_id(), &"placing", "the tutorial always begins on step 1.")

	await _teardown_menu()


# --- Step 1: placing ---------------------------------------------------------

func test_step_placing_advances_exactly_once_on_block_placed() -> void:
	_setup_menu()
	_start_tutorial()

	Events.block_placed.emit(null, &"cube")
	assert_eq(_tutorial.current_step_id(), &"rotating", "step 1 advances on Events.block_placed.")

	# A second block_placed while "rotating" is current must not also fire
	# that step's own advance a second time (it isn't listening for this
	# signal any more) -- proves the completion check is scoped to the
	# *current* step, not "any step this signal could ever complete".
	Events.block_placed.emit(null, &"cube")
	assert_eq(_tutorial.current_step_id(), &"rotating", "a second block_placed must not skip past step 2.")

	await _teardown_menu()


# --- Step 2: rotating ---------------------------------------------------------

func test_step_rotating_advances_on_orientation_change() -> void:
	_setup_menu()
	_start_tutorial()
	Events.block_placed.emit(null, &"cube")
	assert_eq(_tutorial.current_step_id(), &"rotating", "fixture: must reach step 2 first.")

	_tutorial._process(0.016)
	assert_eq(_tutorial.current_step_id(), &"rotating", "no orientation change yet -- must not advance early.")

	_tutorial.ghost().set_orientation_index(1)
	_tutorial._process(0.016)
	assert_eq(_tutorial.current_step_id(), &"territory", "step 2 advances once the ghost's orientation changes.")

	await _teardown_menu()


# --- Step 3: territory --------------------------------------------------------

func test_step_territory_advances_when_the_tutorial_slots_team_owns_area() -> void:
	_setup_menu()
	_start_tutorial()
	_advance_to_territory_step()
	assert_eq(_tutorial.current_step_id(), &"territory", "fixture: must reach step 3 first.")

	# team_of(0) is team 0 (team_mode OFF, single slot) -- a zero share must
	# not advance the step.
	Events.territory_share_changed.emit(PackedFloat32Array([0.0]))
	assert_eq(_tutorial.current_step_id(), &"territory", "zero share must not complete this step.")

	Events.territory_share_changed.emit(PackedFloat32Array([1.0]))
	assert_eq(_tutorial.current_step_id(), &"specials", "step 3 advances once the tutorial slot's team owns area.")

	await _teardown_menu()


# --- Step 4: specials/throwing ------------------------------------------------

func test_step_specials_queues_the_demo_special_and_advances_on_special_consumed() -> void:
	_setup_menu()
	_start_tutorial()
	_advance_to_specials_step()
	assert_eq(_tutorial.current_step_id(), &"specials", "fixture: must reach step 4 first.")
	assert_eq(
		Match.pending_special_count(0), 1,
		"step 4 must force-queue tutorial_config.demo_special_id via Match.debug_queue_special()."
	)

	# A consumed event for a slot that isn't the tutorial's own must not
	# advance (defensive -- there is only ever slot 0 here, but this pins the
	# guard rather than assuming it is dead code).
	Events.special_consumed.emit(1, _tutorial.tutorial_config.demo_special_id)
	assert_eq(_tutorial.current_step_id(), &"specials", "a different slot's special_consumed must not complete this step.")

	Events.special_consumed.emit(0, _tutorial.tutorial_config.demo_special_id)
	assert_eq(_tutorial.current_step_id(), &"camera", "step 4 advances once the tutorial slot's special is consumed.")

	await _teardown_menu()


# --- Step 5: camera, and the tutorial ending ----------------------------------

func test_step_camera_advances_after_the_configured_hold_and_ends_the_tutorial() -> void:
	_setup_menu()
	_start_tutorial()
	_advance_to_camera_step()
	assert_eq(_tutorial.current_step_id(), &"camera", "fixture: must reach step 5 first.")

	Input.action_press(&"camera_orbit")
	_tutorial._process(1.0)
	assert_eq(
		_tutorial.current_step_id(), &"camera",
		"1s of a %.1fs hold must not finish the tutorial yet." % [_tutorial.tutorial_config.camera_hold_seconds]
	)

	_tutorial._process(1.5)
	Input.action_release(&"camera_orbit")

	assert_eq(Match.state(), Match.State.LOBBY, "step 5 completing ends the tutorial (Match.abort_match()).")
	assert_null(_main._tutorial, "game/Main.gd frees the Tutorial node once `finished` fires.")
	assert_not_null(_main._main_menu, "the tutorial finishing returns control to the Main Menu.")

	await _teardown_menu()


# --- Cancel (ui_cancel) --------------------------------------------------------

func test_ui_cancel_aborts_cleanly_from_any_step() -> void:
	_setup_menu()
	_start_tutorial()
	var freed_tutorial: Tutorial = _tutorial

	var cancel_event: InputEventAction = InputEventAction.new()
	cancel_event.action = &"ui_cancel"
	cancel_event.pressed = true
	_tutorial._unhandled_input(cancel_event)

	assert_eq(Match.state(), Match.State.LOBBY, "ui_cancel must call Match.abort_match().")
	assert_null(_main._tutorial, "game/Main.gd frees the Tutorial node once `finished` fires.")
	assert_not_null(_main._main_menu, "cancelling returns control to the Main Menu.")

	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(is_instance_valid(freed_tutorial), "no Tutorial node must be left in the tree.")

	await _teardown_menu()
