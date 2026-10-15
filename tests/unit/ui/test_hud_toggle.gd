extends GutTest
## hud_toggle (F8 / PADDLE4) shows and hides the whole in-match HUD,
## in every match and the sandbox, and a new match starts with it visible.

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()


func after_each() -> void:
	Match.abort_match()


func _make_hud() -> HUD:
	var hud: HUD = autofree((load("res://ui/hud/HUD.tscn") as PackedScene).instantiate())
	add_child_autofree(hud)
	return hud


func _key(pressed: bool) -> InputEventKey:
	var e: InputEventKey = InputEventKey.new()
	e.device = -1
	e.physical_keycode = KEY_F8
	e.pressed = pressed
	return e


func _pad(button: JoyButton, pressed: bool) -> InputEventJoypadButton:
	var e: InputEventJoypadButton = InputEventJoypadButton.new()
	e.device = -1
	e.button_index = button
	e.pressed = pressed
	return e


func _shown(hud: HUD) -> bool:
	return hud.visible and hud._scale_root.visible


func test_f8_hides_and_shows_every_hud_control() -> void:
	var hud: HUD = _make_hud()
	var bystander: CanvasLayer = CanvasLayer.new()
	add_child_autofree(bystander)
	assert_true(_key(true).is_action_pressed(&"hud_toggle"))
	assert_true(_shown(hud))
	hud._unhandled_input(_key(true))
	assert_false(hud._scale_root.visible, "F8 hides every HUD control")
	assert_true(hud.is_hud_hidden())
	assert_true(bystander.visible, "other layers (pause menu, F1 overlay, ...) are untouched")
	hud._unhandled_input(_key(true))
	assert_true(_shown(hud), "the next F8 shows it again")


func test_paddle4_toggles_on_release() -> void:
	var hud: HUD = _make_hud()
	hud._unhandled_input(_pad(JOY_BUTTON_PADDLE4, true))
	hud._unhandled_input(_pad(JOY_BUTTON_PADDLE4, false))
	assert_false(hud._scale_root.visible)
	hud._unhandled_input(_pad(JOY_BUTTON_PADDLE4, true))
	hud._unhandled_input(_pad(JOY_BUTTON_PADDLE4, false))
	assert_true(hud._scale_root.visible)


func _boot_main() -> Node:
	var main: Node = MAIN_SCENE.instantiate()
	var tiny: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	tiny.field_radius = 20.0
	(main.get_node("Field") as Field).map_def = tiny
	add_child_autofree(main)
	return main


func test_works_in_the_sandbox_and_chord_does_not_toggle() -> void:
	var main: Node = _boot_main()
	main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	var sandbox: Sandbox = main._sandbox
	var hud: HUD = sandbox.hud()
	var overlay: TerritoryOverlay = main._field.overlay()
	var overlay_before: bool = overlay.visible
	hud._unhandled_input(_key(true))
	sandbox._unhandled_input(_key(true))
	assert_false(hud._scale_root.visible, "F8 hides the sandbox HUD")
	assert_eq(overlay.visible, overlay_before, "F8 leaves the territory overlay alone")
	hud._unhandled_input(_key(true))
	assert_true(hud._scale_root.visible)

	# PADDLE4 held, then PADDLE1 pressed: slow motion, no HUD toggle.
	var p4: InputEventJoypadButton = _pad(JOY_BUTTON_PADDLE4, true)
	hud._unhandled_input(p4)
	Input.action_press(&"hud_toggle")
	var p1: InputEventJoypadButton = _pad(JOY_BUTTON_PADDLE1, true)
	sandbox._unhandled_input(p1)
	hud._unhandled_input(p1)
	Input.action_release(&"hud_toggle")
	hud._unhandled_input(_pad(JOY_BUTTON_PADDLE4, false))
	assert_true(sandbox.is_slow_motion_active(), "the chord still triggers slow motion")
	assert_true(hud._scale_root.visible, "the chord must not also toggle the HUD")
