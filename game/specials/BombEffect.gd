class_name BombEffect
extends SpecialEffect
## Bomb / DaBomb special (spec 2.6: "large explosion on activation" -- an
## ordinary impact/fuse special, nothing type-specific about *when* it goes
## off). docs/M4_SPECIALS_PACKAGES.md's P3-BOMB package. Unlike the P5 timed
## effects (Earthquake/Propeller/...), Bomb overrides neither physics_tick()
## nor wants_early_trigger() -- activation is entirely the base impact/fuse
## detection SpecialBehavior.advance() already runs (arm_impulse decel or
## fuse_timeout_s), so this class only needs detonate().

## Reaches config/special_tuning.tres the same way game/Field.gd reaches
## PhysicsTuning (`@export var tuning: PhysicsTuning =
## preload("res://config/physics_tuning.tres")`) -- docs/M4_SPECIALS_PACKAGES.md's
## own P2a note: "SpecialTuning is reached the way Field.gd reaches
## PhysicsTuning", since SpecialBehavior exposes no def()/tuning() getter and
## SpecialEffect is a plain Resource with no scene-tree handle of its own.
## DECISION (game/specials/BombEffect.gd): mirrored verbatim by RocketEffect.gd.
@export var tuning: SpecialTuning = preload("res://config/special_tuning.tres")

## Explosion radius in meters (spec 2.6's Bomb row; docs/M4_SPECIALS_PACKAGES.md
## tunables table: 3.5, provisional).
@export var explosion_radius: float = 3.5

## Explosion impulse magnitude fed into SpecialPhysics.explode()'s falloff,
## before tuning.max_explosion_impulse's clamp (tunables table: 18.0,
## provisional).
@export var explosion_impulse: float = 18.0


## The moment SpecialBehavior triggers this special (impact or fuse
## timeout -- see the class doc above), push every real RigidBody3D within
## explosion_radius, excluding the bomb's own body, then chain into any other
## armed special within the same radius one depth deeper.
func detonate(block: Block, behavior: SpecialBehavior, chain_depth: int) -> void:
	SpecialPhysics.explode(
		block.get_world_3d().direct_space_state,
		block.global_position,
		explosion_radius,
		explosion_impulse,
		tuning.max_explosion_impulse,
		[block.get_rid()]
	)
	behavior.trigger_others_in_range(block.global_position, explosion_radius, chain_depth)
