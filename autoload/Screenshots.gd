extends Node
## In-game screenshot capture (owner request 2026-09-23: "add a button to
## take in-game screenshots which automatically saves to the docs" -- the
## owner has been dropping bug screenshots into docs/ by hand, e.g.
## docs/solid-blocks2-issue.png).
##
## Bound to the screenshot_capture action (F12 + gamepad, see
## tools/bootstrap_project.gd), fired from _unhandled_input so it works while
## the mouse is captured and over menus alike. Listens directly on the Input
## Map action rather than Events (CLAUDE.md's bus is for gameplay state
## changes between systems; a screenshot is a one-shot local side effect with
## no other system caring about it, the same reasoning ui/MainMenu.gd and
## ui/Lobby.gd use for calling Sfx.play() directly on button press).
##
## No class_name: this is the Screenshots autoload singleton (same reason
## Events, Settings, Net, Match and Sfx have none -- see autoload/Net.gd's
## header).

const ACTION_NAME: StringName = &"screenshot_capture"
const TIMESTAMP_FORMAT: String = "%04d%02d%02d_%02d%02d%02d"

## Test seam: overrides the save directory so tests never touch res://docs or
## a shared user:// folder. Empty means "use the real resolution logic below"
## (autoload/Sfx.gd's set_root_dir_for_test is the same pattern).
var output_dir_override: String = ""

## Test seam: overrides how the captured Image is produced.
## get_viewport().get_texture().get_image() can come back an empty Image in a
## headless run (no real render target exists to read back), so tests stub
## this to assert on the save path without depending on real pixels.
var image_provider: Callable = Callable(self, "_grab_viewport_image")

## Test seam: skips the `await RenderingServer.frame_post_draw` below.
## DECISION (autoload/Screenshots.gd, found while writing test_screenshots.gd):
## a headless `godot --headless -s addons/gut/gut_cmdln.gd` run never draws a
## frame, so RenderingServer never emits frame_post_draw and an unconditional
## await here hung every test (and would hang capture() forever on a headless
## bot-match host too, spec 3.2 M5). Production capture() still needs the
## wait -- reading the viewport texture before the frame finishes drawing can
## grab a stale or partial image -- so the wait stays the default and only
## tests, which already stub image_provider and have no real frame to wait
## for, turn it off.
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


func _resolve_output_dir() -> String:
	if output_dir_override != "":
		return output_dir_override
	var docs_dir: String = ProjectSettings.globalize_path("res://docs")
	if _dir_is_writable(docs_dir):
		return docs_dir
	return ProjectSettings.globalize_path("user://screenshots")


## DECISION (autoload/Screenshots.gd): OS.has_feature("editor") only tells us
## the *editor process* is running, not whether res://docs exists on disk --
## `godot --path .` (an unexported source run, the brief's own manual-proof
## command) reports has_feature("editor") == false despite res://docs being a
## real, writable folder, which would wrongly send every screenshot to
## user://screenshots/ instead of docs/. A DirAccess write probe answers the
## actual question ("can I write a file at res://docs's real path right now?")
## and degrades correctly in an exported build too, where res://docs is
## packed into the .pck and DirAccess.dir_exists_absolute() on its globalized
## path correctly reports nothing there.
func _dir_is_writable(path: String) -> bool:
	if not DirAccess.dir_exists_absolute(path):
		return false
	var probe_path: String = path.path_join(".screenshot_write_probe")
	var file: FileAccess = FileAccess.open(probe_path, FileAccess.WRITE)
	if file == null:
		return false
	file.close()
	DirAccess.remove_absolute(probe_path)
	return true
