extends Node
## Windowed evidence probe for Bontago-xtq.20 (owner, 2026-09-23: "graphics
## flickering, the main light source is super visible in the reflection",
## then on c50510c "none of the feel issues were fixed").
##
## Boots the owner's own path: Main.tscn with the real
## `--headless-host --bots=<n> --players=<n>` command line (Main._ready()
## reads it exactly as it does in a normal launch), so the disc, DiscMirror,
## Skybox (the installed original 'lake' set when assets/original/ exists),
## ReflectionProbe, SSR and DirectionalLight3D are all the shipped ones.
## Places a small cube stack for slot 0, then aims the camera at the disc from
## the SUN'S side (the view ray's mirror image points at the light, i.e.
## where a specular highlight of that light lands) and captures:
##
##   <prefix>-sun.png        follow-distance shot, pitch == sun elevation
##   <prefix>-sun-low.png    shallow shot toward the sun's azimuth
##   <prefix>-static-<i>.png FRAME_BURST consecutive frames with the tree
##                           paused (camera, bots and physics frozen), so any
##                           frame-to-frame pixel change is render instability
##   <prefix>-mirror.png     game/DiscMirror.gd's SubViewport contents
##   <prefix>-orbit-<i>.png  consecutive frames while the camera orbits slowly
##
## `--bisect` additionally re-shoots the sun view with one reflection/lighting
## contributor toggled off at a time (<prefix>-bisect-<name>.png plus a burst
## for each). Intended animations (rim/outline pulse, contested shimmer) are
## zeroed on a duplicated TerritoryVisuals for the whole run so they cannot
## masquerade as flicker in the frame diffs; the shipped resource is never
## written. Frame diffs are computed offline from the saved PNGs.
##
##   godot --path . --position 10000,10000 \
##       --scene res://tools/screenshot_feel8b_disc_glare.tscn -- \
##       --headless-host --bots=1 --players=2 --port=47911 \
##       --prefix=feel8b-before --bisect [--ghost-bisect]
##
## `--ghost-bisect` repeats the orbit with the tree paused and one live
## GhostPreview part hidden at a time (footprint quads, block-projection
## Decal, prism, whole ghost) -- <prefix>-ghost-<case>-<i>.png.
##
## Lives in tools/ (CLAUDE.md: manual-QA scripts, not part of the game).

const OUTPUT_DIR: String = "res://feedback/"
const PREFIX_ARG: String = "--prefix="
const BISECT_ARG: String = "--bisect"
## Re-shoots the orbit with one GhostPreview/disc element hidden at a time
## (read-only visibility toggles on live nodes; GhostPreview.gd is not edited)
## to localise the moving-camera speckle at the ghost's footprint.
const GHOST_BISECT_ARG: String = "--ghost-bisect"
const DEFAULT_PREFIX: String = "feel8b"
const SETTLE_FRAMES: int = 45
const FRAME_BURST: int = 4
const ORBIT_FRAMES: int = 4
const ORBIT_STEP_DEG: float = 0.4
const LOW_PITCH_DEG: float = -12.0
const BOT_PLAY_SECONDS: float = 6.0
const PLAYING_POLL_MAX_FRAMES: int = 900
const CUBE_SHAPE: BlockShape = preload("res://config/blocks/cube.tres")
const _TERRITORY_TUNING: TerritoryTuning = preload("res://config/territory_tuning.tres")
const _PHYSICS_TUNING: PhysicsTuning = preload("res://config/physics_tuning.tres")
const BLOCK_COUNT: int = 3
const BLOCK_DROP_HEIGHT: float = 0.6
const BLOCK_DROP_STEP: float = 1.1
const BLOCK_SETTLE_FRAMES: int = 40

var _prefix: String = DEFAULT_PREFIX
var _main: Node = null
var _rig: CameraRig = null
var _field: Field = null
var _skybox: Skybox = null
var _mirror: DiscMirror = null
var _light: DirectionalLight3D = null
var _visuals: TerritoryVisuals = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_prefix = _string_arg(args, PREFIX_ARG, DEFAULT_PREFIX)
	var bisect: bool = args.has(BISECT_ARG)
	var ghost_bisect: bool = args.has(GHOST_BISECT_ARG)

	_main = (load("res://game/Main.tscn") as PackedScene).instantiate()
	_field = _main.get_node("Field") as Field
	_rig = _main.get_node("CameraRig") as CameraRig
	_skybox = _main.get_node("Skybox") as Skybox
	_mirror = _main.get_node("DiscMirror") as DiscMirror
	_light = _main.get_node("DirectionalLight3D") as DirectionalLight3D

	_visuals = (_field.visuals as TerritoryVisuals).duplicate(true) as TerritoryVisuals
	_visuals.rim_pulse_depth = 0.0
	_visuals.outline_pulse_depth = 0.0
	_visuals.contested_shimmer_strength = 0.0
	_field.visuals = _visuals
	_skybox.visuals = _visuals
	_mirror.visuals = _visuals

	var free_tuning: CameraTuning = (_rig.tuning as CameraTuning).duplicate(true) as CameraTuning
	free_tuning.follow_block = false
	_rig.tuning = free_tuning

	get_tree().root.add_child.call_deferred(_main)
	await get_tree().process_frame
	await get_tree().process_frame

	await _wait_for_playing()
	var spot: Vector3 = await _place_blocks()
	await get_tree().create_timer(BOT_PLAY_SECONDS).timeout

	var to_sun: Vector3 = _light.global_transform.basis.z.normalized()
	var sun_yaw_deg: float = rad_to_deg(atan2(-to_sun.x, -to_sun.z))
	var sun_elev_deg: float = rad_to_deg(asin(clampf(to_sun.y, -1.0, 1.0)))
	var target: Vector3 = Vector3(spot.x, 0.0, spot.z)
	print("FEEL8B state=%s spot=%s to_sun=%s sun_yaw=%.1f sun_elev=%.1f skybox_fallback=%s window=%s" % [
		Match.state(), spot, to_sun, sun_yaw_deg, sun_elev_deg, _skybox.fallback_active,
		get_viewport().size,
	])
	print("FEEL8B light energy=%.2f specular=%.2f angular=%.2f metallic=%.2f roughness=%.2f" % [
		_light.light_energy, _light.light_specular, _light.light_angular_distance,
		_visuals.disk_metallic, _visuals.disk_roughness,
	])

	var follow_distance: float = free_tuning.follow_distance
	_point(target, follow_distance, sun_yaw_deg, -sun_elev_deg)
	await _frames(SETTLE_FRAMES)
	await _shoot("sun")
	_point(target, follow_distance * 1.6, sun_yaw_deg, LOW_PITCH_DEG)
	await _frames(SETTLE_FRAMES)
	await _shoot("sun-low")

	# Static burst: pause everything but this node, so the only thing that can
	# change between frames is the renderer itself.
	_point(target, follow_distance, sun_yaw_deg + 20.0, -sun_elev_deg)
	await _frames(SETTLE_FRAMES)
	get_tree().paused = true
	await _burst("static")
	_save_mirror("mirror")
	get_tree().paused = false

	# Slow orbit: consecutive frames while the camera moves, the owner's own
	# "orbiting shimmers" case.
	var orbit_yaw: float = _rig._yaw
	await _orbit("orbit")

	if ghost_bisect:
		var ghosts: Array[Node] = get_tree().root.find_children("*", "GhostPreview", true, false)
		print("FEEL8B ghosts=%d" % ghosts.size())
		for node: Node in ghosts:
			var ghost: GhostPreview = node as GhostPreview
			print("FEEL8B ghost=%s result=%s locked=%s footprints=%d" % [
				ghost.get_path(), ghost._last_result, ghost._locked, ghost._footprint_quads.size(),
			])
		await _ghost_case("baseline", ghosts, &"none", orbit_yaw)
		await _ghost_case("footprint-off", ghosts, &"footprint", orbit_yaw)
		await _ghost_case("decal-off", ghosts, &"decal", orbit_yaw)
		await _ghost_case("prism-off", ghosts, &"prism", orbit_yaw)
		await _ghost_case("ghost-off", ghosts, &"all", orbit_yaw)

	if bisect:
		_point(target, follow_distance, sun_yaw_deg, -sun_elev_deg)
		await _bisect_case("baseline", func() -> void: pass, func() -> void: pass)
		await _bisect_case("mirror-off",
			func() -> void: _visuals.mirror_enabled = false,
			func() -> void: _visuals.mirror_enabled = true)
		await _bisect_case("ssr-off",
			_set_ssr.bind(false), _set_ssr.bind(true))
		await _bisect_case("probe-off",
			_set_probe.bind(false), _set_probe.bind(true))
		var spec: float = _light.light_specular
		await _bisect_case("light-spec0",
			func() -> void: _light.light_specular = 0.0,
			func() -> void: _light.light_specular = spec)
		await _bisect_case("metal02",
			func() -> void: _field.overlay().material().set_shader_parameter(&"base_metallic", 0.2),
			func() -> void: _field.overlay().material().set_shader_parameter(&"base_metallic", _visuals.disk_metallic))
		await _bisect_case("shadows-off",
			func() -> void: _light.shadow_enabled = false,
			func() -> void: _light.shadow_enabled = true)
	get_tree().quit()


func _orbit(label: String, frozen: bool = false) -> void:
	for i: int in range(ORBIT_FRAMES):
		_rig._yaw += deg_to_rad(ORBIT_STEP_DEG)
		if frozen:
			# Tree paused: the rig does not process, so apply the pose here.
			_rig._update_transform()
			_rig.reset_physics_interpolation()
			(_rig.get_node("Camera3D") as Camera3D).reset_physics_interpolation()
		await _shoot("%s-%d" % [label, i])


func _ghost_case(case_name: String, ghosts: Array[Node], part: StringName, yaw: float) -> void:
	_rig._yaw = yaw
	await _frames(SETTLE_FRAMES)
	get_tree().paused = true
	_set_ghost_parts(ghosts, part, false)
	await _frames(2)
	await _orbit("ghost-%s" % case_name, true)
	_set_ghost_parts(ghosts, part, true)
	get_tree().paused = false


func _set_ghost_parts(ghosts: Array[Node], part: StringName, shown: bool) -> void:
	for node: Node in ghosts:
		var ghost: GhostPreview = node as GhostPreview
		match part:
			&"none":
				pass
			&"footprint":
				for quad: MeshInstance3D in ghost._footprint_quads:
					quad.visible = shown
			&"decal":
				if ghost._block_projection_decal != null:
					ghost._block_projection_decal.visible = shown
			&"prism":
				if ghost._projection_mesh != null:
					ghost._projection_mesh.visible = shown
			_:
				ghost.visible = shown


func _set_ssr(enabled: bool) -> void:
	_visuals.ssr_enabled = enabled
	_skybox.refresh_from_visuals()


func _set_probe(enabled: bool) -> void:
	_visuals.reflection_probe_enabled = enabled
	_skybox.refresh_from_visuals()


func _bisect_case(case_name: String, apply: Callable, restore: Callable) -> void:
	apply.call()
	await _frames(SETTLE_FRAMES)
	get_tree().paused = true
	await _burst("bisect-%s" % case_name)
	get_tree().paused = false
	restore.call()


func _burst(label: String) -> void:
	for i: int in range(FRAME_BURST):
		await _shoot("%s-%d" % [label, i])


func _wait_for_playing() -> void:
	var frames: int = 0
	while Match.state() != Match.State.PLAYING and frames < PLAYING_POLL_MAX_FRAMES:
		await get_tree().physics_frame
		frames += 1


func _place_blocks() -> Vector3:
	var fallback: Vector3 = Vector3.ZERO
	if Match.slot_count() <= 0:
		return fallback
	var home: Vector2 = Match.slot(0).home_position
	var inset: float = maxf(_TERRITORY_TUNING.home_radius - _PHYSICS_TUNING.cube_size, 0.5)
	var disk_spot: Vector2 = home - home.normalized() * inset
	var placed: Vector3 = _field.world_from_disk_local(disk_spot, 0.0)
	for step: int in range(BLOCK_COUNT):
		var world_spot: Vector3 = _field.world_from_disk_local(
			disk_spot, BLOCK_DROP_HEIGHT + float(step) * BLOCK_DROP_STEP
		)
		Match._held_shapes[0] = CUBE_SHAPE
		var reason: StringName = Match.request_place(0, world_spot, 0, Quaternion.IDENTITY, false)
		print("FEEL8B place step=%d reason=%s" % [step, reason])
		await _physics(BLOCK_SETTLE_FRAMES)
	return placed


func _point(target: Vector3, distance: float, yaw_deg: float, pitch_deg: float) -> void:
	_rig._target = target
	_rig._distance = distance
	_rig._pitch = deg_to_rad(pitch_deg)
	_rig._yaw = deg_to_rad(yaw_deg)
	_rig._update_transform()
	_rig.reset_physics_interpolation()
	(_rig.get_node("Camera3D") as Camera3D).reset_physics_interpolation()


func _shoot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	_save(image, label)


func _save_mirror(label: String) -> void:
	var viewport: SubViewport = _mirror.get_node_or_null("MirrorViewport") as SubViewport
	if viewport == null:
		print("FEEL8B no mirror viewport")
		return
	_save(viewport.get_texture().get_image(), label)


func _save(image: Image, label: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var path: String = OUTPUT_DIR + "%s-%s.png" % [_prefix, label]
	image.save_png(path)
	print("FEEL8B saved=%s" % ProjectSettings.globalize_path(path))


func _frames(count: int) -> void:
	for _i: int in range(count):
		await get_tree().process_frame


func _physics(count: int) -> void:
	for _i: int in range(count):
		await get_tree().physics_frame


func _string_arg(args: PackedStringArray, prefix: String, fallback: String) -> String:
	for arg: String in args:
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return fallback
