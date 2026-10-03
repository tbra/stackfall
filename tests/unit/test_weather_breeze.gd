extends GutTest
## Breeze (Bontago-470.2): the pure gust rules (core/BreezeField.gd), the host
## effect (autoload/match/BreezeEffect.gd) against real Jolt bodies, the wire
## sanitizer and the bounded presenter. Shipped numbers: config/breeze.tres.

const DELTA: float = 1.0 / 60.0
const SEED_A: int = 4242
const SEED_B: int = 777
const HIGH_M: float = 20.0
const LOW_M: float = 0.4
const SIM_SECONDS: float = 1200.0
const SIM_STEP: float = 0.1
const TALL_TOWER_CUBES: int = 32
const TALL_SETTLE_TICKS: int = 120
const GUST_CENTER_HEIGHT_M: float = 24.0
const TOWER_FOOTPRINT: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0), Vector2(1.0, 1.0)]
const TOWER_GAP_M: float = 0.03
const MIN_SWAY_M: float = 1.5
const SHORT_TOWER_CUBES: int = 4
const MAX_SHORT_SWAY_M: float = 0.15

var _tuning: BreezeTuning = null
var _blocks: Array[Block] = []
var _root: Node3D = null
var _gusts_seen: Array[Dictionary] = []


func before_each() -> void:
	_tuning = (load("res://config/breeze.tres") as BreezeTuning).duplicate() as BreezeTuning
	_blocks.clear()
	_gusts_seen.clear()
	_root = Node3D.new()
	add_child_autofree(_root)
	Events.breeze_gust_started.connect(_on_gust)


func after_each() -> void:
	Events.breeze_gust_started.disconnect(_on_gust)
	for block: Block in _blocks:
		if is_instance_valid(block):
			block.free()
	_blocks.clear()
	await get_tree().process_frame


func _on_gust(gust: Dictionary) -> void:
	_gusts_seen.append(gust)


func _block(pos: Vector3) -> Block:
	var shape: BlockShape = load("res://config/blocks/cube.tres") as BlockShape
	var block: Block = BlockFactory.build(shape, load("res://config/physics_tuning.tres") as PhysicsTuning)
	block.gravity_scale = 0.0
	block.linear_damp = 0.0
	_root.add_child(block)
	block.global_position = pos
	_blocks.append(block)
	return block


func _effect(tuning: BreezeTuning = null) -> BreezeEffect:
	var effect: BreezeEffect = BreezeEffect.new()
	if tuning != null:
		effect.tuning = tuning
	else:
		effect.tuning = _tuning
	effect.set_test_world(func() -> Array: return _blocks, func() -> float: return 0.0)
	return effect


func _inject_gust(effect: BreezeEffect, pos: Vector3, radius: float = 3.0, angle: float = 0.0, strength: float = 1.0) -> void:
	effect.gusts().append({"id": 1, "x": pos.x, "y": pos.y, "z": pos.z, "a": angle, "r": radius, "d": 1000.0, "s": strength, "age": 500.0})


func _quiet_tuning() -> BreezeTuning:
	var quiet: BreezeTuning = _tuning.duplicate() as BreezeTuning
	quiet.spawn_interval_s = 1.0e6
	return quiet


func _simulate(effect: BreezeEffect, seed_value: int, seconds: float) -> void:
	effect.begin(seed_value)
	for _i: int in range(int(seconds / SIM_STEP)):
		effect.tick(SIM_STEP)


# --- Config and pure rules ---------------------------------------------------------

func test_breeze_is_weak_and_not_a_weather_type() -> void:
	var storm: StormTuning = load("res://config/weather/storm.tres") as StormTuning
	assert_lt(_tuning.max_accel, storm.max_accel * 0.65, "weaker than Storm")
	assert_lt(_tuning.max_speed_ms, storm.max_speed_ms)
	assert_lt(_tuning.max_dv_per_tick, storm.max_dv_per_tick)
	for def: WeatherTuning in WeatherTuning.load_all():
		assert_ne(def.id, &"breeze", "not schedulable or pickable in the lobby")
	assert_true(_tuning.enabled, "always on by default")


func test_spawn_probability_and_strength_rise_with_height() -> void:
	assert_almost_eq(BreezeField.spawn_probability(0.0, _tuning), _tuning.low_spawn_probability, 0.0001)
	assert_almost_eq(BreezeField.spawn_probability(_tuning.cap_height_m + 3.0, _tuning), 1.0, 0.0001)
	assert_almost_eq(BreezeField.gust_strength(0.0, _tuning), _tuning.low_strength_factor, 0.0001)
	assert_almost_eq(BreezeField.gust_strength(_tuning.cap_height_m, _tuning), 1.0, 0.0001)
	var previous_p: float = -1.0
	var previous_s: float = -1.0
	for i: int in range(0, 15):
		var p: float = BreezeField.spawn_probability(float(i), _tuning)
		var s: float = BreezeField.gust_strength(float(i), _tuning)
		assert_gte(p, previous_p)
		assert_gte(s, previous_s)
		previous_p = p
		previous_s = s


func test_envelope_and_falloff_shapes() -> void:
	assert_almost_eq(BreezeField.envelope(0.0, 3.0), 0.0, 0.0001)
	assert_almost_eq(BreezeField.envelope(1.5, 3.0), 1.0, 0.0001)
	assert_almost_eq(BreezeField.envelope(3.0, 3.0), 0.0, 0.0001)
	assert_almost_eq(BreezeField.falloff(0.0, 4.0), 1.0, 0.0001)
	assert_almost_eq(BreezeField.falloff(4.0, 4.0), 0.0, 0.0001)
	assert_eq(BreezeField.falloff(9.0, 4.0), 0.0)
	assert_gt(BreezeField.falloff(1.0, 4.0), BreezeField.falloff(3.0, 4.0))


func test_gust_accel_is_local_clamped_and_swirls_to_both_sides() -> void:
	var gust: Dictionary = {"id": 1, "x": 0.0, "y": HIGH_M, "z": 0.0, "a": 0.0, "r": 4.0, "d": 4.0, "s": 1.0}
	assert_eq(BreezeField.gust_accel(gust, 2.0, Vector3(9.0, HIGH_M, 0.0), 0.0, DELTA, _tuning), Vector3.ZERO, "outside the sphere")
	assert_eq(BreezeField.gust_accel(gust, 0.0, Vector3(0.5, HIGH_M, 0.0), 0.0, DELTA, _tuning), Vector3.ZERO, "no envelope at birth")
	var low_gust: Dictionary = gust.duplicate()
	low_gust["y"] = _tuning.threshold_height_m * 0.5
	assert_eq(BreezeField.gust_accel(low_gust, 2.0, Vector3(0.5, _tuning.threshold_height_m * 0.5, 0.0), 0.0, DELTA, _tuning), Vector3.ZERO, "below the threshold nothing moves")
	var left: Vector3 = BreezeField.gust_accel(gust, 2.0, Vector3(0.0, HIGH_M, 1.0), 0.0, DELTA, _tuning)
	var right: Vector3 = BreezeField.gust_accel(gust, 2.0, Vector3(0.0, HIGH_M, -1.0), 0.0, DELTA, _tuning)
	assert_gt(left.length(), 0.0)
	assert_ne(signf(left.z), signf(right.z), "opposite sides are pushed off the heading opposite ways")
	assert_lte(left.length() * DELTA, _tuning.max_dv_per_tick + 0.0001, "per-tick dv clamp")
	var strong: BreezeTuning = _tuning.duplicate() as BreezeTuning
	strong.strength = 100.0
	assert_lte(BreezeField.gust_accel(gust, 2.0, Vector3(0.0, HIGH_M, 1.0), 0.0, DELTA, strong).length() * DELTA, strong.max_dv_per_tick + 0.0001, "global strength cannot break the clamp")


# --- Tower sway (Bontago-mp0.28) ------------------------------------------------------

func _tall_field() -> Field:
	var field: Field = Field.new()
	field.map_def = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	field.map_def.field_radius = 8.0
	_root.add_child(field)
	return field


func _real_tower(count: int) -> Array[Block]:
	var shape: BlockShape = load("res://config/blocks/cube.tres") as BlockShape
	var physics: PhysicsTuning = load("res://config/physics_tuning.tres") as PhysicsTuning
	var edge: float = physics.cube_size - physics.cube_margin
	var built: Array[Block] = []
	for i: int in range(count):
		for column: Vector2 in TOWER_FOOTPRINT:
			var block: Block = BlockFactory.build(shape, physics)
			_root.add_child(block)
			block.global_position = Vector3(column.x * (edge + TOWER_GAP_M), edge * 0.5 + edge * float(i), column.y * (edge + TOWER_GAP_M))
			_blocks.append(block)
			if column == TOWER_FOOTPRINT[0]:
				built.append(block)
	return built


## Largest horizontal displacement of the tower's top over one gust (or none).
func _top_sway(count: int, with_gust: bool, center_height: float) -> float:
	_tall_field()
	var tower: Array[Block] = _real_tower(count)
	for _i: int in range(TALL_SETTLE_TICKS):
		await get_tree().physics_frame
	var top: Block = tower[count - 1]
	var start: Vector3 = top.global_position
	var effect: BreezeEffect = _effect(_quiet_tuning())
	effect.begin(SEED_A)
	if with_gust:
		var duration: float = (_tuning.duration_min_s + _tuning.duration_max_s) * 0.5
		var radius: float = (_tuning.radius_min_m + _tuning.radius_max_m) * 0.5
		effect.gusts().append({"id": 1, "x": 0.0, "y": center_height, "z": 0.0, "a": 0.0, "r": radius, "d": duration, "s": 1.0, "age": 0.0})
	var moved: float = 0.0
	for _i: int in range(int((_tuning.duration_max_s + 3.0) * 60.0)):
		effect.tick(DELTA)
		await get_tree().physics_frame
		if not is_instance_valid(top):
			return INF
		moved = maxf(moved, Vector2(top.global_position.x - start.x, top.global_position.z - start.z).length())
	return moved


func test_a_gust_visibly_sways_a_tall_tower() -> void:
	var quiet: float = await _top_sway(TALL_TOWER_CUBES, false, GUST_CENTER_HEIGHT_M)
	for block: Block in _blocks:
		block.free()
	_blocks.clear()
	var gusted: float = await _top_sway(TALL_TOWER_CUBES, true, GUST_CENTER_HEIGHT_M)
	gut.p("tall tower top sway: quiet %.2f m, gusted %.2f m" % [quiet, gusted])
	assert_gt(gusted, quiet + MIN_SWAY_M, "a gust moves a 48 m tower's top")


func test_gust_visual_travels_along_the_physics_heading() -> void:
	var straight: BreezeTuning = _tuning.duplicate() as BreezeTuning
	straight.swirl_deg = 0.0
	for angle: float in [0.0, 1.0, 2.5, -2.0, 4.0]:
		var gust: Dictionary = {"id": 3, "x": 0.0, "y": HIGH_M, "z": 0.0, "a": angle, "r": 6.0, "d": 4.0, "s": 1.0}
		var visual: GustPresentation = GustPresentation.new()
		visual.configure(gust, straight)
		add_child_autofree(visual)
		var drawn: Vector3 = visual.material().get_shader_parameter(&"wind_dir") as Vector3
		var pushed: Vector3 = BreezeField.gust_accel(gust, 2.0, Vector3(0.0, HIGH_M, 0.0), 0.0, DELTA, straight)
		assert_gt(pushed.length(), 0.0)
		assert_lt(drawn.distance_to(pushed.normalized()), 0.001, "visual heading equals the push at angle %.1f" % angle)
		var field: Vector2 = BreezeField.heading(angle)
		assert_lt(drawn.distance_to(Vector3(field.x, 0.0, field.y)), 0.001)


func test_shipped_swirl_keeps_the_push_near_the_visual_heading() -> void:
	assert_lte(_tuning.swirl_deg, 15.0, "swirl may only nudge blocks off the drawn heading")


func test_a_short_stack_barely_notices_a_gust() -> void:
	var sway: float = await _top_sway(SHORT_TOWER_CUBES, true, float(SHORT_TOWER_CUBES) * 0.5)
	assert_lt(sway, MAX_SHORT_SWAY_M, "a 4 m stack stays put (%.3f m)" % sway)


# --- Spawning ------------------------------------------------------------------------

func test_spawn_sequence_is_deterministic_per_seed() -> void:
	for h: float in [HIGH_M, HIGH_M + 2.0, HIGH_M - 3.0]:
		_block(Vector3(h * 0.1, h, 0.0))
	var effect: BreezeEffect = _effect()
	_simulate(effect, SEED_A, 120.0)
	var first: Array[Dictionary] = _gusts_seen.duplicate(true)
	_gusts_seen.clear()
	_simulate(effect, SEED_A, 120.0)
	var second: Array[Dictionary] = _gusts_seen.duplicate(true)
	_gusts_seen.clear()
	_simulate(effect, SEED_B, 120.0)
	assert_gt(first.size(), 5)
	assert_eq(first, second, "same seed and blocks, same gusts")
	assert_ne(first, _gusts_seen, "another seed differs")


func test_gusts_are_rare_low_and_common_high() -> void:
	_block(Vector3(0.0, LOW_M, 0.0))
	var low_effect: BreezeEffect = _effect()
	_simulate(low_effect, SEED_A, SIM_SECONDS)
	var low_count: int = _gusts_seen.size()
	var low_strength: float = 0.0
	for gust: Dictionary in _gusts_seen:
		low_strength += float(gust["s"])
	_gusts_seen.clear()
	_blocks[0].global_position = Vector3(0.0, HIGH_M, 0.0)
	var high_effect: BreezeEffect = _effect()
	_simulate(high_effect, SEED_A, SIM_SECONDS)
	var high_count: int = _gusts_seen.size()
	assert_gt(high_count, 200, "common above the cap height")
	assert_lt(low_count, high_count / 8, "rare at the disc")
	if low_count > 0:
		assert_lt(low_strength / float(low_count), 0.6, "low gusts are weak")
	for gust: Dictionary in _gusts_seen:
		assert_almost_eq(float(gust["s"]), 1.0, 0.0001, "high gusts are full strength")


func test_active_gusts_are_capped_and_expire() -> void:
	_block(Vector3(0.0, HIGH_M, 0.0))
	var fast: BreezeTuning = _tuning.duplicate() as BreezeTuning
	fast.spawn_interval_s = 0.1
	fast.max_active_gusts = 3
	var effect: BreezeEffect = _effect(fast)
	effect.begin(SEED_A)
	for _i: int in range(300):
		effect.tick(SIM_STEP)
		assert_lte(effect.gust_count(), 3)
	effect.set_enabled(false)
	assert_eq(effect.gust_count(), 0, "the F4 toggle ends every gust")
	for _i: int in range(100):
		effect.tick(SIM_STEP)
	assert_eq(effect.gust_count(), 0, "and none spawn while off")


# --- Host effect on real bodies ------------------------------------------------------

func test_a_gust_pushes_only_blocks_inside_it() -> void:
	var near: Block = _block(Vector3(0.0, HIGH_M, 0.0))
	var far: Block = _block(Vector3(40.0, HIGH_M, 0.0))
	var effect: BreezeEffect = _effect(_quiet_tuning())
	effect.begin(SEED_A)
	_inject_gust(effect, Vector3(0.0, HIGH_M, 0.6))
	for _i: int in range(30):
		effect.tick(DELTA)
		await get_tree().physics_frame
	assert_gt(near.linear_velocity.length(), 0.01, "inside the gust")
	assert_almost_eq(far.linear_velocity.length(), 0.0, 0.0001, "outside is untouched")
	assert_eq(near.linear_velocity.y, 0.0, "horizontal only")


func test_speed_and_dv_are_clamped_over_a_long_gust() -> void:
	var block: Block = _block(Vector3(0.0, HIGH_M, 0.0))
	var effect: BreezeEffect = _effect(_quiet_tuning())
	effect.begin(SEED_A)
	_inject_gust(effect, Vector3(0.0, HIGH_M, 0.6), 6.0)
	var widest: float = 0.0
	var previous: Vector3 = Vector3.ZERO
	for _i: int in range(60 * 6):
		effect.tick(DELTA)
		await get_tree().physics_frame
		widest = maxf(widest, (block.linear_velocity - previous).length())
		previous = block.linear_velocity
		block.global_position.x = 0.0
	assert_lte(widest, _tuning.max_dv_per_tick * 3.0)
	assert_lte(block.linear_velocity.length(), _tuning.max_speed_ms + _tuning.max_dv_per_tick * 3.0)


func test_sleepers_wake_only_when_the_push_reaches_the_wake_threshold() -> void:
	var strong_tuning: BreezeTuning = _quiet_tuning()
	strong_tuning.wake_accel = 0.0001
	var block: Block = _block(Vector3(0.0, HIGH_M, 0.0))
	await get_tree().physics_frame
	block.sleeping = true
	var picky: BreezeTuning = _quiet_tuning()
	picky.wake_accel = 1000.0
	var effect: BreezeEffect = _effect(picky)
	effect.begin(SEED_A)
	_inject_gust(effect, Vector3(0.0, HIGH_M, 0.6))
	for _i: int in range(20):
		effect.tick(DELTA)
		await get_tree().physics_frame
	assert_true(block.sleeping, "a gentle push leaves a sleeper asleep")
	var eager: BreezeEffect = _effect(strong_tuning)
	eager.begin(SEED_A)
	_inject_gust(eager, Vector3(0.0, HIGH_M, 0.6))
	for _i: int in range(20):
		eager.tick(DELTA)
		await get_tree().physics_frame
	assert_false(block.sleeping, "a push at the threshold wakes it")


func test_frozen_blocks_and_clients_are_never_pushed() -> void:
	var frozen: Block = _block(Vector3(0.0, HIGH_M, 0.0))
	frozen.request_freeze_static(Block.FREEZE_REASON_STABLE)
	var effect: BreezeEffect = _effect(_quiet_tuning())
	effect.begin(SEED_A)
	_inject_gust(effect, Vector3(0.0, HIGH_M, 0.6))
	effect.tick(DELTA)
	assert_eq(effect.last_pushed, 0)
	var client: BreezeEffect = BreezeEffect.new()
	client.tuning = _quiet_tuning()
	client._blocks_source = func() -> Array: return _blocks
	client._surface_source = func() -> float: return 0.0
	client.begin(SEED_A)
	_inject_gust(client, Vector3(0.0, HIGH_M, 0.6))
	client.tick(DELTA)
	assert_eq(client.last_pushed, 0, "no host authority, no push")
	assert_eq(_gusts_seen.size(), 0, "and no spawn")


func test_breeze_and_storm_sum_and_stay_within_both_clamps() -> void:
	var storm_tuning: StormTuning = load("res://config/weather/storm.tres") as StormTuning
	var block: Block = _block(Vector3(0.0, HIGH_M, 0.0))
	var storm: StormEffect = StormEffect.new()
	storm.tuning = storm_tuning
	storm.set_seed(SEED_A)
	storm.set_test_world(func() -> Array: return _blocks, func() -> float: return 0.0)
	var breeze: BreezeEffect = _effect(_quiet_tuning())
	breeze.begin(SEED_A)
	_inject_gust(breeze, Vector3(0.0, HIGH_M, 0.6), 8.0)
	var both_ticks: int = 0
	var widest: float = 0.0
	var previous: Vector3 = Vector3.ZERO
	for _i: int in range(60 * 4):
		storm.tick(DELTA, 1.0)
		breeze.tick(DELTA)
		if storm.last_pushed > 0 and breeze.last_pushed > 0:
			both_ticks += 1
		await get_tree().physics_frame
		widest = maxf(widest, (block.linear_velocity - previous).length())
		previous = block.linear_velocity
		block.global_position.x = 0.0
		block.global_position.z = 0.0
	assert_gt(both_ticks, 5, "both layers act on the same block (Breeze then hits its own speed cap)")
	assert_lte(widest, (storm_tuning.max_dv_per_tick + _tuning.max_dv_per_tick) * 3.0, "summed dv is bounded by the two clamps")
	assert_lte(block.linear_velocity.length(), storm_tuning.max_speed_ms + _tuning.max_speed_ms + 0.6, "summed speed is bounded")


# --- Lifecycle through MatchWeather ------------------------------------------------------

func test_breeze_runs_with_weather_off_and_stops_on_reset_and_is_host_only_toggle() -> void:
	var w: MatchWeather = MatchWeather.new()
	w.set_host_override(true)
	var config: MatchConfig = MatchConfig.new()
	config.weather_mode = MatchConfig.WeatherMode.OFF
	config.rng_seed = 9
	w.begin_match(config)
	assert_false(w.is_running(), "no weather scheduled")
	w.begin_breeze(config)
	assert_true(w.breeze().is_running(), "breeze does not depend on the weather mode")
	assert_true(w.set_breeze_enabled(false))
	assert_false(w.breeze_enabled())
	w.reset()
	assert_false(w.breeze().is_running())
	assert_eq(w.breeze().gust_count(), 0)
	var client: MatchWeather = MatchWeather.new()
	client.set_host_override(false)
	assert_false(client.set_breeze_enabled(false))


# --- Wire and presentation ---------------------------------------------------------------

func _wire(id: int = 1) -> Dictionary:
	return {"id": id, "x": 1.0, "y": 8.0, "z": -2.0, "a": 1.2, "r": 3.0, "d": 3.0, "s": 0.8}


func test_client_sanitizer_accepts_good_and_refuses_hostile_gusts() -> void:
	assert_false(BreezeNet.sanitize_gust(_wire(), _tuning).is_empty())
	assert_true(BreezeNet.sanitize_gust("nope", _tuning).is_empty())
	var extra: Dictionary = _wire()
	extra["evil"] = 1
	assert_true(BreezeNet.sanitize_gust(extra, _tuning).is_empty(), "extra key")
	var missing: Dictionary = _wire()
	missing.erase("s")
	assert_true(BreezeNet.sanitize_gust(missing, _tuning).is_empty(), "missing key")
	for bad: Array in [["x", INF], ["x", NAN], ["y", 1.0e9], ["r", 0.0], ["r", 1000.0], ["d", -1.0], ["d", 9999.0], ["s", 2.0], ["s", -0.1], ["a", 1.0e6], ["id", 0], ["id", 1.5], ["z", "1"]]:
		var gust: Dictionary = _wire()
		gust[bad[0]] = bad[1]
		assert_true(BreezeNet.sanitize_gust(gust, _tuning).is_empty(), "rejects %s=%s" % [bad[0], bad[1]])


func test_client_drops_duplicate_and_stale_gust_ids() -> void:
	var net: BreezeNet = BreezeNet.new()
	add_child_autofree(net)
	assert_true(net.apply_gust(_wire(5)))
	assert_false(net.apply_gust(_wire(5)), "duplicate")
	assert_false(net.apply_gust(_wire(3)), "stale")
	assert_true(net.apply_gust(_wire(6)))
	assert_eq(net.gusts_applied, 2)
	assert_eq(net.gusts_refused, 2)
	assert_eq(_gusts_seen.size(), 2, "accepted gusts are re-emitted for the presenter")


func test_presenter_draws_gusts_bounded_and_frees_them() -> void:
	var presenter: BreezePresenter = BreezePresenter.new()
	presenter.tuning = _tuning
	add_child_autofree(presenter)
	for i: int in range(_tuning.max_presented_gusts + 8):
		Events.breeze_gust_started.emit(_wire(i + 1))
	assert_eq(presenter.live_count(), _tuning.max_presented_gusts, "bounded")
	var first: GustPresentation = presenter.get_child(0) as GustPresentation
	assert_gt(first.streak_count(), 0)
	presenter.clear()
	await get_tree().process_frame
	assert_eq(presenter.live_count(), 0)


func test_gust_ribbon_is_a_flat_wisp_strip() -> void:
	# Bontago-mp0.81: a gust draws the soft wisp look (the curled swoosh moved to the ambient wind).
	var mesh: ArrayMesh = GustPresentation.build_wisp_ribbon()
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	assert_eq(verts.size(), (GustPresentation.RIBBON_SEGMENTS + 1) * 2)
	assert_almost_eq(uvs[0].x, 0.0, 0.0001)
	assert_almost_eq(uvs[uvs.size() - 1].x, 1.0, 0.0001)
	for v: Vector3 in verts:
		assert_almost_eq(absf(v.y), 0.5, 0.0001, "two straight edges: the shader bows and tapers the strip")


func test_a_gust_draws_wisps_in_a_box_around_itself() -> void:
	var gust: Dictionary = _wire(1)
	var presenter: BreezePresenter = BreezePresenter.new()
	presenter.tuning = _tuning
	add_child_autofree(presenter)
	Events.breeze_gust_started.emit(gust)
	var visual: GustPresentation = presenter.get_child(0) as GustPresentation
	assert_eq(visual.get_child_count(), 1, "one MultiMesh of wisps")
	var material: ShaderMaterial = visual.material()
	assert_eq(material.shader.resource_path, "res://shaders/wind_streak.gdshader", "the wisp shader")
	assert_eq(float(material.get_shader_parameter(&"mote_mix")), 0.0, "wisps, not motes")
	assert_true(bool(material.get_shader_parameter(&"box_align")), "scattered along and across the heading")
	assert_eq(material.get_shader_parameter(&"box_center") as Vector3, Vector3(float(gust["x"]), float(gust["y"]), float(gust["z"])))
	var half: Vector3 = material.get_shader_parameter(&"box_half") as Vector3
	assert_almost_eq(half.x, float(gust["r"]) * _tuning.gust_spread_along_frac, 0.0001)
	assert_almost_eq(half.y, float(gust["r"]) * _tuning.gust_spread_up_frac, 0.0001)
	assert_almost_eq(half.z, float(gust["r"]) * _tuning.gust_spread_side_frac, 0.0001)
	assert_almost_eq(float(material.get_shader_parameter(&"box_base_y")), -half.y, 0.0001)
	assert_gte(_tuning.gust_streak_count, 15, "a gust is a band of many wisps")
	assert_gt(_tuning.gust_height_bias, 1.0, "more wisps high up")
	assert_gt(_tuning.gust_height_length_gain, 0.0, "longer wisps high up")
	assert_almost_eq(GustPresentation.wisp_life_m(_tuning) / _tuning.gust_streak_speed_ms, _tuning.gust_stroke_cycle_s, 0.0001, "a wisp cycles in the gust stroke cycle")


func _drawn_strokes(preset_id: StringName) -> int:
	Settings.set_graphics_preset(preset_id)
	var presenter: BreezePresenter = BreezePresenter.new()
	presenter.tuning = _tuning
	add_child_autofree(presenter)
	Events.breeze_gust_started.emit(_wire(1))
	var gust: GustPresentation = presenter.get_child(0) as GustPresentation
	return gust.streak_count()


func test_gust_stroke_count_and_low_preset_density() -> void:
	var original: StringName = Settings.current_graphics_preset().id
	var high: int = _drawn_strokes(&"high")
	var low: int = _drawn_strokes(&"low")
	Settings.set_graphics_preset(original)
	assert_eq(high, _tuning.gust_streak_count, "High draws every stroke")
	assert_lt(low, high, "Low draws fewer strokes than High")
	assert_eq(low, int(round(float(high) * _tuning.gust_low_preset_density)), "Low draws the tuned fraction")


func test_a_gust_visual_frees_itself_when_the_gust_ends() -> void:
	var presenter: BreezePresenter = BreezePresenter.new()
	presenter.tuning = _tuning
	add_child_autofree(presenter)
	var gust: Dictionary = _wire()
	gust["d"] = 0.1
	Events.breeze_gust_started.emit(gust)
	assert_eq(presenter.live_count(), 1)
	await get_tree().create_timer(0.4).timeout
	assert_eq(presenter.live_count(), 0)


func test_tuning_panel_breeze_toggle_is_host_only() -> void:
	var panel: TuningPanel = load("res://ui/TuningPanel.tscn").instantiate() as TuningPanel
	add_child_autofree(panel)
	var w: MatchWeather = MatchWeather.new()
	w.set_host_override(true)
	panel.weather_provider = w
	panel.net_provider = FakeNet.host()
	panel.rebuild()
	var toggle: CheckButton = panel._tab_container.find_child("BreezeToggle", true, false) as CheckButton
	assert_not_null(toggle)
	assert_false(toggle.disabled)
	assert_true(panel.apply_breeze_enabled(false))
	assert_false(w.breeze_enabled())
	panel.net_provider = FakeNet.client(0)
	panel.rebuild()
	toggle = panel._tab_container.find_child("BreezeToggle", true, false) as CheckButton
	assert_true(toggle.disabled)
	assert_false(panel.apply_breeze_enabled(true))
