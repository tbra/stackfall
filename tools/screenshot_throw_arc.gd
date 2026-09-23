extends Node
## Windowed smoke-shot of M4 P2e's throw-arc preview + ghost throw hint
## (docs/M4_P2_PACKAGES.md P2e). Run:
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
	Match._gifts._ensure_capacity(0)
	Match._gifts._pending_queues[0].append(&"rocket")

	Input.action_press(&"throw_aim")
	controller._update_throw_aim(1.0 / 60.0)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(400.0, 150.0)
	controller._unhandled_input(motion)
	controller._update_throw_aim(1.0 / 60.0)
	await _wait(SETTLE_FRAMES)

	print("SCREENSHOT aiming=%s ghost_state=%s arc_visible=%s" % [
		controller.is_aiming_throw(),
		ghost.current_state(),
		controller._arc_preview.visible if controller._arc_preview != null else "null(no arc wired)",
	])

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
