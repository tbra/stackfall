extends GutTest
## SoakMonitor through its public surface only: sample_now() and violations(). The world is the
## real game (Main scene, real Match and BlockRegistry); the monitor is built the way Main builds
## it, config / role / sampler set before add_child. Bodies are moved through their public
## transform, the same state a physics step would leave.

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")
const SOAK_CONFIG: Resource = preload("res://config/soak/soak_config.tres")
const SETTLE_FRAMES: int = 20

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


## A monitor built the way Main builds it: config, role and sampler set before add_child.
func _monitor(role: StringName, warmup_s: float = -1.0, sample_interval_s: float = -1.0) -> SoakMonitor:
	var config: SoakConfig = SOAK_CONFIG.duplicate(true) as SoakConfig
	if warmup_s >= 0.0:
		config.warmup_s = warmup_s
	if sample_interval_s > 0.0:
		config.sample_interval_s = sample_interval_s
	var sampler: PerfSampler = PerfSampler.new()
	add_child_autofree(sampler)
	var monitor: SoakMonitor = SoakMonitor.new()
	monitor.config = config
	monitor.role = role
	monitor.sampler = sampler
	add_child_autofree(monitor)
	return monitor


func _start_match_with_block() -> void:
	_main.start_gift_demo_from_menu()
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)
	Match.set_process(true)
	var field: Field = _main.get_node("Field") as Field
	var home: Vector2 = Match.slot(0).home_position
	var spot: Vector2 = home - home.normalized() * 2.0
	Match.request_place(0, field.to_global(Vector3(spot.x, 1.5, spot.y)), 0, Quaternion.IDENTITY, false)
	await wait_physics_frames(SETTLE_FRAMES)


func _first_block() -> Block:
	var registry: BlockRegistry = Match.registry() as BlockRegistry
	var bodies: Array[Block] = registry.physics_bodies()
	return bodies[0] if not bodies.is_empty() else null


func _below_plane(violations: Array[SoakCheck.Violation]) -> Array[SoakCheck.Violation]:
	var below: Array[SoakCheck.Violation] = []
	for v: SoakCheck.Violation in violations:
		if v.invariant == &"physics.below_kill_plane":
			below.append(v)
	return below


func _ids_of(violations: Array[SoakCheck.Violation]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for v: SoakCheck.Violation in violations:
		ids.append(v.invariant)
	return ids


func test_block_below_the_kill_plane_is_reported_with_its_net_id() -> void:
	await _start_match_with_block()
	var block: Block = _first_block()
	assert_not_null(block, "a placed block is tracked by the registry before the monitor looks")
	if block == null:
		return
	var kill_y: float = (load("res://config/physics/physics_tuning.tres") as PhysicsTuning).kill_plane_y
	block.global_position = Vector3(block.global_position.x, kill_y - 5.0, block.global_position.z)
	var monitor: SoakMonitor = _monitor(&"host", 0.0)
	var found: Array[SoakCheck.Violation] = monitor.sample_now()
	var below: Array[SoakCheck.Violation] = []
	for v: SoakCheck.Violation in found:
		if v.invariant == &"physics.below_kill_plane":
			below.append(v)
	assert_eq(below.size(), 1, "exactly one below-kill-plane violation for one bad block")
	if below.size() == 1:
		assert_eq(below[0].subject, str(block.net_id), "the violation names the block by its net id")
		assert_lt(below[0].value, below[0].limit, "measured height is under the limit it crossed")


func test_clean_world_yields_zero_violations() -> void:
	await _start_match_with_block()
	var block: Block = _first_block()
	assert_not_null(block, "a placed block is tracked before the monitor looks")
	var monitor: SoakMonitor = _monitor(&"host", 0.0)
	var found: Array[SoakCheck.Violation] = monitor.sample_now()
	assert_eq(_ids_of(found), [] as Array[StringName], "a settled, in-field block breaks no invariant")
	assert_eq(monitor.violations().size(), 0, "violations() agrees with the empty sample")


func test_sample_now_writes_nothing_to_the_world() -> void:
	await _start_match_with_block()
	var registry: BlockRegistry = Match.registry() as BlockRegistry
	var transforms_before: Array[Transform3D] = []
	for block: Block in registry.physics_bodies():
		transforms_before.append(block.global_transform)
	var hash_before: int = Match.raster().ownership_hash()
	var tracked_before: int = registry.tracked_block_count()
	var sent_before: int = MatchNet.counters.sent_count(0)
	var accepted_before: int = MatchNet.counters.accepted_count(0)
	var refused_before: int = MatchNet.counters.refused_count(0)
	var monitor: SoakMonitor = _monitor(&"host", 0.0)
	monitor.sample_now()
	monitor.sample_now()
	var transforms_after: Array[Transform3D] = []
	for block: Block in registry.physics_bodies():
		transforms_after.append(block.global_transform)
	assert_eq(transforms_after, transforms_before, "no body transform changed")
	assert_eq(Match.raster().ownership_hash(), hash_before, "the raster ownership hash is unchanged")
	assert_eq(registry.tracked_block_count(), tracked_before, "the tracked block count is unchanged")
	assert_eq(MatchNet.counters.sent_count(0), sent_before, "sent counter unchanged")
	assert_eq(MatchNet.counters.accepted_count(0), accepted_before, "accepted counter unchanged")
	assert_eq(MatchNet.counters.refused_count(0), refused_before, "refused counter unchanged")


func test_host_local_slot_is_outside_the_spawn_identity() -> void:
	# Slot 0 is host-local: its placements go through Match directly, with no gateway counters, so
	# an accepted-counter mismatch must not be reported for it. A remote-driven slot is not
	# reachable through the public path without a session peer (boundary, see the handback).
	await _start_match_with_block()
	assert_true(Match.slot(0).is_local, "slot 0 is host-local")
	MatchNet.counters.count_sent(0)
	MatchNet.counters.count_accepted(0)
	var monitor: SoakMonitor = _monitor(&"host", 0.0)
	var found: Array[SoakCheck.Violation] = monitor.sample_now()
	assert_false(&"authority.spawn_identity" in _ids_of(found),
		"a host-local slot's placements are not checked against gateway counters")


func test_client_role_reports_no_host_only_checks() -> void:
	await _start_match_with_block()
	var block: Block = _first_block()
	assert_not_null(block, "a placed block is tracked before the monitor looks")
	if block == null:
		return
	var kill_y: float = (load("res://config/physics/physics_tuning.tres") as PhysicsTuning).kill_plane_y
	block.global_position = Vector3(block.global_position.x, kill_y - 5.0, block.global_position.z)
	# The same counter mismatch that the host reports for a remote slot must be silent here.
	MatchNet.counters.count_sent(0)
	MatchNet.counters.count_accepted(0)
	var monitor: SoakMonitor = _monitor(&"client", 0.0)
	var found: Array[SoakCheck.Violation] = monitor.sample_now()
	assert_true(&"physics.below_kill_plane" in _ids_of(found),
		"the client still runs the local physics checks")
	for v: SoakCheck.Violation in found:
		assert_false(String(v.invariant).begins_with("authority."),
			"a client never reports host-only authority checks (got %s)" % v.invariant)
		assert_ne(v.invariant, &"territory.fresh_solve", "a client never runs the fresh solve")
		assert_ne(v.invariant, &"physics.awake_fraction", "a client never checks the awake fraction")


func test_warm_up_suppresses_checks() -> void:
	await _start_match_with_block()
	var block: Block = _first_block()
	assert_not_null(block, "a placed block is tracked before the monitor looks")
	if block == null:
		return
	var kill_y: float = (load("res://config/physics/physics_tuning.tres") as PhysicsTuning).kill_plane_y
	block.global_position = Vector3(block.global_position.x, kill_y - 5.0, block.global_position.z)
	var monitor: SoakMonitor = _monitor(&"host", 600.0)
	assert_eq(_below_plane(monitor.sample_now()).size(), 0, "inside warm-up no invariant is checked")
	assert_eq(monitor.violations().size(), 0, "inside warm-up nothing is recorded")
	var after_warm_up: SoakMonitor = _monitor(&"host", 0.0)
	assert_eq(_below_plane(after_warm_up.sample_now()).size(), 1, "the same bad block is reported once warm-up is over")


func test_persistent_violation_is_recorded_once_per_epoch() -> void:
	await _start_match_with_block()
	var block: Block = _first_block()
	assert_not_null(block, "a placed block is tracked before the monitor looks")
	if block == null:
		return
	var kill_y: float = (load("res://config/physics/physics_tuning.tres") as PhysicsTuning).kill_plane_y
	block.global_position = Vector3(block.global_position.x, kill_y - 5.0, block.global_position.z)
	# A long interval keeps both samples inside one wall-aligned epoch.
	var monitor: SoakMonitor = _monitor(&"host", 0.0, 600.0)
	var first: Array[SoakCheck.Violation] = _below_plane(monitor.sample_now())
	var second: Array[SoakCheck.Violation] = _below_plane(monitor.sample_now())
	assert_eq(first.size(), 1, "the first sample reports the bad block")
	assert_eq(second.size(), 0, "the same violation in the same epoch is not reported again")
	assert_eq(_below_plane(monitor.violations()).size(), 1, "one line per epoch, however many ticks keep it broken")
