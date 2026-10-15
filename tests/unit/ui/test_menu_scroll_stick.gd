extends GutTest
## Bontago-1pi.159.19: the right stick scrolls a FocusScrollContainer, the next ui_up / ui_down
## after a stick scroll jumps the selection into the visible viewport, and a held left stick / d-pad
## keeps moving the selection with the sliders' hysteresis (one move at the press threshold,
## repeat only at full deflection after the delay).

const FRAME: float = 1.0 / 60.0
const ROWS: int = 30
const ROW_HEIGHT: float = 40.0
const VIEW_HEIGHT: float = 200.0
const FULL: float = 1.0
const PARTIAL: float = 0.6
const HOLD_SECONDS: float = 3.0
const EPS: float = 0.0001

var _scroll: FocusScrollContainer = null
var _rows: Array[Button] = []
var _right_y: float = 0.0
var _left_y: float = 0.0


func before_each() -> void:
	_scroll = FocusScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(300.0, VIEW_HEIGHT)
	_scroll.size = _scroll.custom_minimum_size
	add_child_autofree(_scroll)
	var list: VBoxContainer = VBoxContainer.new()
	_scroll.add_child(list)
	_rows.clear()
	for i: int in ROWS:
		var row: Button = Button.new()
		row.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
		list.add_child(row)
		_rows.append(row)
	_right_y = 0.0
	_left_y = 0.0
	_scroll.scroll_axis_reader = func() -> float: return _right_y
	_scroll._hold.axis_reader = func(_device: int, _axis: int) -> float: return _left_y
	await get_tree().process_frame
	await get_tree().process_frame
	_scroll.scroll_vertical = 0
	_rows[0].grab_focus()
	_scroll.stick_scrolled = false


func _focused_index() -> int:
	return _rows.find(get_viewport().gui_get_focus_owner())


func _stick(value: float) -> void:
	_left_y = value
	var motion: InputEventJoypadMotion = InputEventJoypadMotion.new()
	motion.axis = JOY_AXIS_LEFT_Y
	motion.axis_value = value
	_scroll.handle_nav_event(motion)


func _hold(seconds: float) -> void:
	for _i: int in roundi(seconds / FRAME):
		_scroll._hold.advance(FRAME, true)


func test_right_stick_scrolls_down_and_up() -> void:
	_right_y = FULL
	for _i: int in 30:
		_scroll.scroll_by_stick(FRAME)
	assert_gt(_scroll.scroll_vertical, 0)
	var mid: int = _scroll.scroll_vertical
	_right_y = -FULL
	for _i: int in 10:
		_scroll.scroll_by_stick(FRAME)
	assert_lt(_scroll.scroll_vertical, mid)


func test_right_stick_inside_deadzone_does_not_scroll() -> void:
	_right_y = 0.1
	for _i: int in 60:
		_scroll.scroll_by_stick(FRAME)
	assert_eq(_scroll.scroll_vertical, 0)
	assert_false(_scroll.stick_scrolled)


func _scroll_far() -> void:
	_right_y = FULL
	for _i: int in 60:
		_scroll.scroll_by_stick(FRAME)
	_right_y = 0.0
	await get_tree().process_frame
	await get_tree().process_frame


func test_next_ui_down_after_stick_scroll_jumps_into_view() -> void:
	await _scroll_far()
	assert_true(_scroll.stick_scrolled)
	var view: Rect2 = _scroll.get_global_rect()
	var down: InputEventAction = InputEventAction.new()
	down.action = &"ui_down"
	down.pressed = true
	assert_true(_scroll.handle_nav_event(down), "the jump consumes the press")
	var focused: Control = get_viewport().gui_get_focus_owner()
	assert_true(view.encloses(focused.get_global_rect()), "focus is inside the visible viewport")
	assert_gt(_focused_index(), 0)
	assert_false(_scroll.stick_scrolled)


func test_dpad_press_after_stick_scroll_jumps_instead_of_scrolling_back() -> void:
	await _scroll_far()
	var scroll_before: int = _scroll.scroll_vertical
	var button: InputEventJoypadButton = InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_DPAD_DOWN
	button.pressed = true
	_scroll.handle_nav_event(button)
	_scroll._hold.release()
	assert_true(_scroll.get_global_rect().encloses(get_viewport().gui_get_focus_owner().get_global_rect()))
	assert_almost_eq(float(_scroll.scroll_vertical), float(scroll_before), ROW_HEIGHT, "view stays near the stick position")


func test_plain_navigation_without_stick_scroll_moves_one_row() -> void:
	_stick(FULL)
	_scroll._hold.release()
	assert_eq(_focused_index(), 1)


func test_partial_push_moves_exactly_one_row() -> void:
	_stick(PARTIAL)
	_hold(HOLD_SECONDS)
	assert_eq(_focused_index(), 1)


func test_hovering_at_the_deadzone_never_moves() -> void:
	for _i: int in 30:
		_stick(0.15)
		_stick(0.35)
	assert_eq(_focused_index(), 0)


func test_full_deflection_hold_repeats_the_selection() -> void:
	_stick(FULL)
	_hold(HOLD_SECONDS)
	assert_gt(_focused_index(), 3, "a held full stick keeps moving the selection")
	assert_lt(_focused_index(), 20, "slower than a per-frame run")


func test_repeat_stops_on_release() -> void:
	_stick(FULL)
	_hold(HOLD_SECONDS)
	_stick(0.0)
	var index: int = _focused_index()
	_hold(HOLD_SECONDS)
	assert_eq(_focused_index(), index)
