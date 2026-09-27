extends Node
## Deterministic visual-comparison capture for the graphics overhaul
## (Bontago-mp0.3 and children). Builds a populated two-player sandbox that
## roughly mirrors docs/art_mockups/08-cel-shaded-home-beacons.png (red towers
## by the left home beacon, blue by the right, one falling piece) and saves
## four 1280x720 frames: overview (mockup-08 framing), player (default
## gameplay camera), menu and lobby (mockups 10/11).
##
##   godot --path . --windowed --position 10000,10000 --resolution 1280x720 res://tools/capture_mockup08.tscn -- --out=feedback/overhaul/<tag>
##
## `--only=overview,player,menu,lobby` limits the frames. Output PNGs are
## <out>/<tag>-<frame>.png where <tag> is the last path segment of --out.
## Not part of the running game (CLAUDE.md: build-time scripts live in tools/).

const FRAME_SIZE: Vector2i = Vector2i(1280, 720)
const SETTLE_S: float = 2.0
const SHAPE_PATHS: Array[String] = [
	"res://config/blocks/L4.tres",
	"res://config/blocks/T4.tres",
	"res://config/blocks/S4.tres",
	"res://config/blocks/square4.tres",
	"res://config/blocks/bar3.tres",
	"res://config/blocks/pillar.tres",
]
const RED: Color = Color(0.93, 0.2, 0.17)
const BLUE: Color = Color(0.12, 0.42, 0.95)

var _out_dir: String = "res://feedback/overhaul/latest"
var _only: PackedStringArray = PackedStringArray()
# Bontago-mp0.3.6 (owner feedback: verify the sun glow/rays + lens flare +
# disc sheen read together like mockup 08, sun upper-right): swaps the
# overview frame's camera placement for one that faces
# config/sun_flare.tres's sun_direction instead of the red/blue home axis.
var _face_sun: bool = false


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var text: String = arg.lstrip("-")
		if text.begins_with("out="):
			_out_dir = text.substr(4)
		elif text.begins_with("only="):
			_only = text.substr(5).split(",")
		elif text == "face-sun":
			_face_sun = true
	if not _out_dir.begins_with("res://") and not _out_dir.contains(":"):
		_out_dir = "res://" + _out_dir
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	call_deferred("_capture")


func _wants(frame: String) -> bool:
	return _only.is_empty() or _only.has(frame)


func _save(frame: String) -> void:
	# The game's Settings autoload may restore a saved fullscreen/size, so
	# force the capture size right before each frame.
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

	if _wants("menu"):
		await _save("menu")
	if _wants("lobby"):
		Net.host_game(0, "Mira")
		await get_tree().create_timer(1.0).timeout
		await _save("lobby")

	if _wants("overview") or _wants("player"):
		var config: MatchConfig = main.get("match_config") as MatchConfig
		config.map_size = MapDef.MapSize.SMALL
		main.call("start_sandbox_from_menu")
		await get_tree().create_timer(SETTLE_S).timeout
		await _populate(main)
		await get_tree().create_timer(0.25).timeout
		if _wants("player"):
			await _save("player")
		if _wants("overview"):
			if _face_sun:
				_frame_face_sun(main)
			else:
				_frame_overview(main)
			await get_tree().create_timer(0.5).timeout
			await _save("overview")
	get_tree().quit()


## Red structures around slot 0's home, blue around slot 1's, plus one blue
## piece in mid-air (unfrozen) so falling-block VFX has something to show.
func _populate(main: Node) -> void:
	var field: Field = main.get("_field") as Field
	var container: Node3D = main.get_node("BlocksContainer") as Node3D
	var tuning: PhysicsTuning = load("res://config/physics_tuning.tres") as PhysicsTuning
	var factory: Script = load("res://game/BlockFactory.gd") as Script
	var red_home: Vector2 = _home(0)
	var blue_home: Vector2 = _home(1)
	for team: int in range(2):
		var home: Vector2 = red_home if team == 0 else blue_home
		var toward_center: Vector2 = -home.normalized()
		var side: Vector2 = Vector2(-toward_center.y, toward_center.x)
		var color: Color = RED if team == 0 else BLUE
		for tower: int in range(5):
			var along: float = 4.0 + float(tower) * 2.6
			var lateral: float = (float(tower % 3) - 1.0) * 3.2
			var base: Vector2 = home + toward_center * along + side * lateral
			var levels: int = 1 + (tower * 2 + team) % 4
			for level: int in range(levels):
				var shape: BlockShape = load(SHAPE_PATHS[(tower + level + team) % SHAPE_PATHS.size()]) as BlockShape
				var block: RigidBody3D = factory.call("build", shape, tuning, team, color) as RigidBody3D
				container.add_child(block)
				block.global_position = field.world_from_disk_local(base, 0.8 + float(level) * 1.6)
				block.rotation.y = float(tower) * 0.35
	await get_tree().create_timer(3.0).timeout
	var falling: RigidBody3D = factory.call(
		"build", load(SHAPE_PATHS[0]) as BlockShape, tuning, 1, BLUE) as RigidBody3D
	container.add_child(falling)
	falling.global_position = field.world_from_disk_local((red_home + blue_home) * 0.5 + (blue_home - red_home) * 0.12, 7.0)
	falling.rotation = Vector3(0.4, 0.2, 0.6)


## Elevated three-quarter view looking across the disc with red home on the
## left and blue on the right, like mockup 08.
func _frame_overview(main: Node) -> void:
	var field: Field = main.get("_field") as Field
	var red_home: Vector3 = field.world_from_disk_local(_home(0), 0.0)
	var blue_home: Vector3 = field.world_from_disk_local(_home(1), 0.0)
	var axis: Vector3 = (blue_home - red_home).normalized()
	var back: Vector3 = axis.cross(Vector3.UP).normalized()
	var radius: float = red_home.distance_to(blue_home) * 0.5
	var rig: Node = main.get_node("CameraRig")
	rig.set_process(false)
	var camera: Camera3D = rig.get_node("Camera3D") as Camera3D
	var focus: Vector3 = (red_home + blue_home) * 0.25
	if back.dot(focus) > 0.0:
		back = -back
	camera.global_position = focus + back * radius * 1.25 + Vector3.UP * radius * 0.8
	camera.look_at(focus + Vector3.DOWN * radius * 0.15)


## Elevated view rotated toward config/sun_flare.tres's sun_direction rather
## than the home axis, offset in yaw so the sun renders in the upper-right of
## frame (mockup 08 framing) instead of dead-center.
func _frame_face_sun(main: Node) -> void:
	var field: Field = main.get("_field") as Field
	var red_home: Vector3 = field.world_from_disk_local(_home(0), 0.0)
	var blue_home: Vector3 = field.world_from_disk_local(_home(1), 0.0)
	var focus: Vector3 = (red_home + blue_home) * 0.5
	var radius: float = red_home.distance_to(blue_home) * 0.5
	var sun_cfg: SunFlareConfig = load("res://config/sun_flare.tres") as SunFlareConfig
	var sun_dir: Vector3 = sun_cfg.sun_direction.normalized()
	var horizontal_sun: Vector3 = Vector3(sun_dir.x, 0.0, sun_dir.z).normalized()
	var look_dir: Vector3 = horizontal_sun.rotated(Vector3.UP, deg_to_rad(28.0))
	var rig: Node = main.get_node("CameraRig")
	rig.set_process(false)
	var camera: Camera3D = rig.get_node("Camera3D") as Camera3D
	camera.global_position = focus - look_dir * radius * 1.6 + Vector3.UP * radius * 0.55
	camera.look_at(focus + Vector3.UP * radius * 0.05)


func _home(slot_id: int) -> Vector2:
	var slot: PlayerSlot = Match.slot(slot_id)
	return slot.home_position
