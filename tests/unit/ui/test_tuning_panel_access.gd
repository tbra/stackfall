extends GutTest
## F4 tuning panel access: opens in every build (debug off) from F4 and gamepad Start + X, and who can
## edit. Offline and the host edit; an online client sees the panel read-only. Everything goes
## through the input path and the controls a player uses.

const EDIT_PROBE_SLIDERS: int = 6
const SETTLE_FRAMES: int = 2

const CUSTOM_LOCKED_PHASE: float = 0.123


## A Skybox with a running cycle locked at a custom phase, so the Sky tab's time-of-day row is live.
class CyclingSky extends Skybox:
	func _ready() -> void:
		add_to_group(Skybox.TUNING_GROUP)

	func is_cycle_active() -> bool:
		return true

	func locked_phase() -> float:
		return CUSTOM_LOCKED_PHASE

	func current_cycle_phase() -> float:
		return CUSTOM_LOCKED_PHASE


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


func _is_edit_control(node: Node) -> bool:
	return node is Slider or node is SpinBox or node is OptionButton or node is CheckBox or node is CheckButton or node is ColorPickerButton


func _is_disabled(node: Node) -> bool:
	if node is Slider:
		return not (node as Slider).editable
	if node is SpinBox:
		return not (node as SpinBox).editable
	return (node as BaseButton).disabled


func _label_with_text(text: String) -> Label:
	for node: Node in _panel.find_children("*", "Label", true, false):
		if (node as Label).text == text:
			return node as Label
	return null


func test_client_finds_every_edit_control_disabled_on_every_visible_tab() -> void:
	add_child_autofree(CyclingSky.new())
	_panel.net_provider = FakeNet.client(0)
	await _open_with_f4()
	var tabs: TabContainer = _panel.find_children("*", "TabContainer", true, false)[0] as TabContainer
	var checked: int = 0
	var sky_seen: bool = false
	for index: int in tabs.get_tab_count():
		if tabs.is_tab_hidden(index):
			continue
		tabs.current_tab = index
		await wait_physics_frames(SETTLE_FRAMES)
		for node: Node in tabs.get_tab_control(index).find_children("*", "Control", true, false):
			if not _is_edit_control(node):
				continue
			checked += 1
			sky_seen = sky_seen or node.name == &"TimeOfDaySlider"
			assert_true(_is_disabled(node), "client: %s on tab %s is disabled" % [node.name, tabs.get_tab_title(index)])
	assert_gt(checked, 0, "fixture: client-visible tabs have edit controls")
	assert_true(sky_seen, "fixture: the Sky tab's time-of-day slider was checked")


func test_client_copy_still_works() -> void:
	_panel.net_provider = FakeNet.client(0)
	await _open_with_f4()
	var copy: Button = null
	for node: Node in _panel.find_children("*", "Button", true, false):
		if (node as Button).text == "Copy":
			copy = node as Button
	assert_not_null(copy, "fixture: the panel has a Copy button")
	assert_false(copy.disabled, "Copy stays enabled for a client")
	copy.pressed.emit()
	assert_not_null(_label_with_text("Copied."), "Copy reaches the clipboard path and reports Copied.")
