class_name SpecialTuning
extends Resource
## Match-wide tunables for specials that aren't per-SpecialDef (spec 2.6,
## 1.5's "mouse flick throws a special"). CLAUDE.md: "No magic numbers...
## every tunable value belongs in a Resource under res://config/". Loaded
## once as config/special_tuning.tres.
##
## DECISION (config/specials/SpecialTuning.gd): deviates from the old M4 plan
## by not pre-declaring `max_explosion_impulse` etc. -- nothing in P2a reads
## them; P3/P4 add what they need when those concrete specials land
## (docs/M4_P2_PACKAGES.md P2a).

## Chain reactions are capped at this depth (spec 2.6: "Cap them at
## max_chain_depth = 4 as a remake performance choice"). A special triggered
## at `chain_depth >= max_chain_depth` still detonates but does not extend
## the chain further (game/specials/SpecialBehavior.gd).
@export var max_chain_depth: int = 4

## Hard clamp on a thrown special's launch speed in m/s (P2d/P2c: the throw
## drag/release gesture never launches faster than this, regardless of drag
## distance).
@export var throw_max_speed: float = 25.0

## Throw launch speed in m/s per meter of aim drag, before the
## throw_max_speed clamp above (P2d).
@export var throw_speed_per_meter: float = 12.0

## Hard per-body clamp on an explosion's applied impulse magnitude (spec 3.5
## "Explosions": "Clamp the impulse per body to max_explosion_impulse" --
## names the clamp, gives no number). Shared across every explosion-based
## special (Rocket, Bomb, Volcano; see game/specials/SpecialPhysics.gd's
## explode()), so one body caught by a very high per-def impulse can never
## launch faster than this.
@export var max_explosion_impulse: float = 30.0

## M4 P4-SPAWN: spec 3.5's continuous-collision threshold ("Rockets, lava
## orbs, thrown specials, and any body moving faster than 15 m/s use
## continuous_cd"). Match.spawn_special_projectile() arms continuous_cd
## whenever its own launch speed clears this. request_throw() already arms
## continuous_cd unconditionally for every thrown special (see its own
## comment) rather than reading this field, since spec 3.5 lists "thrown
## specials" as a case of its own alongside the numeric threshold, not
## conditioned on it.
@export var ccd_speed_threshold_mps: float = 15.0

## M4 P2d throw loft: the vertical component added to a throw's ground-plane
## drag direction, as a fraction of the drag distance, before normalising.
## 1.0 lofts every throw at 45 degrees; lower is flatter, higher is steeper.
## Spec 2.6 leaves the arc OPEN; PlayerController._commit_throw_aim() reads it.
@export var throw_loft_ratio: float = 1.0

## Bontago-t8x.5: seconds a gift body lingers after its effect triggered
## (its action is done) before the host removes it.
@export var gift_despawn_delay_s: float = 0.75

## Bontago-t8x.5: hard backstop. A gift body whose action never completed
## (e.g. never reached its fuse) is removed this many seconds after binding.
@export var gift_max_lifetime_s: float = 60.0

## Bontago-1pi.85.9: a gift whose effect declares effect_effect_lifetime_s() > 0 gets a fuse
## backstop of (time its lifetime starts) + effect_lifetime_s() + this margin instead
## of the blanket arm_delay + fuse_timeout_s force-trigger.
@export var fuse_backstop_margin_s: float = 5.0

## Bontago-1pi.85.16: the fixed gift throw (Bomb, Magnet, Jumping Bean). The host ignores the
## client's drag length/speed: every thrown gift leaves at this speed and loft; only the
## horizontal heading of the client's aim is used.
@export var gift_throw_speed_mps: float = 22.0

## Vertical component of the fixed gift throw relative to its horizontal heading (1.0 = 45 deg).
@export var gift_throw_loft_ratio: float = 1.0

## Accepted length range of a client-sent aim direction (Rocket/Paintball camera forward).
## The client sends a unit vector; anything outside this band is a malformed intent and is
## refused (the piece stays held).
@export var gift_aim_min_length: float = 0.5
@export var gift_aim_max_length: float = 2.0

## Smallest horizontal component of a fixed-throw aim treated as a heading at all.
@export var gift_aim_min_horizontal: float = 0.001

## Bontago-1pi.85.35 (core/gifts/GiftAim.gd): how far back along the camera forward, in meters,
## a camera-aimed gift spawns from the cursor surface point, so the aim line passes through
## what the player points at.
@export var gift_aim_back_m: float = 8.0

## Bontago-1pi.85.35: the aimed spawn point is never lower than this many meters above the
## surface (stops a flat camera spawning the projectile inside the disc).
@export var gift_aim_min_height_m: float = 1.0

## Bontago-1pi.85.35: vertical component added to the unit camera forward of a THROW gift
## (Bomb, Magnet, Jumping Bean) before renormalising; replaces gift_throw_loft_ratio for the
## camera-aimed throw (GiftAim.throw_velocity).
@export var gift_throw_up_ratio: float = 0.35

## Bontago-1pi.85.35: carrier mass = cube_mass * activation_scale ^ this exponent
## (1.0 = mass grows linearly with scale; 3.0 = with volume).
@export var activation_mass_exponent: float = 1.0
