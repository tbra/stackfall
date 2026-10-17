extends Node
## In-game screenshot capture, saved to a folder outside the repo (see
## OUTPUT_DIR_ENV).
##
## Bound to the screenshot_capture action (F12 + gamepad, see
## tools/bootstrap_project.gd), fired from _unhandled_input so it works while
## the mouse is captured and over menus alike. Listens directly on the Input
## Map action rather than Events: a screenshot is a one-shot local side effect
## no other system cares about.
##
## No class_name: this is the Screenshots autoload singleton (see
## autoload/Net.gd's header).

const ACTION_NAME: StringName = &"screenshot_capture"
const TIMESTAMP_FORMAT: String = "%04d%02d%02d_%02d%02d%02d"

## Test seam: overrides the save directory so tests never touch a shared user://
## folder. Empty means "use the real resolution logic below".
var output_dir_override: String = ""

## Test seam: overrides how the captured Image is produced.
## get_viewport().get_texture().get_image() can come back an empty Image in a
## headless run (no real render target exists to read back), so tests stub
## this to assert on the save path without depending on real pixels.
var image_provider: Callable = Callable(self, "_grab_viewport_image")

## Test seam: skips the `await RenderingServer.frame_post_draw` below.
## DECISION (autoload/Screenshots.gd): a headless GUT run never draws a frame,
## so RenderingServer never emits frame_post_draw and an unconditional await
## would hang every test (and capture() on a headless bot-match host).
## Production capture() still needs the wait -- reading the viewport texture
## before the frame finishes drawing can grab a stale or partial image -- so
## only tests, which stub image_provider, turn it off.
var wait_for_frame_draw: bool = true

var _last_capture_unix_second: int = -1
var _captures_this_second: int = 0


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(ACTION_NAME):
		return
	# Debounce: InputEvent.is_action_pressed() only reports true once per
	# physical press by default (allow_echo defaults to false), so holding
	# F12/the pad button down does not repeat this. get_viewport() also isn't
	# available on some test doubles that call _unhandled_input directly with
	# no viewport, hence the null check rather than an unconditional call.
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
	capture()


## Public so tests can await the full save instead of racing the
## fire-and-forget call _unhandled_input makes.
func capture() -> void:
	if wait_for_frame_draw:
		await RenderingServer.frame_post_draw
	var image: Image = image_provider.call()
	if image == null or image.is_empty():
		push_warning("Screenshots: captured image is empty (likely a headless run with no real render target); skipping save.")
		return
	var dir: String = _resolve_output_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var path: String = dir.path_join(_next_filename())
	var err: Error = image.save_png(path)
	if err != OK:
		push_warning("Screenshots: could not save %s: %s" % [path, error_string(err)])
		return
	print("Screenshot saved: %s" % path)


func _grab_viewport_image() -> Image:
	return get_viewport().get_texture().get_image()


## yyyymmdd_hhmmss, with a _<n> counter suffix for a second capture landing in
## the same wall-clock second (Time's resolution here is 1 s).
func _next_filename() -> String:
	var unix_second: int = int(Time.get_unix_time_from_system())
	if unix_second == _last_capture_unix_second:
		_captures_this_second += 1
	else:
		_last_capture_unix_second = unix_second
		_captures_this_second = 0
	var now: Dictionary = Time.get_datetime_dict_from_system()
	var stamp: String = TIMESTAMP_FORMAT % [now.year, now.month, now.day, now.hour, now.minute, now.second]
	if _captures_this_second == 0:
		return "screenshot_%s.png" % stamp
	return "screenshot_%s_%d.png" % [stamp, _captures_this_second]


## Screenshots land in user://screenshots, or in the folder named by the
## STACKFALL_SCREENSHOT_DIR environment variable when set (agent or owner drop
## folders live outside the repo).
const OUTPUT_DIR_ENV: String = "STACKFALL_SCREENSHOT_DIR"
const DEFAULT_DIR: String = "user://screenshots"


func _resolve_output_dir() -> String:
	if output_dir_override != "":
		return output_dir_override
	var env_dir: String = OS.get_environment(OUTPUT_DIR_ENV)
	if env_dir != "":
		return env_dir
	return ProjectSettings.globalize_path(DEFAULT_DIR)
