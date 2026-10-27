extends GutTest
## One shared input gate: pause, chat and results block gameplay and camera input, and
## Events.match_scope_reset clears all three for the controller and the rig alike.
## The tuning panel blocker is not match-scoped and survives a reset.


func _make_controller() -> PlayerController:
	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	return controller


func _make_rig() -> CameraRig:
	var rig: CameraRig = load("res://game/player/CameraRig.tscn").instantiate() as CameraRig
	add_child_autofree(rig)
	return rig


func after_each() -> void:
	DebugMode.clear_override_for_test()


func test_reset_with_nothing_open_changes_nothing() -> void:
	var controller: PlayerController = _make_controller()
	var rig: CameraRig = _make_rig()
	Events.match_scope_reset.emit()
	assert_true(controller.input_enabled)
	assert_false(rig.input_gate.is_blocked())


func test_reset_with_chat_open_unblocks_both_without_a_chat_close() -> void:
	var controller: PlayerController = _make_controller()
	var rig: CameraRig = _make_rig()
	Events.chat_input_opened.emit()
	assert_false(controller.input_enabled)
	assert_true(rig.input_gate.is_blocked())
	Events.match_scope_reset.emit()
	assert_false(rig.input_gate.is_blocked())
	assert_true(controller.input_enabled, "no stuck input after a chat-only reset")


func test_reset_with_pause_open_unblocks_both_and_later_chat_leaves_input_on() -> void:
	var controller: PlayerController = _make_controller()
	var rig: CameraRig = _make_rig()
	Events.pause_menu_opened.emit()
	assert_false(controller.input_enabled)
	assert_true(rig.input_gate.is_blocked())
	Events.match_scope_reset.emit()
	assert_false(rig.input_gate.is_blocked())
	assert_true(controller.input_enabled, "pause is match-scoped")
	Events.chat_input_opened.emit()
	assert_false(controller.input_enabled)
	Events.chat_input_closed.emit()
	assert_true(controller.input_enabled, "a later chat open/close leaves input on")


func test_reset_with_results_open_clears_both() -> void:
	var controller: PlayerController = _make_controller()
	var rig: CameraRig = _make_rig()
	Events.match_results_ready.emit({})
	assert_false(controller.input_enabled)
	assert_true(rig.input_gate.is_blocked())
	Events.match_scope_reset.emit()
	assert_true(controller.input_enabled)
	assert_false(rig.input_gate.is_blocked())


func test_reset_with_results_and_chat_open_clears_both() -> void:
	var controller: PlayerController = _make_controller()
	var rig: CameraRig = _make_rig()
	Events.match_results_ready.emit({})
	Events.chat_input_opened.emit()
	Events.match_scope_reset.emit()
	assert_true(controller.input_enabled)
	assert_false(rig.input_gate.is_blocked())


func test_reset_with_results_and_pause_open_clears_both() -> void:
	var controller: PlayerController = _make_controller()
	var rig: CameraRig = _make_rig()
	Events.match_results_ready.emit({})
	Events.pause_menu_opened.emit()
	Events.match_scope_reset.emit()
	assert_true(controller.input_enabled)
	assert_false(rig.input_gate.is_blocked())
	Events.chat_input_opened.emit()
	Events.chat_input_closed.emit()
	assert_true(controller.input_enabled)


func test_reset_with_all_three_open_clears_both() -> void:
	var controller: PlayerController = _make_controller()
	var rig: CameraRig = _make_rig()
	Events.match_results_ready.emit({})
	Events.pause_menu_opened.emit()
	Events.chat_input_opened.emit()
	Events.match_scope_reset.emit()
	assert_true(controller.input_enabled)
	assert_false(rig.input_gate.is_blocked())


func test_controller_and_rig_read_one_gate_after_set_camera_rig() -> void:
	var controller: PlayerController = _make_controller()
	var rig: CameraRig = _make_rig()
	controller.set_camera_rig(rig)
	assert_same(controller.input_gate, rig.input_gate)
	Events.pause_menu_opened.emit()
	assert_false(controller.input_enabled)
	assert_true(rig.input_gate.is_blocked())
	Events.match_scope_reset.emit()
	assert_true(controller.input_enabled)
	assert_false(rig.input_gate.is_blocked())


func test_panel_blocker_survives_a_reset() -> void:
	var controller: PlayerController = _make_controller()
	var rig: CameraRig = _make_rig()
	controller.set_camera_rig(rig)
	rig.input_gate.set_blocker(InputGate.Blocker.PANEL, true)
	assert_false(controller.input_enabled)
	Events.match_scope_reset.emit()
	assert_false(controller.input_enabled)
	assert_true(rig.input_gate.is_blocked())


func test_open_tuning_panel_freed_at_match_end_leaves_next_match_enabled() -> void:
	DebugMode.set_override_for_test(true)
	var controller: PlayerController = _make_controller()
	var rig: CameraRig = _make_rig()
	controller.set_camera_rig(rig)
	var panel: TuningPanel = load("res://ui/debug/TuningPanel.tscn").instantiate() as TuningPanel
	add_child(panel)
	panel.set_controller(controller)
	var toggle: InputEventAction = InputEventAction.new()
	toggle.action = &"tuning_panel_toggle"
	toggle.pressed = true
	panel._unhandled_input(toggle)
	assert_false(controller.input_enabled, "fixture: the open panel blocks input")
	assert_true(rig.input_gate.is_blocked_by(InputGate.Blocker.PANEL))
	# Match end: the panel scene is freed while open, then the next match starts.
	panel.free()
	Events.match_scope_reset.emit()
	assert_true(controller.input_enabled)
	assert_false(rig.input_gate.is_blocked())
