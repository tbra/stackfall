extends GutTest
## Owner playtest 2026-10-14: chip toggles without a check box and with silhouette icons
## (Bontago-1pi.159.54 / .55), the lobby chat log back in a well (.57), the redrawn hourglass (.61).

const GIFT_ID: StringName = &"anvil"


func _chip(on: bool) -> UiChipToggle:
	var chip: UiChipToggle = UiChipToggle.new()
	chip.label = "Anvil"
	chip.chip_icon = GiftIconTable.shared().gift_pictogram(GIFT_ID)
	add_child_autofree(chip)
	chip.set_on_silent(on)
	return chip


func test_chip_icon_is_a_flat_white_silhouette_with_the_source_alpha() -> void:
	var source: Texture2D = GiftIconTable.shared().gift_pictogram(GIFT_ID)
	var chip: UiChipToggle = _chip(false)
	assert_ne(chip.icon, source, "the shown icon is the derived silhouette")
	assert_eq(chip.chip_icon, source, "the property keeps the source")
	var shown: Image = chip.icon.get_image()
	var original: Image = source.get_image()
	original.convert(Image.FORMAT_RGBA8)
	shown.convert(Image.FORMAT_RGBA8)
	assert_eq(shown.get_size(), original.get_size())
	var visible_pixels: int = 0
	for y: int in range(original.get_height()):
		for x: int in range(original.get_width()):
			var a: Color = original.get_pixel(x, y)
			var b: Color = shown.get_pixel(x, y)
			assert_almost_eq(b.a, a.a, 0.01)
			if a.a > 0.0:
				visible_pixels += 1
				assert_eq(Color(b.r, b.g, b.b), Color.WHITE)
	assert_gt(visible_pixels, 0)


func test_silhouette_is_cached_per_source() -> void:
	var source: Texture2D = GiftIconTable.shared().gift_pictogram(GIFT_ID)
	assert_same(UiChipToggle.silhouette_of(source), UiChipToggle.silhouette_of(source))
	assert_null(UiChipToggle.silhouette_of(null))


func test_chip_has_no_check_box_children_and_no_extra_lead() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var chip: UiChipToggle = _chip(true)
	assert_eq(chip.get_child_count(), 0)
	assert_eq(chip.get_theme_stylebox("normal").content_margin_left, float(arcade.space_3_px), "text starts at the block padding")


func test_icon_ink_follows_the_state_and_the_disabled_dim() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var off_chip: UiChipToggle = _chip(false)
	var on_chip: UiChipToggle = _chip(true)
	assert_eq(off_chip.get_theme_color("icon_normal_color"), arcade.cream_color)
	assert_eq(on_chip.get_theme_color("icon_pressed_color"), arcade.ink_color)
	on_chip.set_available(false)
	off_chip.set_available(false)
	assert_eq(on_chip.get_theme_color("icon_disabled_color"), Color(arcade.ink_color, arcade.disabled_alpha))
	assert_eq(off_chip.get_theme_color("icon_disabled_color"), Color(arcade.cream_color, arcade.disabled_alpha))
	assert_eq(off_chip.get_theme_color("font_disabled_color"), Color(arcade.cream_color, arcade.disabled_alpha))


func test_on_and_off_faces_stay_far_apart_in_luminance_without_the_box() -> void:
	var on_face: Color = UiChipToggle.face_for(true)
	var off_face: Color = UiChipToggle.face_for(false)
	assert_gt(absf(on_face.get_luminance() - off_face.get_luminance()), 0.3)


func test_chip_focus_ring_style_exists() -> void:
	var chip: UiChipToggle = _chip(false)
	assert_not_null(chip.get_theme_stylebox("focus"))


func test_lobby_chat_log_sits_in_a_well_and_hud_has_none() -> void:
	var panel: UiChatPanel = UiChatPanel.new()
	add_child_autofree(panel)
	assert_true(panel.log.get_parent() is UiWell, "lobby log inside the well")
	assert_true((panel.log.get_parent() as UiWell).visible)
	panel.mode = UiChatPanel.Mode.HUD
	assert_false(panel.log.get_parent() is UiWell, "HUD log is unboxed")
	panel.mode = UiChatPanel.Mode.LOBBY
	assert_true(panel.log.get_parent() is UiWell)


func test_hourglass_is_a_solid_silhouette_inside_its_box() -> void:
	var origin: Vector2 = Vector2(2.0, 3.0)
	var edge: float = 28.0
	var outline: PackedVector2Array = UiStatusBadge.mark_points(UiStatusBadge.Look.NOT_READY, origin, edge)
	var box: Rect2 = Rect2(origin, Vector2(edge, edge)).grow(0.01)
	for point: Vector2 in outline:
		assert_true(box.has_point(point))
	assert_false(Geometry2D.triangulate_polygon(outline).is_empty(), "a simple polygon that fills")
	for point: Vector2 in UiStatusBadge.glass_points(origin, edge):
		assert_true(Geometry2D.is_point_in_polygon(point, outline), "glass cut-out stays inside the solid")
		assert_true(box.has_point(point))
