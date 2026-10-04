extends SceneTree
func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0].path_join("gamepad_motion_catalog.json")))
	DirAccess.make_dir_recursive_absolute(args[1])
	for item: Dictionary in catalog["glyphs"]:
		var svg: String = FileAccess.get_file_as_string(args[0].path_join(item["file"]))
		for size: int in [24,32,48]:
			var image: Image = Image.new()
			if image.load_svg_from_string(svg,float(size)/64.0) != OK:
				quit(1)
				return
			var name: String = String(item["file"]).get_basename()+"_%s.png"%size
			if image.save_png(args[1].path_join(name)) != OK:
				quit(1)
				return
	print("12 native glyphs x3 sizes:PASS")
	quit()
