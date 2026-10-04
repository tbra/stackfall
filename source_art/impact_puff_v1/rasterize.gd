extends SceneTree
func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(args[1])
	var dir := DirAccess.open(args[0])
	for file: String in dir.get_files():
		if not file.ends_with(".svg"):
			continue
		var image := Image.new()
		var size: int = 1024 if "atlas" in file else 256
		if image.load_svg_from_string(FileAccess.get_file_as_string(args[0].path_join(file))) != OK:
			quit(1)
			return
		if image.save_png(args[1].path_join("%s_%d.png" % [file.get_basename(),size])) != OK:
			quit(1)
			return
	print("2impact atlases +32frames: native raster PASS")
	quit()
