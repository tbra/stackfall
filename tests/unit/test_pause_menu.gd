extends GutTest
## Bontago-xtq.42 (M7 P42, owner playtest: "there's no pause menu, I can't
## abandon a game and go back to the main menu or quit the game").
##
## Same deterministic-equivalent-of-a-real-input technique
## tests/unit/test_tuning_panel.gd's own header documents: driving
## _unhandled_input() directly with a synthetic InputEventKey/
## InputEventJoypadButton is the headless stand-in for a real Escape/gamepad
## Start press (this environment's own operating notes: synthetic OS keyboard
## injection does not reach a real game window here).

var _menu: PauseMenu = null


func before_each() -> void:
	_menu = autofree(load("res://ui/PauseMenu.tscn").instantiate())
	add_child_autofree(_menu)


func after_each() -> void:
	Input.action_release(&"pause_menu")
	_quit_called = false


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


# --- Escape / gamepad Start toggles visibility --------------------------------

func test_escape_toggles_visibility_both_ways() -> void:
	var event: InputEventKey = _key_press(KEY_ESCAPE)
	assert_true(event.is_action_pressed(&"pause_menu"), "Escape should map to pause_menu")

	assert_false(_menu.visible)
	_menu._unhandled_input(event)
	assert_true(_menu.visible)
	_menu._unhandled_input(event)
	assert_false(_menu.visible)


func test_gamepad_start_toggles_visibility() -> void:
	var event: InputEventJoypadButton = _pad_press(JOY_BUTTON_START)
	assert_true(event.is_action_pressed(&"pause_menu"), "gamepad Start should map to pause_menu")

	assert_false(_menu.visible)
	_menu._unhandled_input(event)
	assert_true(_menu.visible)


# --- Suppressed while Tutorial owns the scene ---------------------------------

func test_suppressed_blocks_the_toggle() -> void:
	_menu.suppressed = true
	_menu._unhandled_input(_key_press(KEY_ESCAPE))
	assert_false(_menu.visible, "suppressed must block pause_menu entirely (Tutorial owns the scene).")


# --- force_close(): game/Main.gd's safety net (Bontago-xtq.42 fix round 2) -----

func test_force_close_is_a_noop_when_already_closed() -> void:
	watch_signals(Events)

	_menu.force_close()

	assert_false(_menu.visible)
	assert_signal_not_emitted(Events, "pause_menu_closed", "force_close() must not fire Events.pause_menu_closed when there was nothing open to close.")


func test_force_close_closes_and_restores_controller_input_when_open() -> void:
	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	_menu._unhandled_input(_key_press(KEY_ESCAPE))  # open
	assert_false(controller.input_enabled, "fixture: opening suppressed input")

	_menu.force_close()

	assert_false(_menu.visible, "force_close() must close the overlay even when the match ended some other way (e.g. a host disconnect).")
	assert_true(controller.input_enabled, "force_close() must still restore gameplay input via Events.pause_menu_closed.")


# --- Events.pause_menu_opened/closed + PlayerController.input_enabled ---------

func test_opening_emits_pause_menu_opened_and_suppresses_controller_input() -> void:
	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	assert_true(controller.input_enabled, "fixture: input starts enabled")

	_menu._unhandled_input(_key_press(KEY_ESCAPE))

	assert_true(_menu.visible)
	assert_false(controller.input_enabled, "opening the pause menu must suppress gameplay input")


func test_closing_emits_pause_menu_closed_and_restores_controller_input() -> void:
	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)

	_menu._unhandled_input(_key_press(KEY_ESCAPE))  # open
	assert_false(controller.input_enabled, "fixture: opening suppressed input")

	_menu._unhandled_input(_key_press(KEY_ESCAPE))  # close
	assert_true(controller.input_enabled, "closing the pause menu must restore gameplay input")


# --- Resume button -------------------------------------------------------------

func test_resume_button_closes_the_menu() -> void:
	_menu._unhandled_input(_key_press(KEY_ESCAPE))
	assert_true(_menu.visible, "fixture: opened.")

	_menu._on_resume_pressed()

	assert_false(_menu.visible)


func test_open_grabs_focus_on_the_resume_button() -> void:
	_menu._unhandled_input(_key_press(KEY_ESCAPE))
	assert_true(_menu._resume_button.has_focus(), "opening must grab focus so gamepad/keyboard navigation works immediately.")


# --- Options: overlay-over-background + re-entrancy guard --------------------

func test_options_button_opens_options_and_hides_center() -> void:
	_menu._unhandled_input(_key_press(KEY_ESCAPE))  # open

	_menu._on_options_pressed()

	assert_false(_menu._center.visible, "Options must hide this menu's own %Center so Options's background shows the pause overlay behind it.")
	assert_not_null(_menu._options_menu)


func test_options_closed_restores_center_and_focus() -> void:
	_menu._unhandled_input(_key_press(KEY_ESCAPE))  # open
	_menu._on_options_pressed()

	_menu._on_options_closed()

	assert_true(_menu._center.visible)
	assert_null(_menu._options_menu)
	assert_true(_menu._options_button.has_focus())


func test_pause_menu_ignored_while_options_is_open() -> void:
	_menu._unhandled_input(_key_press(KEY_ESCAPE))  # open
	_menu._on_options_pressed()

	# A second Start/Escape press while Options owns the scene must do
	# nothing -- the _options_menu != null guard in _unhandled_input().
	_menu._unhandled_input(_pad_press(JOY_BUTTON_START))

	assert_true(_menu.visible, "the pause menu itself must stay open (Options is a child overlay of it).")
	assert_not_null(_menu._options_menu, "the guard must have skipped the toggle, leaving Options open.")


# --- Leave match: confirmation gate --------------------------------------------
#
# GUT's own watch_signals()/assert_signal_emitted() idiom (tests/unit/
# test_field.gd, tests/unit/test_gift_claim.gd), not a lambda closing over a
# local bool -- GDScript lambdas capture outer locals by value, not by
# reference, so `func() -> void: emitted = true` would only ever flip its own
# private snapshot and never the test method's own `emitted` variable.

func test_leave_button_does_not_emit_before_confirmation() -> void:
	watch_signals(_menu)

	_menu._on_leave_pressed()

	assert_signal_not_emitted(_menu, "leave_match_requested", "pressing Leave must only open the confirmation dialog, not leave immediately.")
	assert_true(_menu._confirm_dialog.visible)


func test_leave_confirmed_emits_leave_match_requested_and_closes() -> void:
	_menu._unhandled_input(_key_press(KEY_ESCAPE))  # open
	watch_signals(_menu)

	_menu._on_leave_pressed()
	_menu._on_confirm_dialog_confirmed()

	assert_signal_emitted(_menu, "leave_match_requested", "confirming Leave must emit leave_match_requested.")
	assert_false(_menu.visible, "confirming Leave must also close this overlay.")


# --- Quit: confirmation gate + Callable test seam ------------------------------
#
# quit_callable is a plain Callable field, not a signal, so watch_signals()
# doesn't apply -- a bound method on this test script (captured by reference
# via `self`, unlike a lambda's captured locals) is the reliable stand-in.

var _quit_called: bool = false


func _mark_quit_called() -> void:
	_quit_called = true


func test_quit_button_does_not_call_quit_before_confirmation() -> void:
	_menu.quit_callable = _mark_quit_called

	_menu._on_quit_pressed()

	assert_false(_quit_called, "pressing Quit must only open the confirmation dialog, not quit immediately.")
	assert_true(_menu._confirm_dialog.visible)


func test_quit_confirmed_invokes_the_quit_callable() -> void:
	_menu.quit_callable = _mark_quit_called

	_menu._on_quit_pressed()
	_menu._on_confirm_dialog_confirmed()

	assert_true(_quit_called, "confirming Quit must invoke quit_callable.")


func test_leave_and_quit_pending_actions_do_not_cross_contaminate() -> void:
	# Press Leave, then Quit, without ever confirming -- only the most recent
	# pending action should fire on confirm (the shared ConfirmationDialog's
	# own _pending_action selection this class documents).
	watch_signals(_menu)
	_menu.quit_callable = _mark_quit_called

	_menu._on_leave_pressed()
	_menu._on_quit_pressed()
	_menu._on_confirm_dialog_confirmed()

	assert_signal_not_emitted(_menu, "leave_match_requested", "Quit was pressed last -- Leave must not fire.")
	assert_true(_quit_called, "Quit was pressed last -- confirming must invoke it.")


# --- Focus chain: wraps top to bottom -----------------------------------------

func test_focus_chain_top_and_bottom_wrap() -> void:
	# _wire_focus_chain() sets focus_neighbor_top/bottom as NodePaths relative
	# to each button -- resolve them back to Control nodes and check the ring.
	var resume: Button = _menu._resume_button
	var options: Button = _menu._options_button
	var leave: Button = _menu._leave_button
	var quit: Button = _menu._quit_button

	assert_eq(resume.get_node(resume.focus_neighbor_bottom), options)
	assert_eq(options.get_node(options.focus_neighbor_bottom), leave)
	assert_eq(leave.get_node(leave.focus_neighbor_bottom), quit)
	assert_eq(quit.get_node(quit.focus_neighbor_bottom), resume, "the chain must wrap from the last button back to the first.")

	assert_eq(resume.get_node(resume.focus_neighbor_top), quit, "the chain must wrap from the first button back to the last.")
	assert_eq(options.get_node(options.focus_neighbor_top), resume)
	assert_eq(leave.get_node(leave.focus_neighbor_top), options)
	assert_eq(quit.get_node(quit.focus_neighbor_top), leave)
