extends GutTest
## Wind weather (Bontago-22y.4): the pure height/gust/direction rules
## (core/WindField.gd), the host effect (autoload/match/StormEffect.gd) against
## real Jolt bodies, and the client presentation. Wind's shipped numbers come
## from config/weather/storm.tres.

const DELTA: float = 1.0 / 60.0
const TOWER_CUBES: int = 14
const LOW_PILE_CUBES: int = 2
const RUN_SECONDS: float = 8.0
const SETTLE_TICKS: int = 90
const TOPPLE_DISPLACEMENT_M: float = 3.0
const STAY_DISPLACEMENT_M: float = 0.5
const SEED_A: int = 12345
const SEED_B: int = 987654

var _tuning: StormTuning = null
var _blocks: Array[Block] = []
var _root: Node3D = null


func before_each() -> void:
	_tuning = load("res://config/weather/storm.tres") as StormTuning
	_blocks.clear()
	_root = Node3D.new()
	add_child_autofree(_root)


func after_each() -> void:
	# Free bodies before the field they rest on, then let the queue drain.
	for block: Block in _blocks:
		if is_instance_valid(block):
			block.free()
	_blocks.clear()
	await get_tree().process_frame


func _effect(seed_value: int = SEED_A) -> StormEffect:
	var effect: StormEffect = StormEffect.new()
	effect.tuning = _tuning
	effect.set_seed(seed_value)
	effect.set_test_world(func() -> Array: return _blocks, func() -> float: return 0.0)
	return effect


func _floating_block(height: float) -> Block:
	var shape: BlockShape = load("res://config/blocks/cube.tres") as BlockShape
	var block: Block = BlockFactory.build(shape, load("res://config/physics_tuning.tres") as PhysicsTuning)
	block.gravity_scale = 0.0
	block.linear_damp = 0.0
	_root.add_child(block)
	block.global_position = Vector3(0.0, height, 0.0)
	_blocks.append(block)
	return block


func _field() -> Field:
	var field: Field = Field.new()
	field.map_def = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	field.map_def.field_radius = 6.0
	_root.add_child(field)
	return field


func _tower(count: int, x: float) -> Array[Block]:
	var shape: BlockShape = load("res://config/blocks/cube.tres") as BlockShape
	var physics: PhysicsTuning = load("res://config/physics_tuning.tres") as PhysicsTuning
	var edge: float = physics.cube_size - physics.cube_margin
	var built: Array[Block] = []
	for i: int in range(count):
		var block: Block = BlockFactory.build(shape, physics)
		_root.add_child(block)
		block.global_position = Vector3(x, edge * 0.5 + edge * float(i), 0.0)
		_blocks.append(block)
		built.append(block)
	return built


func _run_wind(effect: StormEffect, seconds: float, intensity: float = 1.0) -> void:
	for _i: int in range(int(seconds * 60.0)):
		effect.tick(DELTA, intensity)
		await get_tree().physics_frame


# --- Pure rules ---------------------------------------------------------------------

func test_force_is_zero_below_threshold_and_monotonic_to_cap() -> void:
	assert_eq(WindField.height_factor(_tuning.threshold_height_m, _tuning), 0.0)
	assert_eq(WindField.height_factor(0.0, _tuning), 0.0)
	assert_eq(WindField.height_factor(_tuning.cap_height_m, _tuning), 1.0)
	assert_eq(WindField.height_factor(_tuning.cap_height_m + 50.0, _tuning), 1.0)
	var previous: float = 0.0
	var h: float = _tuning.threshold_height_m
	while h <= _tuning.cap_height_m:
		var factor: float = WindField.height_factor(h, _tuning)
		assert_gte(factor, previous, "monotonic at %.2f m" % h)
		previous = factor
		h += 0.25


func test_accel_scales_with_intensity_and_clamps_per_tick() -> void:
	var full: float = WindField.accel_at(_tuning.cap_height_m, 0.5, 1.0, DELTA, _tuning)
	var half: float = WindField.accel_at(_tuning.cap_height_m, 0.25, 1.0, DELTA, _tuning)
	assert_almost_eq(half, full * 0.5, 0.0001)
	assert_lte(WindField.accel_at(_tuning.cap_height_m, 1.0, 1.0, DELTA, _tuning) * DELTA, _tuning.max_dv_per_tick + 0.0001)
	var strong: StormTuning = _tuning.duplicate() as StormTuning
	strong.max_accel = 1000.0
	assert_almost_eq(WindField.accel_at(strong.cap_height_m, 1.0, 1.0, DELTA, strong) * DELTA, strong.max_dv_per_tick, 0.0001)


func test_direction_and_gust_are_deterministic_from_seed() -> void:
	assert_eq(WindField.direction(SEED_A, 3.0, _tuning), WindField.direction(SEED_A, 3.0, _tuning))
	assert_ne(WindField.direction(SEED_A, 3.0, _tuning), WindField.direction(SEED_B, 3.0, _tuning))
	assert_almost_eq(WindField.direction(SEED_A, 11.0, _tuning).length(), 1.0, 0.0001)
	assert_eq(WindField.gust(SEED_A, 4.2, _tuning), WindField.gust(SEED_A, 4.2, _tuning))
	var lowest: float = 2.0
	var highest: float = -1.0
	var t: float = 0.0
	while t < 60.0:
		var g: float = WindField.gust(SEED_A, t, _tuning)
		lowest = minf(lowest, g)
		highest = maxf(highest, g)
		t += 0.1
	assert_gte(lowest, 1.0 - _tuning.gust_amplitude - 0.0001)
	assert_lte(highest, 1.0 + 0.0001)
	assert_gt(highest - lowest, 0.1, "gusts actually vary")
	var drift: float = WindField.direction(SEED_A, 0.0, _tuning).angle_to(WindField.direction(SEED_A, _tuning.veer_period_s * 0.25, _tuning))
	assert_lte(absf(drift), deg_to_rad(_tuning.veer_amplitude_deg * 2.0) + 0.0001, "veer stays inside its amplitude")


func test_direction_is_drawn_per_event_and_replicated() -> void:
	var first: Vector2 = WindField.direction(WindField.event_seed(SEED_A, 1), 0.0, _tuning)
	var second: Vector2 = WindField.direction(WindField.event_seed(SEED_A, 2), 0.0, _tuning)
	assert_ne(first, second, "each event has its own heading")
	assert_eq(first, WindField.direction(WindField.event_seed(SEED_A, 1), 0.0, _tuning))
	# The event index rides the wire: a client adopting host state gets the same seed inputs.
	var host: MatchWeather = MatchWeather.new()
	host.set_host_override(true)
	host.set_defs([_tuning] as Array[WeatherTuning])
	assert_true(host.start_event(&"storm"))
	var state: Dictionary = host.state_dict()
	assert_eq(int(state["ev"]), 1)
	var client: MatchWeather = MatchWeather.new()
	client.set_host_override(false)
	client.set_defs([_tuning] as Array[WeatherTuning])
	assert_true(client.apply_replicated_state(state, true))
	assert_eq(client.event_index(), host.event_index())
	assert_eq(client.seed_value(), host.seed_value())
	host.reset()
	client.reset()


func test_blocks_owning_their_physics_are_skipped() -> void:
	var special: Block = _floating_block(_tuning.cap_height_m + 2.0)
	special.add_child(SpecialBehavior.new())
	var glued: Block = _floating_block(_tuning.cap_height_m + 2.0)
	glued.add_child(GlueJoint.new())
	var effect: StormEffect = _effect()
	effect.tick(DELTA, 1.0)
	assert_eq(effect.last_pushed, 0)
	special.get_child(special.get_child_count() - 1).queue_free()
	await get_tree().process_frame
	effect.tick(DELTA, 1.0)
	assert_eq(effect.last_pushed, 1, "the ordinary block stays pushable")


# --- Host effect --------------------------------------------------------------------

func test_only_blocks_above_threshold_are_pushed() -> void:
	var low: Block = _floating_block(_tuning.threshold_height_m - 0.5)
	var high: Block = _floating_block(_tuning.cap_height_m + 2.0)
	var effect: StormEffect = _effect()
	await _run_wind(effect, 0.5)
	assert_almost_eq(low.linear_velocity.length(), 0.0, 0.001, "below the threshold nothing moves")
	assert_gt(high.linear_velocity.length(), 0.1, "above the cap the block is pushed")
	assert_eq(high.linear_velocity.y, 0.0, "the wind is horizontal")


func test_speed_and_velocity_change_are_clamped() -> void:
	var high: Block = _floating_block(_tuning.cap_height_m + 5.0)
	var effect: StormEffect = _effect()
	var widest_step: float = 0.0
	var previous: Vector3 = Vector3.ZERO
	for _i: int in range(60 * 6):
		effect.tick(DELTA, 1.0)
		await get_tree().physics_frame
		widest_step = maxf(widest_step, (high.linear_velocity - previous).length())
		previous = high.linear_velocity
	assert_lte(widest_step, _tuning.max_dv_per_tick * 3.0, "per-tick dv stays near the clamp")
	assert_lte(high.linear_velocity.length(), _tuning.max_speed_ms + _tuning.max_dv_per_tick * 3.0, "capped along-wind speed")


func test_sleeping_blocks_wake_only_above_the_wake_threshold() -> void:
	var gentle_height: float = _tuning.threshold_height_m + 0.5
	assert_lt(WindField.accel_at(gentle_height, 1.0, 1.0, DELTA, _tuning), _tuning.wake_accel, "fixture: gentle push is below the wake threshold")
	var gentle: Block = _floating_block(gentle_height)
	var strong: Block = _floating_block(_tuning.cap_height_m + 2.0)
	await get_tree().physics_frame
	gentle.sleeping = true
	strong.sleeping = true
	var effect: StormEffect = _effect()
	await _run_wind(effect, 0.5)
	assert_true(gentle.sleeping, "a gentle push leaves a sleeper asleep")
	assert_false(strong.sleeping, "a strong push wakes it")


func test_sleepers_are_a_rotating_subset() -> void:
	var sleeper: Block = _floating_block(_tuning.cap_height_m + 2.0)
	await get_tree().physics_frame
	sleeper.sleeping = true
	var effect: StormEffect = _effect()
	var pushed_ticks: int = 0
	var awake_pushes: int = 0
	for _i: int in range(_tuning.sleeper_stride_ticks):
		effect.tick(DELTA, 1.0)
		pushed_ticks += effect.last_pushed
		# Re-sleep so every tick is judged as a sleeper (the fixture is one block).
		sleeper.sleeping = true
	assert_eq(pushed_ticks, 1, "one sleeper is evaluated once per stride")
	sleeper.sleeping = false
	effect.tick(DELTA, 1.0)
	awake_pushes = effect.last_pushed
	assert_eq(awake_pushes, 1, "an awake block is pushed every tick")


func test_frozen_blocks_are_never_pushed() -> void:
	var frozen: Block = _floating_block(_tuning.cap_height_m + 2.0)
	frozen.request_freeze_static(Block.FREEZE_REASON_STABLE)
	var effect: StormEffect = _effect()
	effect.tick(DELTA, 1.0)
	assert_eq(effect.last_pushed, 0)


func test_clients_never_apply_physics() -> void:
	var high: Block = _floating_block(_tuning.cap_height_m + 2.0)
	# A client has no host authority: an effect with no host seam and no
	# authoritative Match never pushes, even given blocks to push.
	var effect: StormEffect = StormEffect.new()
	effect.tuning = _tuning
	effect._blocks_source = func() -> Array: return _blocks
	effect._surface_source = func() -> float: return 0.0
	effect.tick(DELTA, 1.0)
	await get_tree().physics_frame
	assert_eq(effect.last_pushed, 0)
	assert_almost_eq(high.linear_velocity.length(), 0.0, 0.0001)


func test_stop_leaves_no_force() -> void:
	var high: Block = _floating_block(_tuning.cap_height_m + 2.0)
	var effect: StormEffect = _effect()
	await _run_wind(effect, 0.5)
	effect.restore()
	effect.restore()
	var speed_after_stop: float = high.linear_velocity.length()
	await _run_wind(effect, 0.0)
	for _i: int in range(30):
		await get_tree().physics_frame
	assert_almost_eq(high.linear_velocity.length(), speed_after_stop, 0.001, "no force lingers after restore")
	assert_eq(effect.last_pushed, 0)


func test_zero_intensity_pushes_nothing() -> void:
	_floating_block(_tuning.cap_height_m + 2.0)
	var effect: StormEffect = _effect()
	effect.tick(DELTA, 0.0)
	assert_eq(effect.last_pushed, 0)


func test_match_weather_builds_wind_effect_from_the_shipped_def() -> void:
	var def: WeatherTuning = load("res://config/weather/storm.tres") as WeatherTuning
	assert_true(def is StormTuning)
	assert_eq(def.id, &"storm")
	var effect: WeatherEffect = (load(def.effect_script) as Script).new() as WeatherEffect
	assert_true(effect is StormEffect)


func test_tall_thin_tower_topples_at_full_intensity() -> void:
	_field()
	var tower: Array[Block] = _tower(TOWER_CUBES, 0.0)
	for _i: int in range(SETTLE_TICKS):
		await get_tree().physics_frame
	var top: Block = tower[TOWER_CUBES - 1]
	var start: Vector3 = top.global_position
	var effect: StormEffect = _effect()
	var moved: float = 0.0
	var lowest: float = start.y
	for _i: int in range(int(RUN_SECONDS * 60.0)):
		effect.tick(DELTA, 1.0)
		await get_tree().physics_frame
		if not is_instance_valid(top):
			# Blown off the small disc and killed by the kill plane: toppled.
			moved = INF
			lowest = -INF
			break
		moved = maxf(moved, Vector2(top.global_position.x - start.x, top.global_position.z - start.z).length())
		lowest = minf(lowest, top.global_position.y)
	assert_gt(moved, TOPPLE_DISPLACEMENT_M, "the 14-high tower's top was blown %.2f m" % moved)
	assert_lt(lowest, start.y - 2.0, "and it came down")


func test_low_pile_stays_at_full_intensity() -> void:
	_field()
	var pile: Array[Block] = _tower(LOW_PILE_CUBES, 0.0)
	for _i: int in range(SETTLE_TICKS):
		await get_tree().physics_frame
	var top: Block = pile[LOW_PILE_CUBES - 1]
	var start: Vector3 = top.global_position
	var effect: StormEffect = _effect()
	await _run_wind(effect, RUN_SECONDS)
	assert_lt(top.global_position.distance_to(start), STAY_DISPLACEMENT_M, "a 2-high pile is not swept")


# --- Presentation -------------------------------------------------------------------

func test_presentation_density_follows_intensity_and_never_touches_physics() -> void:
	var presentation: StormPresentation = StormPresentation.new()
	add_child_autofree(presentation)
	presentation.configure(SEED_A)
	assert_eq(presentation.total_instances(), _tuning.streak_count + _tuning.mote_count)
	presentation.set_intensity(0.0)
	assert_false(presentation.visible)
	presentation.set_intensity(0.7)
	assert_true(presentation.visible)
	var streaks: MultiMeshInstance3D = presentation.get_node("Streaks") as MultiMeshInstance3D
	var material: ShaderMaterial = streaks.material_override as ShaderMaterial
	var breeze: BreezeTuning = load("res://config/breeze.tres") as BreezeTuning
	assert_almost_eq(float(material.get_shader_parameter(&"density")), 0.7, 0.0001)
	assert_eq(streaks.layers, RainPresentation.RENDER_LAYER_BIT)
	assert_lte(_tuning.streak_length_m, 12.0)
	assert_lt(_tuning.streak_count, breeze.gust_streak_count * 4, "few streaks at once")
	assert_false(presentation.is_class("PhysicsBody3D"))


func test_ambient_wind_draws_curled_swoosh_strokes() -> void:
	# Bontago-mp0.81: the ambient wind takes the swoosh look a gust used to have; the motes keep the wisp shader.
	var presentation: StormPresentation = StormPresentation.new()
	add_child_autofree(presentation)
	presentation.configure(SEED_A)
	var material: ShaderMaterial = presentation.streak_material()
	assert_eq(material.shader.resource_path, "res://shaders/gust_swoosh.gdshader")
	assert_not_null(presentation.get_node_or_null("StreakLeaders"), "curl-headed leaders are their own MultiMesh")
	var motes: MultiMeshInstance3D = presentation.get_node("Motes") as MultiMeshInstance3D
	assert_eq((motes.material_override as ShaderMaterial).shader.resource_path, "res://shaders/wind_streak.gdshader")
	assert_almost_eq(float(material.get_shader_parameter(&"cycle_s")) * float(material.get_shader_parameter(&"speed")), StormPresentation.stroke_drift_m(_tuning), 0.001, "drifts a short sweep per cycle")
	assert_almost_eq(float(material.get_shader_parameter(&"radius")), _tuning.area_half_extent_m, 0.0001, "the weather box is the stroke volume")


func test_stroke_reveal_window_draws_on_then_off_along_the_stroke() -> void:
	# Bontago-mp0.131: head leads while drawing on, tail follows while drawing off.
	var soft: float = 0.25
	var start: Vector2 = StormPresentation.reveal_window(0.0, 0.4, 0.3, soft)
	assert_almost_eq(start.y, 0.0, 0.0001, "nothing drawn at the start")
	assert_lt(start.x, 0.0, "tail edge waits behind the stroke start")
	var mid_on: Vector2 = StormPresentation.reveal_window(0.2, 0.4, 0.3, soft)
	assert_between(mid_on.y, 0.2, 0.9, "head is mid-stroke while drawing on")
	assert_lt(mid_on.x, 0.0, "tail has not moved yet")
	var hold: Vector2 = StormPresentation.reveal_window(0.5, 0.4, 0.3, soft)
	assert_gte(hold.y, 1.0 + soft - 0.0001, "head fully clears the far tip")
	assert_lte(hold.x, 0.0, "tail still at the start while holding")
	var mid_off: Vector2 = StormPresentation.reveal_window(0.85, 0.4, 0.3, soft)
	assert_between(mid_off.x, 0.0, 1.0, "tail is mid-stroke while drawing off")
	var end: Vector2 = StormPresentation.reveal_window(1.0, 0.4, 0.3, soft)
	assert_almost_eq(end.x, 1.0, 0.0001, "tail has swept past the whole stroke")
	var prev: float = -1.0
	for i: int in range(21):
		var head: float = StormPresentation.reveal_window(0.4 * float(i) / 20.0, 0.4, 0.3, soft).y
		assert_gte(head, prev, "head only moves forward")
		prev = head


func test_stroke_timings_load_from_config_and_drive_the_cycle() -> void:
	var storm: StormTuning = load("res://config/weather/storm.tres") as StormTuning
	assert_gt(storm.streak_draw_on_s, 0.0)
	assert_gt(storm.streak_draw_off_s, 0.0)
	assert_gte(storm.streak_hold_s, 0.0)
	assert_eq(storm.streak_count, 72, "mp0.115 stroke count unchanged")
	assert_almost_eq(StormPresentation.stroke_cycle_s(storm), storm.streak_draw_on_s + storm.streak_hold_s + storm.streak_draw_off_s, 0.0001)
	var fracs: Vector2 = StormPresentation.phase_fracs(storm)
	assert_lt(fracs.x + fracs.y, 1.0 + 0.0001, "draw-on and draw-off fit the cycle")


func test_swoosh_ribbon_is_a_tapered_curling_strip() -> void:
	var mesh: ArrayMesh = StormPresentation.build_swoosh_ribbon(_tuning)
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	assert_eq(verts.size(), (_tuning.swoosh_ribbon_segments + 1) * 2)
	assert_almost_eq(uvs[0].x, 0.0, 0.0001)
	assert_almost_eq(uvs[uvs.size() - 1].x, 1.0, 0.0001)
	var max_y: float = 0.0
	var max_x: float = 0.0
	for v: Vector3 in verts:
		max_y = maxf(max_y, v.y)
		max_x = maxf(max_x, v.x)
	assert_gt(max_y, 0.05, "the head curls up out of the lead-in")
	assert_lt(verts[verts.size() - 1].x, max_x - 0.01, "the hook curls back over itself")


func test_only_leading_swoosh_strokes_curl() -> void:
	var straight: ArrayMesh = StormPresentation.build_swoosh_ribbon(_tuning, false)
	var verts: PackedVector3Array = straight.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var prev_x: float = -1.0
	for v: Vector3 in verts:
		assert_gte(v.x, prev_x - 0.0001, "a non-leader never curls back over itself")
		prev_x = maxf(prev_x, v.x)
	assert_lt(_tuning.swoosh_curl_lead_frac, 0.5, "most strokes are straight")


func test_presentation_heading_matches_the_host_field() -> void:
	var presentation: StormPresentation = StormPresentation.new()
	add_child_autofree(presentation)
	presentation.configure(SEED_A)
	assert_eq(presentation.heading(), WindField.direction(SEED_A, 0.0, _tuning))


func test_presentation_streaks_travel_along_the_field_heading() -> void:
	var presentation: StormPresentation = StormPresentation.new()
	add_child_autofree(presentation)
	presentation.configure(SEED_A)
	presentation.set_intensity(1.0)
	presentation._process(0.0)
	var field: Vector2 = WindField.direction(SEED_A, 0.0, _tuning)
	var streaks: MultiMeshInstance3D = presentation.get_node("Streaks") as MultiMeshInstance3D
	var drawn: Vector3 = (streaks.material_override as ShaderMaterial).get_shader_parameter(&"wind_dir") as Vector3
	assert_lt(drawn.distance_to(Vector3(field.x, 0.0, field.y)), 0.001, "shader wind_dir is the host's (x, z) heading")


func test_streak_spawns_keep_their_distance_from_the_camera() -> void:
	var presentation: StormPresentation = StormPresentation.new()
	add_child_autofree(presentation)
	presentation.configure(SEED_A)
	var material: ShaderMaterial = presentation.streak_material()
	var fade: Vector2 = material.get_shader_parameter(&"near_fade_m") as Vector2
	assert_eq(fade, Vector2(_tuning.streak_near_fade_start_m, _tuning.streak_near_fade_end_m))
	assert_gte(fade.x, 10.0, "min camera distance is well beyond the screen-spanning range")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 77
	var visible_count: int = 0
	for n: int in range(4000):
		var spawn: Vector3 = StormPresentation.streak_spawn(rng.randf(), rng.randi_range(0, 50), _tuning)
		var camera: Vector3 = Vector3(rng.randf_range(-60.0, 60.0), rng.randf_range(0.0, 30.0), rng.randf_range(-60.0, 60.0))
		var weight: float = StormPresentation.streak_near_weight(spawn.distance_to(camera), _tuning)
		if spawn.distance_to(camera) <= _tuning.streak_near_fade_start_m:
			assert_eq(weight, 0.0, "invisible inside the minimum camera distance")
		if weight > 0.0:
			visible_count += 1
			assert_gt(spawn.distance_to(camera), _tuning.streak_near_fade_start_m)
	assert_gt(visible_count, 0, "most spawns are visible away from the camera")
	assert_eq(StormPresentation.streak_near_weight(_tuning.streak_near_fade_end_m, _tuning), 1.0)


func test_streak_heading_matches_wind_field_over_time() -> void:
	var presentation: StormPresentation = StormPresentation.new()
	add_child_autofree(presentation)
	presentation.configure(SEED_B)
	presentation.set_intensity(1.0)
	for _i: int in range(30):
		presentation._process(1.0)
		var field: Vector2 = WindField.direction(SEED_B, presentation._elapsed, _tuning)
		var drawn: Vector3 = presentation.streak_material().get_shader_parameter(&"wind_dir") as Vector3
		assert_lt(drawn.distance_to(Vector3(field.x, 0.0, field.y)), 0.001)


func test_active_presentation_rebuilds_for_graphics_preset() -> void:
	var original: GraphicsPreset = Settings.current_graphics_preset()
	Settings.set_graphics_preset(&"high")
	var presentation: StormPresentation = StormPresentation.new()
	add_child_autofree(presentation)
	assert_eq(presentation.total_instances(), _tuning.streak_count + _tuning.mote_count)
	Settings.set_graphics_preset(&"low")
	assert_eq(presentation.total_instances(), int(round(float(_tuning.streak_count) * _tuning.low_preset_density))
			+ int(round(float(_tuning.mote_count) * _tuning.low_preset_density)))
	Settings.set_graphics_preset(original.id)
