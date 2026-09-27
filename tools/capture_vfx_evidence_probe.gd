extends Node
## Bontago-mp0.3.4 fix round (owner: "I need to SEE the new effects"): two
## close-up frames proving game/BlockEffectsManager.gd's landing
## cubelet+dust burst and falling trail actually render, since
## tools/capture_mockup08.gd's own timing (one falling piece dropped ~0.25s
## before its single "player" frame) is not reliable for catching either
## effect mid-flight. Not part of the running game (CLAUDE.md: build-time
## scripts live in tools/; kept in vfx/ as this package's own throwaway
## verification tool, matching vfx/capture_sun_flare_probe.gd).
##
##   godot --path . --windowed --position 10000,10000 --resolution 1280x720 res://tools/capture_vfx_evidence_probe.tscn -- --out=feedback/overhaul/<tag>

const FRAME_SIZE: Vector2i = Vector2i(1280, 720)
const SETTLE_S: float = 1.5

var _out_dir: String = "res://feedback/overhaul/latest"
var _impact_events: Array[Dictionary] = []


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var text: String = arg.lstrip("-")
		if text.begins_with("out="):
			_out_dir = text.substr(4)
	if not _out_dir.begins_with("res://") and not _out_dir.contains(":"):
		_out_dir = "res://" + _out_dir
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	call_deferred("_capture")


func _on_block_impacted_at(speed: float, position: Vector3) -> void:
	_impact_events.append({"speed": speed, "position": position})


func _save(main: Node, frame: String) -> void:
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = FRAME_SIZE
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var tag: String = _out_dir.get_file()
	var path: String = "%s/%s-%s.png" % [_out_dir, tag, frame]
	get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE saved=%s" % ProjectSettings.globalize_path(path))


func _capture() -> void:
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = FRAME_SIZE
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(SETTLE_S).timeout

	var config: MatchConfig = main.get("match_config") as MatchConfig
	config.map_size = MapDef.MapSize.SMALL
	main.call("start_sandbox_from_menu")
	await get_tree().create_timer(SETTLE_S).timeout

	Events.block_impacted_at.connect(_on_block_impacted_at)

	var field: Field = main.get("_field") as Field
	var container: Node3D = main.get_node("BlocksContainer") as Node3D
	var tuning: PhysicsTuning = load("res://config/physics_tuning.tres") as PhysicsTuning
	var factory: Script = load("res://game/BlockFactory.gd") as Script
	var shape: BlockShape = load("res://config/blocks/square4.tres") as BlockShape
	var rig: Node = main.get_node("CameraRig")
	rig.set_process(false)
	var camera: Camera3D = rig.get_node("Camera3D") as Camera3D

	var drop_point_local: Vector2 = Vector2(0.0, 0.0)

	# --- Trail frame: a block kicked to a strong downward speed, camera in
	# close, captured while it is still well above config.trail_speed_
	# threshold and above the disc.
	var trail_block: RigidBody3D = factory.call("build", shape, tuning, 1, Color(0.15, 0.45, 0.95)) as RigidBody3D
	container.add_child(trail_block)
	var trail_spawn: Vector3 = field.world_from_disk_local(drop_point_local, 14.0)
	trail_block.global_position = trail_spawn
	trail_block.linear_velocity = Vector3(0.0, -20.0, 0.0)
	camera.global_position = trail_spawn + Vector3(4.0, 0.5, 4.0)
	camera.look_at(trail_spawn, Vector3.UP)
	# Two physics ticks so BlockEffectsManager's own _update_falling_trails()
	# has both a seeded previous position and a real measured fall speed
	# (see that method's own doc) before the trail is expected to exist.
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	await _save(main, "trail")

	# --- Impact frame: a second block dropped from just above the disc so
	# it lands hard and fast, camera in close on the landing point, captured
	# ~0.1s after Events.block_impacted_at actually fires for it.
	var impact_block: RigidBody3D = factory.call("build", shape, tuning, 0, Color(0.93, 0.2, 0.17)) as RigidBody3D
	container.add_child(impact_block)
	var impact_spawn: Vector3 = field.world_from_disk_local(drop_point_local + Vector2(6.0, 0.0), 6.0)
	impact_block.global_position = impact_spawn
	impact_block.linear_velocity = Vector3(0.0, -14.0, 0.0)
	camera.global_position = impact_spawn + Vector3(3.0, -2.5, 3.0)
	camera.look_at(impact_spawn + Vector3.DOWN * 3.0, Vector3.UP)

	var waited_s: float = 0.0
	while _impact_events.is_empty() and waited_s < 3.0:
		await get_tree().create_timer(0.05).timeout
		waited_s += 0.05
	await get_tree().create_timer(0.1).timeout
	await _save(main, "impact")

	get_tree().quit()
