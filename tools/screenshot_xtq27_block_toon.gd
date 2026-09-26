extends Node3D
## Windowed screenshot for Bontago-xtq.27 (M7 P2): two real spawned blocks
## (BlockFactory.build(), not build_visual_only()'s ghost path) show the
## toon-banded cel material, the UV-edge cell-grid face lines, and the
## inverted-hull outline pass -- but deliberately in TWO DIFFERENT settle
## states, so the per-instance "contributing" glow (block.sleeping -> true
## once settled -- see BlockFactory.build()'s own doc comment) is visibly ON
## for one block and OFF for the other in the same single capture:
## review MINOR (Bontago-xtq.27 fix round): the previous version waited for
## BOTH blocks to sleep before ever taking a shot, so the glow-off (baseline
## dark cell-grid lines, no glow) case was never actually shown. Block A
## (BLOCK_X_OFFSETS[0]) starts almost touching the field (SETTLED_DROP_
## HEIGHT) so it settles and sleeps almost immediately; block B
## (BLOCK_X_OFFSETS[1]) starts well above it (INFLIGHT_DROP_HEIGHT) so it is
## still airborne -- `sleeping == false`, glow off -- at the moment the loop
## below stops waiting (it only waits for block A).
##
## Brief-mandated SubViewport (1280x720, UPDATE_ALWAYS, own_world_3d=false):
## the light, environment, Field and both blocks are added directly under
## this node (the *main window's* World3D, since this scene is the run
## target), and only a Camera3D lives under the SubViewport --
## own_world_3d=false makes the SubViewport render that same World3D from
## its own camera, so the capture matches exactly what the blocks look like
## without duplicating any scene content.
##
## Run windowed, off-screen (a real render is required for the screenshot):
##   godot --path . --scene res://tools/screenshot_xtq27_block_toon.tscn --position 10000,10000
## Quits right after saving the capture -- see CLAUDE.md's windowed-run rules
## (never --always-on-top/--maximized).

const OUTPUT_PATH: String = "user://m7p2_block_toon.png"
const VIEWPORT_SIZE: Vector2i = Vector2i(1280, 720)
const BLOCK_X_OFFSETS: Array[float] = [-1.2, 1.2]
## Block A: already almost resting on the field, so it settles (and its glow
## turns on) within a handful of ticks.
const SETTLED_DROP_HEIGHT: float = 0.02
## Block B: dropped from well above block A so it is still comfortably
## airborne (glow off) by the time block A alone has settled -- see this
## file's own top-of-file doc comment for the fall-time/settle-time margin
## this relies on (physics_tuning.tres' sleep_settle_time is much shorter
## than the fall time from this height).
const INFLIGHT_DROP_HEIGHT: float = 3.0
const BLOCK_DROP_HEIGHTS: Array[float] = [SETTLED_DROP_HEIGHT, INFLIGHT_DROP_HEIGHT]
## Generous ceiling so a slow settle never hangs the run; the loop below
## exits early the moment block A (the "settled" one) reports asleep.
const MAX_SETTLE_TICKS: int = 300
## A few more ticks after block A first reads asleep, so its
## sleeping_state_changed-driven glow toggle (BlockFactory.build()) has
## definitely been applied before the frame we capture.
const EXTRA_SETTLE_TICKS: int = 10

var _tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
var _blocks: Array[Block] = []
var _sub_viewport: SubViewport


func _ready() -> void:
	_add_light_and_environment()

	var field: Field = Field.new()
	add_child(field)

	var shapes: Array[BlockShape] = BlockShape.load_all_shapes()
	var colors: PackedColorArray = MatchConfig.default_player_colors()
	for i: int in range(mini(BLOCK_X_OFFSETS.size(), shapes.size())):
		var block: Block = BlockFactory.build(shapes[i], _tuning, i, colors[i])
		add_child(block)
		block.global_position = Vector3(BLOCK_X_OFFSETS[i], BLOCK_DROP_HEIGHTS[i], 0.0)
		_blocks.append(block)

	_sub_viewport = _add_sub_viewport()
	var camera: Camera3D = Camera3D.new()
	_sub_viewport.add_child(camera)
	camera.current = true
	camera.global_position = Vector3(-2.0, 2.3, 5.0)
	camera.look_at(Vector3(0.0, 0.5, 0.0), Vector3.UP)

	var tick: int = 0
	while tick < MAX_SETTLE_TICKS and not _settled_block_asleep():
		await get_tree().physics_frame
		tick += 1
	for _i: int in range(EXTRA_SETTLE_TICKS):
		await get_tree().physics_frame

	print(
		(
			"SCREENSHOT xtq27_block_toon settle_ticks=%d settled_block_asleep=%s inflight_block_asleep=%s"
			% [tick, _settled_block_asleep(), _inflight_block_asleep()]
		)
	)
	await _shoot()
	get_tree().quit()


## Block A (BLOCK_X_OFFSETS[0], SETTLED_DROP_HEIGHT): the one this capture
## waits on -- once it sleeps, its "contributing" glow is on.
func _settled_block_asleep() -> bool:
	return _blocks[0].sleeping


## Block B (BLOCK_X_OFFSETS[1], INFLIGHT_DROP_HEIGHT): only read for the
## diagnostic print, never waited on -- it should still read false (glow
## off) at capture time, which is the whole point of this fix round.
func _inflight_block_asleep() -> bool:
	return _blocks[1].sleeping


func _add_sub_viewport() -> SubViewport:
	var container: SubViewportContainer = SubViewportContainer.new()
	container.stretch = true
	container.size = Vector2(VIEWPORT_SIZE)
	add_child(container)

	var sub_viewport: SubViewport = SubViewport.new()
	sub_viewport.size = VIEWPORT_SIZE
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub_viewport.own_world_3d = false
	container.add_child(sub_viewport)
	return sub_viewport


func _add_light_and_environment() -> void:
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.15, 0.15, 0.18)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.35, 0.35, 0.35)
	world_environment.environment = environment
	add_child(world_environment)

	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	light.light_energy = 1.2
	add_child(light)


func _shoot() -> void:
	await RenderingServer.frame_post_draw
	var image: Image = _sub_viewport.get_texture().get_image()
	image.save_png(OUTPUT_PATH)
	print("SCREENSHOT xtq27_block_toon saved=%s" % ProjectSettings.globalize_path(OUTPUT_PATH))
