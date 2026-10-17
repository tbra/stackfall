class_name SpecialEffect
extends Resource
## Base class for a special's own behavior (spec 1.6: "Every special is its
## own SpecialDef resource plus a script"). One concrete subclass per special
## type (RocketEffect.gd, VolcanoEffect.gd, ...); this class defines the shared no-op
## interface `game/gifts/specials/SpecialBehavior.gd` drives every physics tick.
##
## Every concrete subclass declares its own typed `@export` tunables (speed, radius,
## impulse, ...) rather than an untyped `params: Dictionary`.

## Runs once per physics tick while the owning SpecialBehavior is armed and
## not yet triggered (homing, a countdown, a shake, ...). No-op by default --
## most specials (Bomb, Anvil) never need it.
func physics_tick(_block: Block, _behavior: SpecialBehavior, _delta: float) -> void:
	pass


## Checked by SpecialBehavior._check_impact() right before an impact
## (mass * speed-drop >= arm_impulse), once armed and not yet triggered, would
## otherwise call trigger(0) this same tick. True by default -- an ordinary
## impact/fuse special (Bomb, Rocket, Anvil) activates on its own hard
## landing or the fuse timeout, nothing else needed.
##
## A "timed-effect pattern" special (Propeller, Jumping Bean, Earthquake, Volcano) overrides this to
## false. Those effects already run physics_tick() every armed tick
## regardless of impact, and their own end is entirely time-driven
## (wants_early_trigger()/the fuse) -- without this veto, a block thrown or
## dropped hard enough that its OWN landing impact exceeds arm_impulse right
## as it arms calls trigger(0) before physics_tick() has run even once, so
## the eruption/shake/lift/hop-timer never starts. Chain triggering
## (SpecialBehavior.trigger_others_in_range() -> trigger()) never goes through this hook
## or _check_impact(), so a nearby explosion still detonates a vetoing special.
func impact_triggers(_block: Block, _behavior: SpecialBehavior) -> bool:
	return true


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


## Lifecycle hooks: every default below is the plain impact/fuse behaviour, so an effect
## opts in individually.

## True: SpecialBehavior runs a LandedProbe and does not call physics_tick()/
## wants_early_trigger() until the carrier has landed (instead of a
## `block.sleeping` gate inside the effect). False by default.
func needs_landing() -> bool:
	return false


## Landing-probe thresholds for this effect's carrier. null (default) =
## LandedProbe's own LandedTuning defaults. SpecialBehavior builds
## its LandedProbe from this once, in bind().
func landed_tuning() -> LandedTuning:
	return null


## Seconds the effect's action runs (after landing when needs_landing(), else
## after arming). <= 0 means "unspecified": the def's fuse_timeout_s keeps
## acting as the force-trigger. > 0 replaces that blanket
## fuse with a backstop derived from this lifetime (SpecialTuning.
## fuse_backstop_margin_s on top).
func effect_lifetime_s() -> float:
	return -1.0


## True: the effect owns a standalone world node, so the host removes the
## carrier at trigger without the gift_despawn_delay_s linger.
func detaches() -> bool:
	return false


## Static switch for impact activation; false means a hard landing never
## triggers this effect (Bomb). Combined with the per-instance
## impact_triggers() veto above: both must allow the impact. True by default.
func triggers_on_impact() -> bool:
	return true
