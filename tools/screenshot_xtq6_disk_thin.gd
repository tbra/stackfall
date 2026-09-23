extends Node
## Windowed smoke-shot for Bontago-xtq.6 (owner feel report,
## docs/solid-blocks2-issue.png: "the glass disk is quite thick and since it's
## glass it kinda looks like the blocks are hovering + the bottom reflects
## what's on top. Also it reflects whatever light source you've put in").
##
## Follows tools/screenshot_xtq3_solid_blocks.gd's pattern: boots the real
## Main.tscn, starts a sandbox match and places a small stack of blocks at a
## player's home, then shoots a low, close-to-the-rim angle that shows both
## the disk's edge profile (thickness) and the blocks resting on its surface
## (mirroring/reflection).
##
## Command-line overrides let one script produce both the "before" and
## "after" evidence shots without touching the checked-in MapDef/
## TerritoryVisuals resources or the git worktree at all (docs/AGENT_WORKFLOW.md,
## no stash/checkout churn needed): a duplicated MapDef/TerritoryVisuals is
## assigned to the Field node *before* it enters the tree (so its own _ready()
## builds from the overridden values), the checked-in .tres resources
## themselves are never touched.
##
## Run windowed (a real render is required for the screenshot):
##   godot --path . --scene res://tools/screenshot_xtq6_disk_thin.tscn -- \
##       --disk-height=1.0 --disk-metallic=0.6 --disk-roughness=0.1 \
##       --out=disk-thin-before.png
##   godot --path . --scene res://tools/screenshot_xtq6_disk_thin.tscn -- \
##       --out=disk-thin-after.png
##
## Omitted overrides keep whatever field.map_def/field.visuals already
## specify (the checked-in, post-fix defaults), so the second call above
## shoots the "after" picture straight from config/maps/*.tres and
## config/territory_visuals.tres.
##
## Lives in tools/ (CLAUDE.md: build-time/manual-QA scripts, not part of the
## running game).

const OUTPUT_DIR: String = "res://docs/"
const DEFAULT_OUTPUT: String = "disk-thin-after.png"
const SETTLE_FRAMES: int = 90
const SHAPE_IDS: Array[String] = ["cube", "cube", "bar4"]
const STACK_LIFT: float = 3.0

## Free-orbit camera framing (game/CameraRig.gd's _target/_distance/_pitch/
## _yaw): close enough that the tower fills a third of the frame, shallow
## enough that a wide band of open disk surface separates the camera from it
## -- the same "lots of glass between camera and blocks" framing the owner's
## report screenshot shows.
const CAMERA_DISTANCE: float = 14.0
const CAMERA_PITCH_DEG: float = -18.0
const CAMERA_YAW_DEG: float = 0.0

## --rim-view: a second framing, almost level with the disk surface and just
## outside its physical edge, so the slab's vertical wall (MapDef.disk_height)
## reads directly in cross-section against the sky rather than being implied
## by shading. RIM_YAW_DEG = 90 rotates CameraRig's offset formula (see
## game/CameraRig.gd's _update_transform()) from its default +z axis onto +x,
## the same axis home_flag_position() puts a player's home (and so the
## nearest rim point) on.
const RIM_TARGET_RADIUS_FRACTION: float = 0.978
const RIM_CAMERA_DISTANCE: float = 6.0
const RIM_CAMERA_PITCH_DEG: float = -4.0
const RIM_YAW_DEG: float = 90.0

const DISK_HEIGHT_ARG: String = "--disk-height="
const DISK_METALLIC_ARG: String = "--disk-metallic="
const DISK_ROUGHNESS_ARG: String = "--disk-roughness="
const OUT_ARG: String = "--out="
const RIM_VIEW_ARG: String = "--rim-view"


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var disk_height: float = _float_arg(args, DISK_HEIGHT_ARG, -1.0)
	var disk_metallic: float = _float_arg(args, DISK_METALLIC_ARG, -1.0)
	var disk_roughness: float = _float_arg(args, DISK_ROUGHNESS_ARG, -1.0)
	var out_name: String = _string_arg(args, OUT_ARG, DEFAULT_OUTPUT)
	var rim_view: bool = args.has(RIM_VIEW_ARG)

	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	var field: Field = main.get_node("Field") as Field
	var rig: CameraRig = main.get_node("CameraRig") as CameraRig

	# CameraRig.follow_block (default true, Bontago-mv0.14) re-centres the
	# camera on the held/last-placed block every _process() frame -- setting
	# camera.global_position directly for this shot would just be overwritten
	# a frame later. Free-orbit mode leaves _target/_distance/_pitch/_yaw
	# alone once nothing is panning them, so this QA tool can point the rig
	# itself instead of fighting it.
	var free_tuning: CameraTuning = (rig.tuning as CameraTuning).duplicate(true) as CameraTuning
	free_tuning.follow_block = false
	rig.tuning = free_tuning

	if disk_height >= 0.0:
		var map_def: MapDef = (field.map_def as MapDef).duplicate(true) as MapDef
		map_def.disk_height = disk_height
		field.map_def = map_def

	if disk_metallic >= 0.0 or disk_roughness >= 0.0:
		var visuals: TerritoryVisuals = (field.visuals as TerritoryVisuals).duplicate(true) as TerritoryVisuals
		if disk_metallic >= 0.0:
			visuals.disk_metallic = disk_metallic
		if disk_roughness >= 0.0:
			visuals.disk_roughness = disk_roughness
		field.visuals = visuals

	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame

	main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(int(3.5 * Engine.physics_ticks_per_second))

	var home: Vector3 = Match.default_ghost_origin(0)
	var index: int = 0
	for shape_id: String in SHAPE_IDS:
		var shape: BlockShape = load("res://config/blocks/%s.tres" % shape_id)
		Match._held_shapes[0] = shape
		var offset: Vector3 = Vector3(0.0, STACK_LIFT + float(index) * 1.2, 0.0)
		var reason: StringName = Match.request_place(0, home + offset, 0, Quaternion.IDENTITY, false)
		if reason != &"":
			# QA tool only: the very first request right after boot can land
			# while the feed's own release lock hasn't cleared yet -- one
			# retry a few frames later is enough headroom (same as xtq3).
			await _wait(30)
			Match._held_shapes[0] = shape
			reason = Match.request_place(0, home + offset, 0, Quaternion.IDENTITY, false)
		print("SCREENSHOT xtq6 place shape=%s offset=%s reason=%s" % [shape_id, offset, reason])
		await _wait(SETTLE_FRAMES)
		index += 1

	await _wait(SETTLE_FRAMES)

	# Low and close, a shallow grazing angle across a wide stretch of open
	# disk surface toward the block stack -- the same framing as the owner's
	# report screenshot (docs/solid-blocks2-issue.png): most of the frame is
	# open glass disk between the camera and the tower, so a mirror-strength
	# reflection of the sky/blocks on that surface (or the block looking like
	# it hovers over a too-thick slab) reads clearly.
	##
	## DECISION (tools/screenshot_xtq6_disk_thin.gd): drives the rig's own
	## underscore-prefixed orbit fields (_target/_distance/_pitch/_yaw)
	## directly rather than adding a public setter to game/CameraRig.gd --
	## that file is not owned by this package (Bontago-xtq.6's brief), and a
	## one-shot QA tool reaching into a sibling's private state for a single
	## deterministic screenshot, then calling its own _update_transform() to
	## apply it immediately, costs less than growing that class's public API
	## for a caller that will never exist anywhere else.
	if rim_view:
		var field_radius: float = field.map_def.field_radius
		rig._target = Vector3(field_radius * RIM_TARGET_RADIUS_FRACTION, 0.05, 0.0)
		rig._distance = RIM_CAMERA_DISTANCE
		rig._pitch = deg_to_rad(RIM_CAMERA_PITCH_DEG)
		rig._yaw = deg_to_rad(RIM_YAW_DEG)
	else:
		rig._target = home + Vector3.UP * 1.5
		rig._distance = CAMERA_DISTANCE
		rig._pitch = deg_to_rad(CAMERA_PITCH_DEG)
		rig._yaw = deg_to_rad(CAMERA_YAW_DEG)
	rig._update_transform()
	var cam3d: Camera3D = rig.get_node("Camera3D") as Camera3D
	# DECISION (tools/screenshot_xtq6_disk_thin.gd): the project runs with
	# physics/common/physics_interpolation on (CLAUDE.md); a plain Node3D's
	# rendered transform is smoothed between the last two *physics* ticks, so
	# a transform written during an idle/process callback (this whole method)
	# is invisible to the renderer until a physics tick commits it -- without
	# this, the screenshot kept showing the pre-override framing even though
	# rig._target/_distance and cam3d.global_position (read straight back)
	# already reported the new values (reproduced while building this tool:
	# distance 16 -> 3 produced pixel-identical output until this was added).
	# reset_physics_interpolation() (Node3D) discards the interpolation
	# history so the very next rendered frame uses the new transform exactly,
	# no physics tick required.
	rig.reset_physics_interpolation()
	cam3d.reset_physics_interpolation()

	await get_tree().process_frame
	print("SCREENSHOT xtq6 disk_height=%s metallic=%s roughness=%s home=%s" % [
		field.map_def.disk_height, field.visuals.disk_metallic, field.visuals.disk_roughness, home
	])
	print("SCREENSHOT xtq6 debug rig_target=%s rig_dist=%s rig_pitch=%s rig_yaw=%s cam_global=%s field_radius=%s" % [
		rig._target, rig._distance, rig._pitch, rig._yaw, cam3d.global_position, field.map_def.field_radius
	])
	await _shoot(out_name)

	get_tree().quit()


func _shoot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = OUTPUT_DIR + file_name
	image.save_png(path)
	print("SCREENSHOT xtq6 saved=%s" % ProjectSettings.globalize_path(path))


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().physics_frame


func _float_arg(args: PackedStringArray, prefix: String, fallback: float) -> float:
	for arg: String in args:
		if arg.begins_with(prefix):
			return arg.substr(prefix.length()).to_float()
	return fallback


func _string_arg(args: PackedStringArray, prefix: String, fallback: String) -> String:
	for arg: String in args:
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return fallback
