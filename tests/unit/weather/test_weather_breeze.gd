extends GutTest
## Breeze: the pure gust rules (core/weather/BreezeField.gd), the host
## effect (autoload/match/BreezeEffect.gd) against real Jolt bodies, the wire
## sanitizer and the bounded presenter. Shipped numbers: config/breeze/breeze.tres.

const DELTA: float = 1.0 / 60.0
const SEED_A: int = 4242
const HIGH_M: float = 20.0
const SIM_STEP: float = 0.1
const BUSY_INTERVAL_S: float = 1.2
const BUSY_DURATION_S: float = 0.5

var _tuning: BreezeTuning = null
var _blocks: Array[Block] = []
var _root: Node3D = null
var _gusts_seen: Array[Dictionary] = []


func before_each() -> void:
	_tuning = (load("res://config/breeze/breeze.tres") as BreezeTuning).duplicate() as BreezeTuning
	# Statistical tests below need many gusts: a frequent, short-lived profile
	# (the shipped defaults are sporadic, see test_default_gusts_are_sporadic_single).
	_tuning.spawn_interval_s = BUSY_INTERVAL_S
	_tuning.duration_min_s = BUSY_DURATION_S
	_tuning.duration_max_s = BUSY_DURATION_S
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
	var block: Block = BlockFactory.build(shape, load("res://config/physics/physics_tuning.tres") as PhysicsTuning)
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
	effect.bind(WeatherTestHost.wind_context(self, func() -> Array: return _blocks, func() -> float: return 0.0))
	return effect


func _inject_gust(effect: BreezeEffect, pos: Vector3, radius: float = 3.0, angle: float = 0.0, strength: float = 1.0) -> void:
	effect.gusts().append({"id": 1, "x": pos.x, "y": pos.y, "z": pos.z, "a": angle, "r": radius, "d": 1000.0, "s": strength, "age": 500.0})


func _quiet_tuning() -> BreezeTuning:
	var quiet: BreezeTuning = _tuning.duplicate() as BreezeTuning
	quiet.spawn_interval_s = 1.0e6
	return quiet


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


func test_at_most_one_gust_is_active_and_it_expires() -> void:
	_block(Vector3(0.0, HIGH_M, 0.0))
	var fast: BreezeTuning = _tuning.duplicate() as BreezeTuning
	fast.spawn_interval_s = 0.1
	fast.duration_min_s = 1.0
	fast.duration_max_s = 1.0
	var effect: BreezeEffect = _effect(fast)
	effect.begin(SEED_A)
	var saw_gust: bool = false
	for _i: int in range(300):
		effect.tick(SIM_STEP)
		assert_lte(effect.gusts().size(), 1)
		saw_gust = saw_gust or effect.gusts().size() == 1
	assert_true(saw_gust, "a gust did spawn")
	effect.set_enabled(false)
	assert_eq(effect.gusts().size(), 0, "the F4 toggle ends every gust")
	for _i: int in range(100):
		effect.tick(SIM_STEP)
	assert_eq(effect.gusts().size(), 0, "and none spawn while off")


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
	var client_context: FakeMatchContext = WeatherTestHost.wind_context(self, func() -> Array: return _blocks, func() -> float: return 0.0)
	client_context.has_authority_value = false
	client.bind(client_context)
	client.begin(SEED_A)
	_inject_gust(client, Vector3(0.0, HIGH_M, 0.6))
	client.tick(DELTA)
	assert_eq(client.last_pushed, 0, "no host authority, no push")
	assert_eq(_gusts_seen.size(), 0, "and no spawn")


func test_breeze_runs_with_weather_off_and_stops_on_reset_and_is_host_only_toggle() -> void:
	var w: MatchWeather = MatchWeather.new()
	WeatherTestHost.bind_host(self, w, true)
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
	assert_eq(w.breeze().gusts().size(), 0)
	var client: MatchWeather = MatchWeather.new()
	WeatherTestHost.bind_host(self, client, false)
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


## An offline session (nothing is sent) that is, or is not, its own host.
func _session(host: bool = false) -> FakeSessionPort:
	var fake: FakeNet = FakeNet.offline()
	fake.is_host_value = host
	return FakeSessionPort.new(fake)


## The host port spy answering the one read BreezeNet makes: state().
class BreezeHost:
	extends FakeHostPort
	var match_state: int = MatchAutoload.State.PLAYING

	func state() -> int:
		return match_state


func _breeze_net(session: SessionPort, authority: MatchHostPort) -> BreezeNet:
	var node: BreezeNet = BreezeNet.new()
	add_child_autofree(node)
	assert_true(node.bind(session, authority), "spy ports bind")
	return node


func test_breeze_net_client_applies_a_good_gust_and_refuses_the_rest() -> void:
	var authority: BreezeHost = BreezeHost.new()
	var node: BreezeNet = _breeze_net(_session(), authority)
	node.net_breeze_gust(_wire(1))
	assert_eq(_gusts_seen.size(), 1, "re-emitted for the presenter")
	node.net_breeze_gust(_wire(1))
	assert_eq(_gusts_seen.size(), 1, "a repeated id is dropped")
	authority.match_state = MatchAutoload.State.END
	node.net_breeze_gust(_wire(2))
	assert_eq(_gusts_seen.size(), 1, "a late packet after the match is dropped")


func test_breeze_net_host_refuses_replicated_gusts_and_rebinding_swaps_the_session() -> void:
	var node: BreezeNet = _breeze_net(_session(true), BreezeHost.new())
	node.net_breeze_gust(_wire(1))
	assert_eq(_gusts_seen.size(), 0, "the host never applies a replicated gust")
	assert_true(node.bind(_session(), BreezeHost.new()))
	node.net_breeze_gust(_wire(1))
	assert_eq(_gusts_seen.size(), 1, "the new binding answers: this node is now a client")


func test_breeze_net_binds_through_the_shared_port_bound_base() -> void:
	var node: BreezeNet = _breeze_net(_session(), BreezeHost.new())
	assert_true(is_instance_of(node, PortBoundNode))
	assert_true(node.bind(_session(), BreezeHost.new()))


func test_breeze_net_bind_refuses_an_invalid_port() -> void:
	var node: BreezeNet = BreezeNet.new()
	add_child_autofree(node)
	var broken: MatchHostPort = MatchHostPort.new(null)
	assert_false(node.bind(_session(), broken))
	assert_false(node.bind(null, null), "null ports are refused")


func test_breeze_net_bind_keeps_the_previous_binding_when_refused() -> void:
	var node: BreezeNet = _breeze_net(_session(), BreezeHost.new())
	var broken: MatchHostPort = MatchHostPort.new(null)
	assert_false(node.bind(_session(), broken))
	node.net_breeze_gust(_wire(1))
	assert_eq(_gusts_seen.size(), 1, "the earlier binding still answers")


func test_an_unbound_breeze_net_reads_the_real_net() -> void:
	assert_true(Net.is_offline(), "fixture: the real Net is offline, so it is its own host")
	var node: BreezeNet = BreezeNet.new()
	add_child_autofree(node)
	node.net_breeze_gust(_wire(1))
	assert_eq(_gusts_seen.size(), 0, "no bind: the host check goes to the real Net")


func test_tuning_panel_breeze_toggle_is_host_only() -> void:
	var panel: TuningPanel = load("res://ui/debug/TuningPanel.tscn").instantiate() as TuningPanel
	add_child_autofree(panel)
	var w: MatchWeather = MatchWeather.new()
	WeatherTestHost.bind_host(self, w, true)
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
