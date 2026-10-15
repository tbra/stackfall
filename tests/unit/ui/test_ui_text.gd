extends GutTest
## Bontago-1pi.159.11 C4a: UiText resolves font, size, colour and outline from the tokens per role.

const ROLES: Array[UiText.Role] = [UiText.Role.TITLE, UiText.Role.HEADING, UiText.Role.BODY, UiText.Role.CAPTION, UiText.Role.VALUE]


func test_each_role_takes_its_size_from_the_tokens() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var expected: Dictionary = {
		UiText.Role.TITLE: arcade.font_size_score_px, UiText.Role.HEADING: arcade.font_size_heading_px,
		UiText.Role.BODY: arcade.font_size_body_px, UiText.Role.CAPTION: arcade.font_size_caption_px,
		UiText.Role.VALUE: UiRowItem.metrics().text_value_font_px,
	}
	for text_role: UiText.Role in ROLES:
		var label: UiText = UiText.make(text_role, "x")
		add_child_autofree(label)
		assert_eq(label.get_theme_font_size("font_size"), expected[text_role] as int, "size of role %d" % text_role)
		assert_eq(label.get_theme_font("font"), UiText.font_for(text_role), "font of role %d" % text_role)


func test_each_role_takes_its_colour_from_the_tokens() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var expected: Dictionary = {
		UiText.Role.TITLE: arcade.cream_color, UiText.Role.HEADING: arcade.cream_color,
		UiText.Role.BODY: arcade.sand_color, UiText.Role.CAPTION: arcade.dust_color,
		UiText.Role.VALUE: arcade.cream_color,
	}
	for text_role: UiText.Role in ROLES:
		var label: UiText = UiText.make(text_role)
		add_child_autofree(label)
		assert_eq(label.get_theme_color("font_color"), expected[text_role] as Color, "colour of role %d" % text_role)
		assert_eq(label.get_theme_constant("outline_size"), UiRowItem.metrics().text_outline_px)


func test_display_roles_use_the_display_font_and_body_does_not() -> void:
	assert_eq(UiText.font_for(UiText.Role.TITLE), UiText.font_for(UiText.Role.VALUE))
	assert_ne(UiText.font_for(UiText.Role.TITLE), UiText.font_for(UiText.Role.BODY))
	assert_not_null(UiText.font_for(UiText.Role.HEADING))


func test_tint_overrides_the_role_colour_and_clearing_restores_it() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var label: UiText = UiText.make(UiText.Role.BODY, "x", arcade.alert_color)
	add_child_autofree(label)
	assert_eq(label.get_theme_color("font_color"), arcade.alert_color)
	label.tint = Color.TRANSPARENT
	assert_eq(label.get_theme_color("font_color"), arcade.sand_color)


func test_set_face_picks_the_readable_ink() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var label: UiText = UiText.make(UiText.Role.HEADING, "x")
	add_child_autofree(label)
	label.set_face(arcade.rim_color)
	assert_eq(label.get_theme_color("font_color"), arcade.ink_color, "ink on a bright face")
	label.set_face(arcade.disc_800_color)
	assert_eq(label.get_theme_color("font_color"), arcade.cream_color, "cream on a disc")


func test_changing_the_role_restyles_and_the_label_ignores_the_mouse() -> void:
	var label: UiText = UiText.new()
	add_child_autofree(label)
	label.role = UiText.Role.CAPTION
	assert_eq(label.get_theme_font_size("font_size"), MenuStyleFactory.arcade_tuning().font_size_caption_px)
	assert_eq(label.mouse_filter, Control.MOUSE_FILTER_IGNORE)


func test_gallery_text_page_shows_every_role_and_a_well() -> void:
	var gallery: ComponentGallery = ComponentGallery.new()
	gallery.page = ComponentGallery.PAGE_TEXT
	add_child_autofree(gallery)
	await wait_frames(2)
	var roles_seen: Dictionary = {}
	for node: Node in gallery.find_children("*", "Label", true, false):
		if node is UiText:
			roles_seen[(node as UiText).role] = true
	assert_eq(roles_seen.size(), UiText.Role.size(), "every role is on the page")
	assert_gt(gallery.find_children("*", "PanelContainer", true, false).filter(func(n: Node) -> bool: return n is UiWell).size(), 0)


func test_label_role_is_the_tracked_uppercase_sand_word() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var label: UiText = UiText.make(UiText.Role.LABEL, "Rotate")
	add_child_autofree(label)
	assert_eq(label.text, "ROTATE")
	assert_eq(label.get_theme_font_size("font_size"), arcade.font_size_caption_px)
	assert_eq(label.get_theme_color("font_color"), arcade.sand_color)
	assert_eq(label.get_theme_font("font"), UiText.font_for(UiText.Role.LABEL))
	var tinted: UiText = UiText.make(UiText.Role.LABEL, "x", arcade.rim_color)
	add_child_autofree(tinted)
	assert_eq(tinted.get_theme_color("font_color"), arcade.rim_color)
