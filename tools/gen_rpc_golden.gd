extends Node
## Generator for tests/unit/net/fixtures/rpc_contract_golden.json (build-time tool, not part of the game).
## Run: godot --headless --path <checkout> res://tools/gen_rpc_golden.tscn -- --out=<golden path>
## Writes {"history": {<config/version>: md5}, "surface": {...}} from the CURRENT checkout.
## Refuses to overwrite an existing history entry with a different md5.

func _ready() -> void:
	var out_path: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
	var surface: Dictionary = RpcSurface.normalise(RpcSurface.build()) as Dictionary
	var version: String = String(ProjectSettings.get_setting("application/config/version", ""))
	var md5: String = RpcSurface.surface_md5(surface)
	var history: Dictionary = { }
	if FileAccess.file_exists(out_path):
		var old: Variant = JSON.parse_string(FileAccess.get_file_as_string(out_path))
		if old is Dictionary:
			history = (old as Dictionary).get("history", { }) as Dictionary
	if history.has(version) and String(history[version]) != md5:
		push_error("history entry for %s exists with a different md5; bump the version instead" % version)
		get_tree().quit(1)
		return
	history[version] = md5
	var data: Dictionary = { "history": history, "surface": surface }
	var file: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t", true) + "\n")
	file.close()
	print("GOLDEN WRITTEN version=%s md5=%s total=%d" % [version, md5, int(surface["rpc_total"])])
	get_tree().quit(0)
