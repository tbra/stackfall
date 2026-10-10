class_name UiTabs
extends BoxContainer
## The design system Tabs (docs/ui_reskin/components.md "Tabs"): a bar of UiTab buttons with a
## `rim` notch on the active one. HORIZONTAL = top tabs (notch on top; Options GAME / GRAPHICS /
## CONTROLS, the owner's override of the side-tab form), VERTICAL = side tabs (notch on the left).
## One tab is always active. Mouse click selects; ui_left / ui_right (ui_up / ui_down when
## VERTICAL) on a focused tab selects its neighbour; LB / RB (menu_tab_previous / menu_tab_next)
## cycle while [member handle_shoulders] is on and the bar is visible. Hidden and disabled tabs
## are skipped. Labels are shown uppercase.

signal tab_changed(id: StringName)

enum Orientation { HORIZONTAL, VERTICAL }

@export var orientation: UiTabs.Orientation = UiTabs.Orientation.HORIZONTAL:
	set(value):
		orientation = value
		vertical = value == UiTabs.Orientation.VERTICAL
		for tab: UiTab in _tabs:
			tab.vertical = vertical
@export var handle_shoulders: bool = true
## The active tab id; assigning selects it (and emits tab_changed when it changed).
var current: StringName:
	get:
		return _current
	set(value):
		select(value)

var _tabs: Array[UiTab] = []
var _group: ButtonGroup = ButtonGroup.new()
var _current: StringName = &""


func _init() -> void:
	add_theme_constant_override("separation", MenuStyleFactory.arcade_tuning().space_1_px)
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN


## Appends a tab; the first one added becomes the active tab (without emitting tab_changed).
func add_tab(id: StringName, label: String) -> void:
	var tab: UiTab = UiTab.new().setup(id, label, orientation == UiTabs.Orientation.VERTICAL)
	tab.button_group = _group
	tab.pressed.connect(_on_tab_pressed.bind(id))
	tab.step_requested.connect(_on_step_requested.bind(id))
	add_child(tab)
	_tabs.append(tab)
	if _current == &"":
		_current = id
		tab.set_pressed_no_signal(true)


func tab_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for tab: UiTab in _tabs:
		ids.append(tab.id)
	return ids


func get_tab(id: StringName) -> UiTab:
	for tab: UiTab in _tabs:
		if tab.id == id:
			return tab
	return null


## Activates [param id] (ignored when unknown, hidden or disabled); emits tab_changed on a change.
func select(id: StringName, grab_focus_on_tab: bool = false) -> void:
	var tab: UiTab = get_tab(id)
	if tab == null or not tab.visible or tab.disabled:
		return
	if grab_focus_on_tab and tab.is_inside_tree():
		tab.grab_focus()
	if id == _current and tab.button_pressed:
		return
	_current = id
	for other: UiTab in _tabs:
		other.set_pressed_no_signal(other == tab)
	tab_changed.emit(id)


func set_tab_visible(id: StringName, shown: bool) -> void:
	var tab: UiTab = get_tab(id)
	if tab == null:
		return
	tab.visible = shown
	if not shown and id == _current:
		_move(1)


func set_tab_disabled(id: StringName, is_disabled: bool) -> void:
	var tab: UiTab = get_tab(id)
	if tab == null:
		return
	tab.disabled = is_disabled
	if is_disabled and id == _current:
		_move(1)


## The index after [param current_index] moved [param direction] among [param count] tabs (wraps).
static func next_index(current_index: int, direction: int, count: int) -> int:
	if count <= 0:
		return 0
	return posmod(current_index + signi(direction), count)


func _index_of(id: StringName) -> int:
	for i: int in _tabs.size():
		if _tabs[i].id == id:
			return i
	return -1


## Selects the next selectable tab in [param direction] from the active one (wrapping).
func _move(direction: int, focus_it: bool = false) -> void:
	var index: int = _index_of(_current)
	for _attempt: int in _tabs.size():
		index = next_index(index, direction, _tabs.size())
		var candidate: UiTab = _tabs[index]
		if candidate.visible and not candidate.disabled:
			select(candidate.id, focus_it)
			return


func _on_tab_pressed(id: StringName) -> void:
	if id == _current:
		return
	_current = id
	tab_changed.emit(id)


func _on_step_requested(direction: int, _id: StringName) -> void:
	_move(direction, true)


func _unhandled_input(event: InputEvent) -> void:
	if not handle_shoulders or not is_visible_in_tree():
		return
	if event.is_action_pressed(&"menu_tab_next"):
		get_viewport().set_input_as_handled()
		_move(1)
	elif event.is_action_pressed(&"menu_tab_previous"):
		get_viewport().set_input_as_handled()
		_move(-1)
