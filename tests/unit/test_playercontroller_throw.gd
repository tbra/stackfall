extends GutTest
## PlayerController.gd throw-aim coverage (M4 P2d, spec 2.5 "Throw (specials
## only)", owner decision 2026-09-22 Bontago-mvl (a): "hold left mouse on the
## held special, drag, flick-release; drag distance/speed sets the arc. Right
## mouse stays camera orbit"). Fixture family of test_playercontroller_mouse.
## gd/test_playercontroller_gamepad.gd -- see those files for the established
## FakeMatch/synthetic-input conventions this one reuses.
##
## The throw-aim lifecycle (_aiming_throw start/stop) lives entirely in
## PlayerController._update_throw_aim()'s per-frame Input.is_action_pressed(
## &"throw_aim") poll (its own doc comment explains why), so every test below
## drives that function directly with Input.action_press()/action_release()
## around it -- exactly the existing convention test_playercontroller_mouse.
## gd's rotate_drag tests already use for a different continuous hold.


func _motion(relative: Vector2) -> InputEventMouseMotion:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.relative = relative
	return event


func _mouse_press(button: MouseButton) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	return event


## A controller holding a claimed special (Match.held_special(slot) != "") on
## slot 0, exactly test_playercontroller_gamepad.gd's own
## test_gamepad_button_places_a_block fixture plus held_special_by_slot.
func _make_special_controller(fake: FakeMatch) -> PlayerController:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))

	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost
	controller._active_slot = 0
	controller._match = fake
	return controller


func _fake_match_with_special(slot_id: int) -> FakeMatch:
	var fake: FakeMatch = FakeMatch.new()
	fake.held_special_by_slot[slot_id] = &"rocket"
	return fake


# --- Mouse: LMB press over a special starts aiming instead of placing -------

func test_lmb_press_over_a_held_special_does_not_place_immediately() -> void:
	var fake: FakeMatch = _fake_match_with_special(0)
	var controller: PlayerController = _make_special_controller(fake)

	controller._unhandled_input(_mouse_press(MOUSE_BUTTON_LEFT))

	assert_eq(
		fake.request_place_calls.size(), 0,
		"pressing LMB over a held special must not place immediately -- it may still be a throw."
	)


## Regression pin: an ordinary (non-special) block must still place on press,
## unaffected by throw_aim sharing the same button (docs/M4_P2_PACKAGES.md
## P2d: "Holding an ordinary block is unaffected -- ghost_place still places
## on press").
func test_lmb_press_on_an_ordinary_block_still_places_immediately() -> void:
	var fake: FakeMatch = FakeMatch.new()  # no held_special_by_slot entry
	var controller: PlayerController = _make_special_controller(fake)

	controller._unhandled_input(_mouse_press(MOUSE_BUTTON_LEFT))

	assert_eq(fake.request_place_calls.size(), 1, "an ordinary block must place on LMB press, exactly as before.")
	assert_false(controller.is_aiming_throw(), "no aim state should ever start for a non-special piece.")


func test_update_throw_aim_starts_aiming_while_throw_aim_is_held_over_a_special() -> void:
	var fake: FakeMatch = _fake_match_with_special(0)
	var controller: PlayerController = _make_special_controller(fake)
	assert_false(controller.is_aiming_throw(), "fixture: not aiming yet.")

	Input.action_press(&"throw_aim")
	controller._update_throw_aim(1.0 / 60.0)

	assert_true(controller.is_aiming_throw(), "holding throw_aim over a held special should start aiming.")
	assert_eq(controller.current_throw_drag(), Vector3.ZERO, "fixture: no drag accumulated yet.")

	Input.action_release(&"throw_aim")
	controller._update_throw_aim(1.0 / 60.0)  # drains the fixture's own drag/no-op place; keeps other tests clean.


# --- Release thresholds (owner decision Bontago-mvl (a)) --------------------

func test_tiny_drag_releases_as_an_ordinary_place_not_a_throw() -> void:
	var fake: FakeMatch = _fake_match_with_special(0)
	var controller: PlayerController = _make_special_controller(fake)

	Input.action_press(&"throw_aim")
	controller._update_throw_aim(1.0 / 60.0)
	assert_true(controller.is_aiming_throw(), "fixture: aiming should have started.")

	# Well under throw_drag_min_distance_m (0.15 m default) at
	# block_move_sensitivity (0.015 m/px default): 1px * 0.015 = 0.015 m.
	controller._unhandled_input(_motion(Vector2(1.0, 0.0)))

	Input.action_release(&"throw_aim")
	controller._update_throw_aim(1.0 / 60.0)

	assert_false(controller.is_aiming_throw(), "releasing must always end the aim state.")
	assert_eq(fake.request_place_calls.size(), 1, "a negligible drag must resolve as one ordinary place.")
	assert_eq(fake.request_throw_calls.size(), 0, "a negligible drag must never throw.")
	assert_eq(fake.request_place_calls[0]["slot_id"], 0)


func test_real_drag_throws_with_velocity_clamped_by_drag_distance() -> void:
	var fake: FakeMatch = _fake_match_with_special(0)
	var controller: PlayerController = _make_special_controller(fake)

	Input.action_press(&"throw_aim")
	controller._update_throw_aim(0.05)
	assert_true(controller.is_aiming_throw())

	# world +X at yaw 0 (no rig wired), same convention
	# test_playercontroller_mouse.gd's own cursor tests use.
	var relative: Vector2 = Vector2(500.0, 0.0)
	controller._unhandled_input(_motion(relative))

	var expected_distance: float = relative.x * controller.ghost_tuning.block_move_sensitivity
	assert_gt(
		expected_distance, controller.special_tuning.throw_drag_min_distance_m,
		"fixture: this drag must actually clear the distance threshold."
	)

	Input.action_release(&"throw_aim")
	controller._update_throw_aim(0.05)

	assert_false(controller.is_aiming_throw())
	assert_eq(fake.request_place_calls.size(), 0, "a real drag must never also place.")
	assert_eq(fake.request_throw_calls.size(), 1, "a real drag must throw exactly once.")

	var call: Dictionary = fake.request_throw_calls[0]
	assert_eq(call["slot_id"], 0)
	var velocity: Vector3 = call["velocity"]
	var expected_speed: float = minf(
		expected_distance * controller.special_tuning.throw_speed_per_meter,
		controller.special_tuning.throw_max_speed
	)
	assert_almost_eq(
		velocity.length(), expected_speed, 0.01,
		"launch speed must be drag distance * throw_speed_per_meter, clamped at throw_max_speed."
	)
	assert_gt(velocity.x, 0.0, "the throw direction should follow the drag (world +X here).")
	assert_almost_eq(velocity.z, 0.0, 0.01, "no Z drag was applied, so there should be no Z component.")

	var direction: Vector3 = velocity.normalized()
	var horizontal_length: float = sqrt(direction.x * direction.x + direction.z * direction.z)
	var ratio: float = direction.y / horizontal_length if horizontal_length > 0.0 else 0.0
	assert_almost_eq(
		ratio,
		controller.special_tuning.throw_loft_ratio,
		1e-3,
		"throw direction's y component must equal horizontal length times throw_loft_ratio"
	)


## The drag distance/speed formula clamps at throw_max_speed regardless of how
## far past both thresholds the drag goes (SpecialTuning.throw_max_speed's own
## doc comment: "regardless of drag distance").
func test_an_enormous_drag_clamps_at_throw_max_speed() -> void:
	var fake: FakeMatch = _fake_match_with_special(0)
	var controller: PlayerController = _make_special_controller(fake)

	Input.action_press(&"throw_aim")
	controller._update_throw_aim(0.05)
	controller._unhandled_input(_motion(Vector2(100000.0, 0.0)))
	Input.action_release(&"throw_aim")
	controller._update_throw_aim(0.05)

	assert_eq(fake.request_throw_calls.size(), 1)
	var velocity: Vector3 = fake.request_throw_calls[0]["velocity"]
	assert_almost_eq(velocity.length(), controller.special_tuning.throw_max_speed, 0.01)


# --- Gamepad: LT + right-stick drag (spec 2.5 "Hold LT, aim, release") ------

func test_gamepad_lt_hold_plus_right_stick_drag_throws() -> void:
	var fake: FakeMatch = _fake_match_with_special(0)
	var controller: PlayerController = _make_special_controller(fake)

	var lt: InputEventJoypadMotion = InputEventJoypadMotion.new()
	lt.device = -1
	lt.axis = JOY_AXIS_TRIGGER_LEFT
	lt.axis_value = 1.0
	assert_true(lt.is_action_pressed(&"throw_aim"), "fixture: LT should map to throw_aim (tools/bootstrap_project.gd).")
	Input.parse_input_event(lt)
	Input.flush_buffered_events()

	controller._update_throw_aim(1.0 / 60.0)
	assert_true(controller.is_aiming_throw(), "holding LT over a held special should start aiming.")

	var stick: InputEventJoypadMotion = InputEventJoypadMotion.new()
	stick.device = -1
	stick.axis = JOY_AXIS_RIGHT_X
	stick.axis_value = 1.0
	Input.parse_input_event(stick)
	Input.flush_buffered_events()

	for _i: int in range(30):
		controller._update_throw_aim(1.0 / 60.0)
	assert_gt(controller.current_throw_drag().length(), 0.0, "the right stick should have accumulated some drag.")

	var lt_release: InputEventJoypadMotion = InputEventJoypadMotion.new()
	lt_release.device = -1
	lt_release.axis = JOY_AXIS_TRIGGER_LEFT
	lt_release.axis_value = 0.0
	Input.parse_input_event(lt_release)
	Input.flush_buffered_events()
	controller._update_throw_aim(1.0 / 60.0)

	assert_false(controller.is_aiming_throw())
	assert_eq(fake.request_throw_calls.size(), 1, "releasing LT after enough right-stick drag should throw.")
	var velocity: Vector3 = fake.request_throw_calls[0]["velocity"]
	assert_gt(velocity.length(), 0.0)
	assert_lte(velocity.length(), controller.special_tuning.throw_max_speed + 0.01)

	# Release the stick too, so it doesn't bleed into later tests.
	var stick_release: InputEventJoypadMotion = InputEventJoypadMotion.new()
	stick_release.device = -1
	stick_release.axis = JOY_AXIS_RIGHT_X
	stick_release.axis_value = 0.0
	Input.parse_input_event(stick_release)
	Input.flush_buffered_events()


# --- Cancel-mid-drag (docs/M4_P2_PACKAGES.md P2d brief: "Aim must cancel
# cleanly if the held piece changes/auto-drops mid-drag") -------------------

func test_aim_cancels_when_a_new_block_is_fed_mid_drag() -> void:
	var fake: FakeMatch = _fake_match_with_special(0)
	var controller: PlayerController = _make_special_controller(fake)

	Input.action_press(&"throw_aim")
	controller._update_throw_aim(1.0 / 60.0)
	controller._unhandled_input(_motion(Vector2(200.0, 0.0)))
	assert_true(controller.is_aiming_throw(), "fixture: should be aiming with a nonzero drag.")
	assert_gt(controller.current_throw_drag().length(), 0.0)

	Events.feed_block_issued.emit(0, &"cube", &"")

	assert_false(controller.is_aiming_throw(), "a new feed mid-drag must cancel the in-progress aim.")
	assert_eq(controller.current_throw_drag(), Vector3.ZERO, "the cancelled drag must not linger for the next piece.")

	Input.action_release(&"throw_aim")
	controller._update_throw_aim(1.0 / 60.0)
	assert_eq(
		fake.request_throw_calls.size(), 0,
		"releasing throw_aim after the aim was already cancelled must not fire a stale throw."
	)
	assert_eq(fake.request_place_calls.size(), 0, "nor should it fire a stale place.")


func test_aim_cancels_when_the_in_flight_request_is_rejected() -> void:
	var fake: FakeMatch = _fake_match_with_special(0)
	var controller: PlayerController = _make_special_controller(fake)

	Input.action_press(&"throw_aim")
	controller._update_throw_aim(1.0 / 60.0)
	controller._unhandled_input(_motion(Vector2(200.0, 0.0)))
	assert_true(controller.is_aiming_throw(), "fixture: should be aiming with a nonzero drag.")

	Events.placement_rejected.emit(0, PlacementRules.REASON_OUTSIDE_TERRITORY)

	assert_false(controller.is_aiming_throw(), "a rejection mid-drag must cancel the in-progress aim.")
	assert_eq(controller.current_throw_drag(), Vector3.ZERO)

	Input.action_release(&"throw_aim")
