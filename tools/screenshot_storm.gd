extends Node
## Bontago-22y.4: wind presentation capture. Boots the real Main.tscn sandbox,
## builds a tall tower, starts a wind event through the real weather schedule
## and shoots the streaks from a wide and a low view. Off-screen only:
##   godot --path . --windowed --position 10000,10000 tools/screenshot_storm.tscn --quit-after 2000
const OUTPUT_DIR: String = "user://"
const CAPTURE_SIZE: Vector2i = Vector2i(1280, 720)
const TOWER_CUBES: int = 12
const RAMP_WAIT_FRAMES: int = 330
var _main: Node = null
var _view: Transform3D = Transform3D.IDENTITY


func _ready() -> void:
	Settings.set_graphics_preset(&"high")
	_main = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(90)
	var field: Field = _main.get_node("Field") as Field
	var shape: BlockShape = load("res://config/blocks/cube.tres") as BlockShape
	for i: int in range(TOWER_CUBES):
		var block: Block = BlockFactory.build(shape, Match._physics_tuning, 0, Match.slot(0).color)
		Match.blocks_parent().add_child(block)
		block.global_position = field.world_from_disk_local(Vector2(-6.0, 0.0), 0.5 + 0.98 * float(i))
		Events.block_placed.emit(block, shape.id)
	if OS.get_cmdline_user_args().has("nomotes"):
		(load("res://config/weather/storm.tres") as StormTuning).mote_count = 0
	print("WIND started=%s" % Match.weather().start_event(&"storm"))
	await _wait(RAMP_WAIT_FRAMES)
	print("WIND active=%s intensity=%.2f" % [Match.weather().active_id(), Match.weather().active_intensity()])
	_aim(Vector3.ZERO, 62.0, -40.0, 0.0)
	await _wait(10)
	await _shoot("wind_r2_1_wide.png")
	_aim(Vector3(-6.0, 6.0, 0.0), 24.0, -12.0, 0.9)
	await _wait(10)
	await _shoot("wind_r2_2_tower.png")
	Match.weather().end_event()
	get_tree().quit()


## The capture uses its own camera (the gameplay rig keeps following the local
## ghost), placed `distance` from `target`, elevated by -pitch_deg, around `yaw`.
func _aim(target: Vector3, distance: float, pitch_deg: float, yaw: float) -> void:
	var elevation: float = deg_to_rad(-pitch_deg)
	var offset: Vector3 = Vector3(sin(yaw) * cos(elevation), sin(elevation), cos(yaw) * cos(elevation)) * distance
	_view = Transform3D(Basis.IDENTITY, target + offset).looking_at(target, Vector3.UP)


func _shoot(file_name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = await _render_large_shot()
	var path: String = OUTPUT_DIR + file_name
	ContactSheet.save_capture(image, path)
	print("SCREENSHOT arena saved=%s size=%s" % [ProjectSettings.globalize_path(path), image.get_size()])


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
	camera.global_transform = _view
	camera.current = true
	for _i: int in range(3):
		await RenderingServer.frame_post_draw
	var image: Image = sub.get_texture().get_image()
	sub.queue_free()
	return image


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().physics_frame
