extends Node
## Windowed smoke-shot for Bontago-xtq.8 (owner feel report: "it reflects
## whatever light source you've put in but not the skybox we added
## recently"). Boots the real Main.tscn/sandbox (same pattern as
## tools/screenshot_xtq6_disk_thin.gd), loads the Beach set, then shoots the
## disk from a low, shallow angle at two camera yaws so the reflected/ambient
## horizon band on the disk surface is visible and comparable between the
## before (Sky still the ProceduralSkyMaterial gradient) and after (Sky
## carries shaders/cubemap_sky.gdshader) states.
##
## `--before`: unwires the Skybox node's `environment` reference right after
## boot, before the sandbox match's own load_set() call -- game/Skybox.gd's
## every sky-material write is a documented no-op without it, so the box
## still shows (unaffected) but the Environment's Sky is left exactly as
## Main.tscn declares it (ProceduralSkyMaterial), reproducing the pre-fix
## behaviour without editing any resource or reverting a checked-in change.
## Omitted, the tool leaves Main.tscn's own wiring in place, i.e. the
## post-fix behaviour.
##
## Run windowed (a real render is required for the screenshot):
##   godot --path . --scene res://tools/screenshot_xtq8_sky_reflection.tscn -- \
##       --before --out=sky-reflection-before.png
##   godot --path . --scene res://tools/screenshot_xtq8_sky_reflection.tscn -- \
##       --out=sky-reflection-after.png
##
## Lives in tools/ (CLAUDE.md: build-time/manual-QA scripts, not part of the
## running game).

const OUTPUT_DIR: String = "res://feedback/"
const DEFAULT_OUTPUT: String = "sky-reflection-after.png"
const SETTLE_FRAMES: int = 90

## Low and shallow: close to the disk's own surface, almost level. A mirror
## reflection off a +Y normal points a steeply-downward view back toward the
## zenith (mostly-uniform sky there in both the fallback gradient and every
## real set) and a near-horizontal view back toward the *horizon* (where the
## set's actual colour/cloud/mountain detail lives) -- pitch is kept only a
## few degrees off level so the reflection samples the horizon band, not the
## zenith, and the before/after difference is actually visible.
const CAMERA_DISTANCE: float = 30.0
const CAMERA_PITCH_DEG: float = -3.0
const YAW_A_DEG: float = 20.0
const YAW_B_DEG: float = 110.0

## `--mirror`: pushes the disk's own visuals toward the pre-Bontago-xtq.6
## mirror look purely for this evidence run (a duplicated TerritoryVisuals,
## same override-a-copy pattern tools/screenshot_xtq6_disk_thin.gd uses for
## MapDef/TerritoryVisuals -- config/territory_visuals.tres itself is never
## touched). TerritoryVisuals is not owned by this package; this is read-only
## QA verification of Bontago-xtq.8, not a design change. The shipped, mostly
## -matte disk (disk_metallic 0.2, disk_roughness 0.45) makes the reflected
## sky band subtle at any camera angle by design (that was the point of
## Bontago-xtq.6), which makes two similar skies hard to tell apart by eye in
## a screenshot -- this flag trades that realism for an unambiguous check
## that the Sky resource itself, not just the disk's general tone, changed.
const MIRROR_METALLIC: float = 0.9
const MIRROR_ROUGHNESS: float = 0.04

const BEFORE_ARG: String = "--before"
const MIRROR_ARG: String = "--mirror"
const OUT_ARG: String = "--out="


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var before: bool = args.has(BEFORE_ARG)
	var mirror: bool = args.has(MIRROR_ARG)
	var out_name: String = _string_arg(args, OUT_ARG, DEFAULT_OUTPUT)

	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	var field: Field = main.get_node("Field") as Field
	var rig: CameraRig = main.get_node("CameraRig") as CameraRig
	var skybox: Skybox = main.get_node("Skybox") as Skybox

	if before:
		# See the class doc: reproduces the pre-fix behaviour (box only, Sky
		# left untouched) without editing game/Skybox.gd or Main.tscn.
		skybox.environment = null

	if mirror:
		var visuals: TerritoryVisuals = (field.visuals as TerritoryVisuals).duplicate(true) as TerritoryVisuals
		visuals.disk_metallic = MIRROR_METALLIC
		visuals.disk_roughness = MIRROR_ROUGHNESS
		field.visuals = visuals

	var free_tuning: CameraTuning = (rig.tuning as CameraTuning).duplicate(true) as CameraTuning
	free_tuning.follow_block = false
	rig.tuning = free_tuning

	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame

	main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(int(1.5 * Engine.physics_ticks_per_second))

	print("SCREENSHOT xtq8 before=%s fallback_active=%s" % [before, skybox.fallback_active])

	_point_camera(rig, YAW_A_DEG)
	await _wait(SETTLE_FRAMES)
	await _shoot(out_name)

	# Second yaw for the seam/orientation comparison the brief asks for.
	_point_camera(rig, YAW_B_DEG)
	await _wait(SETTLE_FRAMES)
	await _shoot("%s-yaw2.png" % out_name.get_basename())

	get_tree().quit()


## Drives the rig's own free-orbit fields directly (see
## tools/screenshot_xtq6_disk_thin.gd's DECISION comments for why setting the
## Camera3D child's transform directly does not stick, and why
## reset_physics_interpolation() is required with physics interpolation on).
func _point_camera(rig: CameraRig, yaw_deg: float) -> void:
	rig._target = Vector3(0.0, 1.0, 0.0)
	rig._distance = CAMERA_DISTANCE
	rig._pitch = deg_to_rad(CAMERA_PITCH_DEG)
	rig._yaw = deg_to_rad(yaw_deg)
	rig._update_transform()
	var cam3d: Camera3D = rig.get_node("Camera3D") as Camera3D
	rig.reset_physics_interpolation()
	cam3d.reset_physics_interpolation()


func _shoot(file_name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = OUTPUT_DIR + file_name
	image.save_png(path)
	print("SCREENSHOT xtq8 saved=%s" % ProjectSettings.globalize_path(path))


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().physics_frame


func _string_arg(args: PackedStringArray, prefix: String, fallback: String) -> String:
	for arg: String in args:
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return fallback
