extends GutTest
## Bontago-bth.1: Block's per-node physics hooks (_integrate_forces +
## _physics_process per awake block per tick) became one batched pass
## (game/BlockStepBatch.gd) plus a one-shot first-sync callback for the release
## tilt. A/B: the same seeded scene runs side by side in separate physics worlds,
## one with LegacyBlock (the pre-batch hooks, copied verbatim from base
## 1bd6e3fa below) and one with the shipped batched Block, and every body's
## transform and velocities must stay bit-identical every tick: a
## falling+rebounding pile at rebound_damping 0.3 and 1.0, a block kicked
## mid-fall, a release-tilt block, a woken+impulsed block and a static
## freeze/release.

const SHAPE_PATHS: Array[String] = [
	"res://config/blocks/cube.tres",
	"res://config/blocks/domino.tres",
	"res://config/blocks/bar3.tres",
	"res://config/blocks/L3.tres",
	"res://config/blocks/T4.tres",
	"res://config/blocks/S4.tres",
	"res://config/blocks/square4.tres",
	"res://config/blocks/slab6.tres",
]
const PILE_COUNT: int = 14
const PILE_SEED: int = 4242
const PILE_RADIUS_M: float = 1.6
const PILE_MIN_Y_M: float = 1.0
const PILE_MAX_Y_M: float = 7.0
const FLOOR_SIZE_M: float = 30.0
const KICK_DROP_Y_M: float = 14.0
const KICK_TICK: int = 25
const KICK_SPEED_MPS: float = 6.0
const TILT_DROP_Y_M: float = 6.0
const TILT_DEGREES: float = 2.0
## The tilt lands at the block's first state sync; a cube can rock back flat
## once it lands, so the fixture checks only the first ticks of the fall.
const TILT_WATCH_TICKS: int = 5
const IMPULSE_TICK: int = 150
const IMPULSE_DV_MPS: float = 4.0
const FREEZE_TICK: int = 170
const RELEASE_TICK: int = 190
const RUN_TICKS: int = 260
const SIDE_OFFSET_M: float = 6.0
## Legacy per-node calls per batched hook call must exceed this (16 blocks).
const MIN_CALL_RATIO: int = 10
const FREEZE_SETTLE_TICKS: int = 4


## Pre-batch Block hooks (base 1bd6e3fa game/Block.gd), the reference the
## batch must match. Only the call counters are added.
class LegacyBlock:
	extends Block

	var integrate_calls: int = 0
	var physics_calls: int = 0

	func _init() -> void:
		step_batched = false

	func _apply_awake(awake: bool) -> void:
		super._apply_awake(awake)
		set_physics_process(awake and is_inside_tree())

	func _physics_process(_delta: float) -> void:
		physics_calls += 1
		if sleeping:
			_prev_linear_velocity = linear_velocity
			_apply_awake(false)
			return
		if freeze:
			_prev_linear_velocity = Vector3.ZERO
			return
		if not impacts_enabled:
			_prev_linear_velocity = linear_velocity
			return
		var prev_speed: float = _prev_linear_velocity.length()
		var now_speed: float = linear_velocity.length()
		var decel: float = prev_speed - now_speed
		_prev_linear_velocity = linear_velocity
		if decel < impact_speed_min:
			return
		var now_ms: int = Time.get_ticks_msec()
		if now_ms - _last_impact_emit_ms < IMPACT_EMIT_INTERVAL_MS:
			return
		_last_impact_emit_ms = now_ms
		Events.block_impacted.emit(decel)
		Events.block_impacted_at.emit(decel, global_position)

	func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
		integrate_calls += 1
		if not _release_checked:
			_release_checked = true
			_apply_release_tilt(state)
		var current_y: float = state.linear_velocity.y
		if freeze or state.sleeping:
			_script_kick_pending = false
			_prev_step_linear_velocity_y = current_y
			return
		rebound_work_runs += 1
		if _script_kick_pending:
			_script_kick_pending = false
		elif tuning != null and tuning.rebound_damping != 1.0:
			var damped_y: float = _damp_rebound(
				_prev_step_linear_velocity_y, current_y, tuning.rebound_damping, tuning.sleep_linear_threshold
			)
			if damped_y != current_y:
				current_y = damped_y
				state.linear_velocity.y = current_y
		_prev_step_linear_velocity_y = current_y


## Drives both worlds identically from _physics_process (where a special's
## own kick/impulse/freeze lands) and compares them every tick.
class Recorder:
	extends Node

	var pairs: Array[Array] = []
	var kicked: Array[Block] = []
	var impulsed: Array[Block] = []
	var frozen: Array[Block] = []
	var tilted: Array[Block] = []
	var tilt_seen: int = 0
	var tick: int = 0
	var mismatch: String = ""
	var compared: int = 0

	func _physics_process(_delta: float) -> void:
		tick += 1
		for pair: Array in pairs:
			var legacy: Block = pair[0]
			var batched: Block = pair[1]
			compared += 1
			if mismatch.is_empty() and (
				legacy.global_transform != batched.global_transform
				or legacy.linear_velocity != batched.linear_velocity
				or legacy.angular_velocity != batched.angular_velocity
				or legacy.sleeping != batched.sleeping
			):
				mismatch = "tick %d %s: legacy %s v%s vs batched %s v%s" % [
					tick, legacy.shape_id, legacy.global_transform.origin, legacy.linear_velocity,
					batched.global_transform.origin, batched.linear_velocity,
				]
		for block: Block in tilted:
			if tick <= TILT_WATCH_TICKS and not block.global_basis.y.is_equal_approx(Vector3.UP):
				tilt_seen += 1
		if tick == KICK_TICK:
			for block: Block in kicked:
				block.kick(Vector3.UP * KICK_SPEED_MPS)
		if tick == IMPULSE_TICK:
			for block: Block in impulsed:
				SpecialPhysics.wake_and_impulse(block, Vector3.UP * IMPULSE_DV_MPS * block.mass)
		if tick == FREEZE_TICK:
			for block: Block in frozen:
				block.request_freeze_static(Block.FREEZE_REASON_STABLE)
		if tick == RELEASE_TICK:
			for block: Block in frozen:
				block.release_freeze_static(Block.FREEZE_REASON_STABLE)
				block.wake()


var _tuning: PhysicsTuning = load("res://config/physics_tuning.tres")


func _world() -> Node3D:
	var viewport: SubViewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(2, 2)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child_autofree(viewport)
	var root: Node3D = Node3D.new()
	viewport.add_child(root)
	var floor_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(FLOOR_SIZE_M, 1.0, FLOOR_SIZE_M)
	collision.shape = box
	floor_body.add_child(collision)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	root.add_child(floor_body)
	return root


func _spawn_list(rebound_damping: float) -> Array[Dictionary]:
	var pile_tuning: PhysicsTuning = _tuning.duplicate() as PhysicsTuning
	pile_tuning.rebound_damping = rebound_damping
	pile_tuning.release_tilt_degrees = 0.0
	var tilt_tuning: PhysicsTuning = pile_tuning.duplicate() as PhysicsTuning
	tilt_tuning.release_tilt_degrees = TILT_DEGREES
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = PILE_SEED
	var spawns: Array[Dictionary] = []
	for i: int in range(PILE_COUNT):
		var shape: BlockShape = load(SHAPE_PATHS[i % SHAPE_PATHS.size()])
		var basis: Basis = Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU))
		var origin: Vector3 = Vector3(
			rng.randf_range(-PILE_RADIUS_M, PILE_RADIUS_M),
			rng.randf_range(PILE_MIN_Y_M, PILE_MAX_Y_M),
			rng.randf_range(-PILE_RADIUS_M, PILE_RADIUS_M)
		)
		spawns.append({"shape": shape, "tuning": pile_tuning, "xform": Transform3D(basis, origin), "role": &"pile"})
	var cube: BlockShape = load(SHAPE_PATHS[0])
	var kick_xform: Transform3D = Transform3D(Basis.IDENTITY, Vector3(SIDE_OFFSET_M, KICK_DROP_Y_M, 0.0))
	spawns.append({"shape": cube, "tuning": pile_tuning, "xform": kick_xform, "role": &"kick"})
	var tilt_xform: Transform3D = Transform3D(Basis.IDENTITY, Vector3(-SIDE_OFFSET_M, TILT_DROP_Y_M, 0.0))
	spawns.append({"shape": cube, "tuning": tilt_tuning, "xform": tilt_xform, "role": &"tilt"})
	return spawns


func _build(spawn: Dictionary, legacy: bool) -> Block:
	var tuning: PhysicsTuning = spawn["tuning"]
	var shape: BlockShape = spawn["shape"]
	var block: Block = BlockFactory.build(shape, tuning)
	if legacy:
		block.set_script(LegacyBlock)
		block.step_batched = false
		block.tuning = tuning
		block.shape_id = shape.id
		block.cube_count = shape.cells.size()
	block.transform = spawn["xform"]
	return block


## Runs one rebound_damping config A/B and returns the batched pile's final
## positions (so the caller can prove damping actually changed the run).
## `idle_spawn` adds the blocks between ticks (a process frame: input, RPC,
## _process) instead of inside a physics frame, so Jolt first syncs them one
## tick later (Block._next_sync_frame()).
func _run_ab(rebound_damping: float, idle_spawn: bool) -> PackedVector3Array:
	var legacy_root: Node3D = _world()
	var batched_root: Node3D = _world()
	var recorder: Recorder = Recorder.new()
	var spawns: Array[Dictionary] = _spawn_list(rebound_damping)
	if idle_spawn:
		await wait_process_frames(1)
		assert_false(Engine.is_in_physics_frame(), "fixture: spawning between ticks")
	else:
		await wait_physics_frames(1)
		assert_true(Engine.is_in_physics_frame(), "fixture: spawning inside a physics frame")
	for spawn: Dictionary in spawns:
		var legacy: Block = _build(spawn, true)
		var batched: Block = _build(spawn, false)
		legacy_root.add_child(legacy)
		batched_root.add_child(batched)
		recorder.pairs.append([legacy, batched])
		match spawn["role"]:
			&"kick":
				recorder.kicked.append_array([legacy, batched])
			&"tilt":
				recorder.tilted.append_array([legacy, batched])
	var first_pile: Array = recorder.pairs[0]
	var second_pile: Array = recorder.pairs[1]
	recorder.impulsed.append_array([first_pile[0], first_pile[1]])
	recorder.frozen.append_array([second_pile[0], second_pile[1]])
	add_child_autofree(recorder)
	var hooks_before: int = BlockStepBatch.hook_runs
	await wait_physics_frames(RUN_TICKS)
	var hook_runs: int = BlockStepBatch.hook_runs - hooks_before

	assert_true(BlockStepBatch.is_installed(), "the batched hook is installed")
	assert_eq(recorder.mismatch, "", "rebound_damping %.1f: batched == legacy every tick" % rebound_damping)
	assert_gt(recorder.compared, PILE_COUNT * RUN_TICKS, "fixture: the comparison actually ran")
	assert_gt(recorder.tilt_seen, 0, "fixture: the release-tilt blocks were tilted at their first sync")
	var legacy_calls: int = 0
	var batched_rebound_runs: int = 0
	var final_positions: PackedVector3Array = PackedVector3Array()
	for pair: Array in recorder.pairs:
		var legacy: LegacyBlock = pair[0] as LegacyBlock
		var batched: Block = pair[1]
		legacy_calls += legacy.integrate_calls + legacy.physics_calls
		batched_rebound_runs += batched.rebound_work_runs
		assert_eq(batched.rebound_work_runs, legacy.rebound_work_runs, "same rebound passes for %s" % batched.shape_id)
		final_positions.append(batched.global_position)
	assert_gt(batched_rebound_runs, 0, "fixture: the batch ran rebound passes")
	# Engine->script calls: two per awake legacy block per tick, one hook per tick.
	gut.p("rebound %.1f: legacy per-node hook calls %d, batched hook calls %d over %d ticks" % [
		rebound_damping, legacy_calls, hook_runs, RUN_TICKS])
	assert_lt(hook_runs * MIN_CALL_RATIO, legacy_calls, "the batch makes far fewer engine->script calls")
	return final_positions


func test_batched_hooks_match_legacy_hooks_tick_for_tick() -> void:
	var damped: PackedVector3Array = await _run_ab(0.3, false)
	var undamped: PackedVector3Array = await _run_ab(1.0, false)
	assert_ne(damped, undamped, "fixture: rebound_damping 0.3 changed the pile (the damping path is live)")


func test_batched_hooks_match_legacy_hooks_for_blocks_spawned_between_ticks() -> void:
	await _run_ab(0.3, true)


func test_batch_hook_is_the_first_physics_frame_listener() -> void:
	var block: Block = BlockFactory.build(load(SHAPE_PATHS[0]), _tuning)
	add_child_autofree(block)
	await wait_physics_frames(2)
	assert_true(BlockStepBatch.is_installed())
	var connections: Array = get_tree().physics_frame.get_connections()
	assert_gt(connections.size(), 1, "fixture: GUT's awaiter listens too")
	var first: Callable = (connections[0] as Dictionary)["callable"]
	assert_eq(first.get_object(), BlockStepBatch._instance, "the batch runs before every other physics_frame listener")


## A block frozen to STATIC between ticks still gets Jolt's already-queued
## state sync next tick (the old _integrate_forces() early-out consumed a
## pending kick there). The STATIC freeze puts the body to sleep, so that sync
## raises sleeping_state_changed and Block runs the same early-out there.
func test_freeze_between_ticks_gets_the_final_sync_like_legacy() -> void:
	var spawn: Dictionary = {
		"shape": load(SHAPE_PATHS[0]), "tuning": _tuning,
		"xform": Transform3D(Basis.IDENTITY, Vector3(0.0, KICK_DROP_Y_M, 0.0)), "role": &"pile",
	}
	var legacy: Block = _build(spawn, true)
	var batched: Block = _build(spawn, false)
	_world().add_child(legacy)
	_world().add_child(batched)
	await wait_physics_frames(FREEZE_SETTLE_TICKS)
	await wait_process_frames(1)
	assert_false(Engine.is_in_physics_frame(), "fixture: freezing between ticks")
	for block: Block in [legacy, batched]:
		block.mark_script_kick()
		block.request_freeze_static(Block.FREEZE_REASON_STABLE)
	await wait_physics_frames(FREEZE_SETTLE_TICKS)
	assert_false(legacy._script_kick_pending, "fixture: the legacy final sync consumed the kick")
	assert_eq(batched._script_kick_pending, legacy._script_kick_pending, "same kick state after the final sync")
	assert_eq(
		batched._prev_step_linear_velocity_y, legacy._prev_step_linear_velocity_y, "same rebound sample after it"
	)


func test_kick_marked_during_sync_phase_is_due_next_frame() -> void:
	var block: Block = BlockFactory.build(load(SHAPE_PATHS[0]), _tuning)
	add_child_autofree(block)
	var frame: int = Engine.get_physics_frames()
	block.mark_script_kick()
	assert_true(block._script_kick_pending)
	assert_eq(block._kick_frame, frame, "the mark remembers its physics frame")
