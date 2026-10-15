extends GutTest
## Bontago-1pi.159.15 (N1): focus must not escape an overlay into the screen behind it.
## Owner: "hovering a dropdown and going left/right on stick or arrow keys moves my selection to
## the main menu". find_valid_focus_neighbor() is the engine's own resolution of ui_left / right /
## up / down, so asserting on it is the headless stand-in for the real stick press.

const SIDES: Array[Side] = [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]


func _button(parent: Node, text: String, pos: Vector2) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.name = text
	button.position = pos
	button.size = Vector2(100.0, 30.0)
	parent.add_child(button)
	return button


## Left "menu" buttons, right "overlay" with a lone control: the engine's spatial search from
## the overlay control would otherwise land on a menu button.
func _stage() -> Dictionary:
	var stage: Control = Control.new()
	add_child_autofree(stage)
	var menu: Control = Control.new()
	stage.add_child(menu)
	var overlay: Control = Control.new()
	stage.add_child(overlay)
	var menu_buttons: Array[Control] = [
		_button(menu, "A", Vector2(0.0, 0.0)), _button(menu, "B", Vector2(0.0, 60.0)),
	]
	var lone: Button = _button(overlay, "Dropdown", Vector2(200.0, 0.0))
	var other: Button = _button(overlay, "Other", Vector2(200.0, 60.0))
	return {"menu": menu, "overlay": overlay, "menu_buttons": menu_buttons, "lone": lone, "other": other}


func _escapes(root: Control) -> Array[String]:
	var bad: Array[String] = []
	for control: Control in UiFocusTrap.focusables(root):
		for side: Side in SIDES:
			var target: Control = control.find_valid_focus_neighbor(side)
			if target != null and target != root and not root.is_ancestor_of(target):
				bad.append("%s side %d -> %s" % [control.name, side, target.name])
	return bad


func test_repro_without_trap_focus_leaves_the_overlay() -> void:
	var stage: Dictionary = _stage()
	var lone: Button = stage["lone"] as Button
	var target: Control = lone.find_valid_focus_neighbor(SIDE_LEFT)
	assert_true(target != null and (stage["menu"] as Control).is_ancestor_of(target),
		"the unfixed engine default sends 'left' from the lone overlay control into the menu")


func test_trap_keeps_every_direction_inside_root() -> void:
	var stage: Dictionary = _stage()
	UiFocusTrap.trap(stage["overlay"] as Control)
	assert_eq(_escapes(stage["overlay"] as Control), [] as Array[String])
	var lone: Button = stage["lone"] as Button
	assert_eq(lone.find_valid_focus_neighbor(SIDE_LEFT), lone, "no neighbour on that side: stay put")


func test_trap_redirects_neighbours_that_point_outside_and_keeps_inside_ones() -> void:
	var stage: Dictionary = _stage()
	var lone: Button = stage["lone"] as Button
	var other: Button = stage["other"] as Button
	var outside: Button = (stage["menu_buttons"] as Array[Control])[0] as Button
	lone.focus_neighbor_left = lone.get_path_to(outside)
	lone.focus_neighbor_bottom = lone.get_path_to(other)
	UiFocusTrap.trap(stage["overlay"] as Control)
	assert_eq(lone.find_valid_focus_neighbor(SIDE_LEFT), lone)
	assert_eq(lone.find_valid_focus_neighbor(SIDE_BOTTOM), other, "an inside neighbour is untouched")


func test_trap_wraps_next_and_previous_inside_root() -> void:
	var stage: Dictionary = _stage()
	UiFocusTrap.trap(stage["overlay"] as Control)
	var lone: Button = stage["lone"] as Button
	var other: Button = stage["other"] as Button
	assert_eq(lone.get_node(lone.focus_next), other)
	assert_eq(other.get_node(other.focus_next), lone)
	assert_eq(lone.get_node(lone.focus_previous), other)


func test_suspend_outside_clears_and_restores_focus_modes() -> void:
	var stage: Dictionary = _stage()
	var menu_buttons: Array[Control] = stage["menu_buttons"] as Array[Control]
	var overlay: Control = stage["overlay"] as Control
	var restore: Callable = UiFocusTrap.suspend_outside(overlay, overlay.get_parent())
	for button: Control in menu_buttons:
		assert_eq(button.focus_mode, Control.FOCUS_NONE)
	assert_eq((stage["lone"] as Button).focus_mode, Control.FOCUS_ALL, "root itself is untouched")
	assert_null((stage["lone"] as Button).find_valid_focus_neighbor(SIDE_LEFT))
	restore.call()
	for button: Control in menu_buttons:
		assert_eq(button.focus_mode, Control.FOCUS_ALL)


# --- Real screens ---------------------------------------------------------------

func test_main_menu_controls_are_focus_none_while_options_is_open_and_restored_after() -> void:
	var menu: MainMenu = autofree(load("res://ui/menus/MainMenu.tscn").instantiate())
	add_child_autofree(menu)
	Net.stop_discovery()
	menu.net_provider = FakeNet.new()
	await get_tree().process_frame
	var before: Dictionary = {}
	for control: Control in menu._wired_controls():
		before[control] = control.focus_mode
	menu._on_options_pressed()
	assert_not_null(menu._options_menu)
	for control: Control in menu._wired_controls():
		assert_eq(control.focus_mode, Control.FOCUS_NONE, "%s must not take focus behind Options" % control.name)
	# Every direction from every Options focusable stays inside Options (the owner's repro).
	await get_tree().process_frame
	assert_eq(_escapes(menu._options_menu), [] as Array[String])
	menu._on_options_closed()
	for control: Control in menu._wired_controls():
		assert_eq(control.focus_mode, before[control], "%s focus mode restored" % control.name)


func test_pause_menu_focus_never_leaves_its_panel() -> void:
	var pause: PauseMenu = autofree(load("res://ui/menus/PauseMenu.tscn").instantiate())
	add_child_autofree(pause)
	pause._open()
	await get_tree().process_frame
	var panel: Control = pause._resume_button.get_parent() as Control
	assert_eq(_escapes(panel), [] as Array[String])
	assert_eq(pause._resume_button.find_valid_focus_neighbor(SIDE_LEFT), pause._resume_button)


func test_pause_options_suspends_pause_buttons_and_restores() -> void:
	var pause: PauseMenu = autofree(load("res://ui/menus/PauseMenu.tscn").instantiate())
	add_child_autofree(pause)
	pause._open()
	pause._on_options_pressed()
	assert_eq(pause._resume_button.focus_mode, Control.FOCUS_NONE)
	pause._on_options_closed()
	assert_eq(pause._resume_button.focus_mode, Control.FOCUS_ALL)


func test_results_screen_focus_never_leaves_the_screen() -> void:
	var screen: Control = autofree(load("res://ui/menus/ResultsScreen.tscn").instantiate())
	add_child_autofree(screen)
	await get_tree().process_frame
	assert_eq(_escapes(screen), [] as Array[String])


# --- Options window (Bontago-1pi.159.16 / .15, O2) --------------------------------

## Opens Options from the main menu (pause = false) or the pause menu and returns the window.
func _open_options(from_pause: bool) -> OptionsMenu:
	if from_pause:
		var pause: PauseMenu = autofree(load("res://ui/menus/PauseMenu.tscn").instantiate())
		add_child_autofree(pause)
		pause._open()
		pause._on_options_pressed()
		await get_tree().process_frame
		return pause._options_menu
	var menu: MainMenu = autofree(load("res://ui/menus/MainMenu.tscn").instantiate())
	add_child_autofree(menu)
	Net.stop_discovery()
	menu.net_provider = FakeNet.new()
	await get_tree().process_frame
	menu._on_options_pressed()
	await get_tree().process_frame
	return menu._options_menu


func _assert_options_trapped(options: OptionsMenu, label: String) -> void:
	for id: StringName in options._tabs.tab_ids():
		options._tabs.select(id)
		assert_eq(_escapes(options), [] as Array[String], "%s / tab %s: no direction leaves Options" % [label, id])
	options._tabs.select(OptionsMenu.TAB_GAME)
	# Owner's case: the dropdown with ui_left / ui_right pressed never leaves and never strands focus.
	var dropdown: Control = options._window_mode_option
	for side: Side in [SIDE_LEFT, SIDE_RIGHT]:
		var target: Control = dropdown.find_valid_focus_neighbor(side)
		assert_true(target == dropdown or options.is_ancestor_of(target), "%s: dropdown side %d stays in Options" % [label, side])
	# Focus can always move back: the vertical chain from the dropdown reaches the Back button and the tabs.
	var seen: Dictionary = {}
	var cursor: Control = dropdown
	while cursor != null and not seen.has(cursor):
		seen[cursor] = true
		cursor = cursor.find_valid_focus_neighbor(SIDE_BOTTOM)
	assert_true(seen.has(options._back_button), "%s: Back reachable from the dropdown by ui_down" % label)


func test_options_from_main_menu_traps_focus_on_every_tab() -> void:
	var options: OptionsMenu = await _open_options(false)
	assert_not_null(options)
	_assert_options_trapped(options, "main menu")


func test_options_from_pause_menu_traps_focus_on_every_tab() -> void:
	var options: OptionsMenu = await _open_options(true)
	assert_not_null(options)
	_assert_options_trapped(options, "pause menu")


func test_options_graphics_controls_are_trapped() -> void:
	var options: OptionsMenu = await _open_options(false)
	for control: Control in options._graphics_page.focus_controls():
		for side: Side in SIDES:
			var target: Control = control.find_valid_focus_neighbor(side)
			assert_true(target == null or target == options or options.is_ancestor_of(target), "%s side %d" % [control.name, side])
