extends Node
## Windowed evidence probe for Bontago-xtq.22 (owner: disc reflectivity is
## "hard to judge with that texture -- add an option to F4 to change the
## skybox"). Boots the owner's own path -- Main.tscn with the real
## `--headless-host --bots=<n> --players=<n>` command line, the same
## tools/screenshot_feel8b_disc_glare.gd pattern -- places a small cube stack
## near slot 0's home so the disc mirror has something recognizable to
## reflect, then calls game/Skybox.apply_set() through the live Skybox node
## (exactly the call ui/TuningPanel.gd's Skybox row makes) to switch between
## two discovered sets, saving a screenshot of the whole scene plus the raw
## DiscMirror SubViewport (game/DiscMirror.gd's own MirrorViewport child)
## after each switch:
##
##   <prefix>-<set>-scene.png   the full view (sky + disc + blocks)
##   <prefix>-<set>-mirror.png  DiscMirror's own per-pixel reflection texture
##
## Picks its two sets from Skybox.list_available_sets() (sorted, so the run is
## reproducible) rather than hard-coding names, so it still runs (with a
## printed warning and only one set shot) on a checkout with the third-party
## original textures not installed (tools/install_original_assets.ps1;
## CLAUDE.md/docs/AGENT_WORKFLOW.md: never committed to this public repo).
##
## Lives in tools/ (CLAUDE.md: manual-QA scripts, not part of the game).
##
##   godot --path . --position 10000,10000 \
##       --scene res://tools/screenshot_skybox_switch.tscn -- \
##       --headless-host --bots=1 --players=2 --port=47912 \
##       --prefix=xtq22-switch

const OUTPUT_DIR: String = "res://feedback/"
const PREFIX_ARG: String = "--prefix="
const DEFAULT_PREFIX: String = "xtq22-switch"
const SETTLE_FRAMES: int = 45
const CUBE_SHAPE: BlockShape = preload("res://config/blocks/cube.tres")
const _TERRITORY_TUNING: TerritoryTuning = preload("res://config/territory_tuning.tres")
const _PHYSICS_TUNING: PhysicsTuning = preload("res://config/physics_tuning.tres")
const BLOCK_COUNT: int = 3
const BLOCK_DROP_HEIGHT: float = 0.6
const BLOCK_DROP_STEP: float = 1.1
const BLOCK_SETTLE_FRAMES: int = 40
const PLAYING_POLL_MAX_FRAMES: int = 900

var _prefix: String = DEFAULT_PREFIX
var _main: Node = null
var _rig: CameraRig = null
var _field: Field = null
var _skybox: Skybox = null
var _mirror: DiscMirror = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_prefix = _string_arg(args, PREFIX_ARG, DEFAULT_PREFIX)

	_main = (load("res://game/Main.tscn") as PackedScene).instantiate()
	_field = _main.get_node("Field") as Field
	_rig = _main.get_node("CameraRig") as CameraRig
	_skybox = _main.get_node("Skybox") as Skybox
	_mirror = _main.get_node("DiscMirror") as DiscMirror

	var free_tuning: CameraTuning = (_rig.tuning as CameraTuning).duplicate(true) as CameraTuning
	free_tuning.follow_block = false
	_rig.tuning = free_tuning

	get_tree().root.add_child.call_deferred(_main)
	await get_tree().process_frame
	await get_tree().process_frame

	await _wait_for_playing()
	var spot: Vector3 = await _place_blocks()
	var target: Vector3 = Vector3(spot.x, 0.0, spot.z)
	_point(target, free_tuning.follow_distance)

	var available: PackedStringArray = Skybox.list_available_sets()
	print("XTQ22 discovered_sets=%s" % [available])
	if available.size() < 2:
		print(
			"XTQ22 fewer than two installed sets -- run " +
			"tools/install_original_assets.ps1 first for a real before/after " +
			"comparison. Shooting whatever is available instead."
		)

	if available.size() >= 1:
		await _apply_and_shoot(available[0])
	if available.size() >= 2:
		await _apply_and_shoot(available[available.size() - 1])
	if available.is_empty():
		await _apply_and_shoot(Skybox.PROCEDURAL_SET_ID)

	get_tree().quit()


func _apply_and_shoot(set_name: String) -> void:
	var result: bool = _skybox.apply_set(set_name)
	var label: String = set_name if set_name != Skybox.PROCEDURAL_SET_ID else "procedural"
	print("XTQ22 apply_set(%s)=%s fallback_active=%s" % [set_name, result, _skybox.fallback_active])
	await _frames(SETTLE_FRAMES)
	await _shoot_scene(label)
	_shoot_mirror(label)


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
		print("XTQ22 place step=%d reason=%s" % [step, reason])
		await _physics(BLOCK_SETTLE_FRAMES)
	return placed


func _point(target: Vector3, distance: float) -> void:
	_rig._target = target
	_rig._distance = distance
	_rig._pitch = deg_to_rad(-35.0)
	_rig._yaw = deg_to_rad(20.0)
	_rig._update_transform()
	_rig.reset_physics_interpolation()
	(_rig.get_node("Camera3D") as Camera3D).reset_physics_interpolation()


func _shoot_scene(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	_save(image, "%s-scene" % label)


func _shoot_mirror(label: String) -> void:
	var viewport: SubViewport = _mirror.get_node_or_null("MirrorViewport") as SubViewport
	if viewport == null:
		print("XTQ22 no mirror viewport")
		return
	_save(viewport.get_texture().get_image(), "%s-mirror" % label)


func _save(image: Image, label: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var path: String = OUTPUT_DIR + "%s-%s.png" % [_prefix, label]
	image.save_png(path)
	print("XTQ22 saved=%s" % ProjectSettings.globalize_path(path))


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
