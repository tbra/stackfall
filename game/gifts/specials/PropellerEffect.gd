class_name PropellerEffect
extends SpecialEffect
## Propeller special (spec 2.6: "stands where it lands, then lifts itself and
## blows for its duration"). Bontago-1pi.85.45 (owner playtest 2026-10-07): the
## propeller activates where the gift is dropped, like the Volcano. The
## SpecialDef is `activates_in_place`, so it triggers at once on the host's
## invisible anchor and detonate() spawns a standalone PropellerStand that rises
## out of the disc, spins, and runs DiscForce.apply(sign -1) every tick for
## `disc_force.duration_s` (the Anvil in reverse: it raises the side it stands
## on). Clients draw the same stand from the replicated special_triggered
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

## Visual rest height (m) above the surface once the model has risen (smoothstepped).
@export var emerge_height_m: float = 0.6

## Seconds the model takes to rise out of the disc.
@export var emerge_s: float = 0.8

## Seconds at the end of the effect the model sinks back into the disc.
@export var sink_s: float = 0.6

## Depth (m) below the surface the model starts from, so it is hidden inside the disc.
@export var start_depth_m: float = 5.0


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
	PropellerStand.spawn_host(self, block.global_position)
