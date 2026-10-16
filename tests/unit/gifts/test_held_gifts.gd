extends GutTest
## Held gifts keep their authored colours, the held slingshot
## faces the aim like the Rocket, and aimed Rocket/Paintball bodies spawn where the held model is
## drawn (host path: Match.request_throw; the client sees the same replicated spawn transform).

const AIM: Vector3 = Vector3(0.6, -0.3, -0.74)
const PIVOT_TOLERANCE_M: float = 0.01
const POSE_HEIGHT_M: float = 5.0
const AIMED_GIFTS: Array[StringName] = [&"rocket", &"paintball"]

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
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
	Match._net_provider = null
	Match.abort_match()
	for child: Node in _blocks_root.get_children():
		child.free()
	Match.set_process(true)
	MatchTestReset.clear_world()
	await get_tree().process_frame


func _start_with(gift: StringName) -> void:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 97531
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)
	Match._gifts._ensure_capacity(0)
	Match._gifts._held_specials[0] = gift
	Match._feed._held_is_gift[0] = true


func test_real_aimed_launch_spawns_the_model_where_the_held_model_is_drawn() -> void:
	var tuning: PhysicsTuning = load("res://config/physics/physics_tuning.tres") as PhysicsTuning
	for id: StringName in AIMED_GIFTS:
		_start_with(id)
		var shape: BlockShape = Match.held_shape(0)
		var home: Vector2 = Match.slot(0).home_position
		var pose: Vector3 = _field.to_global(Vector3(home.x, POSE_HEIGHT_M, home.y))
		var held_pivot: Vector3 = pose + BlockFactory.gift_cell_center(shape, tuning)
		var reason: StringName = Match.request_throw(0, pose, 0, Quaternion.IDENTITY, AIM.normalized())
		assert_eq(reason, PlacementRules.REASON_OK, String(id))
		var block: Block = _blocks_root.get_child(_blocks_root.get_child_count() - 1) as Block
		var visual: Node3D = block.get_node(NodePath(String(BlockFactory.GIFT_VISUAL_NODE))) as Node3D
		var pivot: Vector3 = block.global_transform * visual.position
		assert_lt(pivot.distance_to(held_pivot), PIVOT_TOLERANCE_M, "%s spawns at the held model (%s vs %s)" % [id, pivot, held_pivot])
		Match.abort_match()
		for child: Node in _blocks_root.get_children():
			child.free()
