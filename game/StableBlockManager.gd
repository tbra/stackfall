class_name StableBlockManager
extends Node
## Stable-block optimization (spec 3.5 [NEW]: "If a block has been asleep for
## more than 20 s and isn't touching any awake body, the host switches it to
## freeze_mode = STATIC. It goes back to normal the moment any impulse,
## tilt, or change in the cells under it happens."), docs/M8_PLAN.md P5.
##
## Host-gated the same way every autoload/match/ controller already is (`if
## not Net.is_host(): return`, true offline too, matching
## game/BotController.gd's own convention) -- built unconditionally at
## game/Main.gd's single wiring point (see that file's own comment there) so
## a client's copy costs nothing and stays inert, never a client-side scan.
##
## "Isn't touching any awake body" is satisfied for free by relying on
## Jolt's own island-sleep semantics (RigidBody3D.sleeping) rather than a
## manual per-tick contact check -- a whole contact-connected island sleeps
## together (config/PhysicsTuning.gd's own long comment on this), so a block
## resting against something still awake never reads as sleeping at all, and
## this class never has to ask "what else is it touching" itself.
##
## Poll-based, not signal-based: rather than connecting to each tracked
## Block's own sleeping_state_changed (game/BlockFactory.build()'s pattern),
## this reads Block.sleeping directly on its own low-rate scan
## (PhysicsTuning.stable_freeze_scan_interval_s) so it never has to manage a
## per-block connect/disconnect lifecycle as game/BlockRegistry.all_blocks()'s
## own set changes underneath it every placement/removal -- and so
## tests/unit/test_stable_block_manager.gd can drive it deterministically
## through _tick() below without waiting any real seconds or needing a real
## physics step to fire a signal.

@export var tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")

var _registry: BlockRegistry = null

## The live manager (the match builds one). Weather effects reach it through
## this instead of touching Block's private freeze bookkeeping (Bontago-1pi.11.46).
static var active: StableBlockManager = null

## instance id (int) -> continuous seconds this block has read as sleeping
## across consecutive scans. Reset to 0 the moment a scan finds it awake.
var _asleep_elapsed: Dictionary = {}
## instance id (int) -> Transform3D the block had when its current rest run
## started (Bontago-1pi.11.24). A wake that leaves the block within
## tuning.stable_freeze_rest_epsilon_m of this pose keeps the run's timer.
var _rest_anchor: Dictionary = {}
## instance id (int) -> true while this manager itself holds
## Block.FREEZE_REASON_STABLE on that block (so release only ever targets a
## block this manager actually froze).
var _frozen_by_this: Dictionary = {}
## instance id -> true for blocks frozen through the awake-but-still settle path. Such
## a block may keep reading awake (can_sleep false, or a body Jolt will not sleep), so
## the awake-read release in _scan() must not undo it (that flapped every window).
var _settle_frozen: Dictionary = {}

## Real-time accumulator gating how often _tick() below actually scans,
## consumed by _tick() itself -- see that function's own doc comment.
var _scan_accumulator: float = 0.0
## Field pose seen on the previous physics tick (Bontago-sen.11).
var _last_field_transform: Transform3D = Transform3D.IDENTITY
## Awake-but-still tracking (Bontago-e7o B; see _settle_awake()).
var _settle: SettleTracker = SettleTracker.new()
## Catch-up cap state last pushed to Engine (the project setting starts capped).
var _catchup_cap_applied: bool = true


## Called once by game/Main.gd right after it builds a match's BlockRegistry
## (its own single wiring-point comment), the same setup() shape
## game/BotController.gd already uses for the same registry reference.
func setup(registry: BlockRegistry) -> void:
	_registry = registry
	active = self


func _exit_tree() -> void:
	if active == self:
		active = null


## True while this manager holds the stable freeze on `block`.
func is_stable_frozen(block: Block) -> bool:
	return block.is_freeze_static() and _frozen_by_this.get(block.get_instance_id(), false)


## Wakes a stable-frozen block so an external force (wind) can move it, and
## puts it back into the normal sleep -> 20 s -> freeze cycle: the frozen flag
## and rest timer are cleared here so the next scan that reads it asleep counts
## from zero and re-freezes it. Returns true when a freeze was released.
func wake_for_external_force(block: Block) -> bool:
	var id: int = block.get_instance_id()
	if not _frozen_by_this.get(id, false):
		return false
	_frozen_by_this[id] = false
	_asleep_elapsed[id] = 0.0
	_rest_anchor.erase(id)
	_settle.reset(id)
	_settle_frozen.erase(id)
	block.release_freeze_static(Block.FREEZE_REASON_STABLE)
	block.wake()
	return true


func _physics_process(delta: float) -> void:
	apply_catchup_cap()
	if not Net.is_host():
		return
	check_field_motion()
	_tick(delta)


## Bontago-e7o D: pushes the F4 catch-up toggle to the engine when it changes
## (every peer: it is per-process frame pacing, not game state). Applied only on a
## change so a bench that raises Engine.max_physics_steps_per_frame itself is not
## overridden every tick; the project setting already starts it capped.
func apply_catchup_cap() -> void:
	var want_capped: bool = tuning.catchup_cap_enabled
	if want_capped == _catchup_cap_applied:
		return
	_catchup_cap_applied = want_capped
	Engine.max_physics_steps_per_frame = tuning.catchup_steps_capped if want_capped else tuning.catchup_steps_default


## Bontago-sen.11 (owner: "gifts that cause tilting lead to settled blocks
## clipping through the disc"): a STATIC-frozen block does not ride a
## kinematic disc, so a tilting Field swept through every long-stable block.
## The scan below only releases a block once it reads awake, which a frozen
## body never does, and only every scan interval. So the moment the disc pose
## changes, release every block this manager froze and wake it, and restart
## its asleep timer; the blocks then ride the disc (awake while it moves,
## Bontago-b0w) and re-freeze after the normal delay once it stops.
func check_field_motion() -> void:
	if _registry == null:
		return
	var current: Transform3D = _registry.field_global_transform()
	if current == _last_field_transform:
		return
	_last_field_transform = current
	for block: Block in _registry.all_blocks():
		var id: int = block.get_instance_id()
		_asleep_elapsed[id] = 0.0
		_rest_anchor.erase(id)
		_settle.reset(id)
		_settle_frozen.erase(id)
		if _frozen_by_this.get(id, false):
			block.release_freeze_static(Block.FREEZE_REASON_STABLE)
			block.wake()
			_frozen_by_this[id] = false


## Test seam (tests/unit/test_stable_block_manager.gd): advances the scan
## accumulator by `delta` seconds and, once it reaches
## tuning.stable_freeze_scan_interval_s, runs exactly one real scan pass with
## that accumulated span as the elapsed time credited to every block still
## found asleep -- so a test can cross tuning.stable_freeze_delay_s in a
## single call (e.g. `_tick(21.0)`) instead of waiting 20 real seconds or
## driving 1200+ individual physics frames. Never checks Net.is_host() itself
## (only _physics_process() above does) so a bare-Node unit test needs no
## networking context to call this directly.
func _tick(delta: float) -> void:
	_scan_accumulator += delta
	if _scan_accumulator < tuning.stable_freeze_scan_interval_s:
		return
	var scan_delta: float = _scan_accumulator
	_scan_accumulator = 0.0
	_scan(scan_delta)


func _scan(scan_delta: float) -> void:
	if _registry == null:
		return
	var live_ids: Dictionary = {}
	var blocks: Array[Block] = _registry.all_blocks()
	var settle_on: bool = tuning.settle_freeze_enabled
	var fast_positions: PackedVector3Array = PackedVector3Array()
	if settle_on:
		_configure_settle()
		fast_positions = _fast_positions(blocks)
	for block: Block in blocks:
		var id: int = block.get_instance_id()
		live_ids[id] = true
		if block.sleeping:
			_settle.reset(id)
			if not _rest_anchor.has(id):
				_rest_anchor[id] = block.global_transform
			var elapsed: float = float(_asleep_elapsed.get(id, 0.0)) + scan_delta
			_asleep_elapsed[id] = elapsed
			if elapsed >= tuning.stable_freeze_delay_s and not _frozen_by_this.get(id, false):
				block.request_freeze_static(Block.FREEZE_REASON_STABLE)
				_frozen_by_this[id] = true
		else:
			# Spec 3.5: "goes back to normal the moment any impulse, tilt, or
			# change in the cells under it happens" -- any of those wakes the
			# body (RigidBody3D.sleeping reads false again the very next
			# scan), so releasing here on the plain wake-read covers all
			# three cases without this class needing to know which one
			# happened.
			if _frozen_by_this.get(id, false) and not (_settle_frozen.get(id, false) and block.freeze):
				block.release_freeze_static(Block.FREEZE_REASON_STABLE)
				_frozen_by_this[id] = false
				_settle_frozen.erase(id)
			if settle_on:
				_settle_awake(block, id, scan_delta, fast_positions)
			else:
				_settle.reset(id)
			# DECISION (game/StableBlockManager.gd, Bontago-1pi.11.24): Jolt
			# wakes a whole contact island when one member is touched, so in a
			# bot match the unfrozen top layer (~65 blocks, one island) woke
			# on every landing, never slept 20 s in a row, and freezing capped
			# near 100 blocks (all of them again after a tilt released every
			# frozen block). A wake that did not move this block beyond
			# tuning.stable_freeze_rest_epsilon_m of the pose it fell asleep
			# in pauses its timer instead of resetting it, so the 20 s counts
			# cumulative time asleep at rest. It still freezes only on a scan
			# that reads it asleep, i.e. with its whole island asleep and so
			# not touching an awake body.
			if not _rest_anchor.has(id) or _moved_from_anchor(block, _rest_anchor[id]):
				_asleep_elapsed[id] = 0.0
				_rest_anchor.erase(id)

	# A block BlockRegistry no longer tracks (removed/freed) can't be scanned
	# again to release it properly -- but Events.block_removed/queue_free()
	# take the body itself out of the world either way, so there is nothing
	# left needing FREEZE_MODE_RIGID restored. Just drop this manager's own
	# bookkeeping for it, the same defensive cleanup
	# game/BlockRegistry.gd's own _physics_process() does for _entries.
	for id: Variant in _asleep_elapsed.keys().duplicate():
		if not live_ids.has(id):
			_asleep_elapsed.erase(id)
			_frozen_by_this.erase(id)
			_rest_anchor.erase(id)
			_settle.reset(id as int)
			_settle_frozen.erase(id)
	# Blocks removed while awake never entered _asleep_elapsed's cleanup above.
	_settle.prune(live_ids)


func _configure_settle() -> void:
	_settle.window_s = tuning.settle_freeze_window_s
	_settle.move_epsilon_m = tuning.settle_freeze_move_epsilon_m
	_settle.rotation_epsilon = tuning.settle_freeze_rotation_epsilon
	_settle.fast_speed_mps = tuning.settle_freeze_fast_speed_mps
	_settle.neighbour_radius_m = tuning.settle_freeze_neighbour_radius_m


## Positions of awake blocks moving faster than the fast-neighbour speed. Reads
## only linear_velocity the engine already holds: no physics query per block.
func _fast_positions(blocks: Array[Block]) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	for block: Block in blocks:
		if not block.sleeping and _settle.is_fast(block.linear_velocity.length_squared()):
			out.append(block.global_position)
	return out


## Bontago-e7o B (spec 3.5): an awake block that stayed still for the whole window
## and has no fast neighbour freezes exactly like an asleep one (request_freeze_static
## puts it to sleep, so the sleeping branch of _scan() then owns it, and every
## release path -- tilt, impulse, wind, glue -- applies unchanged). DECISION: the
## fast-neighbour test is a distance check against the few fast blocks, not a per-
## block physics query (Block runs without contact_monitor, see Block.gd).
func _settle_awake(block: Block, id: int, scan_delta: float, fast_positions: PackedVector3Array) -> void:
	if block.is_freeze_static():
		_settle.reset(id)
		return
	_settle.observe(id, block.global_transform, scan_delta)
	if not _settle.is_window_complete(id):
		return
	if _settle.is_fast(block.linear_velocity.length_squared()):
		return
	if _settle.has_fast_neighbour(block.global_position, fast_positions):
		return
	block.request_freeze_static(Block.FREEZE_REASON_STABLE)
	_frozen_by_this[id] = true
	_settle_frozen[id] = true
	_settle.reset(id)


func _moved_from_anchor(block: Block, anchor: Transform3D) -> bool:
	var current: Transform3D = block.global_transform
	var eps_sq: float = tuning.stable_freeze_rest_epsilon_m * tuning.stable_freeze_rest_epsilon_m
	return (
		current.origin.distance_squared_to(anchor.origin) > eps_sq
		or current.basis.x.distance_squared_to(anchor.basis.x) > eps_sq
		or current.basis.y.distance_squared_to(anchor.basis.y) > eps_sq
		or current.basis.z.distance_squared_to(anchor.basis.z) > eps_sq
	)
