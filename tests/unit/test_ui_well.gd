extends GutTest
## Bontago-1pi.159.11 C4a: UiWell is the disc-900 well (2px disc-400 edge, radius-block, top shadow).


func test_well_style_matches_the_tokens() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var well: UiWell = UiWell.new()
	add_child_autofree(well)
	var box: StyleBoxFlat = well.get_theme_stylebox("panel") as StyleBoxFlat
	assert_not_null(box)
	assert_eq(box.bg_color, arcade.disc_900_color)
	assert_eq(box.border_color, arcade.disc_400_color)
	assert_eq(box.border_width_left, arcade.well_border_px)
	assert_eq(box.border_width_top, arcade.well_border_px)
	assert_eq(box.corner_radius_top_left, arcade.radius_block_px)
	assert_eq(box.corner_radius_bottom_right, arcade.radius_block_px)


func test_shadow_band_sits_under_the_top_edge_inside_the_corners() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var band: Rect2 = UiWell.shadow_rect(Vector2(200.0, 80.0))
	assert_eq(band.position.y, float(arcade.well_border_px))
	assert_eq(band.size.y, float(arcade.well_shadow_px))
	assert_eq(band.position.x, float(arcade.radius_block_px))
	assert_eq(band.size.x, 200.0 - 2.0 * float(arcade.radius_block_px))
	assert_lt(UiWell.shadow_color().get_luminance(), arcade.disc_900_color.get_luminance())
	assert_eq(UiWell.shadow_rect(Vector2.ZERO).size.x, 0.0, "a collapsed well never has a negative band")


func test_well_holds_children_and_pads_them() -> void:
	var well: UiWell = UiWell.new()
	add_child_autofree(well)
	var label: UiText = UiText.make(UiText.Role.BODY, "Host")
	well.add_child(label)
	await wait_frames(2)
	var pad: float = float(MenuStyleFactory.arcade_tuning().space_3_px + MenuStyleFactory.arcade_tuning().well_border_px)
	assert_gte(label.position.x, float(MenuStyleFactory.arcade_tuning().space_3_px))
	assert_gte(well.size.x, label.size.x + pad)
