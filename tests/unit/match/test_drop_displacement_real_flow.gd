extends GutTest
## through the real Main scene, the next piece loading under a just-dropped block must not lift
## the ghost or camera, and a needed raise waits until the dropped block has settled.

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")
const HOST_SLOT: int = 0
## How far the held piece hangs above A's top when the player drops B (the
## owner's screenshots read "Block: 2.2 m").
const DROP_GAP_M: float = 1.5
const SETTLE_MAX_FRAMES: int = 600
const CAMERA_SETTLE_FRAMES: int = 180
const WATCH_FRAMES: int = 150
## A dropped block that falls clear of the next ghost must not lift it: any
## rise above the player's own hover is the displacement the user reports.
const MAX_GHOST_RISE_M: float = 0.05
const MAX_CAMERA_RISE_M: float = 0.05

var _main: Variant = null
var _tiny_map: MapDef

var _saved_feed_config: BlockFeedConfig = null


func before_each() -> void:
	# synthetic events parsed into the global Input singleton stay latched
	# (stick axis, ui_* actions) for every later script in the same process; clear them.
	Input.flush_buffered_events()
	for action: StringName in InputMap.get_actions():
		Input.action_release(action)
	Match.set_process(false)
	Match.abort_match()
	_pin_feed_to_convex_shape()
	SnapshotSync.end_match()
	_main = MAIN_SCENE.instantiate()
	_tiny_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	(_main.get_node("Field") as Field).map_def = _tiny_map
	var config: MatchConfig = (load("res://config/match/match_defaults.tres") as MatchConfig).duplicate(true)
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.rng_seed = 13579
	_main.match_config = config
	add_child_autofree(_main)

## DECISION: these tests aim at a placed block's origin or rely on the
## held piece being solid there, which fails for concave shapes (u5, arch5, corner4, stair6)
## now in the random feed. Pin the feed to the cube; the shape mix is not under test.
func _pin_feed_to_convex_shape() -> void:
	_saved_feed_config = Match._block_feed_config
	var pinned: BlockFeedConfig = _saved_feed_config.duplicate() as BlockFeedConfig
	pinned.shapes = [load("res://config/blocks/cube.tres") as BlockShape]
	pinned.weight_overrides = PackedFloat32Array()
	Match._block_feed_config = pinned


func after_each() -> void:
	Net.leave()
	Match._block_feed_config = _saved_feed_config
	Match.abort_match()
	SnapshotSync.end_match()
	Match.set_process(true)
	await get_tree().process_frame
	await get_tree().process_frame


func _start_hosted_match() -> void:
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "Hostie"), OK)
	_main._start_headless_bot_match_with_args(PackedStringArray(["--bots=1", "--players=2"]))
	await get_tree().process_frame
	await get_tree().process_frame
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)
	assert_eq(Match.state(), Match.State.PLAYING, "fixture should reach PLAYING")
	await get_tree().process_frame
	await get_tree().process_frame


func _controller() -> PlayerController:
	return _main._local_player.controller()


func _ghost() -> GhostPreview:
	return _main._local_player.ghost()


func _field_surface_y() -> float:
	return (_main.get_node("Field") as Field).surface_y()


## The player's wheel notch down, delivered the way the Input Map delivers it.
func _wheel_down() -> void:
	var wheel: InputEventMouseButton = InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	_controller()._unhandled_input(wheel)


## The ghost_place press the Input Map delivers.
func _click_place() -> void:
	var press: InputEventAction = InputEventAction.new()
	press.action = &"ghost_place"
	press.pressed = true
	_controller()._unhandled_input(press)


## The held piece is parked over `cursor` (the seed the game gives a slot) and wheeled down to the floor.
func _park_over(cursor: Vector3) -> void:
	_controller().set_home_position(cursor)
	_player_lowers_first_piece_to_the_floor()


func _held_overlaps_a_placed_block() -> bool:
	return GhostOverlapProbe.overlaps_placed_block(_controller().get_viewport().world_3d, _ghost())


## the match's first piece now starts raised clear of the home
## beacon (PlayerController.set_home_position()). These tests exercise the
## ordinary hover, so the player first wheels it back down to the floor -- the
## same input that makes any raise their own -- which restores the geometry
## they were written against.
func _player_lowers_first_piece_to_the_floor() -> void:
	_ghost().manual_hover_offset = 0.0
	_wheel_down()


## One engine frame: a physics tick and the controller's own _process.
func _frame() -> void:
	await wait_physics_frames(1)
	await get_tree().process_frame


func _place() -> Block:
	var captured: Array[Block] = []
	var grab: Callable = func(block: RigidBody3D, _shape_id: StringName) -> void:
		captured.append(block as Block)
	Events.block_placed.connect(grab)
	_click_place()
	Events.block_placed.disconnect(grab)
	assert_eq(captured.size(), 1, "the host accepts the drop")
	return captured[0] if not captured.is_empty() else null


func _wait_settled(block: Block) -> void:
	for _i: int in range(SETTLE_MAX_FRAMES):
		if block.sleeping:
			return
		await _frame()


func _top_y(block: Block) -> float:
	var top: float = -INF
	for child: Node in block.get_children():
		var collision: CollisionShape3D = child as CollisionShape3D
		if collision == null or not collision.shape is BoxShape3D:
			continue
		var half: Vector3 = (collision.shape as BoxShape3D).size * 0.5
		for x: float in [-half.x, half.x]:
			for y: float in [-half.y, half.y]:
				for z: float in [-half.z, half.z]:
					top = maxf(top, (block.global_transform * (collision.transform * Vector3(x, y, z))).y)
	return top


func _drift(a: Transform3D, b: Transform3D) -> Array[float]:
	var angle: float = a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion())
	return [a.origin.distance_to(b.origin), angle]


## The owner's stacking drop. Returns
## {ghost_rise, camera_rise, a_drift, a_rot, b_rot}.
func _stack_drop_trace() -> Dictionary:
	await _start_hosted_match()
	_player_lowers_first_piece_to_the_floor()
	var controller: PlayerController = _controller()
	var ghost: GhostPreview = _ghost()
	var rig: CameraRig = _main._camera_rig
	# Two metres in from the home flag, toward the disk centre (own territory).
	# the first spawn now sits home_spawn_back_offset outward of
	# the flag, so measure from the flag itself to keep this fixture's geometry
	# (A's spot, and B tumbling clear of it) exactly as it was written.
	var home: Vector3 = Match.default_ghost_origin(HOST_SLOT)
	var inward: Vector3 = Vector3(-home.x, 0.0, -home.z).normalized()
	_park_over(home + inward * (2.0 + controller.ghost_tuning.home_spawn_back_offset))
	for _i: int in range(5):
		await _frame()
	var a: Block = _place()
	await _wait_settled(a)
	for _i: int in range(10):
		await _frame()
	Match._feed._release_locked[HOST_SLOT] = false
	Match._feed._feed_time_left[HOST_SLOT] = Match.config.block_timer
	Match._feed._feed_expired[HOST_SLOT] = false
	# The player wheels the held piece up so it hangs DROP_GAP_M above A.
	var player_offset: float = maxf(_top_y(a) - _field_surface_y() - controller.tuning.hover_height, 0.0) + DROP_GAP_M
	# one wheel notch down from a notch above the target, so the hover is the player's own
	ghost.manual_hover_offset = player_offset + controller.ghost_tuning.hover_wheel_step
	_wheel_down()
	# Let the follow camera finish easing onto the player's own new hover.
	for _i: int in range(CAMERA_SETTLE_FRAMES):
		await _frame()
	player_offset = ghost.manual_hover_offset
	var a_before: Transform3D = a.global_transform
	var cam_before: float = rig.get_target().y
	var b: Block = _place()
	var b_released: Transform3D = b.global_transform
	var ghost_rise: float = 0.0
	var camera_rise: float = 0.0
	var a_drift: float = 0.0
	var a_rot: float = 0.0
	for i: int in range(WATCH_FRAMES):
		await _frame()
		ghost_rise = maxf(ghost_rise, ghost.manual_hover_offset - player_offset)
		camera_rise = maxf(camera_rise, rig.get_target().y - cam_before)
		var d: Array[float] = _drift(a_before, a.global_transform)
		a_drift = maxf(a_drift, d[0])
		a_rot = maxf(a_rot, d[1])
		if i % 10 == 0:
			gut.p("f%03d ghost_off=%.3f cam_y=%.3f B_y=%.3f B_sleep=%s A_drift=%.4f" % [
				i, ghost.manual_hover_offset, rig.get_target().y,
				b.global_position.y, b.sleeping, d[0],
			])
	var b_rot: float = _drift(b_released, b.global_transform)[1]
	var result: Dictionary = {
		"ghost_rise": ghost_rise, "camera_rise": camera_rise, "a_drift": a_drift, "a_rot": a_rot, "b_rot": b_rot,
	}
	gut.p("RESULT %s" % [result])
	return result


func test_next_piece_is_not_displaced_by_the_block_just_dropped_under_it() -> void:
	var result: Dictionary = await _stack_drop_trace()
	assert_lte(
		float(result["ghost_rise"]), MAX_GHOST_RISE_M,
		"the next ghost must not be pushed up by the still-falling block it loaded inside (was %.3f m)" % float(result["ghost_rise"])
	)
	assert_lte(
		float(result["camera_rise"]), MAX_CAMERA_RISE_M,
		"and the camera that follows it must not jump (was %.3f m)" % float(result["camera_rise"])
	)


## The case where a raise is genuinely needed: a drop at the player's default
## hover onto bare disk leaves the dropped block resting inside the space the
## next piece occupies. The raise must wait for that block to settle (never
## while it is still falling) and then lift the ghost clear of it.
func test_a_raise_waits_for_the_dropped_block_to_settle_then_clears_it() -> void:
	await _start_hosted_match()
	_player_lowers_first_piece_to_the_floor()
	var controller: PlayerController = _controller()
	var ghost: GhostPreview = _ghost()
	var home: Vector3 = Match.default_ghost_origin(HOST_SLOT)
	_park_over(home + Vector3(-home.x, 0.0, -home.z).normalized() * 2.0)
	for _i: int in range(5):
		await _frame()
	var player_offset: float = ghost.manual_hover_offset
	var a: Block = _place()
	var rise_while_unsettled: float = 0.0
	var settled_at: int = -1
	for i: int in range(SETTLE_MAX_FRAMES):
		await _frame()
		if not a.sleeping:
			rise_while_unsettled = maxf(rise_while_unsettled, ghost.manual_hover_offset - player_offset)
		elif settled_at < 0:
			settled_at = i
		if settled_at >= 0 and i > settled_at + 5:
			break
	gut.p("ground drop: settled_at=f%d rise_while_unsettled=%.3f final_offset=%.3f overlaps=%s" % [
		settled_at, rise_while_unsettled, ghost.manual_hover_offset, _held_overlaps_a_placed_block(),
	])
	assert_gte(settled_at, 0, "fixture: the dropped block comes to rest")
	assert_lte(rise_while_unsettled, MAX_GHOST_RISE_M, "no raise while the dropped block is still moving")
	assert_gt(ghost.manual_hover_offset, player_offset, "once it rests inside the next piece, the piece is raised")
	assert_false(_held_overlaps_a_placed_block(), "and clears it")

