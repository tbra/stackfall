extends Node
## Windowed smoke-shot for M7 P5 (docs/M7_PLAN.md "P5 -- HUD minimap +
## reskin", Bontago-xtq.30): confirms the in-match HUD shows the reskinned
## cream/coral status/shares panels together with a populated live minimap
## (bottom-right) without playing it by hand. Same shape as
## tools/screenshot_hud_status.gd; not part of the running game (CLAUDE.md).
## Run windowed and off-screen only:
##   godot --path . --scene res://tools/screenshot_m7p5_hud_minimap.tscn --position 10000,10000

const OUTPUT_PATH: String = "user://m7p5_hud_minimap_smoke.png"
const SETTLE_FRAMES: int = 45


func _ready() -> void:
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame

	main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(int(3.5 * Engine.physics_ticks_per_second))

	var hud: HUD = main._sandbox.hud() as HUD
	print("SCREENSHOT minimap active=%s" % hud._minimap.is_active())

	await _wait(SETTLE_FRAMES)
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(OUTPUT_PATH)
	print("SCREENSHOT saved=%s size=%dx%d minimap_active=%s" % [
		ProjectSettings.globalize_path(OUTPUT_PATH),
		image.get_width(), image.get_height(),
		hud._minimap.is_active(),
	])
	get_tree().quit()


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().physics_frame
