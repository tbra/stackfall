extends GutTest
## Bontago-1pi.85.53: a thrown Rocket/Magnet carrier spawns already facing its flight line, so
## the pose captured at block_placed (just before replicate_spawn) is never upright. Real host path
## (Match.request_throw), tiny-map fixture of test_gift_throw_origin.gd.

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
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


func after_each() -> void:
	Match.set_net_provider(null)
	Match.abort_match()
	for child: Node in _blocks_root.get_children():
		child.free()
	Match.set_process(true)
	MatchTestReset.clear_world()
	await get_tree().process_frame


func _config() -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 97531
	return config


const NOSE_TOLERANCE: float = 0.01
const AIM: Vector3 = Vector3(0.0, 1.0, -0.001)
const THROW_AIM: Vector3 = Vector3(0.3, -0.2, -0.9)

var _placed_basis: Basis = Basis.IDENTITY
var _placed_seen: bool = false


func _on_block_placed(block: Node, _shape_id: StringName) -> void:
	_placed_basis = (block as Block).global_basis
	_placed_seen = true


func _start_with(gift: StringName) -> void:
	Match.start_match(_config())
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)
	Match._gifts._ensure_capacity(0)
	Match._gifts._held_specials[0] = gift
	Match._feed._held_is_gift[0] = true
	Events.block_placed.connect(_on_block_placed)


func _pose() -> Vector3:
	var home: Vector2 = Match.slot(0).home_position
	return _field.to_global(Vector3(home.x, 5.0, home.y))


func _nose_of(gift: StringName) -> Vector3:
	var effect: SpecialEffect = SpecialDef.find_by_id(gift).effect
	if effect is RocketEffect:
		return (effect as RocketEffect).model_nose_axis.normalized()
	return (effect as MagnetEffect).model_nose_axis.normalized()


func _check(gift: StringName, aim: Vector3) -> void:
	_start_with(gift)
	var reason: StringName = Match.request_throw(0, _pose(), 0, Quaternion.IDENTITY, aim)
	Events.block_placed.disconnect(_on_block_placed)
	assert_eq(reason, PlacementRules.REASON_OK)
	assert_true(_placed_seen)
	var block: Block = _blocks_root.get_child(_blocks_root.get_child_count() - 1) as Block
	var launch: Vector3 = block.linear_velocity.normalized()
	if gift == &"rocket":
		launch = RocketEffect.sanitize_launch_direction(aim)
	var spawn_nose: Vector3 = _placed_basis * _nose_of(gift)
	assert_gt(spawn_nose.dot(launch), 1.0 - NOSE_TOLERANCE, "nose along launch at spawn")
	assert_gt((block.global_basis * _nose_of(gift)).dot(launch), 1.0 - NOSE_TOLERANCE, "tick 0")


func test_rocket_spawns_faced_straight_up() -> void:
	_check(&"rocket", AIM)


func test_rocket_spawns_faced_along_a_forward_aim() -> void:
	_check(&"rocket", THROW_AIM)


func test_magnet_spawns_faced_along_its_throw_velocity() -> void:
	_check(&"magnet", THROW_AIM)


func test_helper_returns_null_for_gifts_that_stay_upright() -> void:
	var bomb: SpecialDef = SpecialDef.find_by_id(&"bomb")
	assert_null(MatchPlacement.launch_facing_basis(bomb, GiftThrow.Mode.THROW, THROW_AIM, THROW_AIM))
	assert_null(MatchPlacement.launch_facing_basis(null, GiftThrow.Mode.AIMED, THROW_AIM, THROW_AIM))
