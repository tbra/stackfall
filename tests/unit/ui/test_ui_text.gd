extends GutTest
## C4a: UiText resolves font, size, colour and outline from the tokens per role.

func test_tint_overrides_the_role_colour_and_clearing_restores_it() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var label: UiText = UiText.make(UiText.Role.BODY, "x", arcade.alert_color)
	add_child_autofree(label)
	assert_eq(label.get_theme_color("font_color"), arcade.alert_color)
	label.tint = Color.TRANSPARENT
	assert_eq(label.get_theme_color("font_color"), arcade.sand_color)


func test_ink_for_face_picks_the_readable_ink() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	assert_eq(MenuStyleFactory.ink_for_face(arcade.rim_color), arcade.ink_color, "ink on a bright face")
	assert_eq(MenuStyleFactory.ink_for_face(arcade.disc_800_color), arcade.cream_color, "cream on a disc")


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
