extends GutTest
## UiField (text/placeholder/signals/focus, token style), UiSection (header,
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
	field.text = "Tony"  # lint-public: allow fixture text, not a user name
	assert_eq(field.edit.placeholder_text, "Your name")
	assert_eq(field.edit.text, "Tony")  # lint-public: allow fixture text, not a user name
	field.edit.text_changed.emit("Tonyx")
	assert_eq(field.text, "Tonyx", "typing updates the component text")
	assert_eq(changed, ["Tonyx"])
	field.edit.text_submitted.emit("Tonyx")
	assert_eq(submitted, ["Tonyx"])


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
	assert_eq(section.advanced_button.text, UiSection.ADVANCED_CHIP_TEXT)
	assert_not_null(section.advanced_button.get_node_or_null("DisclosureArrow"), "drawn triangle")
	section.advanced_button.toggled.emit(true)
	assert_true(section.advanced.visible)
	assert_eq(section.advanced_button.text, UiSection.ADVANCED_CHIP_TEXT)
	section.toggle_advanced()
	assert_eq(opened, [true, false])
	section.set_advanced_open(false)
	assert_eq(opened.size(), 2, "no emit without a change")


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
