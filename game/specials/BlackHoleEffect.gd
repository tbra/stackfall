class_name BlackHoleEffect
extends SpecialEffect
## Black hole gift (docs/SPEC.md 2.6; owner 2026-10-02, replaces Gravity well):
## "Spawns a black hole that pulls in nearby blocks" of ALL teams. Ordinary
## impact/fuse special: the gift's own impact (or fuse) triggers it, and
## detonate() spawns a BlackHoleField at that point that runs the pull for
## lifetime_s on the host. Clients/host draw the placeholder BlackHoleVisual
## from the already replicated Events.special_triggered (GiftFxPresenter).
##
## Bontago-1pi.85.12: strength and capture. The pull is RadialPull (mass-independent
## acceleration plus friction compensation, so an 8 kg block really slides across the
## disc; the old 14 m/s^2 capped at 60 N was below friction). A block entering
## pull.core_radius_m is captured and removed through the SAME removal as a territory
## hole (HoleDissolver.request_dissolve; owner resolution Bontago-1pi.85.2). No
## territory hole is punched (owner resolution Bontago-1pi.85.3).
##
## DECISION: a SpecialDef's `effect` is one shared Resource, so it keeps no
## per-activation state; the BlackHoleField node owns the timer.

## Pull reach, strength and capture core. Radius 7 m, acceleration 26 m/s^2 at the
## core (linear falloff), friction compensation 24 m/s^2 (the measured breakaway
## value, see RadialPullTuning), core 0.8 m.
@export var pull: RadialPullTuning = RadialPullTuning.new()

## Seconds the black hole lives after it spawns.
@export var lifetime_s: float = 6.0

## Visual radius (m) of the placeholder sphere (not the pull radius).
@export var visual_radius_m: float = 0.7

## Pull radius (m); read-only alias kept for BotSpecialPlanner and the visual.
var pull_radius_m: float:
	get:
		return pull.radius_m


## DECISION: effect_lifetime_s() is NOT overridden. lifetime_s counts from the
## trigger (the field's own timer), whereas effect_lifetime_s() would postpone the
## pre-trigger fuse (arm_delay + lifetime + margin) and so delay an untriggered gift.

## The field is a standalone world node: the carrier goes at trigger.
func detaches() -> bool:
	return true


func detonate(block: Block, _behavior: SpecialBehavior, _chain_depth: int) -> void:
	if block == null or not block.is_inside_tree():
		return
	# Same per-match container as BlackHoleVisual, so the field dies with the match world.
	var world: Node3D = Match.blocks_parent()
	var parent: Node = world if world != null else block.get_parent()
	var field: BlackHoleField = BlackHoleField.new()
	field.bind_to_match = world != null
	field.configure(self, [block.get_rid()])
	parent.add_child(field)
	field.global_position = block.global_position
