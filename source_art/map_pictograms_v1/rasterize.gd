extends SceneTree
func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var svg: String = FileAccess.get_file_as_string(args[0])
	DirAccess.make_dir_recursive_absolute(args[1])
	for size: int in [24,32,48]:
		var image: Image = Image.new()
		if image.load_svg_from_string(svg, float(size)/64.0) != OK or image.get_size() != Vector2i(size*4,size*2):
			push_error("Map SVG raster failed: %s" % size)
			quit(1)
			return
		if image.save_png(args[1].path_join("atlas_%s.png" % size)) != OK:
			quit(1)
			return
	print("Native map SVG24/32/48: PASS")
	quit()
