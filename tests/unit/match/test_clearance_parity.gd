extends GutTest
## A released plain block that overlaps a settled one is lifted just clear by two
## independent searches: the host (Match.request_place, fed the pose the client
## ghost showed before its own lift) and the client (the lift the PlayerController
## applies to its ghost on release). The player sees the client ghost, the host
## spawns the block, so the two raised poses must agree within the search's own
## precision. Scope: plain blocks at the unfaced pose over placed blocks (enlarged
## gifts and faced throws use a different overlap query).
##
## Fixture follows test_playercontroller_spawn_clearance.gd: tiny map, real
## Field/Match, no live peer, so Match.request_place() resolves host-inline.

const SETTLE_MAX_FRAMES: int = 240
const HOME_SLOT: int = 0
## The controller listens to feed events of its acting slot only; during the host
## phase it acts for this other seat so the host spawn cannot move its ghost.
const OTHER_SLOT: int = 1

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef
var _saved_feed_config: BlockFeedConfig = null
var _tuning: GhostTuning = load("res://config/blocks/tuning/ghost_tuning.tres") as GhostTuning


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_saved_feed_config = Match._block_feed_config
	var pinned: BlockFeedConfig = _saved_feed_config.duplicate() as BlockFeedConfig
	pinned.shapes = [load("res://config/blocks/cube.tres") as BlockShape]
	pinned.weight_overrides = PackedFloat32Array()
	Match._block_feed_config = pinned
	_tiny_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _tiny_map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)


func after_each() -> void:
	Match._block_feed_config = _saved_feed_config
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _config() -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.block_timer = 6.0
	config.rng_seed = 24680
	return config


func _start_match() -> void:
	Match.start_match(_config())
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)
	# unlimited releases: no per-interval release lock between the fixture's drops
	Match._feed.set_feed_timer_enabled(false)


func _make_controller() -> PlayerController:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	var controller: PlayerController = autofree(PlayerController.new())
	controller.ghost_tuning = controller.ghost_tuning.duplicate() as GhostTuning
	controller.ghost_tuning.spawn_clearance_enabled = true
	add_child_autofree(controller)
	controller._ghost = ghost
	controller.set_acting_slot(OTHER_SLOT)
	controller._ghost.set_shape(Match.held_shape(HOME_SLOT))
	var home: Vector2 = Match.slot(HOME_SLOT).home_position
	controller._cursor = _field.to_global(Vector3(home.x, 5.0, home.y))
	return controller


## The pose the ghost shows at `hover_offset`, before any release lift.
func _ghost_pose(controller: PlayerController, hover_offset: float) -> Transform3D:
	controller._ghost.manual_hover_offset = hover_offset
	controller._update_ghost_transform()
	return controller._ghost.global_transform


## Host request path. Returns the block it spawned (null if refused).
func _host_place(pose: Transform3D, controller: PlayerController) -> Block:
	var captured: Array[Block] = []
	var grab: Callable = func(block: RigidBody3D, _shape_id: StringName) -> void:
		captured.append(block as Block)
	Events.block_placed.connect(grab)
	var reason: StringName = Match.request_place(
		HOME_SLOT, pose.origin, controller._ghost.orientation_index, controller._ghost.free_quaternion, false
	)
	Events.block_placed.disconnect(grab)
	assert_eq(reason, PlacementRules.REASON_OK, "the host accepts the release")
	return captured[0] if not captured.is_empty() else null


func _wait_settled(block: Block) -> void:
	for _i: int in range(SETTLE_MAX_FRAMES):
		if block.sleeping:
			return
		await wait_physics_frames(1)


## Builds a tower of settled blocks on the home spot through the host path.
func _build_tower(controller: PlayerController, height: int) -> void:
	for _i: int in range(height):
		var block: Block = _host_place(_ghost_pose(controller, 0.0), controller)
		await _wait_settled(block)


## Host lift (unlifted pose in) vs client release lift (same pose), as rises in
## metres. Returns {host, client, clear}.
func _lifts_for(tower_height: int, hover_offset: float) -> Dictionary:
	_start_match()
	var controller: PlayerController = _make_controller()
	await _build_tower(controller, tower_height)
	var unlifted: Transform3D = _ghost_pose(controller, hover_offset)
	var clear_already: bool = not controller._ghost_overlaps_a_placed_block()
	# host search on its own, from the unlifted pose; its block is then removed
	var host_block: Block = _host_place(unlifted, controller)
	var host_rise: float = host_block.global_position.y - unlifted.origin.y
	host_block.get_parent().remove_child(host_block)
	host_block.free()
	await wait_physics_frames(2)
	# client lift: the controller's own release of the same pose
	controller.set_acting_slot(HOME_SLOT)
	var shown: Vector3 = _ghost_pose(controller, hover_offset).origin
	assert_eq(shown, unlifted.origin, "fixture: the ghost shows the same unlifted pose")
	assert_eq(controller._request_place(false), PlacementRules.REASON_OK, "the client's release is accepted")
	var client_rise: float = controller._ghost.global_position.y - unlifted.origin.y
	return {"host": host_rise, "client": client_rise, "clear": clear_already}


## step / 2^bisect: strictly below the margin spawn_clearance.
func _tolerance() -> float:
	return _tuning.spawn_clearance_step / pow(2.0, float(_tuning.spawn_clearance_bisect_steps))


func _assert_parity(result: Dictionary, label: String, expect_lift: bool) -> void:
	var host: float = float(result["host"])
	var client: float = float(result["client"])
	gut.p("%s: host %.4f client %.4f" % [label, host, client])
	if expect_lift:
		assert_gt(host, 0.0, "%s: the host lifted the overlapping pose" % label)
		assert_gt(client, 0.0, "%s: the client lifted the overlapping pose" % label)
	else:
		assert_almost_eq(host, 0.0, 0.0001, "%s: a clear pose is not lifted by the host" % label)
		assert_almost_eq(client, 0.0, 0.0001, "%s: a clear pose is not lifted by the client" % label)
	assert_almost_eq(host, client, _tolerance(), "%s: host and client raise agree within step/2^bisect" % label)


func test_clear_pose_is_not_lifted_by_either_side() -> void:
	var result: Dictionary = await _lifts_for(1, 3.0)
	assert_true(bool(result["clear"]), "fixture: the pose is clear of the placed block")
	_assert_parity(result, "clear", false)


func test_pose_needing_less_than_one_step_agrees() -> void:
	var result: Dictionary = await _lifts_for(1, 0.55)
	assert_false(bool(result["clear"]), "fixture: the pose overlaps the placed block")
	_assert_parity(result, "sub-step", true)
	assert_lt(float(result["host"]), _tuning.spawn_clearance_step + _tuning.spawn_clearance, "fixture: inside the first step")


func test_pose_needing_several_steps_agrees() -> void:
	var result: Dictionary = await _lifts_for(1, 0.0)
	assert_false(bool(result["clear"]), "fixture: the pose overlaps the placed block")
	_assert_parity(result, "several steps", true)
	assert_gt(float(result["host"]), 2.0 * _tuning.spawn_clearance_step, "fixture: the lift spans several steps")


func test_pose_over_a_taller_tower_agrees() -> void:
	var result: Dictionary = await _lifts_for(3, 0.0)
	_assert_parity(result, "tower of three", true)
	assert_gt(float(result["host"]), 2.0, "fixture: a tall tower needs a long lift")


func test_bisect_refined_depths_agree() -> void:
	# depths between step boundaries, so the answer is set by the bisection
	for offset: float in [0.03, 0.09, 0.13, 0.19, 0.24, 0.31, 0.37, 0.43, 0.47, 0.53, 0.58, 0.62]:
		var result: Dictionary = await _lifts_for(1, offset)
		_assert_parity(result, "offset %.2f" % offset, true)
		after_each()
		before_each()
