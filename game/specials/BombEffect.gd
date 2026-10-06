class_name BombEffect
extends SpecialEffect
## Bomb / DaBomb special. OWNER decision 2026-10-05 (docs/SPEC.md 2.6, Bontago-1pi.85):
## "When dropped the Bomb blinks for a few seconds, then explodes, sending nearby
## blocks flying away from the centre of the explosion." Impacts never set it off; a
## chain trigger from a neighbouring blast still detonates it early.
##
## Timeline (docs/GIFT_EFFECTS_PLAN.md section 3): the Bomb blinks for
## `blink_duration_s` from the moment it is dropped, then ExplosionFx blasts. That is
## `behavior.age() >= blink_duration_s` on the host; the blink visual is derived from
## the same clock on every peer (GiftBlink.start_for_gift, no RPC).
##
## DECISION (Bontago-1pi.85.10): the clock starts at the drop (spawn), not at landing.
## Clients cannot see a landing (their copy of the body is frozen kinematic and reports
## no velocity) and plan section 7 forbids a new RPC, so a landing-anchored timeline
## would leave the client's blink ending before the host's explosion by the fall time.
## The spec text ("when dropped ... blinks ..., then explodes") matches. A Bomb still
## in the air at the end of its blink explodes there; the blast is mass-independent
## and team-agnostic either way.
##
## Like every shared SpecialEffect resource this keeps NO per-block state on itself:
## the one flag it needs lives in block meta.

## Seconds the Bomb blinks before it explodes (plan section 3: 3.0).
@export var blink_duration_s: float = 3.0

## Blink period at the start of the blink, in seconds; it accelerates toward
## `period * GiftBlinkTuning.end_period_ratio` (plan: 0.25 s to 0.1 s).
@export var blink_period_s: float = 0.25

## Blink colour, peak opacity and end-period ratio.
@export var blink_tuning: GiftBlinkTuning = preload("res://config/specials/fx/gift_blink_tuning.tres")

## Blast shape: radius, peak delta-v, falloff, upward bias, per-body cap. Mass independent
## (ExplosionFx), unlike the old kg*m/s impulse that did nothing to an 8 kg block.
@export var blast: ExplosionTuning = ExplosionTuning.new()

## block.set_meta() key: the host-side blink was already started for this carrier, so the
## per-tick fallback below starts it once and a finished blink is not restarted.
const _BLINK_STARTED_META: StringName = &"bomb_blink_started"


## Impacts never detonate the Bomb (it explodes on its timer, "regardless of impacts").
func triggers_on_impact() -> bool:
	return false


## The action runs `blink_duration_s` from the drop; SpecialBehavior derives its fuse
## backstop from this.
func effect_lifetime_s() -> float:
	return blink_duration_s


## DECISION (Bontago-1pi.85.10): the spent carrier is removed at the explosion, with no
## 0.75 s linger (SpecialBehavior.trigger -> completed). Nothing of the bomb is left to
## show, and a lingering collider would keep shoving the blown-away blocks.
func detaches() -> bool:
	return true


## Host-side blink fallback: the blink normally starts at spawn on every peer through
## GiftBlink.start_for_gift (needs a spawn hook outside this package); until that hook
## exists the host's own carrier starts it on its first armed tick, with its age so the
## blink still ends with the explosion. Idempotent via block meta.
func physics_tick(block: Block, behavior: SpecialBehavior, _delta: float) -> void:
	if block.has_meta(_BLINK_STARTED_META):
		return
	block.set_meta(_BLINK_STARTED_META, true)
	if block.get_node_or_null(NodePath(String(GiftBlink.DRIVER_NAME))) == null:
		GiftBlink.apply(block, blink_period_s, blink_duration_s, blink_tuning, behavior.age())


## The blink is over: explode (SpecialBehavior calls this once armed, so a Bomb whose
## blink is shorter than arm_delay waits for arming).
func wants_early_trigger(_block: Block, behavior: SpecialBehavior) -> bool:
	return behavior.age() >= blink_duration_s


## Blast every real RigidBody3D within `blast.radius_m` (the Bomb's own body excluded),
## then chain into any other special in range one depth deeper.
func detonate(block: Block, behavior: SpecialBehavior, chain_depth: int) -> void:
	var center: Vector3 = block.global_position
	ExplosionFx.blast(block.get_world_3d().direct_space_state, center, blast, [block.get_rid()])
	ExplosionFx.chain(behavior, center, blast.radius_m, chain_depth)
