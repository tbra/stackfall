extends GutTest
## Characterization of today's input-gate behaviour on Events.match_scope_reset.
## PlayerController and CameraRig each track pause/chat/results and they differ on
## reset: the rig clears all three, the controller clears chat and results but its
## pause flag survives, and a chat-only reset leaves the controller's input off.
## This pins that behaviour as it is; any later change to either handler shows up as a diff here.


func _make_controller() -> PlayerController:
	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	return controller


func _make_rig() -> CameraRig:
	var rig: CameraRig = load("res://game/player/CameraRig.tscn").instantiate() as CameraRig
	add_child_autofree(rig)
	return rig


func test_reset_with_nothing_open_changes_nothing() -> void:
	var controller: PlayerController = _make_controller()
	var rig: CameraRig = _make_rig()
	Events.match_scope_reset.emit()
	assert_true(controller.input_enabled)
	assert_false(rig.is_input_blocked())


func test_reset_with_chat_open_unblocks_rig_but_leaves_controller_input_off() -> void:
	var controller: PlayerController = _make_controller()
	var rig: CameraRig = _make_rig()
	Events.chat_input_opened.emit()
	assert_false(controller.input_enabled)
	assert_true(rig.is_input_blocked())
	Events.match_scope_reset.emit()
	assert_false(rig.is_input_blocked(), "rig clears chat on reset")
	assert_false(controller.input_enabled, "controller keeps input off after a chat-only reset")


func test_controller_input_returns_when_chat_closes_after_a_chat_reset() -> void:
	var controller: PlayerController = _make_controller()
	Events.chat_input_opened.emit()
	Events.match_scope_reset.emit()
	Events.chat_input_closed.emit()
	assert_true(controller.input_enabled)


func test_reset_with_pause_open_unblocks_rig_but_pause_survives_in_controller() -> void:
	var controller: PlayerController = _make_controller()
	var rig: CameraRig = _make_rig()
	Events.pause_menu_opened.emit()
	assert_false(controller.input_enabled)
	assert_true(rig.is_input_blocked())
	Events.match_scope_reset.emit()
	assert_false(rig.is_input_blocked(), "rig clears pause on reset")
	assert_false(controller.input_enabled, "controller still holds input off for pause")
	# The surviving flag is observable: closing chat does not hand input back.
	Events.chat_input_opened.emit()
	Events.chat_input_closed.emit()
	assert_false(controller.input_enabled, "the pause flag survived the reset")
	Events.pause_menu_closed.emit()
	assert_true(controller.input_enabled)


func test_reset_with_results_open_clears_both() -> void:
	var controller: PlayerController = _make_controller()
	var rig: CameraRig = _make_rig()
	Events.match_results_ready.emit({})
	assert_false(controller.input_enabled)
	assert_true(rig.is_input_blocked())
	Events.match_scope_reset.emit()
	assert_true(controller.input_enabled)
	assert_false(rig.is_input_blocked())


func test_reset_with_results_and_chat_open_clears_both() -> void:
	var controller: PlayerController = _make_controller()
	var rig: CameraRig = _make_rig()
	Events.match_results_ready.emit({})
	Events.chat_input_opened.emit()
	Events.match_scope_reset.emit()
	assert_true(controller.input_enabled)
	assert_false(rig.is_input_blocked())


func test_reset_with_results_and_pause_open_enables_controller_input_despite_pause() -> void:
	var controller: PlayerController = _make_controller()
	var rig: CameraRig = _make_rig()
	Events.match_results_ready.emit({})
	Events.pause_menu_opened.emit()
	Events.match_scope_reset.emit()
	assert_true(controller.input_enabled, "results reset forces input on even with pause open")
	assert_false(rig.is_input_blocked())
	# The controller's pause flag still survives: chat open/close turns input back off.
	Events.chat_input_opened.emit()
	Events.chat_input_closed.emit()
	assert_false(controller.input_enabled)
