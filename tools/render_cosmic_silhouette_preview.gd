extends SceneTree


func _initialize() -> void:
	for name: String in ["cosmic_horizon_silhouette_preview"]:
		var image := Image.new()
		var source := "res://docs/art_mockups/%s.svg" % name
		var target := "res://docs/art_mockups/%s.png" % name
		var loaded := image.load(source)
		if loaded != OK:
			push_error("SVG load failed: %s (%s)" % [source, loaded])
			quit(1)
			return
		var saved := image.save_png(target)
		if saved != OK:
			push_error("PNG save failed: %s (%s)" % [target, saved])
			quit(1)
			return
		print("Rendered %s at %s x %s" % [target, image.get_width(), image.get_height()])
	for state: String in ["dim", "watch", "flare"]:
		var image := Image.new()
		var source := "res://assets/maps/cosmic_horror/horizon_eye_%s.svg" % state
		var target := "res://assets/maps/cosmic_horror/horizon_eye_%s.png" % state
		var loaded := image.load(source)
		if loaded != OK:
			push_error("SVG load failed: %s (%s)" % [source, loaded])
			quit(1)
			return
		var saved := image.save_png(target)
		if saved != OK:
			push_error("PNG save failed: %s (%s)" % [target, saved])
			quit(1)
			return
		print("Rendered %s at %s x %s" % [target, image.get_width(), image.get_height()])
	quit()
