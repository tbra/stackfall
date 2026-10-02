class_name UserPaths
extends RefCounted
## Maps persistent user:// config files to per-process files during GUT runs
## so tests (and sharded gate processes) never read or write the player's real
## settings or F4 overrides (Bontago-1pi.20 / .21). Normal runs, exports and
## --headless-host are unaffected: is_gut_run() is false without gut_cmdln.gd.

const GUT_CMDLN_SCRIPT: String = "gut_cmdln.gd"
const GUT_INFIX: String = "_gut_"
const GUT_STALE_SECONDS: float = 3600.0
const USER_ROOT: String = "user://"
const HEADLESS_DRIVER: String = "headless"
const CONFIG_EXTENSION: String = ".cfg"


static func is_gut_run() -> bool:
	for arg: String in OS.get_cmdline_args():
		if arg.ends_with(GUT_CMDLN_SCRIPT):
			return true
	return false


## Bontago-1pi.22: true when a run may write user:// config. GUT runs always
## may (they use per-PID files); any other headless run (editor import, smoke,
## --headless-host bots) must never touch the owner's real files.
static func persistence_allowed() -> bool:
	return persistence_allowed_for(is_gut_run(), DisplayServer.get_name())


static func persistence_allowed_for(gut_run: bool, display_driver: String) -> bool:
	return gut_run or display_driver != HEADLESS_DRIVER


## "user://settings.cfg" -> "user://settings_gut_<pid>.cfg" in a GUT run; the
## path unchanged otherwise.
static func gut_path(real_path: String) -> String:
	return real_path.get_basename() + GUT_INFIX + str(OS.get_process_id()) + "." + real_path.get_extension()


static func resolve(real_path: String) -> String:
	return gut_path(real_path) if is_gut_run() else real_path


## True when path is the real file (user:// or globalized form).
static func is_real_path(real_path: String, path: String) -> bool:
	return path == real_path or path == ProjectSettings.globalize_path(real_path)


## Deletes per-PID GUT files left by crashed runs (older than an hour).
static func sweep_stale() -> void:
	var dir: DirAccess = DirAccess.open(USER_ROOT)
	if dir == null:
		return
	for file_name: String in dir.get_files():
		if not file_name.ends_with(CONFIG_EXTENSION) or not file_name.contains(GUT_INFIX):
			continue
		if Time.get_unix_time_from_system() - FileAccess.get_modified_time(USER_ROOT + file_name) > GUT_STALE_SECONDS:
			dir.remove(file_name)
