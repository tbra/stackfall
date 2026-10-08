extends GutTest
## Bontago-1pi.14 round 3 (owner playtest 2026-10-02): "when dropping a block
## the next block loads instantly ... always inside a block when spawning" and
## the dropped block gets displaced. Drops block A through the real host path,
## lets the next piece load (spawn clearance + decay, as _process() would),
## drops block B from the ghost's pose and measures how far A moves.

const REST_FRAMES: int = 240
const WATCH_FRAMES: int = 90
## Tight bound: a block resting on the disk with a block placed on top of it
## should not creep. 5 cm / 3 degrees leaves room for solver noise only.
const MAX_POSITION_DRIFT: float = 0.05
const MAX_ROTATION_DRIFT_RAD: float = 0.0524

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef

var _saved_feed_config: BlockFeedConfig = null


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_pin_feed_to_convex_shape()
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _tiny_map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)

## DECISION (Bontago-1pi.115): these tests aim at a placed block's origin or rely on the
## held piece being solid there, which fails for concave shapes (u5, arch5, corner4, stair6)
## now in the random feed. Pin the feed to the cube; the shape mix is not under test.
func _pin_feed_to_convex_shape() -> void:
	_saved_feed_config = Match._block_feed_config
	var pinned: BlockFeedConfig = _saved_feed_config.duplicate() as BlockFeedConfig
	pinned.shapes = [load("res://config/blocks/cube.tres") as BlockShape]
	pinned.weight_overrides = PackedFloat32Array()
	Match._block_feed_config = pinned


func after_each() -> void:
	Match._block_feed_config = _saved_feed_config
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _config() -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 24680
	return config


func _make_controller() -> PlayerController:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost
	return controller


func _tick_feed(seconds: float) -> void:
	var ticks: int = int(ceil(seconds * Engine.physics_ticks_per_second))
	for _i: int in range(ticks):
		Match._process(1.0 / Engine.physics_ticks_per_second)


func _frame(controller: PlayerController) -> void:
	await wait_physics_frames(1)
	controller._update_ghost_transform()
	controller._decay_clearance_raise(1.0 / 60.0)


func _drift(a: Transform3D, b: Transform3D) -> Array[float]:
	var angle: float = a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion())
	return [a.origin.distance_to(b.origin), angle]


## Drops A, lets the next piece load, waits `delay_frames` physics frames
## (the player aiming), drops B from the ghost pose and returns A's maximum
## drift from its pose just before B spawned (position, rotation).
func _drop_two(delay_frames: int) -> Array[float]:
	Match.start_match(_config())
	_tick_feed(Match.COUNTDOWN_SECONDS + 0.1)
	var controller: PlayerController = _make_controller()
	controller.set_acting_slot(0)
	var home: Vector2 = Match.slot(0).home_position
	var cursor: Vector3 = _field.to_global(Vector3(home.x, 5.0, home.y))
	controller._cursor = cursor
	controller._ghost.set_shape(Match.held_shape(0))
	controller._update_ghost_transform()
	controller._place_ghost_block()
	var block_a: Node3D = _blocks_root.get_child(0) as Node3D
	await wait_physics_frames(1)
	controller._update_ghost_transform()
	controller._apply_spawn_clearance()
	for _i: int in range(delay_frames):
		await _frame(controller)
	_tick_feed(Match.config.block_timer + 0.1)
	controller._cursor = cursor
	controller._update_ghost_transform()
	var before: Transform3D = block_a.global_transform
	controller._place_ghost_block()
	assert_eq(_blocks_root.get_child_count(), 2, "fixture: the second drop must have spawned.")
	var worst: Array[float] = [0.0, 0.0]
	for _i: int in range(WATCH_FRAMES):
		await wait_physics_frames(1)
		var d: Array[float] = _drift(before, block_a.global_transform)
		worst[0] = maxf(worst[0], d[0])
		worst[1] = maxf(worst[1], d[1])
	return worst


func test_dropped_block_is_not_displaced_after_the_next_loads_and_settles() -> void:
	var worst: Array[float] = await _drop_two(REST_FRAMES)
	gut.p("settled-delay drift pos=%.4f rot=%.4f" % [worst[0], worst[1]])
	assert_lt(worst[0], MAX_POSITION_DRIFT, "dropped block position drift")
	assert_lt(worst[1], MAX_ROTATION_DRIFT_RAD, "dropped block rotation drift")


## The real failure: the held pose interpenetrates a block that was already
## placed (it replicated after the post-placement clearance ran, or the ghost
## was rotated into it). The host spawns the new block there and Jolt shoves
## the old one away.
func test_release_from_a_pose_inside_a_placed_block_does_not_displace_it() -> void:
	Match.start_match(_config())
	_tick_feed(Match.COUNTDOWN_SECONDS + 0.1)
	var controller: PlayerController = _make_controller()
	controller.set_acting_slot(0)
	var home: Vector2 = Match.slot(0).home_position
	var cursor: Vector3 = _field.to_global(Vector3(home.x, 5.0, home.y))
	controller._cursor = cursor
	controller._ghost.set_shape(Match.held_shape(0))
	controller._update_ghost_transform()
	controller._place_ghost_block()
	var block_a: Node3D = _blocks_root.get_child(0) as Node3D
	await wait_physics_frames(1)
	controller._update_ghost_transform()
	controller._apply_spawn_clearance()
	for _i: int in range(REST_FRAMES):
		await _frame(controller)
	_tick_feed(Match.config.block_timer + 0.1)
	# The old block is now where the ghost stands: drop the ghost's raise.
	controller._ghost.manual_hover_offset = 0.0
	controller._clearance_raise = 0.0
	controller._update_ghost_transform()
	assert_true(controller._ghost_overlaps_a_placed_block(), "fixture: the pose must be inside the old block.")
	var before: Transform3D = block_a.global_transform
	controller._place_ghost_block()
	assert_eq(_blocks_root.get_child_count(), 2, "fixture: the second drop must have spawned.")
	var worst: Array[float] = [0.0, 0.0]
	for _i: int in range(WATCH_FRAMES):
		await wait_physics_frames(1)
		var d: Array[float] = _drift(before, block_a.global_transform)
		worst[0] = maxf(worst[0], d[0])
		worst[1] = maxf(worst[1], d[1])
	gut.p("inside-pose drift pos=%.4f rot=%.4f" % [worst[0], worst[1]])
	assert_lt(worst[0], MAX_POSITION_DRIFT, "dropped block position drift")
	assert_lt(worst[1], MAX_ROTATION_DRIFT_RAD, "dropped block rotation drift")


## Host guard (MatchPlacement._lift_pose_clear): the pose arrives over the wire
## with no client-side prediction at all, inside the old block.
func _release_into_block_a(auto_drop: bool) -> Array:
	Match.start_match(_config())
	_tick_feed(Match.COUNTDOWN_SECONDS + 0.1)
	var home: Vector2 = Match.slot(0).home_position
	var origin: Vector3 = _field.to_global(Vector3(home.x, 5.0, home.y))
	assert_eq(Match.request_place(0, origin, 0, Quaternion.IDENTITY, false), PlacementRules.REASON_OK)
	var block_a: Node3D = _blocks_root.get_child(0) as Node3D
	await wait_physics_frames(REST_FRAMES)
	_tick_feed(Match.config.block_timer + 0.1)
	var inside: Vector3 = block_a.global_position
	var before: Transform3D = block_a.global_transform
	var reason: StringName = Match.request_place(0, inside, 0, Quaternion.IDENTITY, auto_drop)
	return [reason, before, block_a]


func test_host_lifts_a_pose_inside_a_placed_block_and_does_not_displace_it() -> void:
	var result: Array = await _release_into_block_a(false)
	assert_eq(result[0], PlacementRules.REASON_OK)
	var block_a: Node3D = result[2] as Node3D
	var block_b: Node3D = _blocks_root.get_child(_blocks_root.get_child_count() - 1) as Node3D
	assert_gt(block_b.global_position.y, block_a.global_position.y + 0.5, "host lifted B clear of A")
	var worst: float = 0.0
	for _i: int in range(WATCH_FRAMES):
		await wait_physics_frames(1)
		worst = maxf(worst, (result[1] as Transform3D).origin.distance_to(block_a.global_position))
	assert_lt(worst, MAX_POSITION_DRIFT, "host guard keeps A still")


func test_host_refuses_an_unresolvable_manual_pose() -> void:
	var tuning: GhostTuning = load("res://config/ghost_tuning.tres") as GhostTuning
	var saved: float = tuning.spawn_clearance_max_raise
	tuning.spawn_clearance_max_raise = 0.1
	var result: Array = await _release_into_block_a(false)
	tuning.spawn_clearance_max_raise = saved
	assert_eq(result[0], PlacementRules.REASON_NO_BLOCK, "no lift within the cap: refused")
	assert_eq(_blocks_root.get_child_count(), 1, "nothing spawned")


func test_host_guard_runs_even_with_spawn_clearance_disabled() -> void:
	var tuning: GhostTuning = load("res://config/ghost_tuning.tres") as GhostTuning
	tuning.spawn_clearance_enabled = false
	var result: Array = await _release_into_block_a(false)
	tuning.spawn_clearance_enabled = true
	assert_eq(result[0], PlacementRules.REASON_OK)
	var block_a: Node3D = result[2] as Node3D
	var block_b: Node3D = _blocks_root.get_child(_blocks_root.get_child_count() - 1) as Node3D
	assert_gt(block_b.global_position.y, block_a.global_position.y + 0.5, "host still lifted B with the toggle off")


func test_host_refuses_a_thrown_pose_inside_a_placed_block() -> void:
	var tuning: GhostTuning = load("res://config/ghost_tuning.tres") as GhostTuning
	var saved: float = tuning.spawn_clearance_max_raise
	Match.start_match(_config())
	_tick_feed(Match.COUNTDOWN_SECONDS + 0.1)
	var home: Vector2 = Match.slot(0).home_position
	var origin: Vector3 = _field.to_global(Vector3(home.x, 5.0, home.y))
	assert_eq(Match.request_place(0, origin, 0, Quaternion.IDENTITY, false), PlacementRules.REASON_OK)
	var block_a: Node3D = _blocks_root.get_child(0) as Node3D
	await wait_physics_frames(REST_FRAMES)
	_tick_feed(Match.config.block_timer + 0.1)
	Match._gifts._ensure_capacity(0)
	Match._gifts._held_specials[0] = &"test_special"
	Match._feed._held_is_gift[0] = true
	tuning.spawn_clearance_max_raise = 0.1
	# Bontago-1pi.85.47: a throw spawns at the held gift (gift_aim_back_m defaults to 0); pin it
	# to 0 so the spawn point coincides with the occupied cursor pose whatever the tuning.
	var special_tuning: SpecialTuning = Match._placement._special_tuning
	var saved_back: float = special_tuning.gift_aim_back_m
	special_tuning.gift_aim_back_m = 0.0
	# The spawn point is also floored at gift_aim_min_height_m over the surface (1.0 m), which
	# lifts it clear of a 1-cube block resting on the disk; pin it to 0 too.
	var saved_min_height: float = special_tuning.gift_aim_min_height_m
	special_tuning.gift_aim_min_height_m = 0.0
	var reason: StringName = Match.request_throw(0, block_a.global_position, 0, Quaternion.IDENTITY, Vector3(1.0, 0.0, 0.0))
	special_tuning.gift_aim_back_m = saved_back
	special_tuning.gift_aim_min_height_m = saved_min_height
	tuning.spawn_clearance_max_raise = saved
	assert_eq(reason, PlacementRules.REASON_NO_BLOCK, "thrown pose inside a block is refused")
	assert_eq(_blocks_root.get_child_count(), 1, "nothing spawned")
	assert_eq(Match.held_special(0), &"test_special", "the special stays in hand")


func test_refused_release_undoes_the_predictive_lift() -> void:
	Match.start_match(_config())
	_tick_feed(Match.COUNTDOWN_SECONDS + 0.1)
	var controller: PlayerController = _make_controller()
	controller.set_acting_slot(0)
	controller._release_raise = 0.7
	controller._clearance_raise = 0.7
	controller._ghost.manual_hover_offset = 0.7
	Events.placement_rejected.emit(0, PlacementRules.REASON_NO_BLOCK)
	assert_eq(controller._ghost.manual_hover_offset, 0.0, "lift reverted")
	assert_eq(controller._clearance_raise, 0.0)
	assert_eq(controller._release_raise, 0.0)
