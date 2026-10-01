extends GutTest
## Bontago-59o.1/.2: SlopShop splash gating, skip handling, assets and icon.


func test_skipped_when_headless_or_cli_args() -> void:
	assert_false(SplashScreen.should_show(true, PackedStringArray()))
	assert_false(SplashScreen.should_show(false, PackedStringArray(["--hot-seat"])))
	assert_true(SplashScreen.should_show(false, PackedStringArray()))


func test_assets_and_settings() -> void:
	assert_true(load(SplashScreen.JINGLE_PATH) is AudioStream)
	assert_true(load(SplashScreen.IMAGE_PATH) is Texture2D)
	assert_eq(ProjectSettings.get_setting("application/boot_splash/image"), SplashScreen.IMAGE_PATH)
	assert_eq(ProjectSettings.get_setting("application/config/icon"), "res://assets/ui/stackfall_mark.svg")


func test_finish_emits_once() -> void:
	var splash: SplashScreen = SplashScreen.new()
	add_child(splash)
	watch_signals(splash)
	splash.finish()
	splash.finish()
	assert_signal_emit_count(splash, "finished", 1)


func test_image_bounces_in_before_the_jingle_finishes() -> void:
	var splash: SplashScreen = SplashScreen.new()
	add_child_autofree(splash)
	assert_almost_eq(splash._image.modulate.a, 0.0, 0.01)
	assert_lt(splash._image.scale.x, 1.0)
	assert_true(splash._entrance_tween.is_running())
	await wait_seconds(0.3)
	assert_gt(splash._image.modulate.a, 0.5)
	assert_gt(splash._image.scale.x, 0.84)
	splash.finish()


func test_ui_accept_skips() -> void:
	var splash: SplashScreen = SplashScreen.new()
	add_child_autofree(splash)
	watch_signals(splash)
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_ENTER
	event.physical_keycode = KEY_ENTER
	event.pressed = true
	splash._unhandled_input(event)
	assert_signal_emitted(splash, "finished")


func test_gamepad_a_and_click_skip() -> void:
	var pad: InputEventJoypadButton = InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	assert_true(SplashScreen._is_skip_event(pad))
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.pressed = true
	assert_true(SplashScreen._is_skip_event(click))
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	assert_false(SplashScreen._is_skip_event(motion))
