extends Node
## Windowed smoke-shot for Bontago-mv0.18's in-game tuning panel: boots the
## real sandbox route the same way tools/screenshot_mv017.gd does, opens the
## panel with a synthetic F4 key event (exactly what a real keypress would
## deliver -- InputEventKey routed through _unhandled_input()), shoots the
## Physics tab, changes gravity_multiplier through the same slider a player
## would drag (HSlider.emit_signal("value_changed", ...) -- see
## tests/unit/test_tuning_panel.gd's own comment on why that is the
## deterministic equivalent of a drag), drops a block, and shoots again so a
## human can confirm the new block visibly falls faster/slower.
##
## Run windowed (a real render is required for the screenshot):
##   godot --path . --scene res://tools/screenshot_mv018.tscn
##
## Lives in tools/ (CLAUDE.md: build-time/manual-QA scripts that are not part
## of the running game), alongside tools/screenshot_mv017.gd, which this
## follows the shape of.

const OUTPUT_DIR: String = "user://"
const SETTLE_FRAMES: int = 20
const NEW_GRAVITY_MULTIPLIER: float = 2.5


func _ready() -> void:
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame

	main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(int(3.5 * Engine.physics_ticks_per_second))

	var sandbox: Sandbox = main._sandbox
	var panel: TuningPanel = sandbox.get_node("TuningPanel") as TuningPanel
	await _wait(SETTLE_FRAMES)

	panel._unhandled_input(_key(KEY_F4))
	await _wait(SETTLE_FRAMES)
	print("SCREENSHOT panel_visible=%s controller_input_enabled=%s" % [
		panel.visible, sandbox.controller().input_enabled
	])
	# TabContainer defaults to whichever tab was last current; force Physics
	# (index 2 -- Camera, Controls, Physics, Territory, Feed) into view so the
	# screenshot actually shows the tab this smoke test is about.
	# ui/TuningPanel.gd's _build_ui() builds its whole layout in code rather
	# than authoring it in the .tscn, so there is no fixed NodePath to name
	# here -- search the subtree instead.
	var tab_container: TabContainer = _find_tab_container(panel)
	if tab_container != null:
		tab_container.current_tab = 2
	await _shoot("01_physics_tab_open")

	var gravity_slider: HSlider = panel.control_for(panel.physics_tuning, "gravity_multiplier") as HSlider
	var before_gravity: float = panel.physics_tuning.gravity_multiplier
	gravity_slider.emit_signal("value_changed", NEW_GRAVITY_MULTIPLIER)
	print("SCREENSHOT gravity_multiplier before=%.2f after=%.2f" % [before_gravity, panel.physics_tuning.gravity_multiplier])

	panel._unhandled_input(_key(KEY_F4))
	await _wait(SETTLE_FRAMES)
	print("SCREENSHOT panel_visible=%s controller_input_enabled=%s" % [
		panel.visible, sandbox.controller().input_enabled
	])

	var spot: Vector3 = Match.default_ghost_origin(0) + Vector3.UP * 3.0
	Match.request_place(0, spot, 0, Quaternion.IDENTITY, false)
	await _wait(SETTLE_FRAMES)
	await _shoot("02_block_dropped_with_new_gravity")

	get_tree().quit()


func _find_tab_container(node: Node) -> TabContainer:
	if node is TabContainer:
		return node as TabContainer
	for child: Node in node.get_children():
		var found: TabContainer = _find_tab_container(child)
		if found != null:
			return found
	return null


func _key(keycode: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	return event


func _shoot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = "%s%s.png" % [OUTPUT_DIR, name]
	image.save_png(path)
	print("SCREENSHOT %s saved=%s" % [name, ProjectSettings.globalize_path(path)])


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().physics_frame
