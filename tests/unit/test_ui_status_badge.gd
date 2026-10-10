extends GutTest
## Bontago-1pi.159.4: UiStatusBadge + the ReadyPill wrapper: token faces per look, never
## focusable / clickable, icon-only glyphs and tooltip, live dot, row height.


func _badge(look: UiStatusBadge.Look, text: String = "TEXT") -> UiStatusBadge:
	var badge: UiStatusBadge = UiStatusBadge.new()
	badge.text = text
	badge.variant = look
	add_child_autofree(badge)
	return badge


func _face(badge: UiStatusBadge) -> Color:
	return (badge.get_theme_stylebox("panel") as StyleBoxFlat).bg_color


func test_faces_come_from_the_tokens() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	assert_eq(_face(_badge(UiStatusBadge.Look.NEUTRAL)), arcade.disc_700_color)
	assert_eq(_face(_badge(UiStatusBadge.Look.READY)), arcade.mint_color)
	assert_eq(_face(_badge(UiStatusBadge.Look.ALL_READY)), arcade.rim_color, "all-ready is the rim form")
	assert_eq(_face(_badge(UiStatusBadge.Look.NOT_READY)), arcade.disc_600_color)


func test_never_takes_focus_or_mouse() -> void:
	var badge: UiStatusBadge = _badge(UiStatusBadge.Look.READY)
	assert_eq(badge.focus_mode, Control.FOCUS_NONE)
	assert_eq(badge.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(badge.label.mouse_filter, Control.MOUSE_FILTER_IGNORE)


func test_label_is_the_first_child_and_uses_ink_on_a_bright_face() -> void:
	var badge: UiStatusBadge = _badge(UiStatusBadge.Look.READY, "READY")
	assert_eq(badge.get_child(0), badge.label)
	assert_eq(badge.label.text, "READY")
	assert_eq(badge.label.get_theme_color("font_color"), MenuStyleFactory.arcade_tuning().ink_color)
	assert_eq(_badge(UiStatusBadge.Look.NEUTRAL).label.get_theme_color("font_color"), MenuStyleFactory.arcade_tuning().cream_color)


func test_icon_only_shows_glyphs_and_keeps_the_words_as_tooltip() -> void:
	var badge: UiStatusBadge = _badge(UiStatusBadge.Look.READY, "Ready")
	badge.icon_only = true
	assert_eq(badge.label.text, char(UiStatusBadge.TICK))
	assert_eq(badge.tooltip_text, "Ready")
	badge.variant = UiStatusBadge.Look.NOT_READY
	assert_eq(badge.label.text, char(UiStatusBadge.HOURGLASS))


func test_live_dot_widens_the_left_margin_and_neutral_is_flat() -> void:
	var badge: UiStatusBadge = _badge(UiStatusBadge.Look.NEUTRAL, "LAN")
	var flat: StyleBoxFlat = badge.get_theme_stylebox("panel") as StyleBoxFlat
	assert_eq(flat.border_width_bottom, 0, "the neutral badge is flat")
	var before: float = flat.content_margin_left
	badge.live = true
	var after: float = (badge.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_left
	assert_eq(after - before, float(UiRowItem.metrics().badge_dot_px + MenuStyleFactory.arcade_tuning().space_2_px))
	assert_gt((_badge(UiStatusBadge.Look.READY).get_theme_stylebox("panel") as StyleBoxFlat).border_width_bottom, 0, "bright faces carry the lip")


func test_badge_is_one_row_height() -> void:
	var badge: UiStatusBadge = _badge(UiStatusBadge.Look.NEUTRAL, "VS BOTS")
	await wait_frames(2)
	assert_eq(badge.size.y, float(UiRowItem.metrics().row_height_px))
	assert_true(badge.is_in_group(UiRowItem.GROUP))


func test_ready_pill_wrapper_keeps_its_api() -> void:
	var size: Vector2 = Vector2(32.0, 24.0)
	var pill: ReadyPill = ReadyPill.create(false, size, 0.0)
	add_child_autofree(pill)
	await wait_frames(2)
	assert_false(pill.is_ready)
	assert_eq(pill.label.text, char(UiStatusBadge.HOURGLASS))
	assert_eq(pill.tooltip_text, ReadyPill.tooltip_for(false))
	assert_eq(pill.custom_minimum_size, size, "the caller's compact size wins over the row height")
	assert_eq((pill.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_top, 0.0)
	pill.set_ready(true)
	assert_true(pill.is_ready)
	assert_eq(pill.label.text, char(UiStatusBadge.TICK))
	assert_eq(_face(pill), MenuStyleFactory.arcade_tuning().mint_color)
