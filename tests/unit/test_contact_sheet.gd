extends GutTest
## tools/ContactSheet.gd (Bontago-fca.8): grid sizing and run naming.

func _solid(width: int, height: int, colour: Color) -> Image:
	var image: Image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	image.fill(colour)
	return image


func test_build_fits_max_width_and_keeps_cell_pixels() -> void:
	var images: Array[Image] = [_solid(1920, 1080, Color.RED), _solid(1920, 1080, Color.GREEN),
			_solid(1920, 1080, Color.BLUE), _solid(1920, 1080, Color.WHITE)]
	var sheet: Image = ContactSheet.build(images, 1280)
	assert_lte(sheet.get_width(), 1280)
	assert_lt(sheet.get_height(), 2160)
	assert_eq(sheet.get_pixel(ContactSheet.GAP + 10, ContactSheet.GAP + 10), Color.RED)


func test_build_empty_is_one_pixel() -> void:
	assert_eq(ContactSheet.build([], 1280).get_size(), Vector2i(1, 1))


func test_run_name() -> void:
	assert_eq(ContactSheet.run_name(PackedStringArray(["--path", ".", "res://tools/screenshot_fog.tscn"])), "screenshot_fog")
	assert_eq(ContactSheet.run_name(PackedStringArray()), ContactSheet.FALLBACK_NAME)
