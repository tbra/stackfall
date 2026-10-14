extends GutTest
## Bontago-1pi.159.5: UiChipToggle: mint + tick box when on, disc-700 + empty box when off, disabled
## with tooltip via set_available(false), ui_accept toggles, row height.

var _toggled: Array[bool] = []


func _make(text: String = "Black hole") -> UiChipToggle:
	var chip: UiChipToggle = UiChipToggle.new()
	chip.label = text
	chip.toggled.connect(func(on: bool) -> void: _toggled.append(on))
	add_child_autofree(chip)
	return chip


func before_each() -> void:
	_toggled.clear()


func test_faces_come_from_the_tokens() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	assert_eq(UiChipToggle.face_for(true), arcade.mint_color)
	assert_eq(UiChipToggle.face_for(false), arcade.disc_700_color)


func test_on_uses_the_pressed_block_in_mint_with_ink_label_and_off_in_disc_700() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var chip: UiChipToggle = _make()
	assert_eq((chip.get_theme_stylebox("normal") as BlockStyleBox).face_color, arcade.disc_700_color)
	assert_eq((chip.get_theme_stylebox("pressed") as BlockStyleBox).face_color, arcade.mint_color)
	assert_false((chip.get_theme_stylebox("pressed") as BlockStyleBox).pressed, "the on block stays lit")
	assert_eq(chip.get_theme_color("font_pressed_color"), arcade.ink_color, "ink on mint")
	assert_eq(chip.get_theme_color("font_color"), arcade.cream_color, "cream on disc-700")


func test_state_api_label_and_signal() -> void:
	var chip: UiChipToggle = _make("Bomb")
	assert_eq(chip.text, "Bomb")
	assert_false(chip.is_on())
	chip.set_on(true)
	assert_true(chip.is_on())
	assert_eq(_toggled, [true])
	chip.set_on_silent(false)
	assert_eq(_toggled, [true])


func test_unavailable_chip_is_disabled_with_an_inline_reason_and_keeps_its_state() -> void:
	var chip: UiChipToggle = _make("Cat")
	chip.set_on(true)
	chip.set_available(false, "Switched off for this match")
	assert_true(chip.disabled)
	assert_false(chip.is_available())
	assert_eq(chip.unavailable_reason(), "Switched off for this match")
	assert_eq(chip.tooltip_text, "", "no tooltip")
	assert_true(chip.is_on())
	assert_true((chip.get_theme_stylebox("disabled") as BlockStyleBox).disabled)
	chip.set_available(true)
	assert_false(chip.disabled)


func test_icon_is_the_buttons_icon() -> void:
	var chip: UiChipToggle = _make()
	chip.chip_icon = PlaceholderTexture2D.new()
	assert_eq(chip.icon, chip.chip_icon)


func test_one_row_height_and_shrink_begin() -> void:
	var chip: UiChipToggle = _make()
	await wait_frames(2)
	assert_eq(chip.size.y, float(UiRowItem.metrics().row_height_px))
	assert_true(chip.is_in_group(UiRowItem.GROUP))
	assert_eq(chip.size_flags_horizontal, Control.SIZE_SHRINK_BEGIN)


func test_ui_accept_toggles_when_focused() -> void:
	var chip: UiChipToggle = _make()
	await wait_frames(1)
	chip.grab_focus()
	var accept: InputEventKey = InputEventKey.new()
	accept.keycode = KEY_ENTER
	accept.physical_keycode = KEY_ENTER
	accept.pressed = true
	Input.parse_input_event(accept)
	var release: InputEventKey = accept.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	await wait_frames(1)
	assert_true(chip.is_on())


func test_unavailable_chip_ignores_accept() -> void:
	var chip: UiChipToggle = _make()
	chip.set_available(false)
	await wait_frames(1)
	chip.grab_focus()
	var accept: InputEventKey = InputEventKey.new()
	accept.keycode = KEY_ENTER
	accept.physical_keycode = KEY_ENTER
	accept.pressed = true
	Input.parse_input_event(accept)
	Input.flush_buffered_events()
	await wait_frames(1)
	assert_false(chip.is_on())


func test_blocks_are_shared_across_chips_and_stay_after_state_changes() -> void:
	var first: UiChipToggle = _make("A")
	var second: UiChipToggle = _make("B")
	assert_same(first.get_theme_stylebox("normal"), second.get_theme_stylebox("normal"), "one block per state per token set")
	var normal_before: StyleBox = first.get_theme_stylebox("normal")
	var margin_top: float = normal_before.content_margin_top
	first.set_on(true)
	first.set_available(false)
	first.set_on_silent(false)
	assert_same(first.get_theme_stylebox("normal"), normal_before, "toggling never rebuilds the block")
	assert_eq(normal_before.content_margin_top, margin_top, "the shared block is never mutated again")


func test_disabled_block_follows_the_chips_own_face() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var on_chip: UiChipToggle = _make("On")
	var off_chip: UiChipToggle = _make("Off")
	on_chip.set_on(true)
	on_chip.set_available(false)
	off_chip.set_available(false)
	assert_eq((on_chip.get_theme_stylebox("disabled") as BlockStyleBox).face_color, arcade.mint_color)
	assert_eq((off_chip.get_theme_stylebox("disabled") as BlockStyleBox).face_color, arcade.disc_700_color)
	on_chip.set_on_silent(false)
	assert_eq((on_chip.get_theme_stylebox("disabled") as BlockStyleBox).face_color, arcade.disc_700_color)


func test_invalidating_the_cache_restyles_from_current_tokens() -> void:
	var chip: UiChipToggle = _make("A")
	var old_box: StyleBox = chip.get_theme_stylebox("normal")
	UiChipToggle.invalidate_style_cache()
	chip.set_on(true)
	assert_ne(chip.get_theme_stylebox("normal"), old_box, "a new block after invalidation")
	assert_eq((chip.get_theme_stylebox("normal") as BlockStyleBox).face_color, MenuStyleFactory.arcade_tuning().disc_700_color)
