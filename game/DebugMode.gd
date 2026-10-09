class_name DebugMode
extends RefCounted
## Bontago-470.8: the single "is debug mode on?" answer. Off for players; the
## F1 perf overlay, F2 physics comparison, F3 net overlay, F4 tuning panel,
## sandbox F5-F11 hotkeys, --force-special and the perf CSV logger all check
## is_enabled() first. F12 screenshots stay ungated.
##
## DECISION (game/DebugMode.gd, Bontago-470.8): sources, first match wins:
##   1. CLI `-- --no-debug`            -> off
##   2. CLI `-- --debug`               -> on
##   3. user://settings.cfg [debug] enabled = true/false (Settings)
##   4. ProjectSettings "stackfall/debug/enabled" = true (set it in
##      override.cfg, which is untracked, or project.godot)
##   5. OS.has_feature("editor") and DebugConfig.auto_enable_in_editor
## Step 5 means the owner's F5-from-editor and `godot --path .` runs (a
## standard Godot binary reports the "editor" feature) are debug runs
## automatically; an exported build has no "editor" feature and stays off.
## `--no-debug` or auto_enable_in_editor=false previews the player build.

const CLI_ON: String = "debug"
const CLI_OFF: String = "no-debug"
const PROJECT_SETTING: String = "stackfall/debug/enabled"
const CONFIG_PATH: String = "res://config/debug_config.tres"

## -1 = not overridden, 0 = forced off, 1 = forced on. Test seam.
static var _override: int = -1
static var _cached: int = -1
static var _config: DebugConfig = null


static func is_enabled() -> bool:
	if _override >= 0:
		return _override == 1
	if _cached < 0:
		_cached = 1 if _resolve() else 0
	return _cached == 1


static func config() -> DebugConfig:
	if _config == null:
		_config = load(CONFIG_PATH) as DebugConfig
	return _config


## Test seam: force the answer (true/false) for the duration of a test.
static func set_override_for_test(enabled: bool) -> void:
	_override = 1 if enabled else 0
	PerfProbe.enabled = enabled


static func clear_override_for_test() -> void:
	_override = -1
	PerfProbe.enabled = is_enabled()


static func _resolve() -> bool:
	return resolve_from(OS.get_cmdline_user_args(), _settings_value(), bool(ProjectSettings.get_setting(PROJECT_SETTING, false)), OS.has_feature("editor"))


## Pure rule (unit-tested): see the source list in the class doc.
## `user_setting` is -1 when the user never set it, else 0/1.
static func resolve_from(user_args: PackedStringArray, user_setting: int, project_setting: bool, in_editor: bool) -> bool:
	var want_on: bool = false
	var want_off: bool = false
	for raw: String in user_args:
		var text: String = raw
		while text.begins_with("-"):
			text = text.substr(1)
		if text == CLI_OFF:
			want_off = true
		elif text == CLI_ON:
			want_on = true
	if want_off:
		return false
	if want_on:
		return true
	if user_setting >= 0:
		return user_setting == 1
	if project_setting:
		return true
	var cfg: DebugConfig = config()
	return in_editor and (cfg == null or cfg.auto_enable_in_editor)


static func _settings_value() -> int:
	return Settings.debug_setting()
