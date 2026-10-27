class_name BombEffect
extends SpecialEffect
## Bomb / DaBomb special. OWNER decision (docs/SPEC.md 2.6):
## "When dropped the Bomb blinks for a few seconds, then explodes, sending nearby
## blocks flying away from the centre of the explosion." Impacts never set it off; a
## chain trigger from a neighbouring blast still detonates it early.
##
## Timeline: the Bomb blinks for `blink_duration_s`, then ExplosionFx blasts
## (`behavior.effect_age() >= blink_duration_s` on the host). A placed Bomb counts from its drop;
## a thrown one from its first landing contact (SpecialBehavior.starts_on_landing), so nothing blinks
## or counts down in flight. The blink visual is derived from the same clock on every peer
## (GiftBlink.start_for_gift, no RPC); see GiftFxPresenter for the thrown case.
##
## DECISION: a Bomb that never lands is exploded by the fuse backstop; the blast is
## mass-independent and team-agnostic.
##
## Like every shared SpecialEffect resource this keeps NO per-block state on itself:
## the one flag it needs lives in the EffectState from new_state().

## Seconds the Bomb blinks before it explodes (plan section 3: 3.0).
@export var blink_duration_s: float = 3.0

## Blink period at the start of the blink, in seconds; it accelerates toward
## `period * GiftBlinkTuning.end_period_ratio` (plan: 0.25 s to 0.1 s).
@export var blink_period_s: float = 0.25

## Blink colour, peak opacity and end-period ratio.
@export var blink_tuning: GiftBlinkTuning = preload("res://config/gifts/specials/fx/gift_blink_tuning.tres")

## Blast shape: radius, peak delta-v, falloff, upward bias, per-body cap. Mass independent
## (ExplosionFx).
@export var blast: ExplosionTuning = ExplosionTuning.new()

class State:
	extends EffectState
	## The host-side blink was already started for this carrier, so the per-tick fallback
	## below starts it once and a finished blink is not restarted.
	var blink_started: bool = false


## Impacts never detonate the Bomb (it explodes on its timer, "regardless of impacts").
func triggers_on_impact() -> bool:
	return false


## The action runs `blink_duration_s` from the drop; SpecialBehavior derives its fuse
## backstop from this.
func effect_lifetime_s() -> float:
	return blink_duration_s


## DECISION: the spent carrier is removed at the explosion, with no
## 0.75 s linger (SpecialBehavior.trigger -> completed). Nothing of the bomb is left to
## show, and a lingering collider would keep shoving the blown-away blocks.
func detaches() -> bool:
	return true


## Host-side blink fallback: the blink normally starts at spawn on every peer through
## GiftBlink.start_for_gift (needs a spawn hook outside this package); until that hook
## exists the host's own carrier starts it on its first armed tick, with its age so the
## blink still ends with the explosion. Idempotent via the state.
func physics_tick(block: Block, behavior: SpecialBehavior, _delta: float) -> void:
	var state: State = behavior.state() as State
	if state.blink_started:
		return
	state.blink_started = true
	if block.get_node_or_null(NodePath(String(GiftBlink.DRIVER_NAME))) == null:
		GiftBlink.apply(block, blink_period_s, blink_duration_s, blink_tuning, behavior.effect_age())


## The blink is over: explode (SpecialBehavior calls this once armed, so a Bomb whose
## blink is shorter than arm_delay waits for arming).
func wants_early_trigger(_block: Block, behavior: SpecialBehavior) -> bool:
	return behavior.effect_age() >= blink_duration_s


func new_state() -> EffectState:
	return State.new()


func effect_radius_m() -> float:
	return blast.radius_m


## Every peer draws the blast at the trigger position.
func build_client_fx(ctx: MatchContext, _block: Block, position: Vector3, _owner_slot: int) -> void:
	CartoonBlast.spawn(ctx, position, blast)


## Blast every real RigidBody3D within `blast.radius_m` (the Bomb's own body excluded),
## then chain into any other special in range one depth deeper.
func detonate(block: Block, behavior: SpecialBehavior, chain_depth: int) -> void:
	var center: Vector3 = block.global_position
	ExplosionFx.blast(block.get_world_3d().direct_space_state, center, blast, [block.get_rid()])
	ExplosionFx.chain(behavior, center, blast.radius_m, chain_depth)
