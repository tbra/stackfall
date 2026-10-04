extends GutTest
## Bontago-1pi.71: every footer/prompt that names an input shows the glyph of the
## BOUND action for the ACTIVE device (ui/InputPromptFlow.gd) and swaps live when
## the player switches between keyboard/mouse and gamepad.

const MAIN_MENU_SCENE: PackedScene = preload("res://ui/MainMenu.tscn")
const LOBBY_SCENE: PackedScene = preload("res://ui/Lobby.tscn")
const OPTIONS_SCENE: PackedScene = preload("res://ui/OptionsMenu.tscn")
const TUTORIAL_CONFIG: TutorialConfig = preload("res://config/tutorial_config.tres")
const PLAYER_FACING_FILES: Array[String] = [
	"res://ui/MainMenu.tscn", "res://ui/Lobby.tscn", "res://ui/OptionsMenu.tscn",
	"res://config/tutorial_config.tres",
]


func after_each() -> void:
	Settings.set_active_input_device_for_test(Settings.DEFAULT_ACTIVE_DEVICE)


## DECISION: events go straight to Settings._input() (the same convention as
## tests/unit/test_input_device.gd) because the global Input.parse_input_event()
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


func _textures(row: InputPromptFlow) -> Array[Texture2D]:
	var found: Array[Texture2D] = []
	for glyph: InputGlyph in row.glyphs():
		found.append(glyph.glyph_texture())
	return found


func _texts(row: InputPromptFlow) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for glyph: InputGlyph in row.glyphs():
		found.append(glyph.label_text())
	return found


func _assert_swaps(row: InputPromptFlow, name: String) -> void:
	_press_pad_button()
	assert_eq(Settings.active_input_device(), Settings.DEVICE_GAMEPAD, "%s: pad press switches device" % name)
	var pad_texts: PackedStringArray = _texts(row)
	var pad_textures: Array[Texture2D] = _textures(row)
	assert_gte(pad_texts.size(), 2, "%s: accept+cancel glyphs on gamepad" % name)
	assert_true(pad_texts.has("A") and pad_texts.has("B"), "%s: gamepad shows A/B glyphs (%s)" % [name, pad_texts])
	_press_key()
	assert_eq(Settings.active_input_device(), Settings.DEVICE_KEYBOARD_MOUSE, "%s: key press switches back" % name)
	var key_texts: PackedStringArray = _texts(row)
	var key_textures: Array[Texture2D] = _textures(row)
	assert_gte(key_texts.size(), 2, "%s: accept+cancel glyphs on keyboard" % name)
	assert_false(key_texts.has("A") or key_texts.has("B"), "%s: keyboard shows no pad glyph (%s)" % [name, key_texts])
	assert_ne(pad_texts, key_texts, "%s: glyph labels differ between devices" % name)
	if pad_textures[0] != null and key_textures[0] != null:
		assert_ne(pad_textures[0], key_textures[0], "%s: glyph textures swap" % name)


func test_main_menu_footer_swaps_glyphs_with_the_active_device() -> void:
	var menu: MainMenu = autofree(MAIN_MENU_SCENE.instantiate())
	add_child_autofree(menu)
	_assert_swaps(menu.get_node("%GamepadHintRow") as InputPromptFlow, "main menu")


func test_lobby_footer_swaps_glyphs_with_the_active_device() -> void:
	var lobby: Lobby = autofree(LOBBY_SCENE.instantiate())
	add_child_autofree(lobby)
	_assert_swaps(lobby.get_node("%GamepadHintBar") as InputPromptFlow, "lobby")


func test_options_footer_swaps_glyphs_with_the_active_device() -> void:
	var menu: OptionsMenu = autofree(OPTIONS_SCENE.instantiate())
	add_child_autofree(menu)
	var row: InputPromptFlow = menu.get_node("%FooterHintLabel") as InputPromptFlow
	_press_pad_button()
	assert_true(_texts(row).has("A") and _texts(row).has("B"))
	assert_true(_texts(row).has("LB") and _texts(row).has("RB"), "gamepad footer shows the tab bumpers")
	_press_key()
	assert_false(_texts(row).has("A"))
	assert_true(_texts(row).has("Enter") or _texts(row).has("Space"), "keyboard footer shows the accept key")


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


func test_unbound_action_falls_back_to_its_name_not_a_key() -> void:
	var row: InputPromptFlow = autofree(InputPromptFlow.new())
	row.template = "Press {no_such_action_71} now"
	add_child_autofree(row)
	assert_eq(row.glyphs().size(), 0)
	assert_eq(row.plain_text(), "Press no such action 71 now")


func test_tutorial_prompts_use_action_tokens_not_key_names() -> void:
	var banned: PackedStringArray = ["left click", "right bumper", "left stick", "right stick", "arrow keys", "(S ", "(R)", "(A)"]
	for step: TutorialStep in TUTORIAL_CONFIG.steps:
		for word: String in banned:
			assert_false(step.prompt_text.contains(word), "%s: '%s' typed in prompt" % [step.id, word])
	assert_true(TUTORIAL_CONFIG.steps[0].prompt_text.contains("{ghost_place}"))


func test_player_facing_files_name_no_key_or_button_literals() -> void:
	var pattern: RegEx = RegEx.new()
	pattern.compile(r"(?i)(Enter · Esc|\(A\) Select|\(B\) Back|A Select|B Back|⌨)")
	for path: String in PLAYER_FACING_FILES:
		var text: String = FileAccess.get_file_as_string(path)
		assert_null(pattern.search(text), "%s still types a key/button name" % path)
