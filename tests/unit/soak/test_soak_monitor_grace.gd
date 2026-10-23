extends GutTest
## SoakMonitor's client grace for a body held below the kill plane, driven through sample_now()
## and violations() on the real game world, the way test_soak_monitor.gd builds it.

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")
const SOAK_CONFIG: Resource = preload("res://config/soak/soak_config.tres")
const SETTLE_FRAMES: int = 20
const DROP_BELOW_M: float = 10.0
const LONG_INTERVAL_S: float = 600.0
const SHORT_GRACE_S: float = 0.2
const LONG_GRACE_S: float = 600.0
const MS_PER_S: float = 1000.0
const GRACE_OVERSHOOT: float = 2.0

var _main: Node3D = null


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	DebugMode.set_override_for_test(true)
	_main = MAIN_SCENE.instantiate()
	var tiny_map: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	tiny_map.field_radius = 20.0
	(_main.get_node("Field") as Field).map_def = tiny_map
	var tiny_match_config: MatchConfig = (load("res://config/match/match_defaults.tres") as MatchConfig).duplicate(true)
	tiny_match_config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(tiny_match_config as TinyMapMatchConfig).set_tiny_map(tiny_map)
	tiny_match_config.rng_seed = 4242
	_main.match_config = tiny_match_config
	add_child_autofree(_main)


func after_each() -> void:
	DebugMode.clear_override_for_test()
	Match.abort_match()
	Match.set_process(true)
	await get_tree().process_frame
	MatchTestReset.clear_world()


func _monitor(role: StringName, grace_s: float) -> SoakMonitor:
	var config: SoakConfig = SOAK_CONFIG.duplicate(true) as SoakConfig
	config.warmup_s = 0.0
	config.sample_interval_s = LONG_INTERVAL_S
	config.client_kill_grace_s = grace_s
	var sampler: PerfSampler = PerfSampler.new()
	add_child_autofree(sampler)
	var monitor: SoakMonitor = SoakMonitor.new()
	monitor.config = config
	monitor.role = role
	monitor.sampler = sampler
	add_child_autofree(monitor)
	return monitor


func _kill_y() -> float:
	return (load("res://config/physics/physics_tuning.tres") as PhysicsTuning).kill_plane_y


## A match with one placed block, dropped below the plane and kept there: the field frees a body
## under the plane, and a client holds it at its last snapshot.
func _block_held_below_plane() -> Block:
	_main.start_gift_demo_from_menu()
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)
	Match.set_process(true)
	var field: Field = _main.get_node("Field") as Field
	var home: Vector2 = Match.slot(0).home_position
	var spot: Vector2 = home - home.normalized() * 2.0
	Match.request_place(0, field.to_global(Vector3(spot.x, 1.5, spot.y)), 0, Quaternion.IDENTITY, false)
	await wait_physics_frames(SETTLE_FRAMES)
	var bodies: Array[Block] = (Match.registry() as BlockRegistry).physics_bodies()
	assert_false(bodies.is_empty(), "a placed block is tracked")
	var block: Block = bodies[0]
	block.global_position = Vector3(block.global_position.x, _kill_y() - DROP_BELOW_M, block.global_position.z)
	field.set_physics_process(false)
	return block


func _below_count(monitor: SoakMonitor) -> int:
	var count: int = 0
	for v: SoakCheck.Violation in monitor.violations():
		if v.invariant == &"physics.below_kill_plane":
			count += 1
	return count


func test_client_body_sampled_twice_within_the_grace_is_not_reported() -> void:
	var block: Block = await _block_held_below_plane()
	var monitor: SoakMonitor = _monitor(&"client", LONG_GRACE_S)
	monitor.sample_now()
	monitor.sample_now()
	assert_true(is_instance_valid(block), "the held body is still tracked")
	assert_eq(_below_count(monitor), 0, "inside the grace a fall in flight is not a violation")


func test_client_body_sampled_twice_past_the_grace_is_reported_by_net_id() -> void:
	var block: Block = await _block_held_below_plane()
	var monitor: SoakMonitor = _monitor(&"client", SHORT_GRACE_S)
	monitor.sample_now()
	assert_eq(_below_count(monitor), 0, "the first sight starts the clock")
	# The monitor reads the wall clock, which a headless engine-time timer does not follow.
	OS.delay_msec(int(SHORT_GRACE_S * GRACE_OVERSHOOT * MS_PER_S))
	monitor.sample_now()
	assert_eq(_below_count(monitor), 1, "still below the plane after the grace is reported")
	assert_eq(monitor.violations()[0].subject, str(block.net_id))


func test_client_body_that_returns_above_the_plane_restarts_its_grace() -> void:
	var block: Block = await _block_held_below_plane()
	var held: Vector3 = block.global_position
	var monitor: SoakMonitor = _monitor(&"client", SHORT_GRACE_S)
	monitor.sample_now()
	block.global_position = Vector3(held.x, _kill_y() + DROP_BELOW_M, held.z)
	OS.delay_msec(int(SHORT_GRACE_S * GRACE_OVERSHOOT * MS_PER_S))
	monitor.sample_now()
	block.global_position = held
	monitor.sample_now()
	assert_eq(_below_count(monitor), 0, "a new fall is graced from its own first sight")


func test_host_body_below_the_plane_is_reported_at_once() -> void:
	await _block_held_below_plane()
	var monitor: SoakMonitor = _monitor(&"host", LONG_GRACE_S)
	monitor.sample_now()
	assert_eq(_below_count(monitor), 1, "the host has no grace")
