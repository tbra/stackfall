extends GutTest
## A Jumping Bean released through the player path hops on a headless host and fires
## Events.bean_hopped (its hop marker is derived from the carrier's own motion, so it
## needs the gift visual hook that only a released gift gets).

const FIELD_RADIUS_M: float = 20.0
const RUN_SECONDS: float = 10.0
const HOP_SIGNAL_COUNT_MIN: int = 1

var _hops: int = 0


func after_each() -> void:
	if Events.bean_hopped.is_connected(_on_bean_hopped):
		Events.bean_hopped.disconnect(_on_bean_hopped)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _on_bean_hopped(_position: Vector3) -> void:
	_hops += 1


func test_released_bean_emits_bean_hopped() -> void:
	Match.set_process(false)
	Match.abort_match()
	var map: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	map.field_radius = FIELD_RADIUS_M
	var field: Field = autofree(Field.new())
	field.map_def = map
	add_child_autofree(field)
	var root: Node3D = autofree(Node3D.new())
	add_child_autofree(root)
	var registry: BlockRegistry = autofree(BlockRegistry.new())
	add_child_autofree(registry)
	Match.register_world(field, registry, root)
	var config: MatchConfig = (load("res://config/match/match_defaults.tres") as MatchConfig).duplicate(true)
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(map)
	config.player_count = 2
	config.block_timer = 6.0
	config.rng_seed = 24680
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)
	Match._gifts._ensure_capacity(0)
	Match._gifts._held_specials[0] = &"jumping_bean"
	Match._feed._held_is_gift[0] = true
	var home: Vector2 = Match.slot(0).home_position
	var reason: StringName = Match.request_place(0, field.to_global(Vector3(home.x, 5.0, home.y)), 0, Quaternion.IDENTITY, false)
	assert_eq(reason, PlacementRules.REASON_OK, "setup: the bean release is accepted")
	Events.bean_hopped.connect(_on_bean_hopped)
	var frames: int = int(RUN_SECONDS * Engine.physics_ticks_per_second)
	while _hops < HOP_SIGNAL_COUNT_MIN and frames > 0:
		await wait_physics_frames(1)
		frames -= 1
	assert_gte(_hops, HOP_SIGNAL_COUNT_MIN, "a released bean hops and announces it")
