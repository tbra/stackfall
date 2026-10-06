extends GutTest
## Owner 2026-10-06: "game windows once again launch in fullscreen and then
## resize. don't know how many times i've asked you to fix it". Godot 4.7
## creates the first window from display/window/size/mode and does not let
## --windowed override it, so agent probes flashed fullscreen until
## AgentProbe.apply() shrank them. tools/bootstrap_project.gd pins an "editor"
## feature override (every run of the editor binary starts windowed, exported
## builds keep borderless fullscreen; main.cpp reads it through GLOBAL_GET =
## get_setting_with_override). These tests fail if a bootstrap regen or
## a hand edit drops it again.

const MODE_KEY: String = "display/window/size/mode"
const BORDERLESS_KEY: String = "display/window/size/borderless"
const EDITOR_SUFFIX: String = ".editor"
const PROJECT_FILE: String = "res://project.godot"


func test_editor_binary_runs_start_windowed() -> void:
	assert_true(OS.has_feature("editor"), "Setup: tests run on the editor binary.")
	assert_eq(int(ProjectSettings.get_setting_with_override(MODE_KEY)), DisplayServer.WINDOW_MODE_WINDOWED,
		"Every editor-binary run (probes, benches, dev runs) must create a windowed window.")
	assert_false(bool(ProjectSettings.get_setting_with_override(BORDERLESS_KEY)),
		"Editor-binary runs must not start borderless.")


func test_project_file_keeps_the_editor_override_and_the_export_fullscreen_default() -> void:
	var text: String = FileAccess.get_file_as_string(PROJECT_FILE)
	assert_string_contains(text, "window/size/mode%s=%d" % [EDITOR_SUFFIX, DisplayServer.WINDOW_MODE_WINDOWED])
	assert_string_contains(text, "window/size/borderless%s=false" % EDITOR_SUFFIX)
	# Exported builds still boot straight into borderless fullscreen (Bontago-xtq.45).
	assert_string_contains(text, "window/size/mode=%d" % DisplayServer.WINDOW_MODE_FULLSCREEN)


func test_bootstrap_pins_the_override_so_a_regen_cannot_drop_it() -> void:
	var text: String = FileAccess.get_file_as_string("res://tools/bootstrap_project.gd")
	assert_string_contains(text, "\"%s%s\": 0" % [MODE_KEY, EDITOR_SUFFIX])
	assert_string_contains(text, "\"%s%s\": false" % [BORDERLESS_KEY, EDITOR_SUFFIX])
