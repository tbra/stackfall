extends Node
## Windowed smoke-shot of game/Main.tscn, for eyeballing the M2 build without
## playing it. Run it as an autoload-style extra scene alongside the game:
##   godot --path . --scene res://tools/screenshot_main.tscn
## It scripts a few placements through Match, waits, saves
## user://m2_main.png and quits.
##
## Lives in tools/ because it is not part of the running game (CLAUDE.md).

const OUTPUT_PATH: String = "user://m2_main.png"
## Seconds to let the match settle before the shot, so the countdown is over
## and the territory has solved at least once.
const WARMUP_SECONDS: float = 3.5
## Blocks each player lays before the shot, so the overlay has something to
## draw and the HUD has a height to report.
const BLOCKS_PER_PLAYER: int = 4
## Frames to let each placement settle.
const SETTLE_FRAMES: int = 42
## How far above the disk a scripted placement is released, in meters.
const PLACE_HEIGHT: float = 0.55

var _tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")
var _physics: PhysicsTuning = preload("res://config/physics_tuning.tres")
var _cube: BlockShape = preload("res://config/blocks/cube.tres")


func _ready() -> void:
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var field: Field = main.get_node("Field") as Field
	await _wait(int(WARMUP_SECONDS * Engine.physics_ticks_per_second))

	for step: int in range(BLOCKS_PER_PLAYER):
		for slot_id: int in range(Match.slot_count()):
			await _place_outward(field, slot_id, step)

	await _wait(Engine.physics_ticks_per_second)
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(OUTPUT_PATH)
	var ghost: GhostPreview = main.get_node("HotSeat/GhostPreview") as GhostPreview
	print("SCREENSHOT ghost shape=%s pos=%s state=%s" % [
		"null" if ghost.get_shape() == null else ghost.get_shape().id,
		ghost.global_position, ghost.current_state()
	])
	print("SCREENSHOT saved=%s size=%dx%d blocks=%d state=%d" % [
		ProjectSettings.globalize_path(OUTPUT_PATH),
		image.get_width(), image.get_height(),
		main.get_node("BlocksContainer").get_child_count(), Match.state()
	])
	get_tree().quit()


## Walks a slot's blocks out from its home flag toward the disk center, which
## is where the goal flag stands, so the shot shows territory reaching in.
func _place_outward(field: Field, slot_id: int, step: int) -> void:
	if Match.state() != Match.State.PLAYING or Match.active_slot() != slot_id:
		return
	var home: Vector2 = Match.slot(slot_id).home_position
	var inward: Vector2 = -home.normalized()
	var reach: float = _tuning.influence_base + _tuning.influence_k * _physics.cube_size
	var distance: float = _tuning.home_radius - _physics.cube_size + float(step) * reach * 0.5
	var spot: Vector3 = field.world_from_disk_local(home + inward * distance, PLACE_HEIGHT)
	Match._held_shapes[slot_id] = _cube
	Match.request_place(slot_id, spot, 0, Quaternion.IDENTITY, false)
	await _wait(SETTLE_FRAMES)


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().physics_frame
