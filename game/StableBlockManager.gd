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

## Real-time accumulator gating how often _tick() below actually scans,
## consumed by _tick() itself -- see that function's own doc comment.
var _scan_accumulator: float = 0.0
## Field pose seen on the previous physics tick (Bontago-sen.11).
var _last_field_transform: Transform3D = Transform3D.IDENTITY


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
	block.release_freeze_static(Block.FREEZE_REASON_STABLE)
	block.wake()
	return true


func _physics_process(delta: float) -> void:
	if not Net.is_host():
		return
	check_field_motion()
	_tick(delta)


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
	for block: Block in _registry.all_blocks():
		var id: int = block.get_instance_id()
		live_ids[id] = true
		if block.sleeping:
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
			if _frozen_by_this.get(id, false):
				block.release_freeze_static(Block.FREEZE_REASON_STABLE)
				_frozen_by_this[id] = false
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


func _moved_from_anchor(block: Block, anchor: Transform3D) -> bool:
	var current: Transform3D = block.global_transform
	var eps_sq: float = tuning.stable_freeze_rest_epsilon_m * tuning.stable_freeze_rest_epsilon_m
	return (
		current.origin.distance_squared_to(anchor.origin) > eps_sq
		or current.basis.x.distance_squared_to(anchor.basis.x) > eps_sq
		or current.basis.y.distance_squared_to(anchor.basis.y) > eps_sq
		or current.basis.z.distance_squared_to(anchor.basis.z) > eps_sq
	)
