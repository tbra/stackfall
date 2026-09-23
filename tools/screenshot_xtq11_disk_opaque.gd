extends Node
## Windowed smoke-shot for Bontago-xtq.11/xtq.12 (owner feel reports: "I think
## the disc is a mirror-like surface and not glass, so it should be
## reflective but not transparent", then "isn't very reflective, like at
## all"). Boots the real Main.tscn/sandbox (same pattern as
## tools/screenshot_xtq8_sky_reflection.gd), places a couple of blocks near
## slot 0's home flag so there is something for the mirror-like surface to
## reflect, then shoots the disk from a low, shallow angle framed on those
## blocks so the sky reflection and the blocks' own reflection are both
## visible in one frame.
##
## `--before`: pushes the disk's own visuals back to the pre-Bontago-xtq.11
## metallic/roughness values purely for this evidence run (a duplicated
## TerritoryVisuals, same override-a-copy pattern
## tools/screenshot_xtq8_sky_reflection.gd uses). TerritoryVisuals's shipped
## resource is never touched by this tool. Omitted, the tool leaves
## config/territory_visuals.tres's own shipped (post-fix) values in place.
##
## `--low`: an even shallower pitch than the default shot, so the sky
## reflection band on the disc reads unambiguously against the placed
## blocks' own reflection in the same frame.
##
## `--reflection-mode=none|once|always` (Bontago-xtq.12): reconfigures the
## Skybox-owned ReflectionProbe after boot (game/Skybox.gd's
## configure_reflection_probe() is a public test/tool seam for exactly this),
## overriding config/territory_visuals.tres's shipped
## reflection_probe_enabled/reflection_probe_update_always on a duplicated
## TerritoryVisuals -- never touches the shipped resource. Omitted, the probe
## keeps whichever mode territory_visuals.tres itself ships (update_always by
## default). Always prints an average-frame-time line
## (SCREENSHOT xtq11 frame_time_ms_avg=...) over the settle window so the
## three modes can be compared directly from one tool.
##
## `--follow` (Bontago-xtq.12 step 2): frames the shot at the owner's actual
## typical view -- config/camera_tuning.tres's own follow_distance/
## follow_pitch_deg -- instead of this tool's own closer/steeper evidence
## angles above.
##
## `--mirror-mode=none|ssr|planar|both` (Bontago-xtq.12 step 2, owner: "the
## disc isn't very reflective, like at all?"): overrides TerritoryVisuals.
## ssr_enabled/mirror_enabled on the same duplicated-copy pattern
## `--reflection-mode=` uses above -- never touches the shipped
## config/territory_visuals.tres. Omitted, the disk keeps whichever
## combination territory_visuals.tres itself ships (both true by default).
##
## Run windowed (a real render is required for the screenshot):
##   godot --path . --scene res://tools/screenshot_xtq11_disk_opaque.tscn -- \
##       --before --out=disk-before.png
##   godot --path . --scene res://tools/screenshot_xtq11_disk_opaque.tscn -- \
##       --out=disk-after.png
##   godot --path . --scene res://tools/screenshot_xtq11_disk_opaque.tscn -- \
##       --low --out=disk-after-low.png
##   godot --path . --scene res://tools/screenshot_xtq11_disk_opaque.tscn -- \
##       --low --reflection-mode=none --out=disk-noprobe-low.png
##   godot --path . --scene res://tools/screenshot_xtq11_disk_opaque.tscn -- \
##       --low --reflection-mode=once --out=disk-probe-once-low.png
##   godot --path . --scene res://tools/screenshot_xtq11_disk_opaque.tscn -- \
##       --low --reflection-mode=always --out=disk-probe-always-low.png
##   godot --path . --scene res://tools/screenshot_xtq11_disk_opaque.tscn -- \
##       --steep --reflection-mode=none --out=disk-noprobe-steep.png
##   godot --path . --scene res://tools/screenshot_xtq11_disk_opaque.tscn -- \
##       --steep --reflection-mode=always --out=disk-probe-always-steep.png
##   godot --path . --scene res://tools/screenshot_xtq11_disk_opaque.tscn -- \
##       --steep --edge-softness=0.3 --out=disk-edge-blurry-steep.png
##   godot --path . --scene res://tools/screenshot_xtq11_disk_opaque.tscn -- \
##       --steep --out=disk-edge-crisp-steep.png
##   godot --path . --scene res://tools/screenshot_xtq11_disk_opaque.tscn -- \
##       --follow --mirror-mode=none --out=xtq12-step2-follow-none.png
##   godot --path . --scene res://tools/screenshot_xtq11_disk_opaque.tscn -- \
##       --follow --mirror-mode=ssr --out=xtq12-step2-follow-ssr.png
##   godot --path . --scene res://tools/screenshot_xtq11_disk_opaque.tscn -- \
##       --follow --mirror-mode=planar --out=xtq12-step2-follow-planar.png
##   godot --path . --scene res://tools/screenshot_xtq11_disk_opaque.tscn -- \
##       --low --mirror-mode=planar --out=xtq12-step2-low-planar.png
##
## Lives in tools/ (CLAUDE.md: build-time/manual-QA scripts, not part of the
## running game).

const OUTPUT_DIR: String = "res://feedback/"
const DEFAULT_OUTPUT: String = "disk-after.png"
const SETTLE_FRAMES: int = 90
## Rendered frames sampled for the frame_time_ms_avg measurement, after the
## camera has already settled into its final pose -- long enough to smooth
## out one-off hitches (shader/material compilation, texture upload) without
## making every screenshot run noticeably slower.
const FRAME_TIME_SAMPLE_COUNT: int = 60

## Low and shallow, close to the disk's own surface: shows the reflected sky
## band and the placed blocks' own reflection in the same shot. Target/
## distance are set at runtime around wherever the blocks actually landed
## (CLOSE_CAMERA_DISTANCE below) rather than a fixed disk-center framing: slot
## 0's home flag sits at a different disk angle depending on player_count/
## map, and framing on the far-off disk center at CAMERA_DISTANCE's original
## 30 m put the (small, 0.6 m) blocks right at the edge of frame and mostly
## unreadable.
const CAMERA_DISTANCE: float = 30.0
const CLOSE_CAMERA_DISTANCE: float = 10.0
const CAMERA_PITCH_DEG: float = -8.0
const LOW_CAMERA_PITCH_DEG: float = -15.0
## `--steep`: closer to top-down than even the default shot, so the untinted
## disk beyond the small home-territory circle fills more of the frame.
## Bontago-xtq.12 review found the low, near-horizontal pitch above reflects
## mostly a near-uniform slice of sky (hard to tell apart from a diffuse
## tint by eye in a still screenshot); this angle is what actually made the
## reflected sky's own colour gradient legible on the disk surface while
## comparing --reflection-mode=none against once/always for this package's
## evidence.
const STEEP_CAMERA_PITCH_DEG: float = -40.0
## Fallback yaw/target, used only if no block ends up placed (defensive; see
## _place_blocks()'s own doc comment for when that can happen).
const FALLBACK_YAW_DEG: float = -30.0
const FALLBACK_TARGET: Vector3 = Vector3(0.0, 1.0, 0.0)
## Second shot's yaw offset from the block-framed yaw, so a reviewer can
## still check the rim/holes from another angle without losing the subject
## entirely.
const YAW_B_OFFSET_DEG: float = 90.0

## Bontago-xtq.4's original metallic/roughness defaults, before
## Bontago-xtq.11 retuned them (config/TerritoryVisuals.gd's DECISION
## comments carry the same numbers). The opacity half of the old "glass"
## material has no equivalent anymore: the shader is unconditionally opaque.
const BEFORE_METALLIC: float = 0.2
const BEFORE_ROUGHNESS: float = 0.45

## Bontago-xtq.12: a small stack of blocks near slot 0's own home flag, so the
## mirror-like surface has something recognizable to reflect in the shot
## besides the sky. Placement legality (core/rules/PlacementRules.gd) refuses
## any point outside the acting slot's own territory, and only each slot's
## permanent home-flag circle (TerritoryTuning.home_radius) is owned this
## early in a match -- a fixed disk-local spot picked without reference to
## that (this package's first attempt) is silently rejected every time
## (REASON_OUTSIDE_TERRITORY, found by printing request_place()'s own return
## value while building this tool).
const CUBE_SHAPE: BlockShape = preload("res://config/blocks/cube.tres")
const _TERRITORY_TUNING: TerritoryTuning = preload("res://config/territory_tuning.tres")
const _PHYSICS_TUNING: PhysicsTuning = preload("res://config/physics_tuning.tres")
const BLOCK_COUNT: int = 3
const BLOCK_DROP_HEIGHT: float = 0.6
const BLOCK_DROP_STEP: float = 1.1
const BLOCK_SETTLE_FRAMES: int = 45

const BEFORE_ARG: String = "--before"
const LOW_ARG: String = "--low"
const STEEP_ARG: String = "--steep"
## Bontago-xtq.12 step 2: the owner's actual typical view (config/
## camera_tuning.tres's own follow_distance/follow_pitch_deg -- read off the
## live CameraTuning at runtime below, not re-hardcoded here), rather than
## this tool's own closer/steeper evidence angles above -- both the follow
## and --low shots are the two the step 2 package report is asked for.
const FOLLOW_ARG: String = "--follow"
const OUT_ARG: String = "--out="
const REFLECTION_MODE_ARG: String = "--reflection-mode="
## Bontago-xtq.12 step 2 (owner: "the disc isn't very reflective, like at
## all?"): none|ssr|planar|both, overriding TerritoryVisuals.ssr_enabled/
## mirror_enabled on the same duplicated-copy pattern REFLECTION_MODE_ARG
## uses right above -- never touches the shipped config/territory_visuals.tres.
## Omitted, the disk keeps whichever combination territory_visuals.tres
## itself ships (both true by default).
const MIRROR_MODE_ARG: String = "--mirror-mode="
## Bontago-xtq.14: overrides the disk's own edge_softness_m for one run, same
## override-a-copy pattern as `--before` right below (never touches the
## shipped config/territory_visuals.tres). e.g. `--edge-softness=0.3` recreates
## the pre-Bontago-xtq.14 blur (rim_soft_width's old shared 0.25 m, rounded
## up) for a same-tool before/after pair; omitted, the disk keeps whichever
## value territory_visuals.tres itself ships (0.03 m by default).
const EDGE_SOFTNESS_ARG: String = "--edge-softness="


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var before: bool = args.has(BEFORE_ARG)
	var low: bool = args.has(LOW_ARG)
	var steep: bool = args.has(STEEP_ARG)
	var follow: bool = args.has(FOLLOW_ARG)
	var out_name: String = _string_arg(args, OUT_ARG, DEFAULT_OUTPUT)
	var reflection_mode: String = _string_arg(args, REFLECTION_MODE_ARG, "")
	var mirror_mode: String = _string_arg(args, MIRROR_MODE_ARG, "")
	var edge_softness_str: String = _string_arg(args, EDGE_SOFTNESS_ARG, "")

	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	var field: Field = main.get_node("Field") as Field
	var rig: CameraRig = main.get_node("CameraRig") as CameraRig
	var skybox: Skybox = main.get_node("Skybox") as Skybox
	var discmirror: DiscMirror = main.get_node("DiscMirror") as DiscMirror

	if before or edge_softness_str != "":
		var visuals: TerritoryVisuals = (field.visuals as TerritoryVisuals).duplicate(true) as TerritoryVisuals
		if before:
			visuals.disk_metallic = BEFORE_METALLIC
			visuals.disk_roughness = BEFORE_ROUGHNESS
		if edge_softness_str != "":
			visuals.edge_softness_m = float(edge_softness_str)
		field.visuals = visuals

	if reflection_mode != "" or mirror_mode != "":
		# One duplicated copy shared by skybox and discmirror (Bontago-xtq.12
		# step 2): both `visuals` exports resolve to the exact same preloaded
		# res://config/territory_visuals.tres instance by default, so a
		# single override here still reads consistently from both nodes --
		# splitting it into two independent duplicates would let
		# --reflection-mode= and --mirror-mode= silently stop agreeing with
		# each other.
		var probe_visuals: TerritoryVisuals = (skybox.visuals as TerritoryVisuals).duplicate(true) as TerritoryVisuals
		if reflection_mode != "":
			match reflection_mode:
				"none":
					probe_visuals.reflection_probe_enabled = false
				"once":
					probe_visuals.reflection_probe_enabled = true
					probe_visuals.reflection_probe_update_always = false
				"always":
					probe_visuals.reflection_probe_enabled = true
					probe_visuals.reflection_probe_update_always = true
				_:
					push_warning("screenshot_xtq11_disk_opaque: unknown --reflection-mode=%s, ignoring." % reflection_mode)
		if mirror_mode != "":
			match mirror_mode:
				"none":
					probe_visuals.ssr_enabled = false
					probe_visuals.mirror_enabled = false
				"ssr":
					probe_visuals.ssr_enabled = true
					probe_visuals.mirror_enabled = false
				"planar":
					probe_visuals.ssr_enabled = false
					probe_visuals.mirror_enabled = true
				"both":
					probe_visuals.ssr_enabled = true
					probe_visuals.mirror_enabled = true
				_:
					push_warning("screenshot_xtq11_disk_opaque: unknown --mirror-mode=%s, ignoring." % mirror_mode)
		skybox.visuals = probe_visuals
		discmirror.visuals = probe_visuals
		# Skybox._ready() already ran configure_reflection_probe()/
		# configure_ssr() once against the shipped resource before this
		# script's override above could reach it -- re-run both now against
		# the duplicated copy (DiscMirror re-reads its own `visuals` every
		# _process() frame, so it needs no equivalent re-run call).
		skybox.refresh_from_visuals()

	var free_tuning: CameraTuning = (rig.tuning as CameraTuning).duplicate(true) as CameraTuning
	free_tuning.follow_block = false
	rig.tuning = free_tuning

	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame

	main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(int(1.5 * Engine.physics_ticks_per_second))
	await _wait_for_playing()

	var block_world_spot: Variant = await _place_blocks(field)
	var yaw_deg: float = FALLBACK_YAW_DEG
	var target: Vector3 = FALLBACK_TARGET
	var distance: float = CAMERA_DISTANCE
	if block_world_spot != null:
		var spot: Vector3 = block_world_spot as Vector3
		# A little above the disk (not the blocks' own drop height), so the
		# camera looks slightly down at the stack rather than dead level with
		# its base -- same idea as FALLBACK_TARGET's y == 1.0. Orbiting the
		# block itself at CLOSE_CAMERA_DISTANCE (well under the ~12 m of disk
		# still left between the block and the rim on every map size) shows
		# plenty of disk in every direction, so FALLBACK_YAW_DEG's fixed angle
		# is kept rather than solved for -- one less place to get the sign of
		# a look-at direction backwards.
		target = Vector3(spot.x, 1.0, spot.z)
		distance = CLOSE_CAMERA_DISTANCE

	print((
		"SCREENSHOT xtq11 before=%s low=%s steep=%s follow=%s reflection_mode=%s mirror_mode=%s "
		+ "metallic=%s roughness=%s edge_softness_m=%s blocks_placed=%s"
	) % [
		before, low, steep, follow, reflection_mode, mirror_mode, field.visuals.disk_metallic,
		field.visuals.disk_roughness, field.visuals.edge_softness_m, block_world_spot != null,
	])

	if follow:
		# The owner's actual typical view: config/camera_tuning.tres's own
		# follow_distance/follow_pitch_deg, read off the live (duplicated)
		# tuning above rather than re-hardcoded here -- follow_block is
		# forced false for this tool's free-orbit camera, but the distance/
		# pitch fields it was duplicated from are untouched.
		_point_camera(rig, target, free_tuning.follow_distance, yaw_deg, free_tuning.follow_pitch_deg)
		await _wait(SETTLE_FRAMES)
		await _measure_frame_time(reflection_mode)
		await _shoot(out_name)
		get_tree().quit()
		return

	if steep:
		_point_camera(rig, target, distance, yaw_deg, STEEP_CAMERA_PITCH_DEG)
		await _wait(SETTLE_FRAMES)
		await _measure_frame_time(reflection_mode)
		await _shoot(out_name)
		get_tree().quit()
		return

	if low:
		_point_camera(rig, target, distance, yaw_deg, LOW_CAMERA_PITCH_DEG)
		await _wait(SETTLE_FRAMES)
		await _measure_frame_time(reflection_mode)
		await _shoot(out_name)
		get_tree().quit()
		return

	_point_camera(rig, target, distance, yaw_deg, CAMERA_PITCH_DEG)
	await _wait(SETTLE_FRAMES)
	await _measure_frame_time(reflection_mode)
	await _shoot(out_name)

	# Second yaw so a reviewer can check the rim/holes still read and there is
	# no z-fighting between the disk and the territory overlay from another
	# angle.
	_point_camera(rig, target, distance, yaw_deg + YAW_B_OFFSET_DEG, CAMERA_PITCH_DEG)
	await _wait(SETTLE_FRAMES)
	await _shoot("%s-yaw2.png" % out_name.get_basename())

	get_tree().quit()


## Match.request_place() only accepts placements once the sandbox match has
## left Match.State.COUNTDOWN (autoload/Match.gd's own COUNTDOWN_SECONDS,
## 3 s) -- the existing 1.5 s settle wait above (present before this package,
## kept for the camera/lighting shots that never used to place anything) is
## not long enough on its own, which silently dropped every placement below
## (request_place() returned REASON_NO_BLOCK for all of them, discovered via
## a throwaway diagnostic scene while building this package). Polls rather
## than hard-coding a wait, so a future change to COUNTDOWN_SECONDS cannot
## silently reintroduce the same bug here.
const PLAYING_POLL_MAX_FRAMES: int = 600


func _wait_for_playing() -> void:
	var frames: int = 0
	while Match.state() != Match.State.PLAYING and frames < PLAYING_POLL_MAX_FRAMES:
		await get_tree().physics_frame
		frames += 1


## Drops BLOCK_COUNT cubes at the same disk-local spot, inset from slot 0's
## home flag toward the disk center by TerritoryTuning.home_radius minus one
## cube (same distance tools/screenshot_main.gd's own _place_outward() uses
## for its first placement) -- so they settle into a small stack, inside the
## home circle with a little margin rather than "a fraction of the way to
## the disk center", which for a small home_radius (6 m, against a 38 m home
## distance on round_medium.tres) is still far outside it (found the same way
## as the earlier fixed-spot rejection: printing request_place()'s return
## value while building this tool). Returns the world spot they were dropped
## at, or null if Match.slot_count() was 0 or the match left PLAYING mid-loop
## (never expected from this tool's own sandbox boot, but a defined, checked
## fallback rather than an assumed success).
func _place_blocks(field: Field) -> Variant:
	if Match.slot_count() <= 0:
		return null
	var slot_id: int = 0
	var home: Vector2 = Match.slot(slot_id).home_position
	var inward: Vector2 = -home.normalized()
	var inset: float = maxf(_TERRITORY_TUNING.home_radius - _PHYSICS_TUNING.cube_size, 0.5)
	var disk_spot: Vector2 = home + inward * inset
	var last_spot: Variant = null
	for step: int in range(BLOCK_COUNT):
		if Match.state() != Match.State.PLAYING:
			break
		var world_spot: Vector3 = field.world_from_disk_local(
			disk_spot, BLOCK_DROP_HEIGHT + float(step) * BLOCK_DROP_STEP
		)
		Match._held_shapes[slot_id] = CUBE_SHAPE
		var reason: StringName = Match.request_place(slot_id, world_spot, 0, Quaternion.IDENTITY, false)
		if reason == PlacementRules.REASON_OK:
			last_spot = world_spot
		await _wait(BLOCK_SETTLE_FRAMES)
	return last_spot


## Bontago-xtq.12 (owner: "isn't very reflective, like at all" -> add a
## ReflectionProbe; "measure Performance.TIME_PROCESS / frame time before/
## after in the probe and report"): samples FRAME_TIME_SAMPLE_COUNT rendered
## frames' worth of Performance.TIME_PROCESS (seconds) and prints the average
## in milliseconds, so --reflection-mode=none/once/always runs are directly
## comparable from their printed output alone.
func _measure_frame_time(reflection_mode: String) -> void:
	var total_seconds: float = 0.0
	for _i: int in range(FRAME_TIME_SAMPLE_COUNT):
		await get_tree().process_frame
		total_seconds += Performance.get_monitor(Performance.TIME_PROCESS)
	var avg_ms: float = (total_seconds / float(FRAME_TIME_SAMPLE_COUNT)) * 1000.0
	print("SCREENSHOT xtq11 frame_time_ms_avg=%.3f reflection_mode=%s samples=%d" % [
		avg_ms, reflection_mode, FRAME_TIME_SAMPLE_COUNT,
	])


## Drives the rig's own free-orbit fields directly (see
## tools/screenshot_xtq6_disk_thin.gd's DECISION comments for why setting the
## Camera3D child's transform directly does not stick, and why
## reset_physics_interpolation() is required with physics interpolation on).
func _point_camera(rig: CameraRig, target: Vector3, distance: float, yaw_deg: float, pitch_deg: float) -> void:
	rig._target = target
	rig._distance = distance
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
