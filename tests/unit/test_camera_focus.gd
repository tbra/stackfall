extends GutTest
## Bontago-b7r (owner decision 2026-09-28, Bontago-aem): camera_snap_home/
## camera_snap_goal's tap-to-TURN / hold-to-PEEK gesture in the default follow
## camera (CameraTuning.follow_block = true). See game/CameraRig.gd's own
## "Focus home/goal" section (_on_focus_pressed()/_on_focus_released()/
## _update_focus_hold()/_resolve_home_target()/_resolve_goal_target()) for the
## implementation these tests exercise.
##
## Fixture mirrors tests/unit/test_camera_drop_continuity.gd's own (real
## Field/Match via Match.register_world(), no live peer, no physics needed
## since these tests never place a block) so home/goal targets come from real
## HomeFlag/GoalFlag beacons, not a placeholder.

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _tiny_map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)
	# Two home flags, two goal flags -- distinct positions on the ring, so the
	# cycling test below can tell them apart.
	_field.place_flags(2, PackedColorArray([Color.RED, Color.BLUE]), 2)


func after_each() -> void:
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()
	Input.action_release(&"camera_snap_home")
	Input.action_release(&"camera_snap_goal")
	Input.action_release(&"pause_menu")
	Input.action_release(&"ghost_move_right")


func _make_rig() -> CameraRig:
	var rig: CameraRig = autofree(load("res://game/CameraRig.tscn").instantiate())
	add_child_autofree(rig)
	# A rig-local tuning duplicate, same DECISION every other CameraRig test in
	# this project makes -- keeps this file from mutating the shared
	# config/camera_tuning.tres singleton every other test/scene reads, and
	# lets these tests shrink the tap/peek/glide durations so they run fast.
	rig.tuning = rig.tuning.duplicate() as CameraTuning
	rig.tuning.focus_hold_threshold_s = 0.05
	rig.tuning.focus_turn_duration_s = 0.05
	rig.tuning.focus_peek_transition_s = 0.05
	return rig


func _action_event(action: StringName, pressed: bool) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event


## Presses `action` (both the real Input singleton, so _update_focus_hold()'s
## own per-frame poll sees it held, and a synthetic event, so _unhandled_
## input()'s press branch fires) and runs `hold_frames` of rig._process().
func _press_and_hold(rig: CameraRig, action: StringName, hold_frames: int) -> void:
	Input.action_press(action)
	rig._unhandled_input(_action_event(action, true))
	for _i: int in range(hold_frames):
		rig._process(1.0 / 60.0)


## Releases `action` on the real Input singleton and runs one more _process()
## so _update_focus_hold()'s own defensive "no longer held" branch ends the
## gesture -- the same path a real is_action_released() event takes, without
## this file needing to fabricate one for every call site.
func _release_and_settle(rig: CameraRig, action: StringName, settle_frames: int = 10) -> void:
	Input.action_release(action)
	for _i: int in range(settle_frames):
		rig._process(1.0 / 60.0)


func _expected_turn_yaw(follow_position: Vector3, target: Vector3) -> float:
	var away: Vector2 = Vector2(follow_position.x - target.x, follow_position.z - target.z)
	return atan2(away.x, away.y)


## Deterministically advances every live SceneTree Tween (the rig's turn/snap
## tweens) by `seconds` of tween time, independent of wall-clock frames.
func _finish_tweens(seconds: float) -> void:
	for tween: Tween in get_tree().get_processed_tweens():
		if tween.is_valid() and tween.is_running():
			tween.custom_step(seconds)


# --- TAP: TURN ---------------------------------------------------------------


func test_tap_camera_snap_home_turns_yaw_toward_the_local_slots_home_beacon() -> void:
	var rig: CameraRig = _make_rig()
	rig.set_local_slot(0)
	rig.set_follow_position(Vector3(3.0, 0.0, -4.0))
	rig._process(1.0 / 60.0)  # let _target settle onto the follow position first.

	var home_target: Vector3 = _field.home_flags()[0].global_position
	var expected_yaw: float = _expected_turn_yaw(rig.get_target(), home_target)

	# A single short hold (well under focus_hold_threshold_s) is a tap: press,
	# one frame, release -- never crosses into PEEK. TURN itself is a Tween
	# (game/CameraRig.gd's _turn_to_face()), which only advances on the
	# engine's own real frames -- not on this file's own manual rig._process()
	# calls -- so the tween is stepped explicitly via _finish_tweens() (no
	# wall-clock wait, which flaked under full-suite load; Bontago-fca.3).
	_press_and_hold(rig, &"camera_snap_home", 1)
	_release_and_settle(rig, &"camera_snap_home")
	assert_false(rig.is_peeking(), "a tap must never engage PEEK.")
	_finish_tweens(rig.tuning.focus_turn_duration_s + 0.05)

	assert_almost_eq(rig.get_yaw(), expected_yaw, 0.01)


func test_tap_camera_snap_goal_turns_yaw_toward_the_first_goal_and_repeated_taps_cycle() -> void:
	var rig: CameraRig = _make_rig()
	rig.set_follow_position(Vector3(0.0, 0.0, 5.0))
	rig._process(1.0 / 60.0)

	var goal_flags: Array[GoalFlag] = _field.goal_flags()
	assert_eq(goal_flags.size(), 2, "fixture: two distinct goals to cycle between.")
	var first_goal: Vector3 = goal_flags[0].global_position
	var second_goal: Vector3 = goal_flags[1].global_position
	assert_gt(first_goal.distance_to(second_goal), 0.5, "fixture: the two goals must be at visibly different spots.")

	_press_and_hold(rig, &"camera_snap_goal", 1)
	_release_and_settle(rig, &"camera_snap_goal")
	_finish_tweens(rig.tuning.focus_turn_duration_s + 0.05)
	assert_almost_eq(rig.get_yaw(), _expected_turn_yaw(rig.get_target(), first_goal), 0.01)

	_press_and_hold(rig, &"camera_snap_goal", 1)
	_release_and_settle(rig, &"camera_snap_goal")
	_finish_tweens(rig.tuning.focus_turn_duration_s + 0.05)
	assert_almost_eq(rig.get_yaw(), _expected_turn_yaw(rig.get_target(), second_goal), 0.01)


# --- HOLD: PEEK ----------------------------------------------------------


func test_holding_camera_snap_home_past_the_threshold_peeks_at_the_beacon_and_release_returns() -> void:
	var rig: CameraRig = _make_rig()
	rig.set_local_slot(0)
	rig.set_follow_position(Vector3(3.0, 0.0, -4.0))
	rig._process(1.0 / 60.0)
	var follow_target_before: Vector3 = rig.get_target()
	var home_target: Vector3 = _field.home_flags()[0].global_position

	# Well past focus_hold_threshold_s (0.05s here) and focus_peek_transition_s
	# (also 0.05s), so PEEK both engages and fully converges.
	_press_and_hold(rig, &"camera_snap_home", 30)

	assert_true(rig.is_peeking(), "holding past the threshold must engage PEEK.")
	assert_almost_eq(rig.get_target().x, home_target.x, 0.05)
	assert_almost_eq(rig.get_target().z, home_target.z, 0.05)
	assert_almost_eq(rig.get_distance(), rig.tuning.focus_peek_distance, 0.05)
	assert_almost_eq(rig.get_pitch(), deg_to_rad(rig.tuning.focus_peek_pitch_deg), 0.001)

	_release_and_settle(rig, &"camera_snap_home", 30)

	assert_false(rig.is_peeking(), "release must end PEEK.")
	assert_almost_eq(rig.get_target().x, follow_target_before.x, 0.05)
	assert_almost_eq(rig.get_target().z, follow_target_before.z, 0.05)
	assert_almost_eq(rig.get_distance(), rig.tuning.follow_distance, 0.05)
	assert_almost_eq(rig.get_pitch(), deg_to_rad(rig.tuning.follow_pitch_deg), 0.001)


# --- Chord gating: Start+X must not also fire focus goal ---------------------


func test_pause_menu_held_blocks_camera_snap_goal_entirely() -> void:
	var rig: CameraRig = _make_rig()
	var yaw_before: float = rig.get_yaw()

	Input.action_press(&"pause_menu")
	rig._unhandled_input(_action_event(&"camera_snap_goal", true))
	for _i: int in range(30):
		rig._process(1.0 / 60.0)

	assert_false(rig.is_peeking(), "Start+X is the tuning-panel chord, not focus goal, even held past the threshold.")
	assert_almost_eq(rig.get_yaw(), yaw_before, 0.0001)

	Input.action_release(&"pause_menu")
	rig._unhandled_input(_action_event(&"camera_snap_goal", false))


func test_camera_snap_home_held_blocks_camera_snap_goal_entirely() -> void:
	# The same gate covers game/Sandbox.gd's own Back+X chord
	# (sandbox_physics_comparison) without this file needing a Sandbox scene.
	# Proven by outcome, not by is_peeking() alone: a bare, short home tap
	# (with a goal press attempted mid-hold) must still turn toward HOME, not
	# toward goal and not nowhere -- if the goal press had snuck in and won,
	# or if it had somehow cancelled the home press, the final yaw would not
	# match home's own expected TURN target.
	var rig: CameraRig = _make_rig()
	rig.set_local_slot(0)
	rig.set_follow_position(Vector3(0.0, 0.0, 5.0))
	rig._process(1.0 / 60.0)
	var home_target: Vector3 = _field.home_flags()[0].global_position
	var expected_home_yaw: float = _expected_turn_yaw(rig.get_target(), home_target)

	Input.action_press(&"camera_snap_home")
	rig._unhandled_input(_action_event(&"camera_snap_home", true))
	rig._unhandled_input(_action_event(&"camera_snap_goal", true))  # must be a no-op; camera_snap_home is held.
	rig._process(1.0 / 60.0)  # one short frame -- still a tap, not a hold.

	_release_and_settle(rig, &"camera_snap_home")
	assert_false(rig.is_peeking(), "fixture: too short a hold to have engaged PEEK.")
	_finish_tweens(rig.tuning.focus_turn_duration_s + 0.05)

	assert_almost_eq(rig.get_yaw(), expected_home_yaw, 0.01)


# --- suppress_pad_home_focus (game/Sandbox.gd's own set_camera_rig() gate) --


func test_suppress_pad_home_focus_ignores_gamepad_back_only() -> void:
	var rig: CameraRig = _make_rig()
	rig.suppress_pad_home_focus = true

	var pad_back: InputEventJoypadButton = InputEventJoypadButton.new()
	pad_back.button_index = JOY_BUTTON_BACK
	pad_back.pressed = true
	assert_true(pad_back.is_action_pressed(&"camera_snap_home"), "fixture: Back is camera_snap_home.")
	rig._unhandled_input(pad_back)
	assert_eq(rig._focus_action, &"", "gamepad Back stays sandbox_next_slot only.")

	var key_one: InputEventKey = InputEventKey.new()
	key_one.physical_keycode = KEY_1
	key_one.pressed = true
	assert_true(key_one.is_action_pressed(&"camera_snap_home"), "fixture: 1 is camera_snap_home.")
	rig._unhandled_input(key_one)
	assert_eq(rig._focus_action, &"camera_snap_home", "keyboard focus still works in the sandbox.")


# --- Legacy free camera (follow_block = false) keeps working -----------------


func test_legacy_camera_still_snaps_instantly_to_the_real_home_beacon() -> void:
	var rig: CameraRig = _make_rig()
	rig.tuning.follow_block = false
	rig.set_local_slot(1)

	var home_target: Vector3 = _field.home_flags()[1].global_position
	rig._unhandled_input(_action_event(&"camera_snap_home", true))
	_finish_tweens(rig.tuning.snap_duration + 0.05)

	assert_almost_eq(rig.get_target().x, home_target.x, 0.05)
	assert_almost_eq(rig.get_target().z, home_target.z, 0.05)

	rig._unhandled_input(_action_event(&"camera_snap_home", false))


# --- Ghost cursor/placement suppression while peeking (PlayerController) ----


func _make_controller_with_rig() -> Dictionary:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost
	controller._ghost.set_shape(load("res://config/blocks/cube.tres"))
	var rig: CameraRig = _make_rig()
	controller.set_camera_rig(rig)
	controller.set_acting_slot(0)
	return {"controller": controller, "rig": rig}


func test_ghost_cursor_does_not_move_while_the_camera_is_peeking() -> void:
	var built: Dictionary = _make_controller_with_rig()
	var controller: PlayerController = built["controller"]
	var rig: CameraRig = built["rig"]

	controller._cursor = Vector3(2.0, 0.0, 2.0)
	var cursor_before: Vector3 = controller._cursor

	_press_and_hold(rig, &"camera_snap_home", 30)
	assert_true(rig.is_peeking(), "fixture: PEEK must actually be engaged for this test to mean anything.")

	Input.action_press(&"ghost_move_right")
	for _i: int in range(10):
		controller._process(1.0 / 60.0)

	assert_eq(controller._cursor, cursor_before, "the ghost cursor must not move while the camera is peeking.")

	Input.action_release(&"ghost_move_right")
	_release_and_settle(rig, &"camera_snap_home")


func test_ghost_place_is_ignored_while_the_camera_is_peeking() -> void:
	var built: Dictionary = _make_controller_with_rig()
	var controller: PlayerController = built["controller"]
	var rig: CameraRig = built["rig"]
	var fake: FakeMatch = FakeMatch.new()
	fake.next_request_result = PlacementRules.REASON_OK
	controller._match = fake

	_press_and_hold(rig, &"camera_snap_home", 30)
	assert_true(rig.is_peeking(), "fixture: PEEK must actually be engaged for this test to mean anything.")

	controller._unhandled_input(_action_event(&"ghost_place", true))

	assert_eq(fake.request_place_calls.size(), 0, "ghost_place must not reach Match while the camera is peeking.")

	_release_and_settle(rig, &"camera_snap_home")

	# Sanity: with the peek over, the same press-and-place path works again --
	# proves the PEEK guard suppressed the call above, rather than something
	# else (a missing shape, an unset slot) being the real reason it never
	# reached Match.
	controller._unhandled_input(_action_event(&"ghost_place", true))
	assert_eq(fake.request_place_calls.size(), 1, "fixture: ghost_place must work normally once PEEK has ended.")
