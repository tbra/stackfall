extends GutTest
## Bontago-1pi.192.2 C1: UiChatPanel (lobby and HUD skins, fade timeline, plain-text log, input rules).

var _submitted: Array[String] = []
var _opened: int = 0
var _closed: int = 0


func _make(mode: UiChatPanel.Mode) -> UiChatPanel:
	var panel: UiChatPanel = UiChatPanel.new()
	panel.mode = mode
	add_child_autofree(panel)
	_submitted.clear()
	_opened = 0
	_closed = 0
	panel.submit_requested.connect(func(text: String) -> void: _submitted.append(text))
	panel.input_opened.connect(func() -> void: _opened += 1)
	panel.input_closed.connect(func() -> void: _closed += 1)
	return panel


func _line(text: String, slot: int = 0, who: String = "Ann") -> Dictionary:
	return ChatRules.make_line(0, 1, slot, who, slot, text)


func test_hud_shows_only_the_last_hud_lines() -> void:
	var panel: UiChatPanel = _make(UiChatPanel.Mode.HUD)
	var cap: int = panel.config.hud_lines
	for i: int in cap + 4:
		panel.append_line(_line("line %d" % i))
	assert_eq(panel.shown_line_count(), cap)
	var text: String = panel.log.get_parsed_text()
	assert_true(text.contains("line %d" % (cap + 3)))
	assert_false(text.contains("line 0"))


func test_lobby_keeps_every_line_and_stays_visible() -> void:
	var panel: UiChatPanel = _make(UiChatPanel.Mode.LOBBY)
	for i: int in panel.config.hud_lines + 4:
		panel.append_line(_line("line %d" % i))
	assert_eq(panel.shown_line_count(), panel.config.hud_lines + 4)
	panel.apply_fade(panel.config.line_visible_s + panel.config.fade_s + 1.0)
	assert_true(panel.visible)
	assert_eq(panel.modulate.a, 1.0)
	assert_true(panel.log.scroll_active)
	assert_true(panel.edit.visible)


func test_fade_timeline_visible_fading_hidden_restored() -> void:
	var panel: UiChatPanel = _make(UiChatPanel.Mode.HUD)
	assert_false(panel.visible, "empty HUD panel starts hidden")
	panel.append_line(_line("hello"))
	assert_true(panel.visible)
	var cfg: ChatConfig = panel.config
	panel.apply_fade(cfg.line_visible_s - 0.1)
	assert_eq(panel.modulate.a, 1.0)
	panel.apply_fade(0.1 + cfg.fade_s * 0.5)
	assert_almost_eq(panel.modulate.a, 0.5, 0.01)
	assert_true(panel.visible)
	panel.apply_fade(cfg.fade_s)
	assert_false(panel.visible)
	assert_eq(panel.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	panel.append_line(_line("again"))
	assert_true(panel.visible)
	assert_eq(panel.modulate.a, 1.0)
	panel.apply_fade(cfg.line_visible_s + cfg.fade_s + 1.0)
	assert_false(panel.visible)
	panel.open_input()
	assert_true(panel.visible)
	assert_eq(panel.modulate.a, 1.0)
	panel.apply_fade(cfg.line_visible_s + cfg.fade_s + 1.0)
	assert_true(panel.visible, "typing keeps the panel up")


func test_enter_submits_trimmed_text_then_closes() -> void:
	var panel: UiChatPanel = _make(UiChatPanel.Mode.HUD)
	panel.open_input()
	assert_true(panel.is_typing())
	assert_true(panel.edit.visible)
	assert_eq(_opened, 1)
	panel.edit.text = "  hello there  "
	panel.edit.text_submitted.emit(panel.edit.text)
	assert_eq(_submitted, ["hello there"] as Array[String])
	assert_false(panel.is_typing())
	assert_false(panel.edit.visible)
	assert_eq(panel.edit.text, "")
	assert_eq(_closed, 1)


func test_empty_submit_sends_nothing_and_closes() -> void:
	var panel: UiChatPanel = _make(UiChatPanel.Mode.HUD)
	panel.open_input()
	panel.edit.text = "   "
	panel.edit.text_submitted.emit(panel.edit.text)
	assert_eq(_submitted.size(), 0)
	assert_false(panel.is_typing())
	assert_eq(_closed, 1)


func test_cancel_discards_closes_and_marks_the_event_handled() -> void:
	var panel: UiChatPanel = _make(UiChatPanel.Mode.HUD)
	panel.open_input()
	panel.edit.text = "oops"
	var cancel: InputEventKey = null
	for event: InputEvent in InputMap.action_get_events(&"ui_cancel"):
		if event is InputEventKey:
			cancel = (event as InputEventKey).duplicate() as InputEventKey
			cancel.pressed = true
	assert_not_null(cancel)
	assert_true(cancel.is_action_pressed(&"ui_cancel"))
	panel.edit.gui_input.emit(cancel)
	assert_eq(_submitted.size(), 0)
	assert_false(panel.is_typing())
	assert_eq(panel.edit.text, "")
	assert_eq(_closed, 1)
	assert_true(get_viewport().is_input_handled())
	panel.open_input()
	assert_eq(panel.edit.text, "", "a cancelled draft is gone")


func test_pad_press_while_typing_closes_and_keeps_the_draft() -> void:
	var panel: UiChatPanel = _make(UiChatPanel.Mode.HUD)
	panel.open_input()
	panel.edit.text = "half a thought"
	var press: InputEventJoypadButton = InputEventJoypadButton.new()
	press.button_index = JOY_BUTTON_A
	press.pressed = true
	panel._input(press)
	assert_false(panel.is_typing())
	assert_eq(_closed, 1)
	assert_eq(_submitted.size(), 0)
	panel.open_input()
	assert_eq(panel.edit.text, "half a thought")
