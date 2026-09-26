extends Node
## Windowed smoke-shot for Bontago-xtq.35 (M7 P3 follow-up): verifies the
## sunset SkyThemeDef's fog (game/Skybox.gd, config/sky_themes/sunset.tres)
## reads crisp at the REAL follow-camera distance -- CameraTuning's shipped
## defaults (follow_distance=9.0m, follow_pitch_deg=-35.0deg -- game/
## CameraRig.gd's apply_follow_tuning()) -- not tools/screenshot_xtq28_
## sunset_fog.gd's far overview framing (field_radius * 1.4, tens of meters),
## where Bontago-xtq.28's own fix round found the disk still carried a pink
## haze.
##
## Boots the real Main.tscn/sandbox, same pattern as screenshot_xtq28_
## sunset_fog.gd, so this exercises the actual Skybox/CameraRig wiring rather
## than a hand-built substitute. Unlike that file, CameraTuning is never
## overridden here (no `free_tuning.follow_block = false`): follow_block
## stays true (config/camera_tuning.tres' own shipped default), so
## _point_camera() below drives the rig through the exact same
## apply_follow_tuning() path PlayerController's real per-frame follow does
## for a held block.
##
## Spawns a few real blocks (BlockFactory.build(), two owner colours, same
## idiom as tools/screenshot_xtq27_block_toon.gd) resting near the disk
## centre; the sandbox's own home/goal flags are already placed for free by
## _start_sandbox_match_with_args() -> Field.place_flags() (the "beacon if
## cheap" this brief asks for -- no separate beacon-spawn code needed).
##
## Fix round (same as xtq28's own history): an off-screen (--position
## 10000,10000) window is clamped by Windows to a tiny size, so capture goes
## through a fixed CAPTURE_SIZE SubViewport sharing the live World3D
## (own_world_3d stays false, the SubViewport default), not the real
## window's own clamped texture.
##
## Run windowed, off-screen (a real render is required):
##   godot --path . --position 10000,10000 tools/screenshot_xtq35_haze.tscn --quit-after 90
## Never --always-on-top/--maximized; quits right after saving.
##
## Lives in tools/ (CLAUDE.md: build-time/manual-QA scripts, not part of the
## running game).

const OUTPUT_DIR: String = "user://"
const OUTPUT_NAME: String = "m7p35_haze.png"
const SETTLE_FRAMES: int = 90
const CAPTURE_SIZE: Vector2i = Vector2i(1280, 720)

## Bontago-xtq.35: "a held block over the disk centre" -- the same Vector3(0,
## 1, 0) convention screenshot_xtq28_sunset_fog.gd already used for its own
## disk-centre `_target`, not an arbitrary height: a small clearance above
## whatever the ghost hovers over (config/GhostTuning.gd's spawn_clearance),
## enough to read clearly as "just above the disk" without wiring up a real
## GhostPreview/PlayerController for this probe.
const HELD_BLOCK_TARGET: Vector3 = Vector3(0.0, 1.0, 0.0)

## Three real spawned blocks (two owner colours -- players=2 below, colours
## cycle 0/1/0), resting almost on the field already (a tiny 0.02 m drop, the
## same SETTLED_DROP_HEIGHT idiom screenshot_xtq27_block_toon.gd uses, so they
## are visibly settled well within SETTLE_TICKS) at, and a little either side
## of, the disk centre -- close enough to the camera's HELD_BLOCK_TARGET to
## show whether nearby geometry reads crisp, per this brief's "blocks and
## beacons must read crisp at gameplay distance" requirement.
const BLOCK_OFFSETS: Array[Vector3] = [
	Vector3(-1.5, 0.02, 0.0),
	Vector3(1.5, 0.02, 0.5),
	Vector3(0.3, 0.02, -3.0),
]
const SETTLE_TICKS: int = 60


func _ready() -> void:
	Settings.set_graphics_preset(&"high")

	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	var rig: CameraRig = main.get_node("CameraRig") as CameraRig
	var skybox: Skybox = main.get_node("Skybox") as Skybox

	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame

	main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(int(1.5 * Engine.physics_ticks_per_second))

	_spawn_blocks(main)
	for _i: int in range(SETTLE_TICKS):
		await get_tree().physics_frame

	var fog_volume: FogVolume = skybox.get_fog_volume()
	print(
		(
			"SCREENSHOT xtq35 fallback_active=%s fog_volume_visible=%s volumetric_fog_enabled=%s "
			+ "follow_block=%s follow_distance=%s follow_pitch_deg=%s fog_density=%s "
			+ "volumetric_fog_density=%s"
		) % [
			skybox.fallback_active,
			fog_volume.visible if fog_volume != null else null,
			main.get_world_3d().environment.volumetric_fog_enabled,
			rig.tuning.follow_block,
			rig.tuning.follow_distance,
			rig.tuning.follow_pitch_deg,
			main.get_world_3d().environment.fog_density,
			main.get_world_3d().environment.volumetric_fog_density,
		]
	)

	_point_camera(rig)
	await _wait(SETTLE_FRAMES)
	await _shoot(OUTPUT_NAME)

	get_tree().quit()


## Places the camera exactly where CameraRig's own apply_follow_tuning()
## would for a block held at HELD_BLOCK_TARGET, using whatever CameraTuning
## this rig already carries -- config/camera_tuning.tres' shipped defaults,
## never overridden by this file (contrast screenshot_xtq28_sunset_fog.gd's
## `free_tuning.follow_block = false`).
func _point_camera(rig: CameraRig) -> void:
	rig._target = HELD_BLOCK_TARGET
	rig._yaw = 0.0
	rig.apply_follow_tuning()
	var cam3d: Camera3D = rig.get_camera()
	rig.reset_physics_interpolation()
	cam3d.reset_physics_interpolation()


func _spawn_blocks(main: Node) -> void:
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
		block.global_position = BLOCK_OFFSETS[i]


func _shoot(file_name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = await _render_large_shot()
	var path: String = OUTPUT_DIR + file_name
	image.save_png(path)
	print("SCREENSHOT xtq35 saved=%s size=%s" % [ProjectSettings.globalize_path(path), image.get_size()])


## Same SubViewport idiom as screenshot_xtq28_sunset_fog.gd's own
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
