extends SceneTree
func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(args[1])
	var dir := DirAccess.open(args[0])
	for file: String in dir.get_files():
		if not file.ends_with(".svg"):
			continue
		var nominal: int = 512 if file == "atlas.svg" else 128
		var sizes: Array = [512] if nominal == 512 else [8,16,32,128]
		for size: int in sizes:
			var image := Image.new()
			if image.load_svg_from_string(FileAccess.get_file_as_string(args[0].path_join(file)),float(size)/nominal) != OK:
				quit(1)
				return
			if image.save_png(args[1].path_join("%s_%d.png" % [file.get_basename(),size])) != OK:
				quit(1)
				return
	print("Snow atlas512 plus16variants x8/16/32/128: native raster PASS")
	quit()
