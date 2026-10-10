extends GutTest
## Bontago-1pi.159.7: UiField (text/placeholder/signals/focus, token style), UiSection (header,
## summary, Advanced disclosure, focus hand-over, ui_accept toggle) and UiPanel / UiTitleRow
## (heading in capitals, content column, trailing items on one centre line); UiSection is the
## thin legacy layer over UiSection.


func _action(action: StringName, pressed: bool = true) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event


func test_field_forwards_text_placeholder_and_signals() -> void:
	var field: UiField = UiField.new()
	add_child_autofree(field)
	var changed: Array[String] = []
	var submitted: Array[String] = []
	field.text_changed.connect(func(t: String) -> void: changed.append(t))
	field.text_submitted.connect(func(t: String) -> void: submitted.append(t))
	field.placeholder = "Your name"
	field.text = "Tony"
	assert_eq(field.edit.placeholder_text, "Your name")
	assert_eq(field.edit.text, "Tony")
	field.edit.text_changed.emit("Tonyx")
	assert_eq(field.text, "Tonyx", "typing updates the component text")
	assert_eq(changed, ["Tonyx"])
	field.edit.text_submitted.emit("Tonyx")
	assert_eq(submitted, ["Tonyx"])


func test_field_label_shows_only_when_given_and_focus_goes_to_the_input() -> void:
	var field: UiField = UiField.new()
	add_child_autofree(field)
	assert_false(field.label.visible)
	field.label_text = "DIRECT IP"
	assert_true(field.label.visible)
	assert_eq(field.label.text, "DIRECT IP")
	await wait_frames(2)
	field.focus_input()
	assert_true(field.edit.has_focus(), "the container hands focus to the LineEdit")
	assert_eq(field.focus_mode, Control.FOCUS_NONE)


func test_field_is_styled_from_tokens_and_is_a_filling_row_item() -> void:
	var field: UiField = UiField.new()
	add_child_autofree(field)
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var normal: StyleBoxFlat = field.edit.get_theme_stylebox("normal") as StyleBoxFlat
	assert_eq(normal.bg_color, arcade.disc_900_color)
	assert_eq(normal.border_color, arcade.disc_400_color)
	var focus: StyleBoxFlat = field.edit.get_theme_stylebox("focus") as StyleBoxFlat
	assert_eq(focus.border_color, arcade.cream_color, "focus turns the edge cream")
	assert_eq(field.edit.get_theme_color("font_placeholder_color"), arcade.dust_color)
	assert_true(field.is_in_group(UiRowItem.GROUP))
	assert_eq(field.size_flags_horizontal, Control.SIZE_EXPAND_FILL)
	assert_gte(field.edit.custom_minimum_size.y, float(UiRowItem.metrics().row_height_px))


func _section(with_advanced: bool = true) -> UiSection:
	var section: UiSection = UiSection.new()
	section.title = "ROUND"
	var body: VBoxContainer = VBoxContainer.new()
	body.name = UiSection.BODY_NAME
	section.add_child(body)
	if with_advanced:
		var advanced: MarginContainer = MarginContainer.new()
		advanced.name = UiSection.ADVANCED_NAME
		var inner: Button = Button.new()
		inner.name = "Inner"
		advanced.add_child(inner)
		section.add_child(advanced)
	add_child_autofree(section)
	return section


func test_section_starts_collapsed_with_a_right_caret_and_toggles() -> void:
	var section: UiSection = _section()
	var opened: Array[bool] = []
	section.advanced_changed.connect(func(open: bool) -> void: opened.append(open))
	assert_false(section.advanced.visible)
	assert_eq(section.advanced_button.text, "%s ADVANCED" % UiSection.DISCLOSURE_CLOSED)
	section.advanced_button.toggled.emit(true)
	assert_true(section.advanced.visible)
	assert_eq(section.advanced_button.text, "%s ADVANCED" % UiSection.DISCLOSURE_OPEN)
	section.toggle_advanced()
	assert_eq(opened, [true, false])
	section.set_advanced_open(false)
	assert_eq(opened.size(), 2, "no emit without a change")


func test_section_summary_and_icon_and_missing_advanced() -> void:
	var section: UiSection = _section(false)
	section.set_summary("Classic - Round")
	assert_eq(section.get_summary(), "Classic - Round")
	assert_null(section.advanced_button)
	section.set_advanced_open(true)
	assert_false(section.is_advanced_open(), "a no-op without an Advanced block")
	assert_null(section.header_icon())


func test_section_hiding_advanced_hands_focus_to_the_bar() -> void:
	var section: UiSection = _section()
	section.set_advanced_open(true)
	await wait_frames(2)
	(section.advanced.get_node("Inner") as Button).grab_focus()
	assert_true(section.has_focus_inside())
	section.set_advanced_open(false)
	assert_true(section.advanced_button.has_focus(), "focus never lands on a hidden control")


func test_section_bar_toggles_on_ui_accept() -> void:
	var section: UiSection = _section()
	await wait_frames(2)
	section.advanced_button.grab_focus()
	Input.parse_input_event(_action(&"ui_accept"))
	Input.parse_input_event(_action(&"ui_accept", false))
	Input.flush_buffered_events()
	await wait_frames(2)
	assert_true(section.is_advanced_open(), "A toggles the section")


func test_lobby_section_is_a_thin_layer_over_ui_section() -> void:
	var lobby_section: UiSection = UiSection.new()
	lobby_section.title = "GAME"
	var body: VBoxContainer = VBoxContainer.new()
	body.name = UiSection.BODY_NAME
	lobby_section.add_child(body)
	add_child_autofree(lobby_section)
	assert_true(lobby_section is UiSection)
	lobby_section.set_summary("Classic")
	assert_eq(lobby_section.get_summary(), "Classic")
	assert_eq(UiSection.DISCLOSURE_CLOSED, UiSection.DISCLOSURE_CLOSED)


func test_panel_heading_is_uppercase_with_content_column() -> void:
	var panel: UiPanel = UiPanel.new()
	panel.heading = "Match settings"
	add_child_autofree(panel)
	assert_true(panel.header.visible)
	assert_eq(panel.header.label.text, "MATCH SETTINGS")
	assert_not_null(panel.content)
	var row: Control = Control.new()
	panel.content.add_child(row)
	assert_eq(row.get_parent(), panel.content)
	assert_true(panel.get_theme_stylebox("panel") is StyleBoxFlat)


func test_panel_without_heading_hides_the_header() -> void:
	var panel: UiPanel = UiPanel.new()
	add_child_autofree(panel)
	assert_false(panel.header.visible)


func test_title_row_centres_trailing_items_on_one_line() -> void:
	var row: UiTitleRow = UiTitleRow.new()
	row.title = "Lobby"
	var badge: UiStatusBadge = UiStatusBadge.new()
	badge.text = "HOSTING"
	row.add_trailing(badge)
	var back: UiBlockButton = UiBlockButton.new()
	back.text = "BACK"
	row.add_trailing(back)
	add_child_autofree(row)
	row.size = Vector2(600.0, 60.0)
	await wait_frames(2)
	assert_eq(row.label.text, "LOBBY")
	var centre_label: float = row.label.global_position.y + row.label.size.y * 0.5
	var centre_badge: float = badge.global_position.y + badge.size.y * 0.5
	assert_almost_eq(centre_label, centre_badge, 1.0, "title and badge share a centre line")
	assert_gt(back.global_position.x, badge.global_position.x, "trailing items are pushed right in order")
