extends GutTest
## No gusts during a Storm (Bontago-mp0.91, owner playtest: "gust shouldn't occur
## during storm"). The host Breeze scheduler (autoload/match/BreezeEffect.gd)
## skips its spawn attempt while the active weather is Storm and resumes when
## the Storm ends; clear/rain/other weather leave it as before. Gusts reach
## clients only as host announcements (net/BreezeNet.gd), so no announcement
## means no client gust. Shipped numbers: config/breeze.tres.

const DELTA: float = 1.0 / 60.0
const SEED_A: int = 4242
const HIGH_M: float = 20.0
const SIM_SECONDS: float = 600.0
const SIM_STEP: float = 0.1
const MIN_GUSTS_CLEAR: int = 100
const STORM_ID: StringName = &"storm"
const BREEZE_TUNING_PATH: String = "res://config/breeze.tres"
const BLOCK_SHAPE_PATH: String = "res://config/blocks/cube.tres"
const PHYSICS_TUNING_PATH: String = "res://config/physics_tuning.tres"
const FAST_SPAWN_INTERVAL_S: float = 0.1
const DURATION_MARGIN_S: float = 1.0

var _tuning: BreezeTuning = null
var _blocks: Array[Block] = []
var _root: Node3D = null
var _gusts_seen: Array[Dictionary] = []
var _weather_id: StringName = &""


func before_each() -> void:
	_tuning = (load(BREEZE_TUNING_PATH) as BreezeTuning).duplicate() as BreezeTuning
	_blocks.clear()
	_gusts_seen.clear()
	_weather_id = &""
	_root = Node3D.new()
	add_child_autofree(_root)
	Events.breeze_gust_started.connect(_on_gust)


func after_each() -> void:
	Events.breeze_gust_started.disconnect(_on_gust)
	for block: Block in _blocks:
		if is_instance_valid(block):
			block.free()
	_blocks.clear()
	var weather: MatchWeather = Match.weather()
	weather.reset()
	weather.set_effect_factory(Callable())
	weather.set_defs(WeatherTuning.load_all())
	weather.set_host_override(null)
	Match.set_process(true)
	await get_tree().process_frame


func _on_gust(gust: Dictionary) -> void:
	_gusts_seen.append(gust)


func _block(pos: Vector3) -> Block:
	var shape: BlockShape = load(BLOCK_SHAPE_PATH) as BlockShape
	var block: Block = BlockFactory.build(shape, load(PHYSICS_TUNING_PATH) as PhysicsTuning)
	block.gravity_scale = 0.0
	block.linear_damp = 0.0
	_root.add_child(block)
	block.global_position = pos
	_blocks.append(block)
	return block


## A Breeze over one high block whose "active weather" is the test's `_weather_id`.
func _effect(tuning: BreezeTuning = null) -> BreezeEffect:
	var effect: BreezeEffect = BreezeEffect.new()
	effect.tuning = tuning if tuning != null else _tuning
	effect.set_test_world(func() -> Array: return _blocks, func() -> float: return 0.0)
	effect.set_weather_source(func() -> StringName: return _weather_id)
	return effect


func _run(effect: BreezeEffect, seconds: float) -> void:
	for _i: int in range(int(seconds / SIM_STEP)):
		effect.tick(SIM_STEP)


func _fast_tuning() -> BreezeTuning:
	var fast: BreezeTuning = _tuning.duplicate() as BreezeTuning
	fast.spawn_interval_s = FAST_SPAWN_INTERVAL_S
	return fast


# --- Scheduler ------------------------------------------------------------------

func test_no_gust_fires_over_a_long_storm() -> void:
	_block(Vector3(0.0, HIGH_M, 0.0))
	_weather_id = STORM_ID
	var effect: BreezeEffect = _effect()
	effect.begin(SEED_A)
	_run(effect, SIM_SECONDS)
	assert_true(effect.is_quieted_by_weather())
	assert_eq(_gusts_seen.size(), 0, "no gust is announced during a storm")
	assert_eq(effect.gust_count(), 0, "and none lives on the host")
	assert_eq(effect.last_pushed, 0)


func test_clear_and_other_weather_still_spawn_gusts_as_before() -> void:
	_block(Vector3(0.0, HIGH_M, 0.0))
	var baseline: BreezeEffect = _effect()
	baseline.begin(SEED_A)
	_run(baseline, SIM_SECONDS)
	var baseline_gusts: Array[Dictionary] = _gusts_seen.duplicate(true)
	assert_gt(baseline_gusts.size(), MIN_GUSTS_CLEAR, "common high up in clear weather")
	for other: StringName in [&"", &"rain", &"snow", &"fog", &"ceiling"]:
		_gusts_seen.clear()
		_weather_id = other
		var effect: BreezeEffect = _effect()
		effect.begin(SEED_A)
		_run(effect, SIM_SECONDS)
		assert_false(effect.is_quieted_by_weather(), "'%s' does not quiet the breeze" % other)
		assert_eq(_gusts_seen, baseline_gusts, "'%s': the same gust sequence as clear weather" % other)


func test_storm_ending_lets_gusts_resume() -> void:
	_block(Vector3(0.0, HIGH_M, 0.0))
	var effect: BreezeEffect = _effect()
	effect.begin(SEED_A)
	_weather_id = STORM_ID
	_run(effect, SIM_SECONDS * 0.25)
	assert_eq(_gusts_seen.size(), 0, "quiet while the storm lasts")
	_weather_id = &""
	_run(effect, SIM_SECONDS * 0.25)
	var after_storm: int = _gusts_seen.size()
	assert_gt(after_storm, MIN_GUSTS_CLEAR / 4, "the storm ending re-enables gusts")
	_weather_id = STORM_ID
	_run(effect, _tuning.duration_max_s + DURATION_MARGIN_S)
	var settled: int = _gusts_seen.size()
	_run(effect, SIM_SECONDS * 0.25)
	assert_eq(_gusts_seen.size(), settled, "a second storm quiets it again")
	assert_eq(effect.gust_count(), 0, "once the last in-flight gust has expired")


func test_a_gust_in_flight_when_the_storm_starts_finishes_and_no_new_one_follows() -> void:
	# DECISION (BreezeEffect, Bontago-mp0.91): the in-flight gust is not cancelled
	# (its visual on clients cannot be cancelled), it just lives out its life.
	_block(Vector3(0.0, HIGH_M, 0.0))
	var fast: BreezeTuning = _fast_tuning()
	var effect: BreezeEffect = _effect(fast)
	effect.begin(SEED_A)
	_run(effect, fast.duration_max_s)
	assert_gt(effect.gust_count(), 0, "a gust is in flight")
	var announced: int = _gusts_seen.size()
	_weather_id = STORM_ID
	assert_gt(effect.gust_count(), 0, "the storm starting does not cancel it")
	_run(effect, fast.duration_max_s + DURATION_MARGIN_S)
	assert_eq(_gusts_seen.size(), announced, "no new gust is announced during the storm")
	assert_eq(effect.gust_count(), 0, "the in-flight gust expired on its own")


func test_a_storm_leaves_the_forces_of_live_gusts_alone() -> void:
	# The suppression is a spawn gate only: a gust that exists still pushes.
	var block: Block = _block(Vector3(0.0, HIGH_M, 0.0))
	var quiet: BreezeTuning = _tuning.duplicate() as BreezeTuning
	quiet.spawn_interval_s = 1.0e6
	var effect: BreezeEffect = _effect(quiet)
	effect.begin(SEED_A)
	effect.gusts().append({"id": 1, "x": 0.0, "y": HIGH_M, "z": 0.6, "a": 0.0, "r": 3.0, "d": 1000.0, "s": 1.0, "age": 500.0})
	_weather_id = STORM_ID
	for _i: int in range(30):
		effect.tick(DELTA)
		await get_tree().physics_frame
	assert_gt(block.linear_velocity.length(), 0.01, "an in-flight gust keeps pushing")


# --- Real weather state on the host ---------------------------------------------------

func test_breeze_reads_the_host_weather_state_through_match() -> void:
	var weather: MatchWeather = Match.weather()
	Match.set_process(false)
	weather.set_host_override(true)
	weather.set_defs(WeatherTuning.load_all())
	weather.set_effect_factory(func(_def: WeatherTuning) -> WeatherEffect: return null)
	_block(Vector3(0.0, HIGH_M, 0.0))
	var effect: BreezeEffect = BreezeEffect.new()
	effect.tuning = _tuning
	effect.bind(Match)
	effect.set_test_world(func() -> Array: return _blocks, func() -> float: return 0.0)
	effect.begin(SEED_A)
	assert_false(effect.is_quieted_by_weather(), "clear before any weather")
	assert_true(weather.start_event(STORM_ID))
	assert_eq(weather.active_id(), STORM_ID)
	assert_true(effect.is_quieted_by_weather())
	_run(effect, SIM_SECONDS * 0.25)
	assert_eq(_gusts_seen.size(), 0, "no gust while the host's storm event is active")
	assert_true(weather.start_event(&"rain"))
	assert_false(effect.is_quieted_by_weather(), "rain does not quiet it")
	weather.reset()
	assert_false(effect.is_quieted_by_weather(), "and neither does the storm having ended")
	_run(effect, SIM_SECONDS * 0.25)
	assert_gt(_gusts_seen.size(), MIN_GUSTS_CLEAR / 4, "gusts return after the storm")
