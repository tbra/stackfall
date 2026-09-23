class_name SpecialEffect
extends Resource
## Base class for a special's own behavior (spec 2.6: "Every special is its
## own SpecialDef resource plus a script"). One concrete subclass per special
## type (RocketEffect.gd, VolcanoEffect.gd, ...) lands in P3-P5; this package
## (M4 P2a) only defines the shared no-op interface `game/specials/
## SpecialBehavior.gd` drives every physics tick.
##
## Every concrete subclass declares its own typed `@export` tunables (speed,
## radius, impulse, ...) rather than an untyped `params: Dictionary`
## (docs/M4_PLAN.md's own DECISION, restated here since this is the base
## class those subclasses extend) -- CLAUDE.md's static-typing rule applies
## to those exports too.

## Runs once per physics tick while the owning SpecialBehavior is armed and
## not yet triggered (homing, a countdown, a shake, ...). No-op by default --
## most specials (Bomb, Anvil) never need it.
func physics_tick(_block: Block, _behavior: SpecialBehavior, _delta: float) -> void:
	pass


## Checked once per physics tick, right after physics_tick() above, while
## armed and not yet triggered. Returning true makes SpecialBehavior call
## trigger() this same tick, independent of any impact. False by default --
## Rocket/Bomb-style specials only trigger via impact or the fuse timeout.
func wants_early_trigger(_block: Block, _behavior: SpecialBehavior) -> bool:
	return false


## Runs exactly once, the moment the owning SpecialBehavior triggers (impact,
## wants_early_trigger(), or the fuse timeout). `chain_depth` is this
## detonation's own depth in the chain (0 for a player-caused hit); an effect
## that wants to chain into nearby specials calls `behavior.
## trigger_others_in_range(position, radius, chain_depth)` itself -- see that
## function's own doc comment for the chain-cap semantics. No-op by default.
func detonate(_block: Block, _behavior: SpecialBehavior, _chain_depth: int) -> void:
	pass
