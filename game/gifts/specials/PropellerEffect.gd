class_name PropellerEffect
extends SpecialEffect
## Propeller special (spec 1.6: "stands where it lands, then lifts itself and
## blows for its duration"). It activates where the gift is dropped, like the Volcano. The
## SpecialDef is `activates_in_place`, so it triggers at once on the host's
## invisible anchor and detonate() spawns a standalone PropellerStand: a team-colour
## party balloon clipped to the disc at the drop point that inflates, rises, and runs
## DiscForce.apply(sign -1) every tick for `disc_force.duration_s` (the Anvil in reverse:
## it raises the side it stands on), then POPs. Clients draw the same stand from the replicated special_triggered
## (GiftFxPresenter._build_propeller); there is no carrier body on any peer.
##
## No per-block state lives on this shared Resource; the stand owns its clock.

## DiscForce tuning. `strength` is tilt impulse per metre of disc-local
## distance per second (DiscForce.apply with delta > 0); `duration_s` is how
## long the blow (and the stand) lasts.
##
## DECISION: strength 0.01 per metre per second for 3 s (0.03 per metre in
## total, 1.5x the Anvil's single 0.02-per-metre kick) because the tilt
## spring decays while a sustained push is still being applied; measured on
## the real Field the peak tilt is about 1.2x the Anvil's (0.02 gave 2.4x).
## test_propeller_effect.gd asserts it stays within 0.5x-2x.
@export var disc_force: DiscForceTuning = DiscForceTuning.new()

## Party balloon presentation tunables (BalloonRig); the timings below belong to the gift.
@export var fx: BalloonFxTuning = BalloonFxTuning.new()

## Seconds the balloon takes to inflate at the clip (the force starts at once).
@export var inflate_s: float = 0.5

## Seconds the inflated balloon takes to rise to the end of its string.
@export var rise_s: float = 0.8

## String length (m): the balloon's rest height above the clip once it has risen.
@export var string_length_m: float = 3.2


## In place: no falling carrier to wait for.
func needs_landing() -> bool:
	return false


func effect_lifetime_s() -> float:
	return disc_force.duration_s


## The stand is a standalone world node; the anchor goes at trigger.
func detaches() -> bool:
	return true


## A hard landing never triggers it (there is no carrier). Chain triggers still do.
func impact_triggers(_block: Block, _behavior: SpecialBehavior) -> bool:
	return false


## Triggers on the first tick: the stand owns the whole blow.
func wants_early_trigger(_block: Block, _behavior: SpecialBehavior) -> bool:
	return true


## Spawns the host-side stand at the drop point (disc force plus visual).
func detonate(block: Block, _behavior: SpecialBehavior, _chain_depth: int) -> void:
	if block == null or not block.is_inside_tree():
		return
	PropellerStand.spawn_host(self, block.global_position, block.owner_slot)
