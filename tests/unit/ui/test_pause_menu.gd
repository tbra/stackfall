extends GutTest
## Bontago-xtq.42 (M7 P42, owner playtest: "there's no pause menu, I can't
## abandon a game and go back to the main menu or quit the game").
##
## Same deterministic-equivalent-of-a-real-input technique
## tests/unit/ui/test_tuning_panel.gd's own header documents: driving
## _unhandled_input() directly with a synthetic InputEventKey/
## InputEventJoypadButton is the headless stand-in for a real Escape/gamepad
## Start press (this environment's own operating notes: synthetic OS keyboard
## injection does not reach a real game window here).

var _menu: PauseMenu = null


func before_each() -> void:
	_menu = autofree(load("res://ui/menus/PauseMenu.tscn").instantiate())
	add_child_autofree(_menu)


func after_each() -> void:
	Input.action_release(&"pause_menu")
	# Bontago-1pi.15.1: the real gamepad-button tests below flip the Settings
	# autoload's own active_input_device() to DEVICE_GAMEPAD as a side effect
	# of routing a real InputEventJoypadButton through Input.parse_input_event()
	# -- reset it so a later test file in the same run (e.g. test_key_rebind_
	# row.gd's own glyph-count assertions) doesn't inherit gamepad mode from
	# this file, the same reset tests/unit/ui/test_options_menu.gd's own
	# after_each() already performs for its own gamepad tests.
	Settings.set_active_input_device_for_test(Settings.DEFAULT_ACTIVE_DEVICE)


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


## Bontago-1pi.15.1 ("B never goes back in any menu"): gamepad B is
## ui_cancel's own binding now (tools/bootstrap_project.gd) -- proves the real
## InputMap route, not just a synthetic ui_cancel InputEventAction.
func test_gamepad_b_closes_the_open_menu() -> void:
	var event: InputEventJoypadButton = _pad_press(JOY_BUTTON_B)
	assert_true(event.is_action_pressed(&"ui_cancel"), "gamepad B should map to ui_cancel")

	_menu._unhandled_input(_pad_press(JOY_BUTTON_START))  # open
	assert_true(_menu.visible, "fixture: opened.")

	_menu._unhandled_input(event)
	assert_false(_menu.visible, "gamepad B must close the pause menu the same way ui_cancel/Escape does.")


# --- Suppressed while Tutorial owns the scene ---------------------------------

func test_suppressed_blocks_the_toggle() -> void:
	_menu.suppressed = true
	_menu._unhandled_input(_key_press(KEY_ESCAPE))
	assert_false(_menu.visible, "suppressed must block pause_menu entirely (Tutorial owns the scene).")


# --- force_close(): game/main/Main.gd's safety net (Bontago-xtq.42 fix round 2) -----

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
# test_field.gd, tests/unit/gifts/test_gift_claim.gd), not a lambda closing over a
# local bool -- GDScript lambdas capture outer locals by value, not by
# reference, so `func() -> void: emitted = true` would only ever flip its own
# private snapshot and never the test method's own `emitted` variable.

func test_leave_confirmed_emits_leave_match_requested_and_closes() -> void:
	_menu._unhandled_input(_key_press(KEY_ESCAPE))  # open
	watch_signals(_menu)

	_menu._on_leave_pressed()
	_menu._on_confirm_dialog_confirmed()

	assert_signal_emitted(_menu, "leave_match_requested", "confirming Leave must emit leave_match_requested.")
	assert_false(_menu.visible, "confirming Leave must also close this overlay.")


# --- Quit game: removed outright (Bontago-1pi.7, owner: "remove quit game as
# an option") -- no button, no handler, no confirmation path left to test.

# --- Focus chain: wraps top to bottom -----------------------------------------

## Headless viewports do not deliver hover/click to the GUI here, so this
## mirrors Godot's mouse pick: layers top-down (CanvasLayer.layer, then later
## tree order on top), first visible Control under the point whose
## mouse_filter is not IGNORE receives the click.
func _pick_topmost_control(point: Vector2) -> Control:
	var layers: Array[CanvasLayer] = []
	for child: Node in get_tree().root.get_children():
		if child is CanvasLayer:
			layers.append(child as CanvasLayer)
	for node: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if not layers.has(node):
			layers.append(node as CanvasLayer)
	layers.sort_custom(func(a: CanvasLayer, b: CanvasLayer) -> bool: return a.layer < b.layer)
	for i: int in range(layers.size() - 1, -1, -1):
		var controls: Array[Node] = layers[i].find_children("*", "Control", true, false)
		controls.reverse()
		for node: Node in controls:
			var control: Control = node as Control
			if control.is_visible_in_tree() and control.mouse_filter != Control.MOUSE_FILTER_IGNORE 					and control.get_global_rect().has_point(point):
				return control
	return null


func test_options_tab_buttons_are_the_topmost_mouse_target_over_the_hud() -> void:
	var hud: CanvasLayer = load("res://ui/hud/HUD.tscn").instantiate()
	add_child_autofree(hud)
	_menu._open()
	_menu._on_options_pressed()
	await get_tree().process_frame
	await get_tree().process_frame
	var options: OptionsMenu = _menu._options_menu
	for path: String in ["%SettingsTabButton", "%ControlsTabButton"]:
		var tab: Button = options.get_node(path)
		var target: Control = _pick_topmost_control(tab.get_global_rect().get_center())
		assert_eq(target, tab, "%s must be the topmost clickable control, not a HUD control." % path)
