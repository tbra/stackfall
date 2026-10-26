class_name SpecialBehavior
extends Node
## Attached (as a child Node) to a spawned special's Block (spec 1.6). Ages
## from bind(), arms at `def.arm_delay`, detects an impact by sampling its
## own parent Block's velocity drop each tick (the same pattern as game/blocks/Block.gd,
## not `contact_monitor`/signals), triggers exactly once (impact, the effect's own early-trigger check, or a
## fuse timeout, whichever comes first), and can chain into nearby specials
## up to `SpecialTuning.max_chain_depth`.
##
## A Node rather than core/ logic: reading a live RigidBody3D's velocity every physics tick
## and finding sibling specials via get_tree().get_nodes_in_group() is scene-tree
## dependence. Every tick's work happens in advance(delta), which _physics_process()
## forwards to, so a test drives advance() with a stub Block whose linear_velocity/mass it
## sets by hand and no physics runs.

## Every SpecialBehavior joins this group so trigger_others_in_range() below
## can find chain-reaction candidates via get_tree().get_nodes_in_group()
## rather than a hand-maintained registry.
const GROUP: StringName = &"specials"

## Emitted the instant trigger() actually runs (idempotent -- never fires
## twice for the same instance). A listener on every spawned special re-emits/replicates
## Events.special_triggered from there.
signal triggered(def_id: StringName, position: Vector3, chain_depth: int)

## Emitted once, host-side, when a gift-bound behavior's
## action is complete (a short linger after trigger(), or the hard
## max-lifetime backstop for an action that never completes). The block's owning slot
## (MatchPlacement) removes the body through the normal block-
## removal path; this class never frees its own parent.
signal completed(block: Block)

## Set by MatchPlacement for a gift-drawn special only. Projectile specials
## (Volcano orbs) and plain blocks never set it, so they are never despawned.
var despawn_when_done: bool = false

var _completed: bool = false
var _despawn_timer: float = -1.0

## The SpecialEffect of a def (SpecialDef.effect is a Resource so config/ stays free
## of game/); null if the def or its effect is missing or of another type.
static func effect_of(def: SpecialDef) -> SpecialEffect:
	return def.effect as SpecialEffect if def != null else null


var _block: Block = null
var _def: SpecialDef = null
var _tuning: SpecialTuning = null
var _state: EffectState = null

var _age: float = 0.0
var _armed: bool = false
var _has_triggered: bool = false
var _chain_depth: int = 0
var _prev_linear_velocity: Vector3 = Vector3.ZERO

## Landing detection for effects with needs_landing(), instead of
## Jolt `sleeping`, which never fires on a tilting disc with an awake island.
var _landed_probe: LandedProbe = null
var _landed_at_age: float = -1.0


## Entry point -- called once, immediately after this node is added as a child of `block`
## (plain @export def/tuning fields would race _ready() on a node built with .new()).
func bind(block: Block, def: SpecialDef, tuning: SpecialTuning) -> void:
	_block = block
	_def = def
	_tuning = tuning
	_age = 0.0
	_armed = false
	_has_triggered = false
	_chain_depth = 0
	_completed = false
	_despawn_timer = -1.0
	var fx0: SpecialEffect = effect_of(_def) if _def != null else null
	_state = fx0.new_state() if fx0 != null else null
	var effect_landed: LandedTuning = fx0.landed_tuning() if fx0 != null else null
	_landed_probe = LandedProbe.new(effect_landed)
	_landed_at_age = -1.0
	_prev_linear_velocity = block.linear_velocity if block != null else Vector3.ZERO
	add_to_group(GROUP)


## The bound def's id; &"" before bind().
func def_id() -> StringName:
	return _def.id if _def != null else &""


## The effect's per-activation state taken in bind(); null for a stateless effect.
func state() -> EffectState:
	return _state


## Every live SpecialBehavior in the tree, in group insertion order.
static func live(tree: SceneTree) -> Array[SpecialBehavior]:
	var result: Array[SpecialBehavior] = []
	for node: Node in tree.get_nodes_in_group(GROUP):
		var behavior: SpecialBehavior = node as SpecialBehavior
		if behavior != null:
			result.append(behavior)
	return result


func is_triggered() -> bool:
	return _has_triggered


func age() -> float:
	return _age


func chain_depth() -> int:
	return _chain_depth


## True once the carrier has landed per the LandedProbe. Only meaningful for an
## effect whose needs_landing() is true (the probe is not fed otherwise).
func has_landed() -> bool:
	return _landed_at_age >= 0.0


## Seconds since landing; 0.0 before it.
func landed_age() -> float:
	return maxf(_age - _landed_at_age, 0.0) if _landed_at_age >= 0.0 else 0.0


func _physics_process(delta: float) -> void:
	advance(delta)


## The per-tick logic, split out from _physics_process() so a test can drive it directly.
func advance(delta: float) -> void:
	if _block == null or _def == null:
		return
	if _has_triggered:
		_advance_completion(delta)
		return
	_age += delta
	if despawn_when_done and _tuning != null and _age >= _tuning.gift_max_lifetime_s:
		_complete()
		return
	if not _armed and _age >= _def.arm_delay:
		_armed = true
		# Re-sample at the arming instant so the first post-arm decel is measured against the
		# velocity at arming, not a stale sample from before arm_delay elapsed.
		_prev_linear_velocity = _block.linear_velocity
	# An in-place activated gift has no falling carrier to wait for.
	var fx1: SpecialEffect = effect_of(_def)
	var needs_landing: bool = (
		_def.effect != null and fx1.needs_landing() and not _def.activates_in_place
	)
	if needs_landing and _landed_at_age < 0.0:
		_landed_probe.update(_block, delta)
		if _landed_probe.has_landed():
			_landed_at_age = _age
	if _armed:
		_check_impact()
	var effect_may_run: bool = not needs_landing or _landed_at_age >= 0.0
	if not _has_triggered and _armed and effect_may_run and _def.effect != null:
		var fx: SpecialEffect = effect_of(_def)
		fx.physics_tick(_block, self, delta)
		if not _has_triggered and fx.wants_early_trigger(_block, self):
			trigger(0)
	if not _has_triggered and _age >= _fuse_deadline():
		trigger(0)


## Age at which the fuse force-triggers. Without an effect lifetime this is
## arm_delay + fuse_timeout_s. With effect_lifetime_s() > 0 it is derived from the
## lifetime: landing time (or, before landing, arm_delay + fuse_timeout_s as the
## landing wait) + lifetime + SpecialTuning.fuse_backstop_margin_s.
func _fuse_deadline() -> float:
	var base: float = _def.arm_delay + _def.fuse_timeout_s
	if _def.effect == null:
		return base
	var fx2: SpecialEffect = effect_of(_def)
	var lifetime: float = fx2.effect_lifetime_s()
	if lifetime <= 0.0:
		return base
	var margin: float = _tuning.fuse_backstop_margin_s if _tuning != null else 0.0
	if fx2.needs_landing() and _landed_at_age < 0.0:
		return base + lifetime + margin
	var start: float = _landed_at_age if _landed_at_age >= 0.0 else _def.arm_delay
	return start + lifetime + margin


## Counts the post-trigger linger down and completes once it elapses.
func _advance_completion(delta: float) -> void:
	if _despawn_timer < 0.0 or _completed:
		return
	_despawn_timer -= delta
	if _despawn_timer <= 0.0:
		_complete()


## DECISION: every effect's action is over when trigger()
## returns -- instant effects (Bomb, Anvil, Rocket explosion, Cat, Glue,
## Paintball, Stackfall) act inside detonate(), and the timed windows
## (Propeller, Jumping Bean hops, Earthquake, Volcano, Magnet) end exactly
## when wants_early_trigger() fires trigger(). So one hook covers all of them:
## `gift_despawn_delay_s` after trigger the gift is complete. Anything that
## never triggers is caught by the fuse timeout and, as a hard backstop, by
## SpecialTuning.gift_max_lifetime_s.
func _complete() -> void:
	if _completed:
		return
	_completed = true
	completed.emit(_block)


## DECISION: reuses game/blocks/Block.gd's velocity-drop impact pattern
## (`mass * (prev_speed - now_speed)`, an impulse-like deceleration measure in kg*m/s)
## instead of RigidBody3D's `contact_monitor`/`body_entered`: no per-block contact_monitor
## wiring, and cheap enough to run every tick for every armed special (a contact_monitor
## revision cost 5-7 ms/step at 300 blocks). Only checked once armed (spec 1.6: activation
## requires both the impact AND having passed arm_delay).
##
## While asleep, Jolt stops integrating the body, so its `linear_velocity` reads as a
## false, constant value the instant something wakes it, which would look like a sudden
## impact and detonate a settled special. So while asleep, re-seed `_prev_linear_velocity`
## and skip the drop test; arming/fuse ageing is unaffected.
##
## A decel past `arm_impulse` also consults `effect_of(_def).impact_triggers()` before
## trigger(): a timed-effect-pattern special vetoes it so its own arming-tick landing
## impact cannot short-circuit its physics_tick() window. A null `_def.effect` always
## triggers.
func _check_impact() -> void:
	if _block.sleeping:
		_prev_linear_velocity = _block.linear_velocity
		return
	var prev_speed: float = _prev_linear_velocity.length()
	var current_velocity: Vector3 = _block.linear_velocity
	var now_speed: float = current_velocity.length()
	var decel: float = _block.mass * (prev_speed - now_speed)
	_prev_linear_velocity = current_velocity
	if _has_triggered or decel < _def.arm_impulse:
		return
	if _def.effect != null:
		var fx3: SpecialEffect = effect_of(_def)
		if not fx3.triggers_on_impact() or not fx3.impact_triggers(_block, self):
			return
	trigger(0)


## `impact_filter`: contact
## filter for an effect that detects its own impact instead of using the velocity-drop
## test above (Rocket probes the contact it is about to make, so it knows the collider).
## True when a contact with `collider` counts as an impact. The carrier itself never
## counts. For the first `SpecialDef.arm_delay` seconds after `window_start_age` (this
## behaviour's age() when the effect started acting, 0 = since bind) the owner's own
## blocks do not count either, so a launch does not detonate on its thrower's stack.
## Anything that is not a Block (the disc, map geometry) always counts.
func impact_filter(collider: Object, window_start_age: float = 0.0) -> bool:
	if collider == null or collider == _block:
		return false
	var other: Block = collider as Block
	if other == null or _block == null or _def == null:
		return true
	var in_grace: bool = _age - window_start_age < _def.arm_delay
	if in_grace and _block.owner_slot >= 0 and other.owner_slot == _block.owner_slot:
		return false
	return true


## Idempotent: a second/third call after the
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
		var fx4: SpecialEffect = effect_of(_def)
		fx4.detonate(_block, self, _chain_depth)
	var def_id: StringName = _def.id if _def != null else &""
	triggered.emit(def_id, position, _chain_depth)
	if despawn_when_done:
		var fx5: SpecialEffect = effect_of(_def) if _def != null else null
		if fx5 != null and fx5.detaches():
			# The effect owns a standalone world node: no linger, the carrier goes now.
			_despawn_timer = 0.0
			_complete()
		else:
			_despawn_timer = _tuning.gift_despawn_delay_s if _tuning != null else 0.0


## Called by a concrete SpecialEffect's own detonate(), not by
## trigger() itself -- each effect knows its own blast/chain radius (a field
## on that effect's subclass, e.g. RocketEffect.radius), which SpecialDef/
## SpecialBehavior have no business knowing generically. Finds every other
## SpecialBehavior in GROUP via the scene tree, then delegates the actual
## in-range/not-already-triggered filtering to the pure _filter_in_range()
## below, and triggers each survivor one chain link deeper.
func trigger_others_in_range(center: Vector3, radius: float, chain_depth: int) -> void:
	var candidates: Array[SpecialBehavior] = live(get_tree())
	candidates.erase(self)
	for target: SpecialBehavior in _filter_in_range(candidates, center, radius, chain_depth):
		target.trigger(chain_depth + 1)


## Pure (no scene-tree/group lookups of its own) so tests/unit/
## test_special_behavior.gd can call it directly with a manufactured
## candidate array. Chain-cap semantics: once
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
