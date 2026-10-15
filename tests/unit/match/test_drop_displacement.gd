extends GutTest
## Bontago-1pi.14: the host lifts or refuses a placement pose that overlaps an already placed block instead of
## shoving that block away.

const REST_FRAMES: int = 240
const WATCH_FRAMES: int = 90
## Tight bound: a block resting on the disk with a block placed on top of it
## should not creep. 5 cm / 3 degrees leaves room for solver noise only.
const MAX_POSITION_DRIFT: float = 0.05

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef

var _saved_feed_config: BlockFeedConfig = null


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_pin_feed_to_convex_shape()
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
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 24680
	return config


func _tick_feed(seconds: float) -> void:
	var ticks: int = int(ceil(seconds * Engine.physics_ticks_per_second))
	for _i: int in range(ticks):
		Match._process(1.0 / Engine.physics_ticks_per_second)


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
	var tuning: GhostTuning = load("res://config/blocks/tuning/ghost_tuning.tres") as GhostTuning
	var saved: float = tuning.spawn_clearance_max_raise
	tuning.spawn_clearance_max_raise = 0.1
	var result: Array = await _release_into_block_a(false)
	tuning.spawn_clearance_max_raise = saved
	assert_eq(result[0], PlacementRules.REASON_NO_BLOCK, "no lift within the cap: refused")
	assert_eq(_blocks_root.get_child_count(), 1, "nothing spawned")

