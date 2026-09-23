class_name SpecialBehavior
extends Node
## Attached (as a child Node) to a spawned special's Block (spec 2.6). Ages
## from bind(), arms at `def.arm_delay`, detects an impact by sampling its
## own parent Block's velocity drop each tick (game/Block.gd:61-75's own
## impact-detection pattern, reused rather than duplicated via
## `contact_monitor`/signals -- see the DECISION on _check_impact() below),
## triggers exactly once (impact, the effect's own early-trigger check, or a
## fuse timeout, whichever comes first), and can chain into nearby specials
## up to `SpecialTuning.max_chain_depth`.
##
## Pure logic wrapped in a Node rather than core/ RefCounted: CLAUDE.md keeps
## core/ free of scene-tree dependence, but this class's whole job --
## reading a live RigidBody3D's velocity every physics tick, finding sibling
## specials via get_tree().get_nodes_in_group() -- IS scene-tree dependence,
## so it belongs in game/ instead. Testable without physics regardless: every
## tick's actual work happens in advance(delta) below, which
## _physics_process() just forwards to; a test calls advance() directly with
## a stub Block whose linear_velocity/mass it sets by hand, so no physics
## simulation ever needs to run for these tests.

## Every SpecialBehavior joins this group so trigger_others_in_range() below
## can find chain-reaction candidates via get_tree().get_nodes_in_group()
## rather than a hand-maintained registry.
const GROUP: StringName = &"specials"

## Emitted the instant trigger() actually runs (idempotent -- never fires
## twice for the same instance). autoload/Events.gd is NOT touched by this
## package (docs/M4_P2_PACKAGES.md's orchestrator amendment 2); P2c listens
## to this signal on every spawned special and re-emits/replicates
## Events.special_triggered from there.
signal triggered(def_id: StringName, position: Vector3, chain_depth: int)

var _block: Block = null
var _def: SpecialDef = null
var _tuning: SpecialTuning = null

var _age: float = 0.0
var _armed: bool = false
var _has_triggered: bool = false
var _chain_depth: int = 0
var _prev_linear_velocity: Vector3 = Vector3.ZERO


## Entry point -- called once, immediately after this node is created and
## added as a child of `block` (docs/M4_P2_PACKAGES.md P2a: "avoids an
## @export-then-add_child() ordering race" that plain @export var def/tuning
## fields would have, since Godot doesn't guarantee export values are set
## before _ready() runs for a node built with .new()).
func bind(block: Block, def: SpecialDef, tuning: SpecialTuning) -> void:
	_block = block
	_def = def
	_tuning = tuning
	_age = 0.0
	_armed = false
	_has_triggered = false
	_chain_depth = 0
	_prev_linear_velocity = block.linear_velocity if block != null else Vector3.ZERO
	add_to_group(GROUP)


func is_armed() -> bool:
	return _armed


func is_triggered() -> bool:
	return _has_triggered


func age() -> float:
	return _age


func chain_depth() -> int:
	return _chain_depth


func _physics_process(delta: float) -> void:
	advance(delta)


## The actual per-tick logic, split out from _physics_process() so a test can
## drive it directly regardless of whether the test tree is actually running
## physics (docs/M4_P2_PACKAGES.md P2a: "tests drive `_physics_process(delta)`
## /an `advance(delta)` hook").
func advance(delta: float) -> void:
	if _has_triggered or _block == null or _def == null:
		return
	_age += delta
	if not _armed and _age >= _def.arm_delay:
		_armed = true
		# Re-sample right at the arming instant so the very first post-arm
		# tick's decel is measured against "velocity when arming happened",
		# not a stale sample from before arm_delay elapsed.
		_prev_linear_velocity = _block.linear_velocity
	if _armed:
		_check_impact()
	if not _has_triggered and _armed and _def.effect != null:
		_def.effect.physics_tick(_block, self, delta)
		if not _has_triggered and _def.effect.wants_early_trigger(_block, self):
			trigger(0)
	if not _has_triggered and _age >= _def.arm_delay + _def.fuse_timeout_s:
		trigger(0)


## DECISION (game/specials/SpecialBehavior.gd, docs/M4_P2_PACKAGES.md P2a
## decision 3): reuses game/Block.gd's own velocity-drop impact pattern
## (`mass * (prev_speed - now_speed)`, an impulse-like deceleration measure
## in kg*m/s) instead of RigidBody3D's `contact_monitor`/`body_entered`
## signals -- no `game/Block.gd` edit, no per-block `contact_monitor`
## wiring, and it is cheap enough to run every tick for every armed special
## (Block.gd's own comment: an earlier contact_monitor revision cost 5-7 ms
## /step at 300 blocks). Only checked once armed (spec 2.6: activation
## requires both the impact AND having passed arm_delay).
##
## Review fix (Bontago-1en.12): mirrors game/Block.gd:61-63's own
## `if not impacts_enabled or sleeping` guard -- Jolt stops integrating a
## sleeping body, so its `linear_velocity` reads as a false, constant value
## the instant something wakes it, which would otherwise look like a sudden
## "impact" the tick after wake and detonate a settled special spuriously.
## While asleep, just re-seed `_prev_linear_velocity` from the current
## (stale-but-honest) reading and skip the drop test entirely; the first
## tick after waking then compares against that fresh sample rather than
## whatever velocity happened to be cached from before sleep, exactly like
## Block.gd's own `_prev_linear_velocity = linear_velocity; return` early
## exit. Arming/fuse ageing (advance()'s caller) is untouched by this --
## only the impact *test* is skipped while asleep.
func _check_impact() -> void:
	if _block.sleeping:
		_prev_linear_velocity = _block.linear_velocity
		return
	var prev_speed: float = _prev_linear_velocity.length()
	var current_velocity: Vector3 = _block.linear_velocity
	var now_speed: float = current_velocity.length()
	var decel: float = _block.mass * (prev_speed - now_speed)
	_prev_linear_velocity = current_velocity
	if not _has_triggered and decel >= _def.arm_impulse:
		trigger(0)


## Idempotent (docs/M4_P2_PACKAGES.md P2a): a second/third call after the
## first is a no-op. Always calls def.effect.detonate() (a SpecialDef with
## no effect assigned just detonates as a no-op -- see SpecialEffect.gd) and
## always emits `triggered`, even past the chain-depth cap -- the hit
## special itself is always visible; only the chain it might have started
## stops extending (see trigger_others_in_range()'s own cap check).
func trigger(incoming_chain_depth: int) -> void:
	if _has_triggered:
		return
	_has_triggered = true
	_chain_depth = incoming_chain_depth
	var position: Vector3 = _block.global_position if _block != null else Vector3.ZERO
	if _def != null and _def.effect != null:
		_def.effect.detonate(_block, self, _chain_depth)
	var def_id: StringName = _def.id if _def != null else &""
	triggered.emit(def_id, position, _chain_depth)


## Called by a concrete SpecialEffect's own detonate() (P3-P5), not by
## trigger() itself -- each effect knows its own blast/chain radius (a field
## on that effect's subclass, e.g. RocketEffect.radius), which SpecialDef/
## SpecialBehavior have no business knowing generically. Finds every other
## SpecialBehavior in GROUP via the scene tree, then delegates the actual
## in-range/not-already-triggered filtering to the pure _filter_in_range()
## below, and triggers each survivor one chain link deeper.
func trigger_others_in_range(center: Vector3, radius: float, chain_depth: int) -> void:
	var candidates: Array[SpecialBehavior] = []
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		if node is SpecialBehavior and node != self:
			candidates.append(node as SpecialBehavior)
	for target: SpecialBehavior in _filter_in_range(candidates, center, radius, chain_depth):
		target.trigger(chain_depth + 1)


## Pure (no scene-tree/group lookups of its own) so tests/unit/
## test_special_behavior.gd can call it directly with a manufactured
## candidate array (docs/M4_P2_PACKAGES.md P2a). Chain-cap semantics: once
## `chain_depth >= _tuning.max_chain_depth`, returns an empty array
## immediately -- the chain stops extending, even though the special that
## got us here already detonated in trigger() regardless of this check.
## Otherwise keeps candidates that are (a) not already triggered and
## (b) within `radius` of `center`.
func _filter_in_range(
	candidates: Array[SpecialBehavior], center: Vector3, radius: float, chain_depth: int
) -> Array[SpecialBehavior]:
	var result: Array[SpecialBehavior] = []
	if _tuning != null and chain_depth >= _tuning.max_chain_depth:
		return result
	for candidate: SpecialBehavior in candidates:
		if candidate == null or candidate.is_triggered():
			continue
		if candidate._block == null:
			continue
		if candidate._block.global_position.distance_to(center) <= radius:
			result.append(candidate)
	return result
