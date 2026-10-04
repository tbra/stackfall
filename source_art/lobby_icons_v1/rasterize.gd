extends SceneTree
func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0].path_join("catalog.json")))
	DirAccess.make_dir_recursive_absolute(args[1])
	for icon: Dictionary in catalog["icons"]:
		var svg: String = FileAccess.get_file_as_string(args[0].path_join(icon["file"]))
		for size: int in [16,24,32]:
			var image: Image = Image.new()
			if image.load_svg_from_string(svg,float(size)/24.0) != OK:
				quit(1)
				return
			if image.save_png(args[1].path_join("%s_%s.png"%[icon["id"],size])) != OK:
				quit(1)
				return
	print("14lobby icons x16/24/32px:native raster PASS")
	quit()
