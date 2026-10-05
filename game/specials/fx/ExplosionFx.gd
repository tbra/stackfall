class_name ExplosionFx
## Physics-based explosion module for blast effects (Bomb, Rocket, Volcano orbs).
##
## `blast` applies mass-proportional impulse in outward direction with upward bias,
## using a configurable falloff curve. Impulse is capped per delta-v (not kg*m/s),
## making strength independent of block mass. `chain` is a helper to trigger
## nearby specials in a chain reaction.
##
## Depends on: ExplosionTuning, SpecialPhysics, Block, SpecialBehavior


## Applies an explosion from center, imparting delta-v to each hit body.
## Delta-v per body = `t.peak_speed_mps * falloff(ratio, t.falloff_exponent)` along
## (outward + `t.upward_bias` up), clamped to `t.max_delta_v_mps`.
## Bodies in `exclude` (RID list) are skipped. Wakes STATIC-frozen blocks via
## SpecialPhysics.wake_and_impulse. Returns the affected bodies.
static func blast(space: PhysicsDirectSpaceState3D, center: Vector3, t: ExplosionTuning, exclude: Array[RID]) -> Array[RigidBody3D]:
	return []


## Chain trigger helper: triggers all specials within `radius` of `center` at the
## given `depth` in the chain. Respects max_chain_depth via behavior.
static func chain(behavior: SpecialBehavior, center: Vector3, radius: float, depth: int) -> void:
	pass
