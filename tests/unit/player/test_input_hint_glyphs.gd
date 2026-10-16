extends GutTest
## every footer/prompt that names an input shows the glyph of the
## BOUND action for the ACTIVE device (ui/hud/InputPromptFlow.gd) and swaps live when
## the player switches between keyboard/mouse and gamepad.

const MAIN_MENU_SCENE: PackedScene = preload("res://ui/menus/MainMenu.tscn")
const TUTORIAL_CONFIG: TutorialConfig = preload("res://config/match/tutorial_config.tres")
func after_each() -> void:
	Settings._input(InputEventKey.new())


## DECISION: events go straight to Settings._input() (the same convention as
## tests/unit/player/test_input_device.gd) because the global Input.parse_input_event()
## does not reliably reach autoload _input() headless; the production path from
## Settings._input() onward (Events.input_device_changed -> the footers) is real.
func _press_pad_button() -> void:
	var pad: InputEventJoypadButton = InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	Settings._input(pad)


func _press_key() -> void:
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_ENTER
	key.pressed = true
	Settings._input(key)


func _texts(row: InputPromptFlow) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for glyph: InputGlyph in row.glyphs():
		found.append(glyph.label_text())
	return found


func _assert_swaps(row: InputPromptFlow, name: String) -> void:
	_press_pad_button()
	assert_eq(Settings.active_input_device(), Settings.DEVICE_GAMEPAD, "%s: pad press switches device" % name)
	var pad_texts: PackedStringArray = _texts(row)
	assert_gte(pad_texts.size(), 2, "%s: accept+cancel glyphs on gamepad" % name)
	assert_true(pad_texts.has("A") and pad_texts.has("B"), "%s: gamepad shows A/B glyphs (%s)" % [name, pad_texts])
	_press_key()
	assert_eq(Settings.active_input_device(), Settings.DEVICE_KEYBOARD_MOUSE, "%s: key press switches back" % name)
	var key_texts: PackedStringArray = _texts(row)
	assert_gte(key_texts.size(), 2, "%s: accept+cancel glyphs on keyboard" % name)
	assert_false(key_texts.has("A") or key_texts.has("B"), "%s: keyboard shows no pad glyph (%s)" % [name, key_texts])
	assert_ne(pad_texts, key_texts, "%s: glyph labels differ between devices" % name)


func test_main_menu_footer_swaps_glyphs_with_the_active_device() -> void:
	var menu: MainMenu = autofree(MAIN_MENU_SCENE.instantiate())
	add_child_autofree(menu)
	_assert_swaps(menu.get_node("%GamepadHintRow") as InputPromptFlow, "main menu")


func test_footer_follows_a_rebind_of_ui_accept() -> void:
	var original: Array[InputEvent] = InputMap.action_get_events(&"ui_accept")
	var row: InputPromptFlow = autofree(InputPromptFlow.new())
	row.template = "{ui_accept}"
	add_child_autofree(row)
	InputMap.action_erase_events(&"ui_accept")
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_J
	InputMap.action_add_event(&"ui_accept", key)
	row.refresh()
	assert_true(_texts(row).has("J"), "rebound key shown: %s" % _texts(row))
	InputMap.action_erase_events(&"ui_accept")
	for event: InputEvent in original:
		InputMap.action_add_event(&"ui_accept", event)


func test_tutorial_prompts_use_action_tokens_not_key_names() -> void:
	var banned: PackedStringArray = ["left click", "right bumper", "left stick", "right stick", "arrow keys", "(S ", "(R)", "(A)"]
	for step: TutorialStep in TUTORIAL_CONFIG.steps:
		for word: String in banned:
			assert_false(step.prompt_text.contains(word), "%s: '%s' typed in prompt" % [step.id, word])
	assert_true(TUTORIAL_CONFIG.steps[0].prompt_text.contains("{ghost_place}"))

