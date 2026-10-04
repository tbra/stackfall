extends SceneTree
## Bontago-1pi.74: writes res://build_info.cfg (gitignored) with the short git
## revision so exported builds (no .git) can show it in the main menu.
## Run before exporting: godot --headless --path . -s tools/stamp_build_info.gd


func _init() -> void:
	var revision: String = BuildVersion.git_revision()
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value(BuildVersion.INFO_SECTION, BuildVersion.INFO_KEY_REVISION, revision)
	var err: Error = cfg.save(BuildVersion.BUILD_INFO_PATH)
	if err != OK:
		push_error("stamp_build_info: could not write %s (%s)" % [BuildVersion.BUILD_INFO_PATH, error_string(err)])
		quit(1)
		return
	print("stamp_build_info: revision=%s" % revision)
	quit(0)
