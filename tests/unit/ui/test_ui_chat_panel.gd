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


func test_hold_visible_keeps_the_hud_panel_up() -> void:
	var panel: UiChatPanel = _make(UiChatPanel.Mode.HUD)
	panel.append_line(_line("hello"))
	panel.hold_visible = true
	panel.apply_fade(panel.config.line_visible_s + panel.config.fade_s + 1.0)
	assert_true(panel.visible)
	panel.hold_visible = false
	panel.apply_fade(panel.config.line_visible_s + panel.config.fade_s + 1.0)
	assert_false(panel.visible)


func test_history_replacement_does_not_wake_a_hidden_hud_panel() -> void:
	var panel: UiChatPanel = _make(UiChatPanel.Mode.HUD)
	panel.replace_history([_line("old one"), _line("old two")])
	assert_false(panel.visible)
	assert_eq(panel.shown_line_count(), 2)
	panel.replace_history([_line("only")])
	assert_eq(panel.shown_line_count(), 1)


func test_log_is_plain_text_and_brackets_render_literally() -> void:
	var panel: UiChatPanel = _make(UiChatPanel.Mode.LOBBY)
	assert_false(panel.log.bbcode_enabled)
	for payload: String in ["[b]x[/b]", "[url]http://a[/url]", "[img]res://icon.svg[/img]"]:
		panel.append_line(_line(payload, 1, "[b]Mal[/b]"))
	var text: String = panel.log.get_parsed_text()
	for payload: String in ["[b]x[/b]", "[url]http://a[/url]", "[img]res://icon.svg[/img]", "[b]Mal[/b]: "]:
		assert_true(text.contains(payload), payload)


func test_sender_name_is_tinted_with_the_palette_colour() -> void:
	var line: Dictionary = _line("hi", 2)
	assert_eq(UiChatPanel.name_color(line), MatchConfig.default_player_colors()[2])


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


func test_pad_events_are_ignored_while_not_typing() -> void:
	var panel: UiChatPanel = _make(UiChatPanel.Mode.LOBBY)
	var motion: InputEventJoypadMotion = InputEventJoypadMotion.new()
	motion.axis_value = 1.0
	panel._input(motion)
	assert_eq(_closed, 0)
	assert_false(panel.is_typing())


func test_max_length_comes_from_the_chat_config() -> void:
	var panel: UiChatPanel = _make(UiChatPanel.Mode.LOBBY)
	assert_eq(panel.edit.max_length, panel.config.max_chars)
	assert_eq(panel.edit.max_length, 140)
	panel.edit.text = "x".repeat(panel.config.max_chars + 20)
	assert_lte(panel.edit.text.length(), panel.config.max_chars)


func test_lobby_edit_is_click_focus_only_and_hud_ignores_the_mouse() -> void:
	var lobby: UiChatPanel = _make(UiChatPanel.Mode.LOBBY)
	assert_eq(lobby.edit.focus_mode, Control.FOCUS_CLICK)
	var hud: UiChatPanel = _make(UiChatPanel.Mode.HUD)
	assert_eq(hud.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(hud.log.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(hud.edit.mouse_filter, Control.MOUSE_FILTER_IGNORE)


func test_mode_switch_restyles_in_place() -> void:
	var panel: UiChatPanel = _make(UiChatPanel.Mode.LOBBY)
	for i: int in panel.config.hud_lines + 2:
		panel.append_line(_line("l%d" % i))
	panel.mode = UiChatPanel.Mode.HUD
	assert_eq(panel.shown_line_count(), panel.config.hud_lines)
	assert_false(panel.edit.visible)
	panel.mode = UiChatPanel.Mode.LOBBY
	assert_eq(panel.shown_line_count(), panel.config.hud_lines + 2)
	assert_true(panel.edit.visible)
