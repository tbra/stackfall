extends Node
## Windowed smoke-shot for Bontago-xtq.41 (owner playtest: "the beacons are
## way too small"): verifies the resized BeaconVisualTuning (config/
## beacon_visual_tuning.tres -- socket/ring/crystal scaled 2.5x, see that
## file's own DECISION comment) reads clearly like docs/M7_ART_DIRECTION.md's
## mockup (docs/art_mockups/08-cel-shaded-home-beacons.png) at the real
## follow-camera distance -- CameraTuning's shipped defaults (follow_distance
## 9.0m, follow_pitch_deg -35.0deg), the same gameplay-distance framing idea
## as tools/screenshot_xtq35_haze.gd, applied to a HomeFlag's beacon instead
## of a held block.
##
## Boots the real Main.tscn/sandbox (same pattern as screenshot_xtq35_haze.gd
## so this exercises the real Field.place_flags() beacon, not a hand-built
## substitute), spawns a couple of settled blocks near one home flag so the
## screenshot shows the beacon next to a familiar 1m reference object, then
## points the camera at that flag the same way screenshot_xtq35_haze.gd
## points it at a held block.
##
## Fix round (same as xtq28/xtq35's own history): an off-screen (--position
## 10000,10000) window is clamped by Windows to a tiny size, so capture goes
## through a fixed CAPTURE_SIZE SubViewport sharing the live World3D
## (own_world_3d stays false, the SubViewport default), not the real
## window's own clamped texture.
##
## Run windowed, off-screen (a real render is required):
##   godot --path . --position 10000,10000 tools/screenshot_xtq41_beacons.tscn --quit-after 90
## Never --always-on-top/--maximized; quits right after saving.
##
## Lives in tools/ (CLAUDE.md: build-time/manual-QA scripts, not part of the
## running game).

const OUTPUT_DIR: String = "user://"
const OUTPUT_NAME: String = "m7p41_beacons.png"
const SETTLE_FRAMES: int = 90
const CAPTURE_SIZE: Vector2i = Vector2i(1280, 720)

## Framing target's height above the flag's own base: roughly the beacon's
## mid-height at HomeFlag scale (socket_height 0.625 + crystal_height 1.875,
## config/beacon_visual_tuning.tres), so the camera centers the whole beacon
## rather than only its base.
const TARGET_HEIGHT_M: float = 1.2

## Two settled blocks (one per owner color, players=2 below) resting beside
## the home flag -- a familiar 1m-cell reference object next to the beacon,
## the same "known-size neighbor" idea screenshot_xtq35_haze.gd uses for
## haze legibility, applied here to beacon scale legibility instead. Offsets
## are relative to the flag's own position, not the disk center.
##
## DECISION (Bontago-xtq.41 fix round): slot 0's home flag sits at pure world
## +x (MapDef.home_flag_position/spec 2.2), and CameraRig's rig node carries a
## baked 90deg yaw (game/Main.tscn), so at _yaw = 0.0 the follow camera's
## screen-horizontal axis maps to world Z, not world X -- an offset that
## varies mostly in X (as the first attempt at this file did) moves a block
## mostly toward/away from the camera (depth) instead of left/right on
## screen, so both blocks land near the same screen column and appear to
## stack into one tower instead of standing clearly apart. These offsets vary
## mostly in Z (screen-horizontal) and stay outside the beacon's own
## footprint (ring_outer_radius 1.375m) so neither block overlaps the ring.
const BLOCK_OFFSETS: Array[Vector3] = [
	Vector3(0.0, 0.02, -2.2),
	Vector3(0.3, 0.02, 2.0),
]
const SETTLE_TICKS: int = 60


func _ready() -> void:
	Settings.set_graphics_preset(&"high")

	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	var rig: CameraRig = main.get_node("CameraRig") as CameraRig

	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame

	main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(int(1.5 * Engine.physics_ticks_per_second))

	var field: Field = main.get_node("Field") as Field
	var flag: HomeFlag = field.home_flags()[0]

	_spawn_blocks(main, flag.global_position)
	for _i: int in range(SETTLE_TICKS):
		await get_tree().physics_frame

	var beacon_visuals: BeaconVisualTuning = preload("res://config/beacon_visual_tuning.tres")
	print(
		(
			"SCREENSHOT xtq41 socket_radius=%s ring_outer_radius=%s crystal_radius=%s "
			+ "crystal_height=%s follow_distance=%s follow_pitch_deg=%s"
		) % [
			beacon_visuals.socket_radius,
			beacon_visuals.ring_outer_radius,
			beacon_visuals.crystal_radius,
			beacon_visuals.crystal_height,
			rig.tuning.follow_distance,
			rig.tuning.follow_pitch_deg,
		]
	)

	_point_camera(rig, flag.global_position)
	await _wait(SETTLE_FRAMES)
	await _shoot(OUTPUT_NAME)

	get_tree().quit()


## Places the camera exactly where CameraRig's own apply_follow_tuning()
## would for a target centered on the flag, using whatever CameraTuning this
## rig already carries -- config/camera_tuning.tres' shipped defaults, never
## overridden by this file (contrast screenshot_xtq28_sunset_fog.gd's
## `free_tuning.follow_block = false`).
func _point_camera(rig: CameraRig, flag_position: Vector3) -> void:
	rig._target = flag_position + Vector3(0.0, TARGET_HEIGHT_M, 0.0)
	rig._yaw = 0.0
	rig.apply_follow_tuning()
	var cam3d: Camera3D = rig.get_camera()
	rig.reset_physics_interpolation()
	cam3d.reset_physics_interpolation()


func _spawn_blocks(main: Node, flag_position: Vector3) -> void:
	var tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
	var shapes: Array[BlockShape] = BlockShape.load_all_shapes()
	var colors: PackedColorArray = MatchConfig.default_player_colors()
	var blocks_container: Node3D = main.get_node("BlocksContainer") as Node3D
	for i: int in range(BLOCK_OFFSETS.size()):
		var shape: BlockShape = shapes[i % shapes.size()]
		var owner_slot: int = i % 2
		var color: Color = colors[owner_slot]
		var block: Block = BlockFactory.build(shape, tuning, owner_slot, color)
		blocks_container.add_child(block)
		block.global_position = flag_position + BLOCK_OFFSETS[i]


func _shoot(file_name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = await _render_large_shot()
	var path: String = OUTPUT_DIR + file_name
	image.save_png(path)
	print("SCREENSHOT xtq41 saved=%s size=%s" % [ProjectSettings.globalize_path(path), image.get_size()])


## Same SubViewport idiom as screenshot_xtq35_haze.gd's own
## _render_large_shot(): a fresh Camera3D matching the real rig camera's
## transform/fov/near/far/environment, sharing the live World3D via
## `sub.world_3d` (own_world_3d stays false), so the capture is CAPTURE_SIZE
## regardless of the actual (OS-clamped) window size.
func _render_large_shot() -> Image:
	var source: Camera3D = get_viewport().get_camera_3d()
	var sub: SubViewport = SubViewport.new()
	sub.size = CAPTURE_SIZE
	sub.world_3d = get_viewport().world_3d
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var camera: Camera3D = Camera3D.new()
	camera.fov = source.fov
	camera.near = source.near
	camera.far = source.far
	camera.environment = source.environment
	sub.add_child(camera)
	add_child(sub)
	camera.global_transform = source.global_transform
	camera.current = true
	for _i: int in range(3):
		await RenderingServer.frame_post_draw
	var image: Image = sub.get_texture().get_image()
	sub.queue_free()
	return image


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().physics_frame
