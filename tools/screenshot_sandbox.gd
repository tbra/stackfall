extends Node
## Windowed smoke-shot of the sandbox route (Bontago-mv0.10/.11/.12 manual
## check), for eyeballing owner-coloured blocks, the centred ghost on an
## off-centre shape, and the interval-lock tint without playing it by hand.
## Run it as an autoload-style extra scene alongside the game:
##   godot --path . --scene res://tools/screenshot_sandbox.gd
## It builds a 2-player sandbox the same way game/Main.gd's
## _start_sandbox_match_with_args() does, forces the held shape to an
## off-centre one (bar3) so the centred pivot is visible, places one block,
## enables the feed timer so the interval lock is reachable, releases a
## second block early to show the locked/grey ghost, saves
## user://sandbox_smoke.png and quits.
##
## Lives in tools/ because it is not part of the running game (CLAUDE.md),
## same shape as tools/screenshot_main.gd.

const OUTPUT_PATH: String = "user://sandbox_smoke.png"
const SETTLE_FRAMES: int = 30
const PLACE_HEIGHT: float = 0.55

var _bar3: BlockShape = preload("res://config/blocks/bar3.tres")


func _ready() -> void:
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame

	main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(int(3.5 * Engine.physics_ticks_per_second))

	var field: Field = main._field as Field
	var ghost: GhostPreview = main._sandbox.ghost() as GhostPreview

	# First block: an off-centre shape (bar3), forced past the bag so the
	# screenshot shows the centred-pivot fix (Bontago-mv0.12) regardless of
	# what the bag would have dealt.
	Match._held_shapes[0] = _bar3
	var home: Vector2 = Match.slot(0).home_position
	var spot: Vector3 = field.world_from_disk_local(home, PLACE_HEIGHT)
	ghost.update_placement(spot, Vector3.UP)
	await _wait(SETTLE_FRAMES)

	# Bontago-mv0.10: sandbox's own timer starts paused ("unlimited blocks",
	# no lock -- autoload/Match.gd's _consume_and_refeed DECISION). Turning it
	# on is what makes the interval lock reachable at all, same as the F6
	# hotkey a manual tester would press.
	Match.set_feed_timer_enabled(true)
	Match.request_place(0, spot, 0, Quaternion.IDENTITY, false)
	await _wait(SETTLE_FRAMES)
	print("SCREENSHOT after first release: locked=%s held=%s" % [
		Match.is_release_locked(0), "null" if Match.held_shape(0) == null else Match.held_shape(0).id
	])

	# Release again immediately: the interval has not elapsed, so this must
	# be refused and the slot's next piece stays locked -- the grey ghost
	# tint the screenshot is meant to show.
	Match.request_place(0, spot, 0, Quaternion.IDENTITY, false)
	ghost.update_placement(spot, Vector3.UP)
	await _wait(5)

	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(OUTPUT_PATH)
	print("SCREENSHOT saved=%s size=%dx%d locked=%s ghost_state=%s blocks_spawned=%d" % [
		ProjectSettings.globalize_path(OUTPUT_PATH),
		image.get_width(), image.get_height(),
		Match.is_release_locked(0), ghost.current_state(), Match.blocks_spawned()
	])
	get_tree().quit()


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().physics_frame
