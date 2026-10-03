extends SceneTree
## Compile-checks GDScript files with the project's autoloads and global classes
## registered (Bontago-fca.17). `godot --check-only -s <script>` parses before
## autoload singletons exist, so any script naming one (Events, Match, ...)
## fails there with "Identifier not found". Loading through ResourceLoader inside
## a running SceneTree compiles each script exactly as the game would.
##
## Usage:
##   godot --headless --path . -s res://tools/check_scripts.gd -- res://tools/a.gd res://tools/b.gd
## Prints one `CHECK OK <path>` / `CHECK FAIL <path>` line per script; exits 1 if
## any script fails to load or compile, else 0.


func _initialize() -> void:
	var failed: int = 0
	var paths: PackedStringArray = OS.get_cmdline_user_args()
	var own_path: String = (get_script() as Script).resource_path
	for path: String in paths:
		# Reloading the running main-loop script with CACHE_MODE_IGNORE corrupts it
		# and hangs the engine; it already compiled to get here.
		if path == own_path:
			print("CHECK OK %s (self)" % path)
			continue
		var script: Script = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Script
		if script == null or not script.can_instantiate():
			failed += 1
			printerr("CHECK FAIL %s" % path)
		else:
			print("CHECK OK %s" % path)
	quit(1 if failed > 0 else 0)
