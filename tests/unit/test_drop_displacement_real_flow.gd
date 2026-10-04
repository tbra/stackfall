extends GutTest
## Bontago-1pi.24 (owner playtest 2026-10-02: "block displacement, no change at
## all, exactly the same issue"; earlier: "when dropping a block the next block
## loads instantly which means it's always inside a block when spawning. Fix:
## don't run for disabled ghost blocks? Don't count the dropped block until
## it's settled? Only count settled blocks? Small delay?").
##
## Real flow, not a synthetic overlap: the real Main scene, a real host, the
## HotSeat PlayerController/GhostPreview/CameraRig Main wires for slot 0, the
## real GhostTuning/PhysicsTuning, and every frame driven by the engine's own
## _process/_physics_process. The player stacks: a block A rests on the disk,
## the player wheels the held piece up so it hangs clear above A, and drops it
## (B). The next piece appears at once at the very same pose, i.e. inside B
## while B is still falling. Traced per frame: the next ghost's hover offset,
## the camera's follow target, and A/B's own poses.

const MAIN_SCENE: PackedScene = preload("res://game/Main.tscn")
const HOST_SLOT: int = 0
## How far the held piece hangs above A's top when the player drops B (the
## owner's screenshots read "Block: 2.2 m").
const DROP_GAP_M: float = 1.5
const SETTLE_MAX_FRAMES: int = 600
const CAMERA_SETTLE_FRAMES: int = 180
const WATCH_FRAMES: int = 150
## A dropped block that falls clear of the next ghost must not lift it: any
## rise above the player's own hover is the displacement the owner reports.
const MAX_GHOST_RISE_M: float = 0.05
const MAX_CAMERA_RISE_M: float = 0.05

var _main: Variant = null
var _tiny_map: MapDef


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
	_main = MAIN_SCENE.instantiate()
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	(_main.get_node("Field") as Field).map_def = _tiny_map
	var config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true)
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.rng_seed = 13579
	_main.match_config = config
	add_child_autofree(_main)


func after_each() -> void:
	Net.leave()
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
	return _main._hot_seat.controller()


## Bontago-1pi.33: the match's first piece now starts raised clear of the home
## beacon (PlayerController.set_home_position()). These tests exercise the
## ordinary hover, so the player first wheels it back down to the floor -- the
## same input that makes any raise their own -- which restores the geometry
## they were written against.
func _player_lowers_first_piece_to_the_floor() -> void:
	_controller()._ghost.manual_hover_offset = 0.0
	_controller()._absorb_clearance_raise()


## One engine frame: a physics tick and the controller's own _process.
func _frame() -> void:
	await wait_physics_frames(1)
	await get_tree().process_frame


func _place() -> Block:
	var captured: Array[Block] = []
	var grab: Callable = func(block: RigidBody3D, _shape_id: StringName) -> void:
		captured.append(block as Block)
	Events.block_placed.connect(grab)
	var reason: StringName = _controller()._request_place(false)
	Events.block_placed.disconnect(grab)
	assert_eq(reason, PlacementRules.REASON_OK, "the host accepts the drop")
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
	var ghost: GhostPreview = controller._ghost
	var rig: CameraRig = _main._camera_rig
	# Two metres in from the home flag, toward the disk centre (own territory).
	# Bontago-1pi.64: the first spawn now sits home_spawn_back_offset outward of
	# the flag, so measure from the flag itself to keep this fixture's geometry
	# (A's spot, and B tumbling clear of it) exactly as it was written.
	var home: Vector3 = controller._cursor
	var inward: Vector3 = Vector3(-home.x, 0.0, -home.z).normalized()
	controller._cursor = home + inward * (2.0 + controller.ghost_tuning.home_spawn_back_offset)
	controller._last_safe_cursor = controller._cursor
	for _i: int in range(5):
		await _frame()
	var a: Block = _place()
	await _wait_settled(a)
	for _i: int in range(10):
		await _frame()
	Match.debug_unlock_slot(HOST_SLOT)
	# The player wheels the held piece up so it hangs DROP_GAP_M above A.
	var player_offset: float = maxf(_top_y(a) - controller._last_hit_point.y - controller.tuning.hover_height, 0.0) + DROP_GAP_M
	ghost.manual_hover_offset = player_offset
	controller._absorb_clearance_raise()
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
			gut.p("f%03d ghost_off=%.3f raise=%.3f cam_y=%.3f B_y=%.3f B_sleep=%s A_drift=%.4f" % [
				i, ghost.manual_hover_offset, controller._clearance_raise, rig.get_target().y,
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
	var ghost: GhostPreview = controller._ghost
	var home: Vector3 = controller._cursor
	controller._cursor = home + Vector3(-home.x, 0.0, -home.z).normalized() * 2.0
	controller._last_safe_cursor = controller._cursor
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
		settled_at, rise_while_unsettled, ghost.manual_hover_offset, controller._ghost_overlaps_a_placed_block(),
	])
	assert_gte(settled_at, 0, "fixture: the dropped block comes to rest")
	assert_lte(rise_while_unsettled, MAX_GHOST_RISE_M, "no raise while the dropped block is still moving")
	assert_gt(ghost.manual_hover_offset, player_offset, "once it rests inside the next piece, the piece is raised")
	assert_false(controller._ghost_overlaps_a_placed_block(), "and clears it")


## Bontago-1pi.33 (owner playtest 2026-10-03: "Start the first block higher up,
## it loads inside the home beacon currently"): through the real Main wiring
## (Main -> HotSeat.bind_local_slot() -> set_home_position()), the first held
## piece hangs above the home beacon's top by the tuned margin.
func test_first_piece_in_the_real_match_starts_clear_of_the_home_beacon() -> void:
	await _start_hosted_match()
	for _i: int in range(5):
		await _frame()
	var controller: PlayerController = _controller()
	assert_not_null(controller._ghost.get_shape(), "fixture: the first piece is held")
	var beacon_top: float = Match.field().global_position.y + controller.beacon_visuals.beacon_top_height()
	var lowest: float = controller._ghost.height_above_surface() + controller._last_hit_point.y
	assert_gte(
		lowest, beacon_top + controller.ghost_tuning.home_spawn_beacon_margin - 0.0001,
		"the first held piece's lowest point (%.3f) must clear the home beacon top (%.3f) plus margin" % [lowest, beacon_top]
	)
