extends GutTest
## Bontago-1pi.85.28 (docs/GIFT_PLAYTEST2_PLAN.md section 1): the Jumping Bean sat idle for
## ~5 s, hopped once, tiny and straight up, and dissolved in its own hole. Real physics: the
## shipped jumping_bean.tres def on a live Match field with a tilting disc and a live
## registry (so HoleDissolver is active), a bean thrown onto the disc on an arc.

const FIELD_RADIUS_M: float = 40.0
const RUN_SECONDS: float = 10.0
const DROP_HEIGHT_M: float = 1.2
const THROW_SPEED_MPS: float = 5.0
const TILT_IMPULSE: float = 0.05
const CONTACT_HEIGHT_M: float = 0.7
## Upper bound (s) from first contact to the first hop (owner: ~1.5 s, was ~5 s).
const MAX_FIRST_HOP_S: float = 1.5
## A hop must carry the bean this fraction of one hop's nominal horizontal reach.
const MIN_REACH_FRACTION: float = 0.5
const MIN_HOPS: int = 3


## Records every hop's pre-hop position and whether the hole opened at that cell.
class _SpyBean:
	extends JumpingBeanEffect
	var hop_positions: Array[Vector3] = []
	var hop_times: Array[float] = []
	var holes: int = 0
	var airborne_kicks: int = 0
	var clock: Callable
	const CONTACT_PROBE_M: float = 0.1

	## Independent contact query (does not rely on the effect's own grounding code, so the
	## test also runs against the old implementation): short downward body test-motion.
	func _touching_below(block: Block) -> bool:
		var params: PhysicsTestMotionParameters3D = PhysicsTestMotionParameters3D.new()
		params.from = block.global_transform
		params.motion = Vector3.DOWN * CONTACT_PROBE_M
		return PhysicsServer3D.body_test_motion(block.get_rid(), params, PhysicsTestMotionResult3D.new())

	func _hop(block: Block) -> void:
		if not _touching_below(block):
			airborne_kicks += 1
		var grid: CellGrid = Match.cell_grid()
		var cell: Vector2i = grid.world_to_cell(Match.field().disk_local_from_world(block.global_position))
		super._hop(block)
		hop_positions.append(block.global_position)
		hop_times.append(float(clock.call()))
		if Match.raster().is_hole(cell.x, cell.y):
			holes += 1


func after_each() -> void:
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _start_match() -> void:
	Match.set_process(false)
	Match.abort_match()
	var map: MapDef = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	map.field_radius = FIELD_RADIUS_M
	var field: Field = autofree(Field.new())
	field.map_def = map
	add_child_autofree(field)
	var root: Node3D = autofree(Node3D.new())
	add_child_autofree(root)
	var registry: BlockRegistry = autofree(BlockRegistry.new())
	add_child_autofree(registry)
	Match.register_world(field, registry, root)
	var config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true)
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(map)
	config.player_count = 2
	config.hot_seat = true
	config.block_timer = 6.0
	config.rng_seed = 12345
	config.hole_mode = MatchConfig.HoleMode.TEMPORARY
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)


func test_bean_hops_promptly_far_and_survives_its_own_holes() -> void:
	_start_match()
	var field: Field = Match.field()
	field.set_tilt_enabled(true)
	field.apply_tilt_impulse(Vector2.RIGHT, TILT_IMPULSE)
	var shipped: SpecialDef = SpecialDef.find_by_id(&"jumping_bean")
	var real: JumpingBeanEffect = shipped.effect as JumpingBeanEffect
	var spy: _SpyBean = _SpyBean.new()
	for property: Dictionary in real.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_STORAGE != 0 and property["name"] != "script":
			spy.set(property["name"], real.get(property["name"]))
	spy._rng.seed = 5
	var def: SpecialDef = shipped.duplicate() as SpecialDef
	def.effect = spy

	var shape: BlockShape = load("res://config/blocks/cube.tres") as BlockShape
	var tuning: PhysicsTuning = load("res://config/physics_tuning.tres") as PhysicsTuning
	var bean: Block = BlockFactory.build(shape, tuning, 0)
	add_child_autofree(bean)
	bean.global_position = field.world_from_disk_local(Vector2(-FIELD_RADIUS_M * 0.25, 0.0), DROP_HEIGHT_M)
	Events.block_placed.emit(bean, shape.id)
	bean.linear_velocity = Vector3(THROW_SPEED_MPS, 0.0, 0.0)
	var behavior: SpecialBehavior = SpecialBehavior.new()
	bean.add_child(behavior)
	behavior.bind(bean, def, SpecialTuning.new())
	var bean_id: int = bean.get_instance_id()

	# Simulated time is the behavior's own age (it sums the real physics deltas); a headless
	# frame can run several physics steps, so counting wait_physics_frames() would be wrong.
	spy.clock = func() -> float: return behavior.age()
	var contact_at: float = -1.0
	var removed: bool = false
	var guard_frames: int = int(RUN_SECONDS * Engine.physics_ticks_per_second) * 2
	while behavior.age() < RUN_SECONDS and guard_frames > 0:
		await wait_physics_frames(1)
		guard_frames -= 1
		if not is_instance_valid(bean) or bean.is_queued_for_deletion():
			removed = true
			break
		var elapsed: float = behavior.age()
		if contact_at < 0.0 and bean.global_position.y - field.surface_y() < CONTACT_HEIGHT_M:
			contact_at = elapsed
	assert_false(removed, "the bean must not be removed (dissolved) by its own holes: id %d" % bean_id)
	assert_gte(contact_at, 0.0, "setup: the bean reached the disc")
	assert_gte(spy.hop_times.size(), MIN_HOPS, "at least %d hops in %.0f s" % [MIN_HOPS, RUN_SECONDS])
	if spy.hop_times.is_empty():
		return
	assert_lte(spy.hop_times[0] - contact_at, MAX_FIRST_HOP_S, "first hop starts promptly after first contact")
	assert_eq(spy.airborne_kicks, 0, "no hop starts while the bean is airborne")
	assert_eq(spy.holes, spy.hop_times.size(), "every hop opens a hole")
	var min_reach: float = real.hop_horizontal_speed * MIN_REACH_FRACTION
	for i: int in range(1, spy.hop_positions.size()):
		var delta: Vector3 = spy.hop_positions[i] - spy.hop_positions[i - 1]
		delta.y = 0.0
		assert_gte(delta.length(), min_reach, "hop %d carried the bean a meaningful horizontal distance" % i)
