extends GutTest
## autoload/Screenshots.gd: F12/gamepad screenshot capture (Bontago-02u, owner
## request 2026-09-23). Uses a fresh Screenshots instance pointed at a temp
## user:// folder (output_dir_override) rather than the real "Screenshots"
## autoload singleton, so these tests never touch res://docs or a shared
## user:// path -- same pattern as tests/unit/test_sfx.gd's
## set_root_dir_for_test and test_tuning_panel.gd's synthetic key events.
##
## Headless note (brief, Bontago-02u): get_viewport().get_texture().get_image()
## can come back empty in this headless run (no real render target), so every
## test here stubs image_provider instead of depending on a real frame.

const SCREENSHOTS_SCRIPT: GDScript = preload("res://autoload/Screenshots.gd")

var _shots: Node
var _tmp_dir: String


func before_each() -> void:
	_shots = autofree(SCREENSHOTS_SCRIPT.new())
	add_child_autofree(_shots)
	_tmp_dir = OS.get_user_data_dir().path_join("test_screenshots_tmp")
	_clear_dir(_tmp_dir)
	DirAccess.make_dir_recursive_absolute(_tmp_dir)
	_shots.output_dir_override = _tmp_dir
	_shots.image_provider = Callable(self, "_fake_image")
	# A headless GUT run never draws a frame, so RenderingServer never emits
	# frame_post_draw -- an unconditional await on it hangs every test here
	# forever (reproduced while writing this file; see the DECISION on
	# wait_for_frame_draw in autoload/Screenshots.gd).
	_shots.wait_for_frame_draw = false


func after_each() -> void:
	_clear_dir(_tmp_dir)


func _clear_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for filename: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(filename))


func _fake_image() -> Image:
	return Image.create(4, 4, false, Image.FORMAT_RGBA8)


func _empty_image() -> Image:
	return Image.new()


func _pngs_in_tmp_dir() -> Array:
	var pngs: Array = []
	for filename: String in DirAccess.get_files_at(_tmp_dir):
		if filename.ends_with(".png"):
			pngs.append(filename)
	return pngs


func _key_press(keycode: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.device = -1
	event.physical_keycode = keycode
	event.pressed = true
	return event


# --- (a): one press, one file ------------------------------------------------

func test_capture_saves_exactly_one_png() -> void:
	await _shots.capture()
	assert_eq(_pngs_in_tmp_dir().size(), 1, "capture() should save exactly one PNG.")


func test_unhandled_input_with_screenshot_action_saves_one_png() -> void:
	var event: InputEventKey = _key_press(KEY_F12)
	assert_true(
		event.is_action_pressed(&"screenshot_capture"),
		"F12 should map to screenshot_capture (tools/bootstrap_project.gd)."
	)
	_shots._unhandled_input(event)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_pngs_in_tmp_dir().size(), 1, "A single screenshot_capture press should save one file.")


func test_unhandled_input_ignores_unrelated_actions() -> void:
	var event: InputEventKey = _key_press(KEY_F4)  # tuning_panel_toggle, not this action.
	_shots._unhandled_input(event)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_pngs_in_tmp_dir().size(), 0, "An unrelated action must not trigger a capture.")


# --- (b): a second press saves a second, differently named file -------------

func test_second_capture_gets_a_distinct_filename() -> void:
	await _shots.capture()
	await _shots.capture()
	var pngs: Array = _pngs_in_tmp_dir()
	assert_eq(pngs.size(), 2, "Two captures should save two distinct files.")
	if pngs.size() == 2:
		assert_ne(pngs[0], pngs[1], "The second capture must not overwrite the first.")


# --- Robustness: an empty captured image is skipped, not saved --------------

func test_empty_image_is_not_saved() -> void:
	_shots.image_provider = Callable(self, "_empty_image")
	await _shots.capture()
	assert_eq(_pngs_in_tmp_dir().size(), 0, "An empty captured image must not produce a file.")
