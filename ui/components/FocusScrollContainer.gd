class_name FocusScrollContainer
extends ScrollContainer
## Bontago-1pi.47 (owner playtest: "In menus that have scrolling, for example
## controller remapping, navigating with gamepad/arrow keys doesn't update the
## scroll position"). A ScrollContainer that keeps whichever descendant just
## took keyboard/gamepad focus visible -- the shared approach for every menu
## list that can outgrow its panel (ui/menus/OptionsMenu.tscn's Settings page and
## Controls rebind list, and ui/lobby/Lobby.tscn's settings column since Bontago-1pi.159.33, use it).
##
## DECISION (Bontago-1pi.47): the engine's own `follow_focus` (set here, and
## explicitly in the scene) does the actual scrolling -- its handler listens to
## the viewport's `gui_focus_changed` and calls ensure_control_visible() for any
## descendant, however deeply nested, and works with the custom focus_neighbor
## wiring because it reacts to the focus change, not to how focus got there.
## Plain follow_focus scrolls the *minimum* distance, so walking UP a list
## leaves the focused control flush against the top edge with the section
## caption above it (e.g. "Rotation" over "Rotate left") clipped away. This
## subclass additionally reveals the caption Label(s) that directly precede the
## focused control (or one of its ancestors) in their parent, so a section's
## heading is never hidden while its first row is selected. Mouse-wheel and
## scrollbar scrolling are untouched.


const TUNING: SliderNavTuning = preload("res://config/ui/slider_nav_tuning.tres")

## Reads the right-stick Y axis; tests replace it (headless Input has no real pad state).
var scroll_axis_reader: Callable = _read_right_stick_y
## True once the right stick moved the view: the next ui_up / ui_down then jumps the selection to
## the nearest control inside the visible viewport instead of scrolling back to the old one
## (Bontago-1pi.159.19, owner playtest 2026-10-11).
var stick_scrolled: bool = false
## Left-stick / d-pad vertical hold: one move per push, repeat only at full deflection.
var _hold: UiHoldRepeat = UiHoldRepeat.new(_move_selection)
var _scroll_remainder: float = 0.0


func _init() -> void:
	follow_focus = true
	_hold.back_action = &"ui_up"
	_hold.forward_action = &"ui_down"


func _ready() -> void:
	# Bontago-1pi.121 (owner playtest: menus with scrollbars don't start at the top): a list
	# opens at its top, then follows focus as before. Deferred so it runs after the opening
	# focus grab (whose ensure_control_visible would otherwise leave it scrolled down).
	visibility_changed.connect(_on_visibility_changed)
	scroll_to_top()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	scroll_by_stick(delta)
	if _hold.is_holding():
		_hold.advance(delta, _owns_focus())


## Scrolls by the right stick for one frame (public for tests); true when the view moved.
func scroll_by_stick(delta: float) -> bool:
	var axis: float = float(scroll_axis_reader.call())
	if absf(axis) < TUNING.scroll_stick_deadzone:
		_scroll_remainder = 0.0
		return false
	var span: float = 1.0 - TUNING.scroll_stick_deadzone
	if is_zero_approx(span):
		return false
	var strength: float = (absf(axis) - TUNING.scroll_stick_deadzone) / span
	_scroll_remainder += signf(axis) * strength * TUNING.scroll_speed_px_per_sec * delta
	var whole: int = int(_scroll_remainder)
	if whole == 0:
		return false
	_scroll_remainder -= float(whole)
	var before: int = scroll_vertical
	scroll_vertical = before + whole
	if scroll_vertical == before:
		return false
	stick_scrolled = true
	return true


func _read_right_stick_y() -> float:
	var best: float = Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	for device: int in Input.get_connected_joypads():
		var value: float = Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y)
		if absf(value) > absf(best):
			best = value
	return best


func _owns_focus() -> bool:
	var owner_control: Control = get_viewport().gui_get_focus_owner() if get_viewport() != null else null
	return owner_control != null and is_ancestor_of(owner_control)


func _input(event: InputEvent) -> void:
	if handle_nav_event(event):
		get_viewport().set_input_as_handled()


## Vertical menu navigation inside this container; true when the event is consumed (public for
## tests). Arrow keys keep the engine's own repeat and focus move; a key press only intercepts to
## jump the selection into view after a stick scroll. D-pad presses and the left stick go through
## UiHoldRepeat so holding keeps moving the selection with the sliders' hysteresis.
func handle_nav_event(event: InputEvent) -> bool:
	if not is_visible_in_tree() or not _owns_focus():
		return false
	if event is InputEventJoypadMotion:
		return _hold.handle_stick(event as InputEventJoypadMotion)
	if event is InputEventJoypadButton:
		return _hold.handle_action_event(event)
	if stick_scrolled and (event.is_action_pressed(&"ui_up") or event.is_action_pressed(&"ui_down")):
		return jump_selection_into_view()
	return false


## Moves the selection one row in [param direction] (-1 up / +1 down), jumping into view first
## when the stick scrolled the focused row out of it.
func _move_selection(direction: int) -> void:
	if stick_scrolled and jump_selection_into_view():
		return
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused == null:
		return
	var target: Control = focused.find_valid_focus_neighbor(SIDE_BOTTOM if direction > 0 else SIDE_TOP)
	if target != null and target != focused:
		Sfx.note_focus_nav()  # Bontago-1pi.159.48: a held-stick repeat has no input event this frame
		target.grab_focus()


## After a stick scroll, focuses the visible control nearest the focused row when that row is no
## longer fully in view; true when focus moved. Clears [member stick_scrolled] either way.
func jump_selection_into_view() -> bool:
	stick_scrolled = false
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused == null:
		return false
	var view: Rect2 = get_global_rect()
	if view.encloses(focused.get_global_rect()):
		return false
	var all: Array[Control] = []
	_collect_focusable(self, all)
	var whole: Array[Control] = []
	for control: Control in all:
		if view.encloses(control.get_global_rect()):
			whole.append(control)
	var from: Vector2 = focused.get_global_rect().get_center().clamp(view.position, view.end)
	# DECISION: inline nearest-to-point pick instead of UiSpatialFocus.nearest_in_rect -- referencing
	# that class from this scene-loaded script pulled it into the Main.tscn closure (layer lint L4).
	var target: Control = null
	var best: float = INF
	for control: Control in (whole if not whole.is_empty() else all):
		var rect: Rect2 = control.get_global_rect()
		if not view.intersects(rect):
			continue
		var distance: float = rect.get_center().distance_squared_to(from)
		if distance < best:
			best = distance
			target = control
	if target == null or target == focused:
		return false
	target.grab_focus()
	return true


func _collect_focusable(node: Node, out: Array[Control]) -> void:
	for child: Node in node.get_children():
		var control: Control = child as Control
		if control != null:
			if control.focus_mode == Control.FOCUS_ALL and control.is_visible_in_tree():
				out.append(control)
		_collect_focusable(child, out)


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		scroll_to_top()


## Resets the vertical scroll to the top on the next idle frame (public for tests).
func scroll_to_top() -> void:
	set_deferred(&"scroll_vertical", 0)


func _enter_tree() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null and not viewport.gui_focus_changed.is_connected(_on_gui_focus_changed):
		viewport.gui_focus_changed.connect(_on_gui_focus_changed)


func _exit_tree() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null and viewport.gui_focus_changed.is_connected(_on_gui_focus_changed):
		viewport.gui_focus_changed.disconnect(_on_gui_focus_changed)


func _on_gui_focus_changed(control: Control) -> void:
	stick_scrolled = false
	if not follow_focus or control == null or not is_ancestor_of(control):
		return
	if not control.is_visible_in_tree():
		return
	for caption: Control in leading_captions(control):
		ensure_control_visible(caption)
	ensure_control_visible(control)


## The visible Labels that sit immediately before `control`, or before any of its
## ancestors inside this container, in their parents' child order -- the section
## captions a row's own focus should not scroll out of view. Public so tests can
## assert the resolution without driving focus.
func leading_captions(control: Control) -> Array[Control]:
	var captions: Array[Control] = []
	var node: Node = control
	while node != null and node != self:
		var parent: Node = node.get_parent()
		if parent == null:
			break
		var index: int = node.get_index()
		if index > 0:
			var previous: Label = parent.get_child(index - 1) as Label
			if previous != null and previous.is_visible_in_tree():
				captions.append(previous)
		node = parent
	return captions
