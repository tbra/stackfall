extends GutTest
## (spec 1.2 "Tutorial"): ui/menus/Tutorial.gd's own
## five-step state machine, driven the same "drive Main from the Main Menu"
## way tests/unit/main/test_sandbox_placement.gd's own Part 2 drives
## start_sandbox_from_menu() -- a real game/main/Main.tscn, a tiny MapDef so the
## fixture is fast, no Lobby/Net state touched.
##
## Each step's own completion condition is driven directly (Events emits, a
## ghost orientation write, Input.action_press/release, a synthetic
## InputEventAction for ui_cancel) rather than through the real placement/
## territory/gift pipeline -- this file means to pin ui/menus/Tutorial.gd's own
## step-advance logic, not re-prove core/'s rules (already covered by their
## own test files).

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")

var _main: Main = null
var _tutorial: Tutorial = null
var _tiny_map: MapDef

const IDLE_TICKS: int = 1800
const COUNTDOWN_TICK_CAP: int = 1200
const CLOCK_FRAMES: int = 10
const END_TICK_CAP: int = 200


func _setup_menu(timed_round: bool = false) -> void:
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
		load("res://config/match/match_defaults.tres") as MatchConfig
	).duplicate(true)
	tiny_config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(tiny_config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	tiny_config.rng_seed = 24681
	if timed_round:
		# A timed round is how a real-rules match ends on its clock without sudden death.
		tiny_config.game_mode = MatchConfig.GameMode.CAPTURE_THE_FLAG
		tiny_config.round_timer_minutes = MatchConfig.ROUND_TIMER_MIN_MINUTES
	_main.match_config = tiny_config

	add_child_autofree(_main)
	assert_not_null(_main_menu(), "fixture: Main boots to the main menu with no command-line flags")


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


## Enters the tutorial and stops before the match reaches PLAYING.
func _start_tutorial_before_play() -> void:
	_main.start_tutorial_from_menu()
	_tutorial = _live_tutorial()


func _start_tutorial() -> void:
	_start_tutorial_before_play()
	_run_countdown()


## The first live (not queued for deletion) node of a class under Main.
func _first_live(type_name: StringName) -> Node:
	for node: Node in _main.find_children("*", type_name, true, false):
		if not node.is_queued_for_deletion():
			return node
	return null


func _live_tutorial() -> Tutorial:
	return _first_live(&"Tutorial") as Tutorial


func _local_player() -> LocalPlayer:
	return _first_live(&"LocalPlayer") as LocalPlayer


func _main_menu() -> MainMenu:
	return _first_live(&"MainMenu") as MainMenu


func _lobby() -> Lobby:
	return _first_live(&"Lobby") as Lobby


func _pause_menu() -> PauseMenu:
	return _first_live(&"PauseMenu") as PauseMenu


## The id of the step the prompt shows ("<n>/<count>" on the step label), or &""
## while no step runs (the prompt panel stays hidden until step 1 begins and after
## the tutorial ends).
func _step_id() -> StringName:
	if _tutorial == null or not is_instance_valid(_tutorial) or not _prompt_panel_visible():
		return &""
	var shown: int = int((_tutorial.get_node("%StepLabel") as Label).text.split("/")[0])
	return _tutorial.tutorial_config.steps[shown - 1].id


func _prompt_panel_visible() -> bool:
	var label: Control = _tutorial.get_node("%PromptLabel") as Control
	return label.get_parent().get_parent().is_visible_in_tree()


## Advances past "placing" (step 1) and "rotating" (step 2) so a test that
## only cares about a later step doesn't have to repeat both drives itself.
func _advance_to_territory_step() -> void:
	Events.block_placed.emit(null, &"cube")
	_local_player().ghost().set_orientation_index(1)
	_tutorial._process(0.016)


func _advance_to_specials_step() -> void:
	_advance_to_territory_step()
	Events.territory_share_changed.emit(PackedFloat32Array([1.0]))


func _advance_to_camera_step() -> void:
	_advance_to_specials_step()
	Events.special_consumed.emit(0, (_tutorial.tutorial_config.demo_special_id))


# --- Fixture / entry point ---------------------------------------------------

func test_start_tutorial_from_menu_builds_a_playing_one_player_real_rules_match() -> void:
	_setup_menu()
	assert_null(_lobby(), "fixture: no Lobby exists before the Tutorial button is reached.")

	_start_tutorial()

	assert_eq(Match.state(), Match.State.PLAYING)
	assert_false(Match.config.sandbox, "the tutorial plays under real rules; only the sandbox relaxes them.")
	assert_eq(Match.config.player_count, 1, "there is only ever one tutorial participant.")
	assert_eq(Match.config.weather_mode, MatchConfig.WeatherMode.OFF, "the tutorial has no weather.")
	assert_eq(
		Match.config.enabled_specials, [_tutorial.tutorial_config.demo_special_id] as Array[StringName],
		"only the gift the lesson teaches is enabled."
	)
	assert_eq(Match.config.special_frequency, 0, "no random crates: the lesson grants its own gift.")
	assert_null(_lobby(), "the Main-Menu tutorial path never builds a Lobby.")
	assert_true(Net.is_offline(), "the Main-Menu tutorial path never touches Net's host/join state.")
	assert_null(_main_menu(), "the menu is cleared once the tutorial world exists.")
	assert_not_null(_tutorial, "start_tutorial_from_menu() must build the Tutorial scene.")
	assert_eq(_step_id(), &"placing", "the tutorial always begins on step 1.")

	await _teardown_menu()


func test_no_random_crate_appears_over_many_ticks() -> void:
	_setup_menu()
	_start_tutorial()
	var spawned: Array[int] = []
	var on_spawn: Callable = func(gift_id: int, _position: Vector2) -> void: spawned.append(gift_id)
	Events.gift_spawned.connect(on_spawn)

	for _i: int in range(IDLE_TICKS):
		Match._process(1.0 / Engine.physics_ticks_per_second)

	Events.gift_spawned.disconnect(on_spawn)
	assert_eq(Match.state(), Match.State.PLAYING, "fixture: still playing after the idle ticks.")
	assert_eq(spawned.size(), 0, "no crate spawns in the tutorial.")
	assert_eq(Match.pending_special_count(0), 0, "no special is queued before the lesson grants one.")

	await _teardown_menu()


func test_the_grant_works_offline_and_the_sky_clock_runs() -> void:
	_setup_menu()
	_start_tutorial()
	assert_true(Net.is_offline(), "fixture: no network session.")
	assert_true(SnapshotSync.is_running(), "the shared match clock runs in the tutorial like in a match.")
	for _i: int in range(CLOCK_FRAMES):
		await get_tree().physics_frame
	assert_gt(SnapshotSync.sky_cycle_seconds(), 0.0, "the sky clock advances.")
	assert_true(
		Match.debug_queue_special(0, _tutorial.tutorial_config.demo_special_id),
		"the lesson's scripted grant is accepted offline under real rules."
	)
	assert_eq(Match.pending_special_count(0), 1)

	await _teardown_menu()


func test_the_f4_tuning_panel_exists_under_the_local_player() -> void:
	_setup_menu()
	_start_tutorial()

	var local_player: Node = _local_player()
	assert_not_null(local_player, "the tutorial runs on the real local player.")
	assert_eq(local_player.find_children("*", "TuningPanel", true, false).size(), 1)

	await _teardown_menu()


# --- Before PLAYING nothing starts -----------------------------------------------

func test_no_step_or_prompt_before_playing_and_step_one_begins_at_playing() -> void:
	_setup_menu()
	_start_tutorial_before_play()
	assert_ne(Match.state(), Match.State.PLAYING, "fixture: the tutorial is attached before play begins.")
	var ticks: int = 0
	while Match.state() != Match.State.PLAYING and ticks < COUNTDOWN_TICK_CAP:
		assert_eq(_step_id(), &"", "no step runs while the match is %d." % Match.state())
		assert_false(_prompt_panel_visible(), "no prompt shows while the match is %d." % Match.state())
		Events.block_placed.emit(null, &"cube")
		Events.territory_share_changed.emit(PackedFloat32Array([1.0]))
		Events.special_consumed.emit(0, _tutorial.tutorial_config.demo_special_id)
		Input.action_press(&"camera_orbit")
		_tutorial._process(_tutorial.tutorial_config.camera_hold_seconds + 1.0)
		Input.action_release(&"camera_orbit")
		Match._process(1.0 / Engine.physics_ticks_per_second)
		ticks += 1
	assert_eq(Match.state(), Match.State.PLAYING, "fixture: the match reached PLAYING.")
	assert_eq(Match.pending_special_count(0), 0, "nothing granted a special before play.")
	assert_ne(_step_id(), &"")
	assert_eq(_step_id(), &"placing", "step 1 begins at PLAYING, untouched by earlier input.")
	assert_true(_prompt_panel_visible(), "the prompt shows once step 1 begins.")

	await _teardown_menu()


# --- Step 1: placing ---------------------------------------------------------

func test_step_placing_advances_exactly_once_on_block_placed() -> void:
	_setup_menu()
	_start_tutorial()

	Events.block_placed.emit(null, &"cube")
	assert_eq(_step_id(), &"rotating", "step 1 advances on Events.block_placed.")

	# A second block_placed while "rotating" is current must not also fire
	# that step's own advance a second time (it isn't listening for this
	# signal any more) -- proves the completion check is scoped to the
	# *current* step, not "any step this signal could ever complete".
	Events.block_placed.emit(null, &"cube")
	assert_eq(_step_id(), &"rotating", "a second block_placed must not skip past step 2.")

	await _teardown_menu()


# --- Step 2: rotating ---------------------------------------------------------

func test_step_specials_queues_the_demo_special_and_advances_on_special_consumed() -> void:
	_setup_menu()
	_start_tutorial()
	_advance_to_specials_step()
	assert_eq(_step_id(), &"specials", "fixture: must reach step 4 first.")
	assert_eq(
		Match.pending_special_count(0), 1,
		"step 4 must force-queue tutorial_config.demo_special_id via Match.debug_queue_special()."
	)

	# A consumed event for a slot that isn't the tutorial's own must not
	# advance (defensive -- there is only ever slot 0 here, but this pins the
	# guard rather than assuming it is dead code).
	Events.special_consumed.emit(1, _tutorial.tutorial_config.demo_special_id)
	assert_eq(_step_id(), &"specials", "a different slot's special_consumed must not complete this step.")

	Events.special_consumed.emit(0, _tutorial.tutorial_config.demo_special_id)
	assert_eq(_step_id(), &"camera", "step 4 advances once the tutorial slot's special is consumed.")

	await _teardown_menu()


# --- Step 5: camera, and the tutorial ending ----------------------------------

func test_step_camera_advances_after_the_configured_hold_and_ends_the_tutorial() -> void:
	_setup_menu()
	_start_tutorial()
	_advance_to_camera_step()
	assert_eq(_step_id(), &"camera", "fixture: must reach step 5 first.")

	Input.action_press(&"camera_orbit")
	_tutorial._process(1.0)
	assert_eq(
		_step_id(), &"camera",
		"1s of a %.1fs hold must not finish the tutorial yet." % [_tutorial.tutorial_config.camera_hold_seconds]
	)

	_tutorial._process(1.5)
	Input.action_release(&"camera_orbit")

	assert_eq(Match.state(), Match.State.LOBBY, "step 5 completing ends the tutorial (Match.abort_match()).")
	assert_null(_live_tutorial(), "game/main/Main.gd frees the Tutorial node once `finished` fires.")
	assert_not_null(_main_menu(), "the tutorial finishing returns control to the Main Menu.")

	await _teardown_menu()


# --- Cancel (pause_menu) --------------------------------------------------------

## fix: this used to fire ui_cancel, but ui_cancel now has a
## gamepad B binding (project-wide menu back-navigation fix) and gamepad B is
## also rotate_snap/camera_snap_goal's own button during gameplay -- reading
## ui_cancel here would end the tutorial on every gamepad snap-rotate. See
## ui/menus/Tutorial.gd's own updated _unhandled_input() doc comment for why
## pause_menu (Escape / gamepad Start) is the correct action to read instead.
func test_pause_menu_action_aborts_cleanly_from_any_step() -> void:
	_setup_menu()
	_start_tutorial()
	var freed_tutorial: Tutorial = _tutorial

	var cancel_event: InputEventAction = InputEventAction.new()
	cancel_event.action = &"pause_menu"
	cancel_event.pressed = true
	_tutorial._unhandled_input(cancel_event)

	assert_eq(Match.state(), Match.State.LOBBY, "pause_menu must call Match.abort_match().")
	assert_null(_live_tutorial(), "game/main/Main.gd frees the Tutorial node once `finished` fires.")
	assert_not_null(_main_menu(), "cancelling returns control to the Main Menu.")

	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(is_instance_valid(freed_tutorial), "no Tutorial node must be left in the tree.")

	await _teardown_menu()


# --- Match end, pause menu -------------------------------------------------------

func test_the_match_reaching_end_ends_the_tutorial_once() -> void:
	_setup_menu(true)
	_start_tutorial()
	var finished_count: Array[int] = [0]
	_tutorial.finished.connect(func() -> void: finished_count[0] += 1)
	var freed_tutorial: Tutorial = _tutorial

	var guard: int = 0
	while Match.state() == Match.State.PLAYING and guard < END_TICK_CAP:
		Match._process(1.0)
		guard += 1

	assert_eq(finished_count[0], 1, "the tutorial finishes exactly once when the match ends.")
	assert_eq(Match.state(), Match.State.LOBBY, "ending the tutorial leaves the match.")
	assert_null(_live_tutorial())
	assert_not_null(_main_menu(), "the menu is shown again.")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(is_instance_valid(freed_tutorial), "no Tutorial node is left in the tree.")

	await _teardown_menu()


func test_the_pause_menu_is_suppressed_while_the_tutorial_runs_and_inert_at_the_menu_after() -> void:
	_setup_menu()
	_start_tutorial()
	assert_true(_pause_menu().suppressed, "Escape quits the tutorial; the pause menu stays closed.")

	_tutorial._unhandled_input(_pause_event())

	assert_not_null(_main_menu(), "the player is back at the main menu.")
	assert_true(_pause_menu().suppressed, "the pause menu stays inert over the main menu.")

	await _teardown_menu()


func _pause_event() -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = &"pause_menu"
	event.pressed = true
	return event
