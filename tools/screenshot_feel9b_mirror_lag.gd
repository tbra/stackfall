extends Node
## Windowed evidence probe for Bontago-xtq.21 (owner 2026-09-24: "there's a
## clear delay between the reflection and the ghost block while moving ...
## they don't align at all").
##
## Boots the owner's own path (tools/screenshot_feel8b_disc_glare.gd's exact
## technique): Main.tscn with the real `--headless-host --bots=<n>
## --players=<n>` command line, a placed cube stack at slot 0's home flag, a
## free-orbit camera (CameraTuning.follow_block forced false, same DECISION
## feel8b's own _ready() makes) driven by directly mutating CameraRig._yaw
## every frame and letting the REAL engine dispatch CameraRig._process() and
## DiscMirror._process() in their own process_priority order (no manual
## _update_transform()/_process() calls of our own -- feel8b's own _orbit()
## with `frozen == false` already proves this dispatch is reliable in this
## exact boot path) -- this exercises the real Bontago-xtq.21 ordering bug
## end to end, not just the synthetic mover tests/unit/test_disc_mirror.gd
## drives directly.
##
## Every orbit frame prints the numeric gap between the mirror camera's
## CORRECT this-frame transform (DiscMirror.mirror_transform() applied to
## THIS frame's real camera pose) and whatever transform game/DiscMirror.gd
## actually left on its own live MirrorCamera (origin_error -- 0 once the fix
## keeps the two in lockstep, a fixed per-frame amount that never closes
## before it).
##
## The final frame (captured mid-orbit, yaw still advancing) additionally
## marks the saved screenshot at (a) where the placed block's reflection
## ACTUALLY shows given whatever transform game/DiscMirror.gd's own _process()
## really left on the live MirrorCamera this frame (red) and (b) where it
## SHOULD show given the mathematically correct, this-frame mirror camera
## pose (blue -- DiscMirror.mirror_transform() applied fresh) -- both back-
## computed the same way shaders/territory.gdshader samples MirrorViewport
## (unproject the block's real world position through the candidate mirror
## pose, then flip screen-space X), through a throwaway probe camera rather
## than the live MirrorCamera (see _reflection_screen_position()'s own
## DECISION for why). A visible gap between the two marks is the owner's own
## "they don't align at all", independent of the printed numeric error above.
## DECISION (tools/screenshot_feel9b_mirror_lag.gd): comparing the
## reflection's own screen position against the DIRECT object's screen
## position (an earlier version of this probe) is not a valid test -- a
## planar mirror's reflection generally lands at a DIFFERENT screen X than
## the real object for any camera that is not looking straight down (found
## the hard way: even with the fix applied, that comparison still measured a
## nonzero gap of ordinary reflection geometry, not lag); only comparing the
## reflection against ITSELF under the correct vs. the actually-rendered
## mirror pose isolates the bug.
##
## Run windowed and off-screen (a real render is required):
##   godot --path . --position 10000,10000 \
##       --scene res://tools/screenshot_feel9b_mirror_lag.tscn -- \
##       --headless-host --bots=1 --players=2 --port=47912 \
##       --prefix=feel9b-after
##
## Lives in tools/ (CLAUDE.md: manual-QA scripts, not part of the running game).

const OUTPUT_DIR: String = "res://feedback/"
const PREFIX_ARG: String = "--prefix="
const DEFAULT_PREFIX: String = "feel9b-mirror-lag"
const SETTLE_FRAMES: int = 45
const ORBIT_FRAMES: int = 24
const ORBIT_STEP_DEG: float = 6.0
const CUBE_SHAPE: BlockShape = preload("res://config/blocks/cube.tres")
const BLOCK_DROP_HEIGHT: float = 0.6
const BLOCK_SETTLE_FRAMES: int = 40
const PLAYING_POLL_MAX_FRAMES: int = 900
const MARKER_HALF_SIZE_PX: int = 5
const MARKER_BLOCK_COLOR: Color = Color(1.0, 0.0, 0.0, 1.0)
const MARKER_REFLECTION_COLOR: Color = Color(0.0, 0.55, 1.0, 1.0)

var _prefix: String = DEFAULT_PREFIX
var _main: Node = null
var _rig: CameraRig = null
var _field: Field = null
var _mirror: DiscMirror = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(PREFIX_ARG):
			_prefix = arg.trim_prefix(PREFIX_ARG)

	_main = (load("res://game/Main.tscn") as PackedScene).instantiate()
	_field = _main.get_node("Field") as Field
	_rig = _main.get_node("CameraRig") as CameraRig
	_mirror = _main.get_node("DiscMirror") as DiscMirror

	# Bontago-xtq.21 (this file's own class doc): free-orbit, not the shipped
	# follow camera -- tools/screenshot_feel8b_disc_glare.gd's own _ready()
	# makes the identical DECISION for the identical reason (a scripted probe
	# drives the camera by directly mutating CameraRig fields, which the
	# follow-camera branch of CameraRig._process() does not read).
	var free_tuning: CameraTuning = (_rig.tuning as CameraTuning).duplicate(true) as CameraTuning
	free_tuning.follow_block = false
	_rig.tuning = free_tuning

	get_tree().root.add_child.call_deferred(_main)
	await get_tree().process_frame
	await get_tree().process_frame

	await _wait_for_playing()
	var spot: Vector3 = await _place_block()

	print("FEEL9B boot prefix=%s state=%s spot=%s window=%s" % [
		_prefix, Match.state(), spot, get_viewport().size,
	])

	# DECISION (tools/screenshot_feel9b_mirror_lag.gd): the orbit target is the
	# DISC CENTRE, not `spot` -- CameraRig._update_transform() always
	# Camera3D.look_at(_target, UP), so a world point sitting exactly AT
	# `_target` re-centres on screen every frame regardless of the mirror's
	# own staleness (found the hard way: an earlier version of this probe
	# orbited around `spot` itself and measured dx_px ~= 0.00 even with the
	# pre-fix code, purely because the placed block WAS the look-at point --
	# no orbit angle ever moves a look-at target's own screen projection).
	# Orbiting around the origin while the block sits off-centre at `spot`
	# gives the block real screen-space parallax as the camera rotates, so a
	# stale mirror camera's own rotation lag becomes visible in exactly the
	# marker this probe draws.
	_rig._target = Vector3.ZERO
	_rig._distance = maxf(spot.length(), 1.0) + 1.5
	_rig._pitch = deg_to_rad(-14.0)
	_rig._yaw = atan2(spot.x, spot.z)
	_rig._update_transform()
	_rig.reset_physics_interpolation()
	_rig.get_camera().reset_physics_interpolation()
	await _frames(SETTLE_FRAMES)

	for i: int in range(ORBIT_FRAMES):
		_rig._yaw += deg_to_rad(ORBIT_STEP_DEG)
		await get_tree().process_frame

		var cam: Camera3D = _rig.get_camera()
		var plane: Plane = _mirror._mirror_plane()
		var expected_mirror_xf: Transform3D = DiscMirror.mirror_transform(cam.global_transform, plane)
		var actual_mirror_xf: Transform3D = _mirror._camera.global_transform
		var origin_error: float = expected_mirror_xf.origin.distance_to(actual_mirror_xf.origin)
		print("FEEL9B frame=%d origin_error=%.5f cam_pos=%s expected_mirror_pos=%s actual_mirror_pos=%s" % [
			i, origin_error, cam.global_position, expected_mirror_xf.origin, actual_mirror_xf.origin,
		])

	# Printed BEFORE the screenshot capture below (which needs a real
	# compositor -- RenderingServer.frame_post_draw never fires under
	# --headless, so a headless smoke run can still read this number even
	# though it then hangs harmlessly until an external timeout kills it).
	#
	# DECISION (this file's own class doc): compares the reflection's own
	# screen position against ITSELF under two candidate mirror-camera poses
	# (correct-this-frame vs. actually-rendered), never against the direct
	# object's own screen position -- see the class doc's own DECISION for
	# why that comparison is not geometrically valid.
	var mirror_viewport: SubViewport = _mirror.get_node("MirrorViewport") as SubViewport
	var mirror_size: Vector2 = Vector2(mirror_viewport.size)
	var main_size: Vector2 = Vector2(get_viewport().size)
	var block_world: Vector3 = spot
	var mirror_cam: Camera3D = _mirror._camera
	var actual_mirror_xf: Transform3D = mirror_cam.global_transform
	var expected_mirror_xf: Transform3D = DiscMirror.mirror_transform(
		_rig.get_camera().global_transform, _mirror._mirror_plane()
	)

	# DECISION (this file's own class doc): unprojects through a THROWAWAY
	# Camera3D with physics_interpolation_mode forced OFF, not by temporarily
	# swapping mirror_cam's own global_transform -- found the hard way: while
	# demonstrating the pre-fix bug (mirror_cam's own physics_interpolation_
	# mode is still the project-inherited default, ON, before game/DiscMirror.
	# gd's fix runs), Camera3D.unproject_position() on the LIVE, interpolated
	# mirror_cam read back a RenderingServer-smoothed transform instead of the
	# one just written a moment earlier in the same frame -- exactly this
	# package's own bug, confounding the measurement tool itself. A scratch
	# camera with interpolation OFF has no such smoothing, so it always
	# reflects whatever transform this probe just assigned it.
	var probe_cam: Camera3D = Camera3D.new()
	probe_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	probe_cam.fov = mirror_cam.fov
	probe_cam.near = mirror_cam.near
	probe_cam.far = mirror_cam.far
	probe_cam.projection = mirror_cam.projection
	mirror_viewport.add_child(probe_cam)

	var actual_reflection_screen: Vector2 = _reflection_screen_position(
		probe_cam, actual_mirror_xf, block_world, mirror_size, main_size
	)
	var expected_reflection_screen: Vector2 = _reflection_screen_position(
		probe_cam, expected_mirror_xf, block_world, mirror_size, main_size
	)
	probe_cam.queue_free()

	print("FEEL9B actual_reflection_screen=%s expected_reflection_screen=%s dx_px=%.2f dy_px=%.2f" % [
		actual_reflection_screen, expected_reflection_screen,
		absf(actual_reflection_screen.x - expected_reflection_screen.x),
		absf(actual_reflection_screen.y - expected_reflection_screen.y),
	])

	await RenderingServer.frame_post_draw
	var main_image: Image = get_viewport().get_texture().get_image()
	var mirror_image: Image = mirror_viewport.get_texture().get_image()

	_draw_marker(main_image, actual_reflection_screen, MARKER_BLOCK_COLOR)
	_draw_marker(main_image, expected_reflection_screen, MARKER_REFLECTION_COLOR)
	_save(main_image, "orbit-marked")
	_save(mirror_image, "mirror-raw")

	get_tree().quit()


## Where the main viewport shows `world_point`'s reflection, given a
## CANDIDATE mirror-camera pose `candidate_xf` -- shaders/territory.gdshader's
## own sampling contract (this file's own class doc): unproject through the
## mirror camera at that pose, normalise by the mirror SubViewport's own size,
## flip screen-space X (DiscMirror.mirror_transform()'s own DECISION comment
## on why the render is left-right flipped), then scale into the MAIN
## viewport's own pixel size. `cam` is the caller's own throwaway, interpolation-
## off probe_cam (this file's own class doc DECISION on why it must not be the
## live MirrorCamera) -- temporarily swapping its global_transform to
## `candidate_xf` reuses Camera3D.unproject_position()'s real projection math
## (respecting the live fov/near/far/aspect DiscMirror._process() copies from
## the source camera every frame) rather than re-deriving the projection
## matrix by hand; restores `cam`'s prior transform before returning, so the
## caller's second call with a different candidate sees only that candidate.
func _reflection_screen_position(
	cam: Camera3D, candidate_xf: Transform3D, world_point: Vector3, mirror_size: Vector2, main_size: Vector2
) -> Vector2:
	var previous_xf: Transform3D = cam.global_transform
	cam.global_transform = candidate_xf
	var mirror_uv: Vector2 = cam.unproject_position(world_point) / mirror_size
	cam.global_transform = previous_xf
	var reflection_uv: Vector2 = Vector2(1.0 - mirror_uv.x, mirror_uv.y)
	return reflection_uv * main_size


func _wait_for_playing() -> void:
	var frames: int = 0
	while Match.state() != Match.State.PLAYING and frames < PLAYING_POLL_MAX_FRAMES:
		await get_tree().physics_frame
		frames += 1


func _place_block() -> Vector3:
	if Match.slot_count() <= 0:
		return Vector3.ZERO
	var home: Vector2 = Match.slot(0).home_position
	var placed: Vector3 = _field.world_from_disk_local(home, 0.0)
	var world_spot: Vector3 = _field.world_from_disk_local(home, BLOCK_DROP_HEIGHT)
	Match._held_shapes[0] = CUBE_SHAPE
	var reason: StringName = Match.request_place(0, world_spot, 0, Quaternion.IDENTITY, false)
	print("FEEL9B place reason=%s" % [reason])
	await _physics(BLOCK_SETTLE_FRAMES)
	return placed


## Red = the placed block's reflection as whatever MirrorCamera actually
## rendered this frame; blue = where it should be given the mathematically
## correct, this-frame mirror pose (see this file's own class doc) --
## overlapping marks means aligned, a visible gap means the owner's own "they
## don't align at all".
func _draw_marker(image: Image, at: Vector2, color: Color) -> void:
	var cx: int = int(round(at.x))
	var cy: int = int(round(at.y))
	for dy: int in range(-MARKER_HALF_SIZE_PX, MARKER_HALF_SIZE_PX + 1):
		for dx: int in range(-MARKER_HALF_SIZE_PX, MARKER_HALF_SIZE_PX + 1):
			if absi(dx) != 0 and absi(dy) != 0:
				continue
			var x: int = cx + dx
			var y: int = cy + dy
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			image.set_pixel(x, y, color)


func _save(image: Image, label: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var path: String = OUTPUT_DIR + "%s-%s.png" % [_prefix, label]
	image.save_png(path)
	print("FEEL9B saved=%s" % ProjectSettings.globalize_path(path))


func _frames(count: int) -> void:
	for _i: int in range(count):
		await get_tree().process_frame


func _physics(count: int) -> void:
	for _i: int in range(count):
		await get_tree().physics_frame
