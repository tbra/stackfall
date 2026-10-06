extends Node
## Windowed smoke-shot of the held-throwable arc preview (Bontago-1pi.85.29; was M4 P2e). Run:
##   godot --path . --scene res://tools/screenshot_throw_arc.tscn
##
## Grants slot 0 a real held special directly through Match._gifts (the same
## direct-internal-poke pattern tools/screenshot_sandbox.gd already uses for
## Match._held_shapes), then drives PlayerController's throw-aim state
## machine directly (Input.action_press + a synthetic InputEventMouseMotion
## routed straight into _unhandled_input()/​_update_throw_aim()) rather than
## relying on OS input reaching this window -- this repo's own operating note
## is that synthetic OS keyboard/mouse injection does not reach the game
## window in this environment, and every existing throw-aim test already
## drives the same two calls directly instead of a real input event loop.

const OUTPUT_PATH: String = "user://throw_arc_smoke.png"
const SETTLE_FRAMES: int = 20


func _ready() -> void:
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame

	main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	# MatchAutoload.COUNTDOWN_SECONDS (3.0) must fully elapse before
	# MatchLifecycle._begin_playing() issues each slot's first block.
	await _wait(int(3.5 * Engine.physics_ticks_per_second))

	# Probe-only: a readable capture, with the menu overlay hidden (window stays off-screen).
	get_window().size = Vector2i(1280, 720)
	for child: Node in main.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
	var controller: PlayerController = main._sandbox.controller()
	var ghost: GhostPreview = main._sandbox.ghost()

	# Sandbox is free-for-all (no hot-seat turn_changed), so make this
	# explicit via the sandbox's own documented seam rather than relying on
	# whatever _active_slot happened to default to.
	controller.set_sandbox_slot(0)

	# docs/M4_P2_PACKAGES.md decision 1 reversed: the per-slot queue holds a
	# drawn special id -- append one directly so held_special(0) reports a
	# throwable piece without waiting on a real gift crate spawn/claim cycle.
	# _ensure_capacity() is the same lazy-grow MatchGifts.gd's own claim path
	# calls before ever indexing _pending_queues by slot.
	# Bontago-1pi.85.29: no LT/drag any more; a held Bomb shows its camera-based arc on its own.
	Match._gifts._ensure_capacity(0)
	Match._gifts._held_specials[0] = &"bomb"
	Match._feed._held_is_gift[0] = true
	ghost.set_held_gift(&"bomb")
	controller._update_throw_aim(1.0 / 60.0)
	await _wait(SETTLE_FRAMES * 3)

	print("SCREENSHOT mode=%s arc_visible=%s" % [
		controller._held_gift_mode(),
		controller._arc_preview.visible if controller._arc_preview != null else "null(no arc wired)",
	])

	var pts: PackedVector3Array = controller._arc_preview.current_points()
	print("SCREENSHOT ghost=%s ghost_visible=%s points=%d first=%s last=%s cam=%s" % [ghost.global_position, ghost.visible, pts.size(), pts[0] if pts.size() > 0 else "-", pts[pts.size() - 1] if pts.size() > 0 else "-", get_viewport().get_camera_3d().global_position])
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(OUTPUT_PATH)
	print("SCREENSHOT saved=%s size=%dx%d" % [
		ProjectSettings.globalize_path(OUTPUT_PATH), image.get_width(), image.get_height()
	])
	get_tree().quit()


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().physics_frame
