extends SceneTree
func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(args[1])
	for name: String in ["moon_disc","moon_halo"]:
		var svg: String = FileAccess.get_file_as_string(args[0].path_join(name+".svg"))
		for size: int in [64,128,1024]:
			var image := Image.new()
			if image.load_svg_from_string(svg,float(size)/1024.0) != OK:
				quit(1)
				return
			if image.save_png(args[1].path_join("%s_%d.png" % [name,size])) != OK:
				quit(1)
				return
	print("Moon disc+halo at64/128/1024: native raster PASS")
	quit()
