extends GutTest
## Legibility floor of the text ink the menu picks for a face.

func test_ink_for_face_picks_the_readable_ink() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	assert_eq(MenuStyleFactory.ink_for_face(arcade.rim_color), arcade.ink_color, "ink on a bright face")
	assert_eq(MenuStyleFactory.ink_for_face(arcade.disc_800_color), arcade.cream_color, "cream on a disc")
