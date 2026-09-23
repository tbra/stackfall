extends Node
## Windowed smoke-shot for Bontago-xtq.11 (owner feel report: "I think the
## disc is a mirror-like surface and not glass, so it should be reflective
## but not transparent"). Boots the real Main.tscn/sandbox (same pattern as
## tools/screenshot_xtq8_sky_reflection.gd), then shoots the disk from a low,
## shallow angle so the sky reflection and a couple of placed blocks are
## visible, comparable between the before (dim near-diffuse: disk_metallic
## 0.2, disk_roughness 0.45 -- the pre-Bontago-xtq.11 "glass" material's
## metallic/roughness pair, opacity aside) and after (opaque mirror:
## config/territory_visuals.tres's shipped defaults) states. The disk itself
## is compile-time opaque either way now (shaders/territory.gdshader no
## longer writes ALPHA at all), so this tool can no longer reproduce the old
## translucent look -- only the metallic/roughness difference that made the
## "before" material read as a duller, less mirror-like disk.
##
## `--before`: pushes the disk's own visuals back to the pre-Bontago-xtq.11
## metallic/roughness values purely for this evidence run (a duplicated
## TerritoryVisuals, same override-a-copy pattern
## tools/screenshot_xtq8_sky_reflection.gd uses). TerritoryVisuals's shipped
## resource is never touched by this tool. Omitted, the tool leaves
## config/territory_visuals.tres's own shipped (post-fix) values in place.
##
## `--low`: an even shallower pitch than the default shot, so the sky
## reflection / DirectionalLight3D specular highlight band on the disc is
## unambiguous in the shot (Bontago-xtq.11 review: the default angle didn't
## show it clearly enough).
##
## Run windowed (a real render is required for the screenshot):
##   godot --path . --scene res://tools/screenshot_xtq11_disk_opaque.tscn -- \
##       --before --out=disk-before.png
##   godot --path . --scene res://tools/screenshot_xtq11_disk_opaque.tscn -- \
##       --out=disk-after.png
##   godot --path . --scene res://tools/screenshot_xtq11_disk_opaque.tscn -- \
##       --low --out=disk-after-low.png
##
## Lives in tools/ (CLAUDE.md: build-time/manual-QA scripts, not part of the
## running game).

const OUTPUT_DIR: String = "res://feedback/"
const DEFAULT_OUTPUT: String = "disk-after.png"
const SETTLE_FRAMES: int = 90

## Low and shallow, close to the disk's own surface: shows the reflected sky
## band and any blocks standing on the disk in the same shot.
const CAMERA_DISTANCE: float = 30.0
const CAMERA_PITCH_DEG: float = -8.0
## `--low`: shallower still, and yawed to the DirectionalLight3D's own
## azimuth (Main.tscn's rotation_degrees.y = -30, and the light's downward
## pitch leaves its source azimuth equal to that same yaw), so the camera
## looks straight down the axis a mirror's law of reflection needs to show
## the sun's own specular highlight, not just the general sky.
const LOW_CAMERA_PITCH_DEG: float = -15.0
const LOW_YAW_DEG: float = -30.0
const YAW_A_DEG: float = 20.0
const YAW_B_DEG: float = 110.0

## Bontago-xtq.4's original metallic/roughness defaults, before
## Bontago-xtq.11 retuned them (config/TerritoryVisuals.gd's DECISION
## comments carry the same numbers). The opacity half of the old "glass"
## material has no equivalent anymore: the shader is unconditionally opaque.
const BEFORE_METALLIC: float = 0.2
const BEFORE_ROUGHNESS: float = 0.45

const BEFORE_ARG: String = "--before"
const LOW_ARG: String = "--low"
const OUT_ARG: String = "--out="


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var before: bool = args.has(BEFORE_ARG)
	var low: bool = args.has(LOW_ARG)
	var out_name: String = _string_arg(args, OUT_ARG, DEFAULT_OUTPUT)

	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	var field: Field = main.get_node("Field") as Field
	var rig: CameraRig = main.get_node("CameraRig") as CameraRig

	if before:
		var visuals: TerritoryVisuals = (field.visuals as TerritoryVisuals).duplicate(true) as TerritoryVisuals
		visuals.disk_metallic = BEFORE_METALLIC
		visuals.disk_roughness = BEFORE_ROUGHNESS
		field.visuals = visuals

	var free_tuning: CameraTuning = (rig.tuning as CameraTuning).duplicate(true) as CameraTuning
	free_tuning.follow_block = false
	rig.tuning = free_tuning

	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame

	main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(int(1.5 * Engine.physics_ticks_per_second))

	print("SCREENSHOT xtq11 before=%s low=%s metallic=%s roughness=%s" % [
		before, low, field.visuals.disk_metallic, field.visuals.disk_roughness,
	])

	if low:
		_point_camera(rig, LOW_YAW_DEG, LOW_CAMERA_PITCH_DEG)
		await _wait(SETTLE_FRAMES)
		await _shoot(out_name)
		get_tree().quit()
		return

	_point_camera(rig, YAW_A_DEG, CAMERA_PITCH_DEG)
	await _wait(SETTLE_FRAMES)
	await _shoot(out_name)

	# Second yaw so a reviewer can check the rim/holes still read and there is
	# no z-fighting between the disk and the territory overlay from another
	# angle.
	_point_camera(rig, YAW_B_DEG, CAMERA_PITCH_DEG)
	await _wait(SETTLE_FRAMES)
	await _shoot("%s-yaw2.png" % out_name.get_basename())

	get_tree().quit()


## Drives the rig's own free-orbit fields directly (see
## tools/screenshot_xtq6_disk_thin.gd's DECISION comments for why setting the
## Camera3D child's transform directly does not stick, and why
## reset_physics_interpolation() is required with physics interpolation on).
func _point_camera(rig: CameraRig, yaw_deg: float, pitch_deg: float) -> void:
	rig._target = Vector3(0.0, 1.0, 0.0)
	rig._distance = CAMERA_DISTANCE
	rig._pitch = deg_to_rad(pitch_deg)
	rig._yaw = deg_to_rad(yaw_deg)
	rig._update_transform()
	var cam3d: Camera3D = rig.get_node("Camera3D") as Camera3D
	rig.reset_physics_interpolation()
	cam3d.reset_physics_interpolation()


func _shoot(file_name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var path: String = OUTPUT_DIR + file_name
	image.save_png(path)
	print("SCREENSHOT xtq11 saved=%s" % ProjectSettings.globalize_path(path))


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().physics_frame


func _string_arg(args: PackedStringArray, prefix: String, fallback: String) -> String:
	for arg: String in args:
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return fallback
