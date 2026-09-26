extends GutTest
## Bontago-8or.19: reproduces the owner's exported-build playtest finding
## ("clicking a mapped row does not enter listening mode") by pushing
## synthetic input into a real, fixed-size SubViewport containing the real
## KeyRebindRow scene -- sidestepping two artifacts that made the earlier,
## Input.parse_input_event()-based version of this test unreliable:
## (1) GUT's headless root Window defaults to a 64x64 size, so a click at the
## button's real get_global_rect() center often lands outside the window
## entirely; (2) the project's own windowed off-screen probe convention
## (tools/screenshot_m7p7_menu.gd's own header comment) documents that
## Windows clamps an off-screen window to a tiny size too, so even a real
## windowed run can't be trusted for GUI click coordinates -- that tool
## renders into a fixed-size SubViewport and captures that for exactly this
## reason. A SubViewport sized explicitly (this file reuses that same
## 1280x720) and fed via Viewport.push_input() (which targets *that*
## viewport, unlike the global Input.parse_input_event(), which always
## targets the SceneTree's root viewport) gives the row a realistic, real
## Control/Button layout with neither artifact, fully headlessly.

const KEY_REBIND_ROW_SCENE: PackedScene = preload("res://ui/KeyRebindRow.tscn")
const DEFAULT_SETTINGS_CFG_PATH: String = "user://settings.cfg"
const VIEWPORT_SIZE: Vector2i = Vector2i(1280, 720)

var _test_action: StringName = &"key_rebind_row_test_action"
var _sub_viewport: SubViewport = null
var _row: KeyRebindRow = null
var _cover: ColorRect = null


func before_each() -> void:
	if not InputMap.has_action(_test_action):
		InputMap.add_action(_test_action)
	_sub_viewport = SubViewport.new()
	_sub_viewport.size = VIEWPORT_SIZE
	_sub_viewport.disable_3d = true
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child_autofree(_sub_viewport)

	# Stands in for ui/OptionsMenu.tscn's own full-screen "Background" ColorRect
	# (mouse_filter defaults to STOP for a Control): added *before* _row below,
	# so it sits behind the row and never steals a click on the RebindButton
	# itself, but still covers every other point in the viewport -- exactly the
	# panel that swallowed a rebind-to-mouse-button click under the old
	# _unhandled_input() capture (Bontago-8or.19).
	_cover = ColorRect.new()
	_cover.size = Vector2(VIEWPORT_SIZE)
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	_sub_viewport.add_child(_cover)

	_row = KEY_REBIND_ROW_SCENE.instantiate()
	_sub_viewport.add_child(_row)
	_row.setup(_test_action)


func after_each() -> void:
	if InputMap.has_action(_test_action):
		InputMap.erase_action(_test_action)
	Settings.set_config_path_for_test(DEFAULT_SETTINGS_CFG_PATH)
	_row = null
	_sub_viewport = null
	_cover = null


## Coordinates read back from the row's own Button are already expressed in
## this SubViewport's own local space (it is the topmost/root viewport of
## this tiny tree, no parent viewport transform to convert through), so
## in_local_coords is passed true rather than left at push_input()'s default
## "containing window" interpretation, which does not apply here.
func _click_button(button: Button) -> void:
	_click_at(button.get_global_rect().get_center())


## Same press+release construction as _click_button() above, at an arbitrary
## viewport point rather than a specific Control's own rect -- used to click
## the covering Control (_cover) instead of the RebindButton.
func _click_at(point: Vector2) -> void:
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = point
	press.global_position = point
	_sub_viewport.push_input(press, true)
	var release: InputEventMouseButton = InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = point
	release.global_position = point
	_sub_viewport.push_input(release, true)


func _press_key(keycode: Key) -> void:
	var key_event: InputEventKey = InputEventKey.new()
	key_event.keycode = keycode
	key_event.physical_keycode = keycode
	key_event.pressed = true
	_sub_viewport.push_input(key_event, true)


func test_real_click_on_rebind_button_enters_listening_state() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	_click_button(_row.rebind_button())
	await get_tree().process_frame

	assert_true(_row.is_listening(), "a real click on the RebindButton must start listening")


func test_real_click_then_real_key_press_replaces_the_binding() -> void:
	var cfg_path: String = OS.get_user_data_dir().path_join("test_key_rebind_row_kbd_tmp.cfg")
	if FileAccess.file_exists(cfg_path):
		DirAccess.remove_absolute(cfg_path)
	Settings.set_config_path_for_test(cfg_path)

	await get_tree().process_frame
	await get_tree().process_frame

	_click_button(_row.rebind_button())
	await get_tree().process_frame
	assert_true(_row.is_listening(), "must be listening before the key press")

	var key_press: InputEventKey = InputEventKey.new()
	key_press.keycode = KEY_F9
	key_press.physical_keycode = KEY_F9
	key_press.pressed = true
	_sub_viewport.push_input(key_press, true)
	await get_tree().process_frame

	assert_false(_row.is_listening(), "the key press must end the listening state")
	var events: Array[InputEvent] = InputMap.action_get_events(_test_action)
	assert_eq(events.size(), 1)
	assert_true(events[0] is InputEventKey)
	assert_eq((events[0] as InputEventKey).keycode, KEY_F9)

	if FileAccess.file_exists(cfg_path):
		DirAccess.remove_absolute(cfg_path)


func test_the_click_that_starts_listening_is_not_itself_captured_as_the_new_binding() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	_click_button(_row.rebind_button())
	await get_tree().process_frame

	assert_true(_row.is_listening(), "must be listening after the click")
	assert_eq(InputMap.action_get_events(_test_action).size(), 0, "the click that started listening must not itself become the new binding")


## Bontago-8or.19 (owner playtest feedback/playtest.md: "no option to
## actually remap the ones that are mapped"). Each of these was, before the
## _input() fix, either swallowed by the still-focused RebindButton's own GUI
## accelerator/focus-navigation handling (Space, Enter, Left, Tab) or by the
## full-screen mouse_filter=STOP _cover Control (the mouse click) -- neither
## ever reached ui/KeyRebindRow.gd's old _unhandled_input().
func _assert_key_replaces_binding(keycode: Key, cfg_name: String) -> void:
	var cfg_path: String = OS.get_user_data_dir().path_join("test_key_rebind_row_%s_tmp.cfg" % cfg_name)
	if FileAccess.file_exists(cfg_path):
		DirAccess.remove_absolute(cfg_path)
	Settings.set_config_path_for_test(cfg_path)

	await get_tree().process_frame
	await get_tree().process_frame

	_click_button(_row.rebind_button())
	await get_tree().process_frame
	assert_true(_row.is_listening(), "must be listening before the key press")

	_press_key(keycode)
	await get_tree().process_frame

	assert_false(_row.is_listening(), "the key press must end the listening state")
	var events: Array[InputEvent] = InputMap.action_get_events(_test_action)
	assert_eq(events.size(), 1)
	assert_true(events[0] is InputEventKey)
	assert_eq((events[0] as InputEventKey).keycode, keycode)

	var binding_label: Label = _row.get_node("%BindingLabel") as Label
	assert_eq(binding_label.text, events[0].as_text(), "the binding label must reflect the new binding")

	var persisted: Array[InputEvent] = Settings.key_override_events(_test_action)
	assert_eq(persisted.size(), 1)
	assert_true(persisted[0] is InputEventKey)
	assert_eq((persisted[0] as InputEventKey).keycode, keycode, "the new binding must persist through Settings")

	if FileAccess.file_exists(cfg_path):
		DirAccess.remove_absolute(cfg_path)


func test_space_key_replaces_the_binding() -> void:
	await _assert_key_replaces_binding(KEY_SPACE, "space")


func test_enter_key_replaces_the_binding() -> void:
	await _assert_key_replaces_binding(KEY_ENTER, "enter")


func test_left_arrow_key_replaces_the_binding() -> void:
	await _assert_key_replaces_binding(KEY_LEFT, "left")


func test_tab_key_replaces_the_binding() -> void:
	await _assert_key_replaces_binding(KEY_TAB, "tab")


func test_click_over_the_covering_control_while_listening_replaces_the_binding() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	_click_button(_row.rebind_button())
	await get_tree().process_frame
	assert_true(_row.is_listening(), "must be listening before the second click")
	assert_eq(InputMap.action_get_events(_test_action).size(), 0, "must not be bound yet")

	# Far corner of the viewport, well outside the row's own small rect at
	# (0, 0) -- this point only ever hits _cover, the mouse_filter=STOP
	# Control standing in for OptionsMenu.tscn's full-screen Background.
	var cover_point: Vector2 = Vector2(_sub_viewport.size) - Vector2(40.0, 40.0)
	_click_at(cover_point)
	await get_tree().process_frame

	assert_false(_row.is_listening(), "a click over the covering Control must end the listening state")
	var events: Array[InputEvent] = InputMap.action_get_events(_test_action)
	assert_eq(events.size(), 1)
	assert_true(events[0] is InputEventMouseButton)
	assert_eq((events[0] as InputEventMouseButton).button_index, MOUSE_BUTTON_LEFT)


func test_ui_cancel_while_listening_cancels_without_binding() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	_click_button(_row.rebind_button())
	await get_tree().process_frame
	assert_true(_row.is_listening(), "must be listening before ui_cancel")

	_press_key(KEY_ESCAPE)
	await get_tree().process_frame

	assert_false(_row.is_listening(), "ui_cancel must end the listening state")
	assert_eq(InputMap.action_get_events(_test_action).size(), 0, "ui_cancel must not bind anything")


func test_key_press_is_not_consumed_when_not_listening() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	assert_false(_row.is_listening(), "must not be listening without a prior click on the RebindButton")
	_press_key(KEY_F9)
	await get_tree().process_frame

	assert_false(_sub_viewport.is_input_handled(), "a key press must not be swallowed when no row is listening")
	assert_eq(InputMap.action_get_events(_test_action).size(), 0)
