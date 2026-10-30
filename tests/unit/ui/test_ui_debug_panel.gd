extends GutTest
## UiDebugPanel and DebugRow (ui/components): what a caller sees. Panels pass data; the tests read DebugRow data
## and the visible Label text found by class, never a child index, alignment, tint or section order.

const TOGGLE: StringName = &"net_debug_toggle"
const MODIFIER: StringName = &"camera_snap_home"

var _panel: UiDebugPanel = null


func before_each() -> void:
	_release_pad_and_use_keyboard()
	await wait_process_frames(2)
	_panel = UiDebugPanel.new()
	_panel.heading = "Probe heading"
	_panel.toggle_action = TOGGLE
	_panel.modifier_action = MODIFIER
	add_child_autofree(_panel)
	await wait_process_frames(1)


func after_all() -> void:
	_release_pad_and_use_keyboard()


## A key release alone classifies the active device as keyboard and leaves nothing held.
func _release_pad_and_use_keyboard() -> void:
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_A
	key.pressed = false
	Input.parse_input_event(key)


func _visible_texts() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for node: Node in _panel.find_children("*", "Label", true, false):
		var label: Label = node as Label
		if label.is_visible_in_tree() and label.text != "":
			out.append(label.text)
	return out


func _count_exact(text: String) -> int:
	var n: int = 0
	for t: String in _visible_texts():
		if t == text:
			n += 1
	return n


func _any_contains(needle: String) -> bool:
	for t: String in _visible_texts():
		if t.contains(needle):
			return true
	return false


func _rows(pairs: Array) -> Array[DebugRow]:
	var rows: Array[DebugRow] = []
	for p: Array in pairs:
		rows.append(DebugRow.pair(p[0] as String, p[1] as String))
	return rows


# --- DebugRow ---

func test_pair_carries_name_value_and_warn() -> void:
	var row: DebugRow = DebugRow.pair("Frame", "16.6 ms")
	assert_eq(row.cells, PackedStringArray(["Frame", "16.6 ms"]))
	assert_false(row.warn)
	assert_true(DebugRow.pair("Frame", "40 ms", true).warn)


# --- sections ---

func test_heading_is_visible() -> void:
	assert_true(_any_contains("Probe heading"))


func test_section_shows_title_and_row_text() -> void:
	_panel.set_section(&"a", "Alpha", _rows([["fps", "60"], ["ping", "12 ms"]]))
	await wait_process_frames(1)
	assert_true(_any_contains("Alpha"), "title")
	assert_true(_any_contains("fps"))
	assert_true(_any_contains("60"))
	assert_true(_any_contains("ping"))
	assert_true(_any_contains("12 ms"))


func test_second_call_updates_in_place_without_duplicates() -> void:
	_panel.set_section(&"a", "Alpha", _rows([["fps", "60"]]))
	await wait_process_frames(1)
	_panel.set_section(&"a", "Alpha", _rows([["fps", "144"]]))
	await wait_process_frames(1)
	assert_false(_any_contains("60"), "old value gone")
	assert_eq(_count_exact("144"), 1, "new value shown once")
	assert_eq(_count_exact("fps"), 1, "name not duplicated")
	assert_eq(_count_exact("Alpha"), 1, "title not duplicated")


func test_row_count_can_shrink_on_update() -> void:
	_panel.set_section(&"a", "Alpha", _rows([["one", "1"], ["two", "2"]]))
	await wait_process_frames(1)
	_panel.set_section(&"a", "Alpha", _rows([["one", "1"]]))
	await wait_process_frames(1)
	assert_true(_any_contains("one"))
	assert_false(_any_contains("two"))


func test_empty_rows_hide_the_section() -> void:
	_panel.set_section(&"a", "Alpha", _rows([["fps", "60"]]))
	await wait_process_frames(1)
	_panel.set_section(&"a", "Alpha", _rows([]))
	await wait_process_frames(1)
	assert_false(_any_contains("Alpha"), "title hidden")
	assert_false(_any_contains("fps"))


func test_hidden_section_returns_when_rows_come_back() -> void:
	_panel.set_section(&"a", "Alpha", _rows([]))
	await wait_process_frames(1)
	assert_false(_any_contains("Alpha"))
	_panel.set_section(&"a", "Alpha", _rows([["fps", "60"]]))
	await wait_process_frames(1)
	assert_true(_any_contains("Alpha"))
	assert_true(_any_contains("60"))


func test_emptied_section_keeps_no_stale_text_and_refills() -> void:
	_panel.set_section(&"a", "Alpha", _rows([["fps", "60"]]))
	_panel.set_section(&"a", "Alpha", _rows([]))
	for node: Node in _panel.find_children("*", "Label", true, false):
		assert_ne((node as Label).text, "fps", "an emptied section keeps no old row text")
		assert_ne((node as Label).text, "60", "an emptied section keeps no old row text")
	_panel.set_section(&"a", "Alpha", _rows([["fps", "60"]]))
	await wait_process_frames(1)
	assert_eq(_count_exact("fps"), 1, "the same rows refill after being emptied")


func test_sections_are_independent() -> void:
	_panel.set_section(&"a", "Alpha", _rows([["fps", "60"]]))
	_panel.set_section(&"b", "Beta", _rows([["bots", "3"]]))
	await wait_process_frames(1)
	_panel.set_section(&"a", "Alpha", _rows([]))
	await wait_process_frames(1)
	assert_false(_any_contains("Alpha"))
	assert_true(_any_contains("Beta"))
	assert_true(_any_contains("bots"))


# --- table ---

func test_table_shows_headers_and_every_cell() -> void:
	var rows: Array[DebugRow] = []
	var r1: DebugRow = DebugRow.new()
	r1.cells = PackedStringArray(["think", "1.5", "20"])
	var r2: DebugRow = DebugRow.new()
	r2.cells = PackedStringArray(["probe", "7.25", "31"])
	rows.append(r1)
	rows.append(r2)
	_panel.set_table(&"t", "Costs", PackedStringArray(["Phase", "ms", "n"]), rows)
	await wait_process_frames(1)
	for expected: String in ["Costs", "Phase", "ms", "n", "think", "1.5", "20", "probe", "7.25", "31"]:
		assert_true(_any_contains(expected), "shows %s" % expected)


func test_table_second_call_replaces_cells() -> void:
	var first: DebugRow = DebugRow.new()
	first.cells = PackedStringArray(["think", "1.5"])
	_panel.set_table(&"t", "Costs", PackedStringArray(["Phase", "ms"]), [first] as Array[DebugRow])
	await wait_process_frames(1)
	var second: DebugRow = DebugRow.new()
	second.cells = PackedStringArray(["think", "9.75"])
	_panel.set_table(&"t", "Costs", PackedStringArray(["Phase", "ms"]), [second] as Array[DebugRow])
	await wait_process_frames(1)
	assert_false(_any_contains("1.5"))
	assert_eq(_count_exact("9.75"), 1)
	assert_eq(_count_exact("Phase"), 1, "headers not duplicated")


# --- notes ---

func test_note_shows_and_updates() -> void:
	_panel.set_note(&"n", "measured on the host")
	await wait_process_frames(1)
	assert_eq(_count_exact("measured on the host"), 1)
	_panel.set_note(&"n", "measured locally")
	await wait_process_frames(1)
	assert_false(_any_contains("on the host"))
	assert_eq(_count_exact("measured locally"), 1)


# --- chip ---

func test_chip_names_the_keyboard_binding() -> void:
	assert_eq(Settings.active_input_device(), Settings.DEVICE_KEYBOARD_MOUSE)
	assert_true(_any_contains("F3"), "keyboard chip text: %s" % [_visible_texts()])
	assert_false(_any_contains("Back + Y"))


func test_chip_names_the_pad_chord_after_a_pad_event() -> void:
	var press: InputEventJoypadButton = InputEventJoypadButton.new()
	press.button_index = JOY_BUTTON_A
	press.pressed = true
	Input.parse_input_event(press)
	await wait_process_frames(2)
	assert_eq(Settings.active_input_device(), Settings.DEVICE_GAMEPAD)
	assert_true(_any_contains("Back + Y"), "pad chip text: %s" % [_visible_texts()])
	assert_false(_any_contains("F3"))
	press.pressed = false
	Input.parse_input_event(press)
	_release_pad_and_use_keyboard()
	await wait_process_frames(2)
	assert_true(_any_contains("F3"), "back to keyboard")


# --- content ---

func test_content_returns_a_container_the_caller_can_fill() -> void:
	var box: VBoxContainer = _panel.content()
	assert_not_null(box)
	if box == null:
		return
	var extra: Label = Label.new()
	extra.text = "custom control"
	box.add_child(extra)
	await wait_process_frames(1)
	assert_true(_any_contains("custom control"))
