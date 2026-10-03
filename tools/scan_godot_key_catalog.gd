extends SceneTree
## Asset-pipeline helper: refresh key_atlas/catalog.json from Godot's own names.

func _initialize() -> void:
	var entries: Array[Dictionary] = []
	for code: int in range(32, 127):
		var name: String = OS.get_keycode_string(code)
		if not name.is_empty() and not name.contains("�"):
			entries.append({"code": code, "godot_name": name})
	for code: int in range(4194305, 4194501):
		var name: String = OS.get_keycode_string(code)
		if not name.is_empty() and not name.contains("�"):
			entries.append({"code": code, "godot_name": name})
	# KEY_NONE and KEY_SPECIAL are sentinels/masks; UNKNOWN can be displayed.
	entries.append({"code": KEY_UNKNOWN, "godot_name": OS.get_keycode_string(KEY_UNKNOWN)})
	var output: String = "res://assets/ui/input_glyphs/key_atlas/catalog.json"
	var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write key catalog: %s" % output)
		quit(1)
		return
	file.store_string(JSON.stringify({"godot_version": Engine.get_version_info().get("string", "unknown"), "keys": entries}, "  ") + "\n")
	file.close()
	print("KEY_CATALOG_READY %d" % entries.size())
	quit()
