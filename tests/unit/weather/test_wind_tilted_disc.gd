extends GutTest
## Storm wind measures a block's height from the live disc surface under it. On a steeply tilted
## disc a block resting low on the uphill side is high above the rest plane but low above the ground
## beneath it, so it gets no push; a block truly high above that ground still does.

const DELTA: float = 1.0 / 60.0
const FIELD_RADIUS_M: float = 12.0
const TILT_RAD: float = 0.35
const UPHILL_X_M: float = 11.0
const RESTING_ABOVE_SURFACE_M: float = 1.0
const SEED: int = 12345
const WIND_SECONDS: float = 0.5

var _tuning: StormTuning = null
var _blocks: Array[Block] = []
var _root: Node3D = null
var _field: Field = null
var _previous_context: MatchContext = null


func before_each() -> void:
	_previous_context = MatchContext.installed()
	_tuning = load("res://config/weather/storm.tres") as StormTuning
	_blocks.clear()
	_root = Node3D.new()
	add_child_autofree(_root)
	var map_def: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true) as MapDef
	map_def.field_radius = FIELD_RADIUS_M
	_field = Field.new()
	_field.map_def = map_def
	_root.add_child(_field)


func after_each() -> void:
	for block: Block in _blocks:
		if is_instance_valid(block):
			block.free()
	_blocks.clear()
	MatchContext.install(_previous_context)
	await get_tree().process_frame


func _effect() -> StormEffect:
	var effect: StormEffect = StormEffect.new()
	var context: FakeMatchContext = WeatherTestHost.wind_context(self, func() -> Array: return _blocks, func() -> float: return 0.0)
	context.field_value = _field
	context.has_weather_value = true
	context.weather_seed_value = SEED
	effect.bind(context, _tuning)
	return effect


func _floating_block(world_xz: Vector2, above_surface: float) -> Block:
	var block: Block = BlockFactory.build(
		load("res://config/blocks/cube.tres") as BlockShape, load("res://config/physics/physics_tuning.tres") as PhysicsTuning)
	block.gravity_scale = 0.0
	block.linear_damp = 0.0
	_root.add_child(block)
	var probe: Vector3 = Vector3(world_xz.x, 0.0, world_xz.y)
	block.global_position = Vector3(world_xz.x, _field.surface_height_at(probe) + above_surface, world_xz.y)
	_blocks.append(block)
	return block


func _run_wind(effect: StormEffect, seconds: float) -> void:
	for _i: int in range(int(seconds / DELTA)):
		effect.tick(DELTA, 1.0)
		await get_tree().physics_frame


func test_block_low_above_an_uphill_surface_gets_no_push_though_high_above_the_rest_plane() -> void:
	_field.apply_replicated_pose(Vector3.ZERO, Quaternion(Vector3.BACK, TILT_RAD))
	await wait_physics_frames(2)
	var resting: Block = _floating_block(Vector2(UPHILL_X_M, 0.0), RESTING_ABOVE_SURFACE_M)
	var tall: Block = _floating_block(Vector2(UPHILL_X_M, 3.0), _tuning.cap_height_m + 2.0)
	assert_gt(resting.global_position.y - _field.surface_y(), _tuning.threshold_height_m + 0.5,
		"fixture: the resting block is well above the threshold measured from the rest plane")
	assert_lt(RESTING_ABOVE_SURFACE_M, _tuning.threshold_height_m, "fixture: but below it over the ground beneath")
	await _run_wind(_effect(), WIND_SECONDS)
	assert_almost_eq(resting.linear_velocity.length(), 0.0, 0.001, "no storm push on a block resting on the uphill side")
	assert_gt(tall.linear_velocity.length(), 0.1, "a block truly high above the tilted ground is still pushed")
