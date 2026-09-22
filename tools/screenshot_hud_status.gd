extends Node
## Windowed smoke-shot for Bontago-mv0.9 (HUD per-player status replaces the
## hot-seat "Player N's turn" banner): confirms the sandbox HUD shows the
## held/next block previews, the timer ring, and the LOCKED state without
## playing it by hand. Same shape and same pattern as
## tools/screenshot_sandbox.gd (Bontago-mv0.10/.11/.12's manual check); not
## part of the running game (CLAUDE.md). Run as:
##   godot --path . --scene res://tools/screenshot_hud_status.gd
##
## Builds a 2-player sandbox the way game/Main.gd's
## _start_sandbox_match_with_args() does, forces slot 0's held piece to an
## off-centre shape (bar3) so the preview icon isn't a plain square, enables
## the feed timer (F6's effect) and releases a block once to seed a next
## shape, then releases again immediately so the interval lock engages
## (Bontago-mv0.10's cadence) -- the same "early drop with F6 timer on" the
## assignment's manual gate describes -- before saving one screenshot that
## shows all three states (held+next previews, ring, LOCKED) at once.

const OUTPUT_PATH: String = "user://hud_status_smoke.png"
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
	var hud: HUD = main._sandbox.hud() as HUD

	# Off-centre shape (bar3), forced past the bag, so the held/next preview
	# icons are visibly non-square.
	Match._held_shapes[0] = _bar3
	var home: Vector2 = Match.slot(0).home_position
	var spot: Vector3 = field.world_from_disk_local(home, PLACE_HEIGHT)
	ghost.update_placement(spot, Vector3.UP)
	await _wait(SETTLE_FRAMES)
	print("SCREENSHOT before any release: turn_label=%s" % hud._turn_label.text)

	# Bontago-mv0.10: sandbox's own timer starts paused ("unlimited blocks",
	# no lock) -- turning it on is what makes the interval lock reachable at
	# all, same as the F6 hotkey a manual tester would press.
	Match.set_feed_timer_enabled(true)
	Match.request_place(0, spot, 0, Quaternion.IDENTITY, false)
	await _wait(SETTLE_FRAMES)
	print("SCREENSHOT after first release: locked=%s held=%s next=%s" % [
		Match.is_release_locked(0),
		"null" if Match.held_shape(0) == null else Match.held_shape(0).id,
		"null" if Match.next_shape(0) == null else Match.next_shape(0).id,
	])

	# Release again immediately: the interval has not elapsed, so this must
	# be refused and the slot's next piece stays locked -- the grey ring and
	# LOCKED label this screenshot is meant to show.
	Match.request_place(0, spot, 0, Quaternion.IDENTITY, false)
	ghost.update_placement(spot, Vector3.UP)
	await _wait(5)

	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(OUTPUT_PATH)
	print("SCREENSHOT saved=%s size=%dx%d locked=%s hud_locked=%s turn_label=%s" % [
		ProjectSettings.globalize_path(OUTPUT_PATH),
		image.get_width(), image.get_height(),
		Match.is_release_locked(0), hud._locked, hud._turn_label.text,
	])
	get_tree().quit()


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().physics_frame
