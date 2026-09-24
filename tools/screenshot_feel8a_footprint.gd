extends Node
## Repro/bisect shot for Bontago-xtq.18/xtq.19 (feedback/owner-noise-footprint.png:
## a pitched domino ghost above a placed L3; the footprint on the disc renders
## as black/white noise and the placed L shows per-cell edges). Places an L3 in
## the sandbox match (the owner's own evidence was a sandbox run), holds a
## pitched domino beside/above it in the VALID state, then saves one
## screenshot per suspect toggled off, all from the same process and pose.
##
## Bontago-xtq.19 attempt 3 (owner screenshots 2026-09-24, screenshot_20260924_
## 204137.png a tilted 4-long bar, screenshot_20260924_204154.png a T-piece:
## "the segmented preview is not fixed"): `--seam-check` instead holds a bar4
## rolled 30 degrees, then a T4, each at a real height above the bare disc, and
## saves one shot per pose so the merged-mesh-silhouette prism (game/
## GhostPreview.gd's _shape_silhouette_loops()) can be read for leftover
## per-cell seams the same way the owner's own screenshots showed them.
##
## Run windowed and off-screen (a real render is required):
##   godot --path . --position 10000,10000 --scene res://tools/screenshot_feel8a_footprint.tscn -- --shot-prefix=feel8a-before
##   godot --path . --position 10000,10000 --scene res://tools/screenshot_feel8a_footprint.tscn -- --seam-check --shot-prefix=xtq19-seam
##
## Lives in tools/ (CLAUDE.md: manual-QA scripts, not part of the running game).

const OUTPUT_DIR: String = "res://feedback/"
const SETTLE_FRAMES: int = 90
const TOGGLE_FRAMES: int = 4

var _prefix: String = "feel8a-before"
var _main: Node = null
var _ghost: GhostPreview = null
var _controller: PlayerController = null
var _cursor: Vector3 = Vector3.ZERO
var _pitch: Quaternion = Quaternion.IDENTITY
var _bisect: bool = true
var _confirm: bool = false
var _after: bool = false
var _seam_check: bool = false


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shot-prefix="):
			_prefix = arg.trim_prefix("--shot-prefix=")
		elif arg == "--no-bisect":
			_bisect = false
		elif arg == "--confirm":
			_confirm = true
		elif arg == "--after":
			_after = true
		elif arg == "--seam-check":
			_seam_check = true
	_main = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(int(3.5 * Engine.physics_ticks_per_second))

	var sandbox: Sandbox = _main._sandbox
	_ghost = sandbox.ghost()
	_controller = sandbox.controller()
	var home: Vector3 = Match.default_ghost_origin(0)

	if _seam_check:
		await _run_seam_check(home)
		get_tree().quit()
		return

	Match._held_shapes[0] = load("res://config/blocks/L3.tres")
	var reason: StringName = Match.request_place(0, home + Vector3.UP * 0.6, 0, Quaternion.IDENTITY, false)
	print("FEEL8A place L3 reason=%s" % [reason])
	await _wait(SETTLE_FRAMES)

	_cursor = home + Vector3(-2.2, 0.0, 0.6)
	_pitch = Quaternion(Vector3(1.0, 0.0, 0.3).normalized(), deg_to_rad(40.0))
	_pose_ghost()
	var rig: CameraRig = _main._camera_rig
	rig._target = home + Vector3(-1.0, 0.5, 0.3)
	rig._yaw = deg_to_rad(-25.0)
	rig._pitch = deg_to_rad(-24.0)
	rig._distance = 7.5
	await _wait(20)

	await _shot("")
	if _after:
		await _run_after_mechanism()
		get_tree().quit()
		return
	if _confirm:
		await _run_confirm(home)
		get_tree().quit()
		return
	var close_target: Vector3 = home + Vector3(0.0, 0.8, 0.0)
	if not _bisect:
		await _close_shot(rig, close_target, "L-close")
		get_tree().quit()
		return

	# Each suspect alone, restored afterwards.
	_ghost._block_projection_decal.visible = false
	await _shot("bisect-decal-off", true)
	_ghost._block_projection_decal.visible = true

	for quad: MeshInstance3D in _ghost._footprint_quads:
		quad.visible = false
	await _shot("bisect-footprint-off")
	for quad: MeshInstance3D in _ghost._footprint_quads:
		quad.visible = true

	_ghost._projection_mesh.visible = false
	await _shot("bisect-prism-off")
	_ghost._projection_mesh.visible = true

	var visuals: TerritoryVisuals = load("res://config/territory_visuals.tres")
	var mirror_was: bool = visuals.mirror_enabled
	visuals.mirror_enabled = false
	await _shot("bisect-mirror-off")
	visuals.mirror_enabled = mirror_was

	var env: Environment = (_main.get_node("WorldEnvironment") as WorldEnvironment).environment
	env.ssr_enabled = false
	await _shot("bisect-ssr-off")
	env.ssr_enabled = true

	var light: DirectionalLight3D = _main.get_node("DirectionalLight3D") as DirectionalLight3D
	light.shadow_enabled = false
	await _shot("bisect-sunshadow-off")
	light.shadow_enabled = true

	for quad: MeshInstance3D in _ghost._footprint_quads:
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	await _shot("bisect-footprint-noshadowcast")
	for quad: MeshInstance3D in _ghost._footprint_quads:
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	var probe: ReflectionProbe = _main.get_node("ReflectionProbe") as ReflectionProbe
	probe.visible = false
	await _shot("bisect-probe-off")
	probe.visible = true

	await _close_shot(rig, close_target, "L-close")
	light.shadow_enabled = false
	await _close_shot(rig, close_target, "L-close-sunshadow-off")
	light.shadow_enabled = true
	env.ssr_enabled = false
	visuals.mirror_enabled = false
	await _close_shot(rig, close_target, "L-close-ssr-mirror-off")
	get_tree().quit()


## Bontago-xtq.19 attempt 3 (owner screenshots 2026-09-24): holds a bar4 rolled
## 30 degrees, then a T4 at the same rotation, both at a real height above the
## bare disc with the projection prism visible, and saves one shot each --
## freezing the controller/camera rig first (same idea as _run_after_
## mechanism() above) so neither the sandbox feed nor the follow camera
## disturbs the pose between _pose_seam_check_ghost() and the saved frame.
func _run_seam_check(home: Vector3) -> void:
	# Bontago-xtq.19 attempt 3: the controller is frozen (so _shot()'s own
	# "re-pin to domino" guard skips, and the sandbox feed cannot reissue a
	# piece mid-shot) -- but CameraRig.follow_block reads its own follow
	# target from PlayerController's own per-frame set_follow_position() call
	# (game/PlayerController.gd), which a frozen controller never makes any
	# more, so _pose_seam_check_ghost() below calls it directly instead. The
	# rig itself stays processing (unlike the controller) so it actually
	# applies _yaw/_pitch/_distance/the follow position into the camera
	# transform every frame (CameraTuning.follow_lag_seconds defaults to 0, an
	# instant snap -- no extra settle wait needed beyond _shot()'s own).
	_controller.set_process(false)
	_controller.set_physics_process(false)
	var rig: CameraRig = _main._camera_rig

	_cursor = home
	rig._yaw = deg_to_rad(40.0)
	rig._pitch = deg_to_rad(-20.0)
	rig._distance = 3.0

	_pose_seam_check_ghost(load("res://config/blocks/bar4.tres"), deg_to_rad(30.0), rig)
	await _wait(6)
	await _shot("bar4-tilted30")

	_pose_seam_check_ghost(load("res://config/blocks/T4.tres"), deg_to_rad(30.0), rig)
	await _wait(6)
	await _shot("t4-tilted30")


func _pose_seam_check_ghost(shape: BlockShape, roll_radians: float, rig: CameraRig) -> void:
	_ghost.set_shape(shape)
	_ghost.orientation_index = 0
	_ghost.free_quaternion = Quaternion(Vector3.RIGHT, roll_radians)
	_ghost._apply_rotation()
	_ghost.apply_validity(PlacementRules.Result.VALID)
	# Bontago-xtq.19 attempt 3: a real height (not just tuning.hover_height's
	# own 0.3 m default) so the prism's own vertical walls read clearly in
	# frame instead of hugging the disc.
	_ghost.manual_hover_offset = 1.0
	_controller._cursor = _cursor
	_controller._update_ghost_transform()
	rig.set_follow_position(_ghost.rotated_center_world())


## Run 3: after the fix, re-prove the mechanism in-process -- freeze the
## controller so nothing re-applies the decal settings, then put the disc back
## under the decal with a positive fade (expected clean) and with fade 0.0
## (expected speckle again).
func _run_after_mechanism() -> void:
	var decal: Decal = _ghost._block_projection_decal
	print("FEEL8A after cull_mask=%d fades=%s viewport=%s" % [
		decal.cull_mask, _ghost.block_projection_decal_fades(), get_viewport().get_visible_rect().size
	])
	_controller.set_process(false)
	_controller.set_physics_process(false)
	decal.cull_mask = 0xFFFFF
	await _shot("mech-disc-painted-fade-positive")
	decal.upper_fade = 0.0
	decal.lower_fade = 0.0
	await _shot("mech-disc-painted-fade-zero")


## Run 2: confirm the decal-fade hypothesis and inspect the placed L's faces.
func _run_confirm(home: Vector3) -> void:
	var decal: Decal = _ghost._block_projection_decal
	print("FEEL8A decal upper_fade=%s lower_fade=%s size=%s pos=%s" % [
		decal.upper_fade, decal.lower_fade, decal.size, decal.global_position
	])
	decal.cull_mask = 0
	await _shot("confirm-decal-cullmask0")
	decal.cull_mask = 1
	decal.upper_fade = 0.001
	decal.lower_fade = 0.001
	await _shot("confirm-decal-fade")
	decal.upper_fade = 0.0
	decal.lower_fade = 0.0
	await _shot("confirm-decal-fade-reverted")

	for block: Node in Match.blocks_parent().get_children():
		var meshes: int = 0
		var verts: int = 0
		for child: Node in block.get_children():
			if child is MeshInstance3D:
				meshes += 1
				var m: Mesh = (child as MeshInstance3D).mesh
				verts += (m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		print("FEEL8A block=%s class=%s meshes=%d verts=%d basis=%s" % [
			block.name, block.get_class(), meshes, verts, (block as Node3D).global_transform.basis
		])

	# Ghost well away so only the placed L is in frame.
	_cursor = home + Vector3(0.0, 0.0, -9.0)
	_pose_ghost()
	var rig: CameraRig = _main._camera_rig
	rig.set_process(false)
	var cam: Camera3D = rig.get_node("Camera3D") as Camera3D
	var look_at_point: Vector3 = home + Vector3(0.5, 0.8, 0.0)
	cam.global_position = look_at_point + Vector3(-2.2, 1.4, 2.6)
	cam.look_at(look_at_point, Vector3.UP)
	var light: DirectionalLight3D = _main.get_node("DirectionalLight3D") as DirectionalLight3D
	var env: Environment = (_main.get_node("WorldEnvironment") as WorldEnvironment).environment
	var probe: ReflectionProbe = _main.get_node("ReflectionProbe") as ReflectionProbe
	var visuals: TerritoryVisuals = load("res://config/territory_visuals.tres")
	print("FEEL8A light bias=%s normal_bias=%s mode=%s blur=%s" % [
		light.shadow_bias, light.shadow_normal_bias, light.directional_shadow_mode, light.shadow_blur
	])
	await _shot("confirm-L")
	light.shadow_enabled = false
	await _shot("confirm-L-sunshadow-off")
	light.shadow_enabled = true
	probe.visible = false
	await _shot("confirm-L-probe-off")
	probe.visible = true
	env.ssr_enabled = false
	visuals.mirror_enabled = false
	await _shot("confirm-L-ssr-mirror-off")
	env.ssr_enabled = true
	visuals.mirror_enabled = true
	var sky_contrib: float = env.ambient_light_sky_contribution
	env.ambient_light_energy = 0.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	await _shot("confirm-L-ambient-reflect-off")
	print("FEEL8A ambient sky_contrib=%s" % [sky_contrib])


func _close_shot(rig: CameraRig, target: Vector3, name: String) -> void:
	rig._target = target
	rig._distance = 3.2
	rig._pitch = deg_to_rad(-20.0)
	await _wait(20)
	await _shot(name)


func _pose_ghost() -> void:
	_ghost.set_shape(load("res://config/blocks/domino.tres"))
	_ghost.orientation_index = 0
	_ghost.free_quaternion = _pitch
	_ghost._apply_rotation()
	_ghost.apply_validity(PlacementRules.Result.VALID)
	_controller._cursor = _cursor
	_controller._update_ghost_transform()


func _shot(suffix: String, _log_state: bool = false) -> void:
	for _i: int in range(TOGGLE_FRAMES):
		await get_tree().process_frame
	if not _controller.is_processing():
		await RenderingServer.frame_post_draw
		_save(suffix)
		return
	# The sandbox feed can reissue a piece at any time; re-pin the pose last.
	if _ghost.get_shape() == null or _ghost.get_shape().id != &"domino":
		_pose_ghost()
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save(suffix)


func _save(suffix: String) -> void:
	var image: Image = get_viewport().get_texture().get_image()
	var name: String = _prefix if suffix.is_empty() else "%s_%s" % [_prefix, suffix]
	var path: String = ProjectSettings.globalize_path("%s%s.png" % [OUTPUT_DIR, name])
	image.save_png(path)
	print("FEEL8A shot=%s state=%s footprint_y=%s quads=%d decal=%s saved=%s" % [
		name, _ghost.current_state(),
		_ghost.footprint_quad_position(0) if _ghost.footprint_quad_count() > 0 else Vector3.ZERO,
		_ghost.footprint_quad_count(), _ghost.block_projection_decal_visible(), path
	])


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().physics_frame
