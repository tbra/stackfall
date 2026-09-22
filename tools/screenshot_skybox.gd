extends Node3D
## Windowed smoke-shot of game/Skybox.gd with the Beach set loaded, after the
## numeric seam correction (tools/skybox_seam_probe.gd) replaced the original
## eyeballed guess. Deliberately does not go through game/Main.tscn/Sandbox
## (game/Field.tscn's root node type currently mismatches Field.gd's `extends
## AnimatableBody3D` -- a pre-existing base-repo defect unrelated to this
## package, see the report -- which throws before a sandbox match can start
## at all). Builds only what a skybox check needs: a WorldEnvironment with
## the same ProceduralSkyMaterial fallback Main.tscn uses, a Skybox instance,
## and a free Camera3D.
##
## Saves one screenshot looking straight at each of the four horizontal
## seams between adjacent side faces (yaw 45/135/225/315 -- halfway between
## the face-center yaws, i.e. looking straight at the join) plus one looking
## straight up at the top face's seams, so all 12 edges this package's seam
## probe scores are also visible by eye in the same run.
##
## Run it with:
##   godot --path . --scene res://tools/screenshot_skybox.tscn
## Saves user://skybox_seam_yaw{45,135,225,315}.png and user://skybox_seam_top.png.

const SKYBOX_SCENE: PackedScene = preload("res://game/Skybox.tscn")
const SEAM_YAWS_DEG: Array = [45.0, 135.0, 225.0, 315.0]

var _camera: Camera3D = null
var _skybox: Skybox = null


func _ready() -> void:
	var env_node: WorldEnvironment = WorldEnvironment.new()
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	var sky: Sky = Sky.new()
	sky.sky_material = sky_material
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env_node.environment = environment
	add_child(env_node)

	_skybox = SKYBOX_SCENE.instantiate() as Skybox
	add_child(_skybox)

	_camera = Camera3D.new()
	_camera.current = true
	add_child(_camera)

	await get_tree().process_frame

	var loaded: bool = _skybox.load_set("beach")
	print("SCREENSHOT skybox load_set('beach')=%s fallback_active=%s" % [loaded, _skybox.fallback_active])

	for yaw_deg: float in SEAM_YAWS_DEG:
		var yaw: float = deg_to_rad(yaw_deg)
		# A representative in-game height (config/camera_tuning.tres's follow
		# height is close to this), looking level at the horizon in that
		# direction so both faces either side of the seam fill the frame.
		_camera.global_position = Vector3(0.0, 15.0, 0.0)
		_camera.look_at(Vector3(sin(yaw), 15.0, cos(yaw)), Vector3.UP)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		var path: String = "user://skybox_seam_yaw%d.png" % int(yaw_deg)
		image.save_png(path)
		print("SCREENSHOT saved=%s (yaw=%d)" % [ProjectSettings.globalize_path(path), int(yaw_deg)])

	# Straight up, to also show the top face's four seams in one frame.
	_camera.global_position = Vector3.ZERO
	_camera.look_at(Vector3(0.05, 1.0, 0.0), Vector3.FORWARD)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var top_image: Image = get_viewport().get_texture().get_image()
	var top_path: String = "user://skybox_seam_top.png"
	top_image.save_png(top_path)
	print("SCREENSHOT saved=%s (top)" % ProjectSettings.globalize_path(top_path))

	get_tree().quit()
