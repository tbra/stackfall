extends GutTest
## Bontago-1pi.47 (owner playtest: "In menus that have scrolling, for example
## controller remapping, navigating with gamepad/arrow keys doesn't update the
## scroll position"). ui/OptionsMenu.tscn's Settings page and Controls rebind
## list are ui/FocusScrollContainer.gd; this drives real ui_up/ui_down through
## Input.parse_input_event (an InputEventKey arrow and an
## InputEventJoypadButton d-pad press, the same route a player's hardware takes)
## and checks the focused row is always inside the ScrollContainer's visible
## rect, the list actually scrolled, and the section caption above the first
## row comes back into view on the way up.

const OPTIONS_MENU_SCENE: PackedScene = preload("res://ui/OptionsMenu.tscn")
const LOBBY_SCENE: PackedScene = preload("res://ui/Lobby.tscn")
const SETTLE_FRAMES: int = 3
const EDGE_EPS: float = 1.0
const PAD_DEVICE: int = 0
## The Settings page fits a 720p panel outright, so the test shortens its view
## (what a small window or a long future settings list does) to force scrolling.
const SHORT_SETTINGS_VIEW_PX: float = 240.0


func after_each() -> void:
	Settings.set_active_input_device_for_test(Settings.DEFAULT_ACTIVE_DEVICE)


# --- harness ----------------------------------------------------------------

func _settle() -> void:
	for _i: int in SETTLE_FRAMES:
		await get_tree().process_frame


## `pad` selects the gamepad family: the menu is built with the gamepad device
## already active so the Controls page lists the gamepad rows from the start (a
## first d-pad press would otherwise flip the device and rewire the chain
## mid-walk).
func _make_menu(pad: bool) -> OptionsMenu:
	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD if pad else Settings.DEFAULT_ACTIVE_DEVICE)
	var menu: OptionsMenu = autofree(OPTIONS_MENU_SCENE.instantiate()) as OptionsMenu
	add_child_autofree(menu)
	await _settle()
	return menu


func _show_controls_tab(menu: OptionsMenu) -> ScrollContainer:
	(menu.get_node("%ControlsTabButton") as Button).button_pressed = true
	await _settle()
	return menu.get_node("%RebindScroll") as ScrollContainer


func _nav_event(pad: bool, down: bool, pressed: bool) -> InputEvent:
	if pad:
		var button: InputEventJoypadButton = InputEventJoypadButton.new()
		button.device = PAD_DEVICE
		button.button_index = JOY_BUTTON_DPAD_DOWN if down else JOY_BUTTON_DPAD_UP
		button.pressed = pressed
		return button
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_DOWN if down else KEY_UP
	key.physical_keycode = key.keycode
	key.pressed = pressed
	return key


## One press + release of ui_down/ui_up from the chosen device, then a few
## frames so the ScrollContainer has re-laid out its content.
func _tap(pad: bool, down: bool) -> void:
	Input.parse_input_event(_nav_event(pad, down, true))
	Input.flush_buffered_events()
	await get_tree().process_frame
	Input.parse_input_event(_nav_event(pad, down, false))
	Input.flush_buffered_events()
	await _settle()


func _focus_owner() -> Control:
	return get_viewport().gui_get_focus_owner()


func _inside(scroll: ScrollContainer, control: Control) -> bool:
	return scroll.get_global_rect().grow(EDGE_EPS).encloses(control.get_global_rect())


func _available_rows(menu: OptionsMenu) -> Array[KeyRebindRow]:
	var rows: Array[KeyRebindRow] = []
	for row: KeyRebindRow in menu.rebind_rows():
		if row.is_available_on_active_device():
			rows.append(row)
	return rows


func _assert_focus_in_view(scroll: ScrollContainer, expected: Control, label: String) -> void:
	assert_eq(_focus_owner(), expected, "%s: focus moved to the next row" % label)
	assert_true(_inside(scroll, expected),
		"%s: %s %s is inside the scroll view %s (scroll_vertical %d)" % [
			label, expected.name, expected.get_global_rect(), scroll.get_global_rect(), scroll.scroll_vertical])


# --- Controls rebind list ---------------------------------------------------------

func _walk_controls_list(pad: bool) -> void:
	var menu: OptionsMenu = await _make_menu(pad)
	var scroll: ScrollContainer = await _show_controls_tab(menu)
	var rows: Array[KeyRebindRow] = _available_rows(menu)
	var family: String = "pad" if pad else "key"
	assert_gt(rows.size(), 8, "%s: the controls list has enough rows to scroll" % family)
	assert_gt(scroll.get_v_scroll_bar().max_value, scroll.get_v_scroll_bar().page,
		"%s: the rebind list overflows its view (otherwise this proves nothing)" % family)

	rows[0].grab_focus()
	await _settle()
	assert_eq(scroll.scroll_vertical, 0, "%s: list starts at the top" % family)

	for i: int in range(1, rows.size()):
		await _tap(pad, true)
		_assert_focus_in_view(scroll, rows[i], "%s down step %d" % [family, i])
	assert_gt(scroll.scroll_vertical, 0, "%s: walking to the last row scrolled the list" % family)
	var bottom: int = scroll.scroll_vertical

	for i: int in range(rows.size() - 2, -1, -1):
		await _tap(pad, false)
		_assert_focus_in_view(scroll, rows[i], "%s up step %d" % [family, i])
	assert_lt(scroll.scroll_vertical, bottom, "%s: walking back up scrolled the list back" % family)
	assert_eq(scroll.scroll_vertical, 0, "%s: first row selected, the list is back at the top" % family)
	for caption: Control in (scroll as FocusScrollContainer).leading_captions(rows[0]):
		assert_true(_inside(scroll, caption), "%s: section caption %s visible above the first row" % [family, caption.name])


func test_keyboard_arrows_scroll_the_controls_list_down_and_up() -> void:
	await _walk_controls_list(false)


func test_gamepad_dpad_scrolls_the_controls_list_down_and_up() -> void:
	await _walk_controls_list(true)


## Walking up past a mid-list section's first row must keep that row's heading
## ("Rotation" above "Rotate left") in view, not just the row (plain
## follow_focus scrolls the minimum distance and clips the caption).
func test_moving_up_into_a_section_start_keeps_its_caption_visible() -> void:
	var menu: OptionsMenu = await _make_menu(false)
	var scroll: ScrollContainer = await _show_controls_tab(menu)
	var rows: Array[KeyRebindRow] = _available_rows(menu)
	var start: int = rows.size() - 1
	rows[start].grab_focus()
	await _settle()
	var target: int = 0
	for i: int in range(rows.size()):
		if rows[i].action_name() == &"rotate_yaw_ccw":
			target = i
	for _step: int in range(start - target):
		await _tap(false, false)
	assert_eq(_focus_owner(), rows[target], "focus reached the first Rotation row")
	var captions: Array[Control] = (scroll as FocusScrollContainer).leading_captions(rows[target])
	assert_eq(captions.size(), 1, "the Rotation heading precedes its first row")
	for caption: Control in captions:
		assert_true(_inside(scroll, caption), "heading %s visible (view %s, rect %s)" % [
			(caption as Label).text, scroll.get_global_rect(), caption.get_global_rect()])


# --- Settings page ----------------------------------------------------------------

func _walk_settings_page(pad: bool) -> void:
	var menu: OptionsMenu = await _make_menu(pad)
	var scroll: ScrollContainer = menu.get_node("%SettingsPage") as ScrollContainer
	scroll.size_flags_vertical = Control.SIZE_FILL
	scroll.custom_minimum_size = Vector2(0.0, SHORT_SETTINGS_VIEW_PX)
	await _settle()
	var chain: Array[Control] = [
		menu.get_node("%PresetOption") as Control,
		menu.get_node("%WindowModeOption") as Control,
		menu.get_node("%CameraShakeCheck") as Control,
		menu.get_node("%AdaptiveQualityCheck") as Control,
		menu.get_node("%MasterMuteButton") as Control,
		menu.get_node("%MasterVolumeSlider") as Control,
		menu.get_node("%MusicMuteButton") as Control,
		menu.get_node("%MusicVolumeSlider") as Control,
		menu.get_node("%SfxMuteButton") as Control,
		menu.get_node("%SfxVolumeSlider") as Control,
		menu.get_node("%WeatherMuteButton") as Control,
		menu.get_node("%WeatherVolumeSlider") as Control,
		menu.get_node("%RumbleEnabledCheck") as Control,
		menu.get_node("%RumbleStrengthSlider") as Control,
	]
	var family: String = "pad" if pad else "key"
	var visible_chain: Array[Control] = []
	for control: Control in chain:
		if control.is_visible_in_tree():
			visible_chain.append(control)
	assert_gt(visible_chain.size(), 6, "%s: settings page has focusable rows" % family)

	visible_chain[0].grab_focus()
	await _settle()
	for i: int in range(1, visible_chain.size()):
		await _tap(pad, true)
		_assert_focus_in_view(scroll, visible_chain[i], "%s settings down step %d" % [family, i])
	var scrolls: bool = scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page + EDGE_EPS
	assert_true(scrolls, "%s: the shortened settings page overflows its view (max %s, page %s)" % [
		family, scroll.get_v_scroll_bar().max_value, scroll.get_v_scroll_bar().page])
	assert_gt(scroll.scroll_vertical, 0, "%s: walking to the last setting scrolled the page" % family)
	for i: int in range(visible_chain.size() - 2, -1, -1):
		await _tap(pad, false)
		_assert_focus_in_view(scroll, visible_chain[i], "%s settings up step %d" % [family, i])
	assert_eq(scroll.scroll_vertical, 0, "%s: back at the first setting the page is at the top" % family)


func test_keyboard_arrows_keep_the_settings_page_focus_visible() -> void:
	await _walk_settings_page(false)


func test_gamepad_dpad_keeps_the_settings_page_focus_visible() -> void:
	await _walk_settings_page(true)


## Reproduction of the reported bug: with follow_focus off (what both Options
## scroll containers shipped with) the same arrow walk leaves the focused row
## outside the view. Proves the walk above would have caught it.
func test_without_follow_focus_the_walk_leaves_the_focused_row_off_screen() -> void:
	var menu: OptionsMenu = await _make_menu(false)
	var scroll: ScrollContainer = await _show_controls_tab(menu)
	scroll.follow_focus = false
	var rows: Array[KeyRebindRow] = _available_rows(menu)
	rows[0].grab_focus()
	await _settle()
	for _i: int in range(1, rows.size()):
		await _tap(false, true)
	assert_eq(_focus_owner(), rows[rows.size() - 1], "focus still reached the last row")
	assert_eq(scroll.scroll_vertical, 0, "nothing scrolled without follow_focus")
	assert_false(_inside(scroll, rows[rows.size() - 1]), "so the focused last row is outside the view")


# --- Focus after a rebind -----------------------------------------------------------

## A row drops focus while it listens (ui/KeyRebindRow.gd _on_pressed); once the
## capture is cancelled the list must keep navigating from that row instead of
## leaving the player with no focus (and so no scroll-follow) until a mouse click.
func test_cancelled_rebind_returns_focus_to_the_row_so_navigation_continues() -> void:
	var menu: OptionsMenu = await _make_menu(false)
	var scroll: ScrollContainer = await _show_controls_tab(menu)
	var rows: Array[KeyRebindRow] = _available_rows(menu)
	var row: KeyRebindRow = rows[rows.size() - 3]
	row.grab_focus()
	await _settle()
	row.rebind_button().pressed.emit()
	assert_true(row.is_listening(), "row is listening after activation")
	assert_null(_focus_owner(), "focus is released while listening")
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	Input.flush_buffered_events()
	await _settle()
	assert_false(row.is_listening(), "ui_cancel stops listening")
	assert_eq(_focus_owner(), row, "focus returns to the row after the capture ends")
	await _tap(false, true)
	_assert_focus_in_view(scroll, rows[rows.size() - 2], "down after a cancelled rebind")


# --- Scene wiring -----------------------------------------------------------------

func test_options_scroll_containers_follow_focus() -> void:
	var menu: OptionsMenu = await _make_menu(false)
	for path: String in ["%SettingsPage", "%RebindScroll"]:
		var scroll: ScrollContainer = menu.get_node(path) as ScrollContainer
		assert_true(scroll is FocusScrollContainer, "%s is a FocusScrollContainer" % path)
		assert_true(scroll.follow_focus, "%s follows focus" % path)
		assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED, "%s keeps horizontal scrolling off" % path)


func test_lobby_settings_scroll_follows_focus() -> void:
	var lobby: Node = autofree(LOBBY_SCENE.instantiate())
	var scroll: ScrollContainer = lobby.get_node("%SettingsScroll") as ScrollContainer
	assert_true(scroll.follow_focus, "the lobby settings column follows focus")


## The caption resolver on a hand-built list: a Label directly before a row (or
## before the HBox the row sits in) is a caption; the row's own inline label
## is revealed too, which is harmless; nothing precedes the first child.
func test_leading_captions_resolves_headings_before_rows_and_nested_rows() -> void:
	var scroll: FocusScrollContainer = FocusScrollContainer.new()
	var list: VBoxContainer = VBoxContainer.new()
	var heading: Label = Label.new()
	var first: Button = Button.new()
	var heading_two: Label = Label.new()
	var nested_row: HBoxContainer = HBoxContainer.new()
	var inline_label: Label = Label.new()
	var nested_button: Button = Button.new()
	scroll.add_child(list)
	for node: Node in [heading, first, heading_two, nested_row]:
		list.add_child(node)
	nested_row.add_child(inline_label)
	nested_row.add_child(nested_button)
	add_child_autofree(scroll)

	assert_true(scroll.follow_focus, "a FocusScrollContainer follows focus by default")
	var expected_first: Array[Control] = [heading]
	assert_eq(scroll.leading_captions(first), expected_first, "a row after a heading is captioned by it")
	assert_true(scroll.leading_captions(heading).is_empty(), "the first child has no caption")
	var nested: Array[Control] = scroll.leading_captions(nested_button)
	assert_true(nested.has(inline_label), "a nested row's own inline label is included")
	assert_true(nested.has(heading_two), "a nested row also gets the heading before its HBox")
