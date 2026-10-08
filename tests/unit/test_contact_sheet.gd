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


func test_build_pages_never_exceed_cap_and_paginate() -> void:
	var images: Array[Image] = []
	for i: int in 40:
		images.append(_solid(1920, 1080, Color.from_hsv(float(i) / 40.0, 1.0, 1.0)))
	var pages: Array[Image] = ContactSheet.build_pages(images, 5000)
	assert_gt(pages.size(), 1)
	for page: Image in pages:
		assert_lte(page.get_width(), ContactSheet.MAX_SHEET_PX_W)
		assert_lte(page.get_height(), ContactSheet.MAX_SHEET_PX_H)


func test_build_pages_single_page_when_fits_and_tall_image_clamped() -> void:
	var few: Array[Image] = [_solid(1920, 1080, Color.RED), _solid(1920, 1080, Color.BLUE)]
	assert_eq(ContactSheet.build_pages(few, 1280).size(), 1)
	var tall: Array[Image] = [_solid(100, 9000, Color.RED)]
	assert_lte(ContactSheet.build_pages(tall, 1280)[0].get_height(), ContactSheet.MAX_SHEET_PX_H)
