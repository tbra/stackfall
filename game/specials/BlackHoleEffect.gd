class_name BlackHoleEffect
extends SpecialEffect
## Black hole gift (docs/SPEC.md 2.6; owner 2026-10-02, replaces Gravity well):
## "Spawns a black hole that pulls in nearby blocks" of ALL teams. Ordinary
## impact/fuse special: the gift's own impact (or fuse) triggers it, and
## detonate() spawns a BlackHoleField at that point that runs the pull for
## lifetime_s on the host. Clients/host draw the placeholder BlackHoleVisual
## from the already replicated Events.special_triggered (Match handler).
##
## DECISION: a SpecialDef's `effect` is one shared Resource, so it keeps no
## per-activation state; the BlackHoleField node owns the timer.
##
## DECISION: pull strength is an acceleration (m/s^2) scaled by body mass and
## a (1 - d/r)^falloff_exponent falloff, then capped at max_pull_force (N) so
## a heavy block next to the core is not flung. Spec leaves magnitudes open.

## Radius (m) within which blocks are pulled.
@export var pull_radius_m: float = 6.0

## Seconds the black hole lives after it spawns.
@export var lifetime_s: float = 5.0

## Peak pull acceleration (m/s^2) at the centre, before the force cap.
@export var pull_acceleration: float = 14.0

## Exponent of the (1 - distance/radius) falloff (1 = linear).
@export var falloff_exponent: float = 1.0

## Hard cap (N) on the force applied to one body per tick.
@export var max_pull_force: float = 60.0

## DECISION: OFF by default. The spec only says the hole "pulls in" blocks;
## destroying them would change territory outcomes, so removal stays a
## tunable until the owner asks for it.
@export var consume_blocks: bool = false

## Blocks whose origin is within this distance (m) of the centre are removed
## when consume_blocks is on.
@export var core_radius_m: float = 0.6

## Visual radius (m) of the placeholder sphere (not the pull radius).
@export var visual_radius_m: float = 0.7


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
