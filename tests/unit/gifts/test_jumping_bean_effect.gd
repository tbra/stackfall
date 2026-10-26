extends GutTest
## JumpingBeanEffect (spec 1.6, installed-tutorial evidence: "Jumping Bean
## creates a hole between random hops"). Two fixture shapes, matching this package's siblings:
##
## - A stub Block + real SpecialBehavior (no physics simulation) plus a
##   plain registered Field, for the settle-gated timed pattern itself --
##   inertness, hop cadence/frame-rate independence, the velocity-kick-not-
##   teleport shape, self-trigger at lifetime_s, two beans' independent
##   timers, and the null-Field guard -- mirrors test_propeller_effect.gd's own fixture.
## - A real host Match fixture with a raster (mirrors
##   test_match_territory_punch.gd's own before_each exactly: TinyMapMatchConfig,
##   a real-time match run through countdown into State.PLAYING), for the two
##   tests that actually need Match.punch_special_hole()'s real effect on
##   TerritoryRaster: a hop opens the expected hole under HoleMode.TEMPORARY,
##   and HoleMode.OFF suppresses the hole but not the hop's own knockback
##   (enforced inside punch_special_hole() itself, not trusted
##   to this effect).

const TICK: float = 1.0 / 60.0
const MAX_LAND_FRAMES: int = 300
## Physics frames for a dropped cube to come to rest on the field.
const SETTLE_FRAMES: int = 20
## Cube centre height above the field surface: resting, inside the landing probe's reach.
const RESTING_OFFSET_M: float = 0.52

func _make_block(position: Vector3 = Vector3.ZERO) -> Block:
	var block: Block = autofree(Block.new())
	add_child_autofree(block)
	block.global_position = position
	block.mass = 1.0
	block.linear_velocity = Vector3.ZERO
	return block


func _make_def(effect: JumpingBeanEffect, arm_delay: float = 0.0) -> SpecialDef:
	var def: SpecialDef = SpecialDef.new()
	def.id = &"jumping_bean"
	def.arm_delay = arm_delay
	def.arm_impulse = 999.0
	def.fuse_timeout_s = 999.0
	def.effect = effect
	return def


func _make_behavior(block: Block, def: SpecialDef) -> SpecialBehavior:
	var tuning: SpecialTuning = SpecialTuning.new()
	var behavior: SpecialBehavior = SpecialBehavior.new()
	block.add_child(behavior)
	autofree(behavior)
	behavior.bind(block, def, tuning)
	return behavior


## A real cube resting on the registered field, so the landing probe finds contact. Call
## after _register_field() / _start_hole_match(); position is the cube's horizontal spot.
func _make_resting_block(position_xz: Vector2) -> Block:
	var shape: BlockShape = load("res://config/blocks/cube.tres") as BlockShape
	var tuning: PhysicsTuning = load("res://config/physics/physics_tuning.tres") as PhysicsTuning
	var block: Block = BlockFactory.build(shape, tuning)
	add_child_autofree(block)
	block.global_position = Vector3(position_xz.x, _field.surface_y() + RESTING_OFFSET_M, position_xz.y)
	await wait_physics_frames(SETTLE_FRAMES)
	return block


## Lands the carrier through SpecialBehavior.advance(): the block's velocity is stubbed to
## rest (no physics frames run while the behaviour is driven) and the real LandedProbe finds
## the field under it. Stops on the landing tick, so landed_age() starts at 0.
func _land(behavior: SpecialBehavior, block: Block) -> void:
	block.linear_velocity = Vector3.ZERO
	var ticks: int = 0
	while not behavior.has_landed() and ticks < MAX_LAND_FRAMES:
		behavior.advance(TICK)
		ticks += 1
	assert_true(behavior.has_landed(), "setup: the resting block must land through advance()")


func _small_map() -> MapDef:
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_jumping_bean"
	map_def.field_radius = 6.0
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 32
	return map_def


var _blocks_root: Node3D = null
var _registry: BlockRegistry = null
var _field: Field = null


func after_each() -> void:
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


## Registers a plain (non-spy) Field -- this package never inspects what
## reaches Field itself (unlike PropellerEffect/AnvilEffect's SpyField, which
## records tilt calls), only what reaches TerritoryRaster via
## Match.punch_special_hole(). Called at the top of every stub-Block test,
## same as test_propeller_effect.gd's _register_spy_field() -- Match._field
## is a plain autoload var nothing resets between test files, so relying on
## it being null/valid without registering a fresh one here would be
## order-dependent.
func _register_field() -> void:
	var field: Field = autofree(Field.new())
	_field = field
	field.map_def = _small_map()
	add_child_autofree(field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(field, _registry, _blocks_root)


# --- inert until first settle ------------------------------------------------

func test_inert_until_landed_no_hop_no_velocity_change() -> void:
	_register_field()
	var effect: JumpingBeanEffect = JumpingBeanEffect.new()
	effect.contact_override = func(_b: Block) -> bool: return true  # stub block: no collision to probe
	effect.hop_interval_s = 0.05  # deliberately tiny: proves this is a landing
	# gate, not merely "hasn't been long enough yet".
	var start_position: Vector3 = Vector3(2.0, 0.0, 2.0)
	var block: Block = _make_block(start_position)
	var behavior: SpecialBehavior = _make_behavior(block, _make_def(effect))

	for _i: int in range(10):
		behavior.advance(TICK)

	assert_eq(block.linear_velocity, Vector3.ZERO, "must not hop while airborne")
	assert_eq(block.global_position, start_position, "must not move while airborne")
	assert_false(behavior.is_triggered())


# --- hop cadence: exactly one hop per hop_interval_s, frame-rate independent -

## Counts _hop() calls (not just physics_tick() calls) -- proves the
## settle-then-hop-on-schedule pattern actually fires the hop itself the
## right number of times, mirroring test_propeller_effect.gd's own
## _CountingPropellerEffect.
class _CountingBeanEffect:
	extends JumpingBeanEffect
	var hop_calls: int = 0

	func _hop(block: Block) -> void:
		hop_calls += 1
		super._hop(block)


func _count_hops_over(dt: float, hop_interval_s: float, total_span_s: float) -> int:
	_register_field()
	var effect: _CountingBeanEffect = _CountingBeanEffect.new()
	effect.contact_override = func(_b: Block) -> bool: return true  # stub block: no collision to probe
	effect.hop_interval_s = hop_interval_s
	effect.first_hop_delay_s = hop_interval_s  # legacy cadence: first hop one interval after landing
	var block: Block = await _make_resting_block(Vector2(2.0, 2.0))
	var behavior: SpecialBehavior = _make_behavior(block, _make_def(effect))
	_land(behavior, block)
	var ticks: int = int(round(total_span_s / dt))
	for _i: int in range(ticks):
		behavior.advance(dt)
	block.queue_free()  # the next call's block rests at the same spot
	return effect.hop_calls


## Two different fixed step sizes, the same total simulated span (3.5x
## hop_interval_s, comfortably clear of the 4th hop's own boundary) -- both
## must land on exactly 3 hops, proving the cadence is driven by simulation
## time, not tick count.
func test_hops_exactly_once_per_hop_interval_s_frame_rate_independent() -> void:
	var hop_interval_s: float = 1.0
	var total_span_s: float = 3.5 * hop_interval_s

	var hops_fine: int = await _count_hops_over(0.05, hop_interval_s, total_span_s)
	var hops_coarse: int = await _count_hops_over(0.1, hop_interval_s, total_span_s)

	assert_eq(hops_fine, 3, "3 full hop_interval_s windows must have elapsed by 3.5x")
	assert_eq(hops_coarse, 3, "must match regardless of the caller's step size")


# --- a hop is a velocity kick, never a position teleport --------------------

func test_hop_kicks_velocity_up_and_horizontal_never_teleports_position() -> void:
	_register_field()
	var effect: JumpingBeanEffect = JumpingBeanEffect.new()
	effect.contact_override = func(_b: Block) -> bool: return true  # stub block: no collision to probe
	effect.hop_interval_s = 1.0
	effect.first_hop_delay_s = 1.0
	effect.hop_impulse = 6.0
	effect.hop_horizontal_speed = 3.0
	var block: Block = await _make_resting_block(Vector2(2.0, 2.0))
	var start_position: Vector3 = block.global_position
	var behavior: SpecialBehavior = _make_behavior(block, _make_def(effect))
	_land(behavior, block)

	behavior.advance(0.5)  # landed 0.5 s: no hop due yet
	assert_eq(block.linear_velocity, Vector3.ZERO, "setup: no hop before hop_interval_s")

	behavior.advance(0.5)  # landed 1.0 s == first_hop_delay_s -> hops
	assert_almost_eq(block.linear_velocity.y, effect.hop_impulse, 0.0001)
	assert_eq(Vector2(block.linear_velocity.x, block.linear_velocity.z), Vector2.ZERO, "sideways part follows next tick")
	behavior.advance(TICK)
	var horizontal: Vector2 = Vector2(block.linear_velocity.x, block.linear_velocity.z)
	assert_almost_eq(horizontal.length(), effect.hop_horizontal_speed, 0.0001)
	assert_eq(
		block.global_position, start_position,
		"a hop must be a velocity kick, never a position teleport (would fight SnapshotSync)"
	)
	assert_false(block.sleeping, "a hop must wake the body")


# --- self-triggers at lifetime_s, frame-rate independent --------------------

func test_self_triggers_once_elapsed_since_settle_reaches_lifetime_s() -> void:
	_register_field()
	var effect: JumpingBeanEffect = JumpingBeanEffect.new()
	effect.contact_override = func(_b: Block) -> bool: return true  # stub block: no collision to probe
	effect.hop_interval_s = 100.0  # keeps hops out of this timing-only test
	effect.lifetime_s = 1.0
	var block: Block = await _make_resting_block(Vector2(2.0, 2.0))
	var def: SpecialDef = _make_def(effect, 0.25)
	var behavior: SpecialBehavior = _make_behavior(block, def)
	_land(behavior, block)

	for _i: int in range(3):
		behavior.advance(0.25)  # landed age reaches 0.75
	assert_false(behavior.is_triggered(), "must not trigger before lifetime_s elapses")

	behavior.advance(0.25)  # landed age reaches 1.0 == lifetime_s
	assert_true(behavior.is_triggered(), "must trigger once lifetime_s elapses after landing")


# --- real Match+territory fixture: the actual hole-punch contract ----------

func _start_hole_match(hole_mode: MatchConfig.HoleMode) -> void:
	Match.set_process(false)
	Match.abort_match()
	var tiny_map: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	tiny_map.field_radius = 20.0

	# A previous test in this file (or an earlier test file, since Match._field
	# is a plain autoload var nothing else resets) may have left Match's own
	# Field null or pointed at a freed one -- register a fresh one for this
	# match, exactly like test_match_territory_punch.gd's own before_each.
	var field: Field = autofree(Field.new())
	_field = field
	field.map_def = tiny_map
	add_child_autofree(field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(field, _registry, _blocks_root)

	var config: MatchConfig = (load("res://config/match/match_defaults.tres") as MatchConfig).duplicate(true)
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(tiny_map)
	config.player_count = 2
	config.block_timer = 6.0
	config.rng_seed = 12345
	config.hole_mode = hole_mode
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)


## Proves spec 1.6's "a hole between hops" at the level that matters: each
## hop punches at wherever the bean actually IS at that hop's own tick, not a
## stale/first-settle position. The stub block is moved by hand between the
## two hops to stand in for whatever real physics carried it there since the
## previous hop (this test drives SpecialBehavior.advance() directly, with
## no physics simulation actually running) -- the second hop must punch at
## the NEW position, and the first hole must still be open (hole_open_s
## hasn't elapsed and nothing here runs the periodic close-delay decay).
func test_each_hop_punches_a_hole_at_the_bean_current_position_under_temporary() -> void:
	_start_hole_match(MatchConfig.HoleMode.TEMPORARY)
	var cell_grid: CellGrid = Match.cell_grid()
	var raster: TerritoryRaster = Match.raster()

	var effect: JumpingBeanEffect = JumpingBeanEffect.new()
	effect.contact_override = func(_b: Block) -> bool: return true  # stub block: no collision to probe
	effect.hop_interval_s = 1.0
	effect.first_hop_delay_s = 1.0
	effect.hole_radius_m = 0.4  # smaller than one 1 m cell -> exactly one cell
	effect.hole_open_s = 2.0

	var block: Block = await _make_resting_block(Vector2(6.0, 6.0))
	var position_1: Vector3 = block.global_position
	var behavior: SpecialBehavior = _make_behavior(block, _make_def(effect))
	_land(behavior, block)

	behavior.advance(0.5)  # landed 0.5 s, no hop yet
	var cell_1: Vector2i = cell_grid.world_to_cell(Vector2(position_1.x, position_1.z))
	assert_false(raster.is_hole(cell_1.x, cell_1.y), "setup: no hop has fired yet")

	behavior.advance(0.5)  # landed 1.0 -> first hop punches at position_1
	assert_true(
		raster.is_hole(cell_1.x, cell_1.y), "the first hop must punch a hole where the bean stood"
	)

	var position_2: Vector3 = Vector3(9.0, position_1.y, 9.0)
	block.global_position = position_2  # stand-in for real physics moving it since the last hop

	behavior.advance(0.1)  # touchdown: the interval counts from here
	behavior.advance(1.1)  # next hop due -> punches at position_2
	var cell_2: Vector2i = cell_grid.world_to_cell(Vector2(position_2.x, position_2.z))
	assert_true(
		raster.is_hole(cell_2.x, cell_2.y),
		"the second hop must punch a hole at the bean's NEW position, not the first"
	)
	assert_true(
		raster.is_hole(cell_1.x, cell_1.y),
		"the earlier hole must still be open (hole_open_s hasn't elapsed)"
	)


## Review finding (SHOULD-FIX): a hop's own landing carries
## roughly sqrt(hop_impulse^2 + hop_horizontal_speed^2) = sqrt(6.0^2 + 3.0^2)
## ~= 6.7 m/s of speed on a level landing (energy-conserving projectile arc
## back to the same ground height) -- close to (and, measured below, over)
## SpecialBehavior's own arm_impulse impact threshold (mass * one-tick
## deceleration, SpecialBehavior._check_impact()) -- so the bean's OWN hop
## could immediately impact-trigger itself on landing, cutting its 12s
## lifetime down to a single hop. Reproduced here with a real
## BlockFactory-built cube dropped onto a real Field's own disk collision
## (game/field/Field.gd, a bigger dedicated map -- see the DECISION below) and a
## real SpecialBehavior bound to the real config/gifts/specials/jumping_bean.tres
## def, so Jolt's own collision response is what is actually measured, not a
## stubbed velocity assignment. At the OLD arm_impulse = 5.0 (every sibling
## .tres's shared value), this failed: "observed_hops=2
## max_observed_speed=6.551 is_triggered=true" (a hop's own landing tripped
## it on the first hop). Fixed by raising jumping_bean.tres's own
## arm_impulse to 10.0 -- see the DECISION on JumpingBeanEffect.gd's class
## doc. Counts hops via a rising edge in linear_velocity.y (each hop's own
## vertical kick), since this fixture has no Match/territory host running to
## spy on Match.punch_special_hole()'s call count.
func test_real_physics_hop_landing_does_not_prematurely_impact_trigger() -> void:
	# DECISION (tests/unit/gifts/test_jumping_bean_effect.gd): a dedicated, larger
	# (20 m radius, matching _start_hole_match()'s own round_medium-derived
	# map above) Field registration, not the shared _register_field()/
	# _small_map() (6 m radius) -- a hop's horizontal kick can carry the bean
	# several meters per cycle (hop_horizontal_speed = 3.0 over roughly
	# 2 * hop_impulse / g =~ 1.2s of hang time), and starting near the small
	# map's edge risks the bean actually hopping off the disk and past
	# PhysicsTuning.kill_plane_y mid-test, freeing the body out from under
	# this test for a reason unrelated to the thing being measured. The bean
	# is seeded deterministically (below) so this test's own outcome doesn't
	# depend on which way an unseeded RNG happens to send it.
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_jumping_bean_physics"
	map_def.field_radius = 20.0
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 32
	var field: Field = autofree(Field.new())
	field.map_def = map_def
	add_child_autofree(field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(field, _registry, _blocks_root)

	var defs: Array[SpecialDef] = SpecialDef.load_all_specials()
	var found: SpecialDef = null
	for def: SpecialDef in defs:
		if def.id == &"jumping_bean":
			found = def
			break
	assert_not_null(found, "config/gifts/specials/jumping_bean.tres must be found by load_all_specials()")
	var loaded_effect: JumpingBeanEffect = found.effect as JumpingBeanEffect
	loaded_effect._rng.seed = 12345  # deterministic hop directions for this test

	var shape: BlockShape = load("res://config/blocks/cube.tres") as BlockShape
	var tuning: PhysicsTuning = load("res://config/physics/physics_tuning.tres") as PhysicsTuning
	var block: Block = BlockFactory.build(shape, tuning)
	add_child_autofree(block)
	block.global_position = Vector3(0.0, field.surface_y() + 1.5, 0.0)  # disk centre: maximal margin

	var behavior: SpecialBehavior = SpecialBehavior.new()
	block.add_child(behavior)
	autofree(behavior)
	behavior.bind(block, found, SpecialTuning.new())

	# Let the initial drop settle before counting hop cycles -- a single
	# 1-cube body settles in well under a second (config/physics/PhysicsTuning.gd's
	# own 40-cube-tower benchmark note: "asleep at 0.52s").
	var settle_ticks: int = 0
	while not behavior.has_landed() and settle_ticks < MAX_LAND_FRAMES:
		await wait_physics_frames(1)
		settle_ticks += 1
	assert_true(
		behavior.has_landed(), "setup: the block must land from its initial drop before hopping starts"
	)
	assert_false(
		behavior.is_triggered(),
		"setup: the initial drop's own landing must not already have triggered it"
	)

	# ~3.5s at 60 Hz -- at hop_interval_s = 1.2s (the real tres value), this
	# spans at least two full hop cycles.
	var span_ticks: int = int(round(3.5 * Engine.physics_ticks_per_second))
	var prev_velocity_y: float = block.linear_velocity.y
	var observed_hops: int = 0
	var max_observed_speed: float = 0.0
	for _i: int in range(span_ticks):
		await wait_physics_frames(1)
		var current_velocity_y: float = block.linear_velocity.y
		if current_velocity_y - prev_velocity_y > 3.0:
			observed_hops += 1  # a rising edge in vertical velocity: a hop's own kick
		prev_velocity_y = current_velocity_y
		max_observed_speed = maxf(max_observed_speed, block.linear_velocity.length())

	print(
		"test_real_physics_hop_landing_does_not_prematurely_impact_trigger: observed_hops=%d max_observed_speed=%.3f is_triggered=%s"
		% [observed_hops, max_observed_speed, behavior.is_triggered()]
	)
	assert_gte(observed_hops, 2, "must observe at least two real hop cycles in ~3.5s")
	assert_false(
		behavior.is_triggered(),
		"a hop's own landing must not prematurely impact-trigger the bean (arm_impulse=%.1f)"
			% found.arm_impulse
	)


# --- centre-weighted hop bearing --------------------------

func test_hop_direction_is_biased_toward_centre_yet_can_leave_the_rim() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 4807
	var rim: Vector2 = Vector2(10.0, 0.0)  # inward bearing is -x
	var samples: int = 2000
	var inward_sum: float = 0.0
	var outward_hops: int = 0
	for _i: int in range(samples):
		var dir: Vector2 = JumpingBeanEffect.hop_direction(rim, rng, 0.65, 70.0)
		assert_almost_eq(dir.length(), 1.0, 0.0001)
		inward_sum += -dir.x
		if dir.x > 0.0:
			outward_hops += 1
	assert_gt(inward_sum / float(samples), 0.3, "mean bearing leans toward the disc centre")
	assert_gt(outward_hops, 0, "an off-disc hop stays possible from the rim")
