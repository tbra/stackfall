extends GutTest
## Bontago-1pi.159.56: the lobby's four category headers are UiSection instances (one component),
## spaced by the section_gap token, each with a rule under the header row.

const SECTION_NAMES: Array[String] = ["%GameSection", "%RoundSection", "%GiftsSection", "%ExperimentsSection"]


func _make_lobby() -> Lobby:
	var lobby: Lobby = autofree((load("res://ui/Lobby.tscn") as PackedScene).instantiate())
	add_child_autofree(lobby)
	var fake: FakeNet = FakeNet.new()
	fake.is_host_value = true
	fake.is_offline_value = true
	lobby.net_provider = fake
	lobby._update_host_only_state()
	return lobby


func test_four_categories_are_ui_sections() -> void:
	var lobby: Lobby = _make_lobby()
	for unique_name: String in SECTION_NAMES:
		assert_true(lobby.get_node(unique_name) is UiSection, "%s is a UiSection" % unique_name)


func test_category_gap_comes_from_token() -> void:
	var lobby: Lobby = _make_lobby()
	var column: VBoxContainer = lobby.get_node("%Settings") as VBoxContainer
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	assert_eq(column.get_theme_constant("separation"), arcade.section_gap_px)
	assert_gt(arcade.section_gap_px, arcade.space_5_px, "categories sit further apart than a panel padding")


func test_header_has_rule_and_cream_caption() -> void:
	var lobby: Lobby = _make_lobby()
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	for unique_name: String in SECTION_NAMES:
		var section: UiSection = lobby.get_node(unique_name) as UiSection
		assert_eq(section.get_child(0).name, &"HeaderRow")
		assert_eq(section.get_child(1).name, &"HeaderRule", "rule directly under the header row")
		var caption: Label = section.get_child(0).get_child(1) as Label
		assert_eq(caption.get_theme_color("font_color"), arcade.cream_color)
		assert_eq((section.get_child(1) as Control).custom_minimum_size.y, float(arcade.section_rule_px))
