extends GutTest
## F4 tuning panel access: opens in every build (debug off) from F4 and gamepad Start + X, and who can
## edit. Offline and the host edit; an online client sees the panel read-only. Everything goes
## through the input path and the controls a player uses.

const EDIT_PROBE_SLIDERS: int = 6
const SETTLE_FRAMES: int = 2

var _panel: TuningPanel = null
var _snapshot: Array[Dictionary] = []


func before_each() -> void:
	DebugMode.set_override_for_test(false)
	_panel = autofree(load("res://ui/debug/TuningPanel.tscn").instantiate())
	add_child_autofree(_panel)
	_snapshot = _snapshot_values(_resources(_panel))


func after_each() -> void:
	if _panel != null and _panel.visible:
		_panel.visible = false
	Input.action_release(&"pause_menu")
	for entry: Dictionary in _snapshot:
		(entry["resource"] as Resource).set(entry["property"] as String, entry["value"])
	_snapshot = []
	DebugMode.clear_override_for_test()


func _resources(panel: TuningPanel) -> Array[Resource]:
	return [
		panel.camera_tuning, panel.ghost_tuning, panel.physics_tuning,
		panel.territory_tuning, panel.territory_visuals, panel.block_feed_config,
	]


func _snapshot_values(resources: Array[Resource]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for resource: Resource in resources:
		for info: Dictionary in resource.get_property_list():
			if int(info["usage"]) & PROPERTY_USAGE_STORAGE == 0 or int(info["usage"]) & PROPERTY_USAGE_EDITOR == 0:
				continue
			var type: int = int(info["type"])
			if type == TYPE_FLOAT or type == TYPE_INT or type == TYPE_BOOL:
				out.append({"resource": resource, "property": info["name"], "value": resource.get(info["name"])})
	return out


func _changed_count() -> int:
	var changed: int = 0
	for entry: Dictionary in _snapshot:
		if (entry["resource"] as Resource).get(entry["property"] as String) != entry["value"]:
			changed += 1
	return changed


func _key_f4() -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.device = -1
	event.physical_keycode = KEY_F4
	event.pressed = true
	return event


func _key_action(action: StringName) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.pressed = true
	for candidate: InputEvent in InputMap.action_get_events(action):
		if candidate is InputEventKey:
			event.keycode = (candidate as InputEventKey).keycode
			break
	return event


func _pad_x() -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = -1
	event.button_index = JOY_BUTTON_X
	event.pressed = true
	return event


## Opens the panel the way a player does (F4) and shows the first tab.
func _open_with_f4() -> void:
	Input.parse_input_event(_key_f4())
	await wait_physics_frames(SETTLE_FRAMES)


## Drives the first visible sliders with the keyboard the way a player edits a value: focus, then
## jump to the end and to the start of the range.
func _try_editing_sliders() -> void:
	var tabs: TabContainer = _panel.find_children("*", "TabContainer", true, false)[0] as TabContainer
	tabs.current_tab = 0
	await wait_physics_frames(SETTLE_FRAMES)
	var tried: int = 0
	for node: Node in tabs.get_current_tab_control().find_children("*", "HSlider", true, false):
		var slider: HSlider = node as HSlider
		if not slider.is_visible_in_tree():
			continue
		slider.grab_focus()
		slider.get_viewport().push_input(_key_action(&"ui_end"))
		await wait_physics_frames(1)
		slider.get_viewport().push_input(_key_action(&"ui_home"))
		await wait_physics_frames(1)
		tried += 1
		if tried >= EDIT_PROBE_SLIDERS:
			break
	assert_gt(tried, 0, "fixture: the panel shows sliders to edit")


func test_f4_opens_and_closes_with_debug_off() -> void:
	assert_false(DebugMode.is_enabled(), "fixture: debug is off")
	assert_false(_panel.visible)
	await _open_with_f4()
	assert_true(_panel.visible, "F4 opens the panel in a build with debug off")
	await _open_with_f4()
	assert_false(_panel.visible, "F4 closes it again")


func test_start_plus_x_opens_with_debug_off() -> void:
	Input.action_press(&"pause_menu")
	Input.parse_input_event(_pad_x())
	await wait_physics_frames(SETTLE_FRAMES)
	assert_true(_panel.visible, "Start held and X pressed opens the panel with debug off")


func test_x_alone_on_the_pad_does_not_open() -> void:
	Input.parse_input_event(_pad_x())
	await wait_physics_frames(SETTLE_FRAMES)
	assert_false(_panel.visible, "X without Start is hover_lower, not the toggle")


func test_offline_editing_still_works() -> void:
	_panel.net_provider = FakeNet.offline()
	await _open_with_f4()
	await _try_editing_sliders()
	assert_gt(_changed_count(), 0, "an offline player's edit reaches the resource")


func test_host_can_edit_in_an_online_match() -> void:
	_panel.net_provider = FakeNet.host()
	await _open_with_f4()
	await _try_editing_sliders()
	assert_gt(_changed_count(), 0, "the host's edit reaches the resource")


func test_client_opens_the_panel_but_cannot_change_a_value() -> void:
	_panel.net_provider = FakeNet.client(0)
	await _open_with_f4()
	assert_true(_panel.visible, "a client can open F4 to read it")
	await _try_editing_sliders()
	assert_eq(_changed_count(), 0, "a client's edit leaves every resource value unchanged")
