extends SceneTree
func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var atlas_path: String = arguments[0]
	var output: String = arguments[1]
	DirAccess.make_dir_recursive_absolute(output)
	var svg: String = FileAccess.get_file_as_string(atlas_path)
	for size: int in [24,32,48]:
		var image: Image = Image.new()
		var error: Error = image.load_svg_from_string(svg, float(size)/64.0)
		if error != OK or image.get_size() != Vector2i(size*4,size*4):
			push_error("Native SVG raster failed: %s" % size)
			quit(1)
			return
		error = image.save_png(output.path_join("atlas_%s.png" % size))
		if error != OK:
			quit(1)
			return
	print("Native SVG raster24/32/48: PASS")
	quit()
