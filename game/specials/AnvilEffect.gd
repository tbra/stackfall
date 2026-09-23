class_name AnvilEffect
extends SpecialEffect
## Anvil (spec 2.6: "applies weight to tilt the field", the JayIsGames review's
## "a tilting anvil" -- lands heavy, tilts the field toward where it lands).
## See docs/M4_SPECIALS_PACKAGES.md's P5-ANVIL package. Unlike Earthquake/
## Propeller/Jumping Bean, Anvil does NOT use "the timed-effect pattern" that
## doc describes -- there is no fixed duration to wait out, just "has it
## landed yet" (see wants_early_trigger() below).

## Mass this special's block is set to once armed (spec 2.6: mass 60,
## provisional -- the number itself is OPEN, only that it is heavy). Higher
## than any ordinary block's mass so the anvil's own weight, not an
## incidental knock from something else, is what settles it and what a
## later impact against it registers as substantial.
@export var mass: float = 60.0

## Tilt-impulse magnitude (Field.apply_tilt_impulse()'s velocity-kick units,
## see game/Field.gd) per meter of the anvil's landing point from the disk
## centre. docs/M4_SPECIALS_PACKAGES.md's tunables table: 0.02, picked so a
## rim landing alone reaches roughly half of TiltTuning.max_tilt_deg before
## Field's own clamp and spring decay take over -- spec's own constant is
## OPEN (2.6: "mass 60 and tilt impulse by distance are provisional").
@export var tilt_impulse_per_distance: float = 0.02

## block.set_meta() key marking "mass already overridden for this block".
##
## DECISION (game/specials/AnvilEffect.gd, docs/M4_SPECIALS_PACKAGES.md
## P5-ANVIL): a SpecialDef's `effect` is one shared Resource instance reused
## by every block spawned with this special during a match
## (autoload/match/MatchPlacement.gd's _attach_pending_special() calls
## `behavior.bind(block, def, _special_tuning)` with the cached, un-duplicated
## def) -- so this effect carries no per-block mutable state of its own.
## Idempotency lives on the block instead, via set_meta()/has_meta(), the
## same seam docs/M4_SPECIALS_PACKAGES.md's timed-effect pattern uses for
## "seconds since armed".
const _MASS_APPLIED_META: StringName = &"anvil_mass_applied"


## DECISION (game/specials/AnvilEffect.gd, docs/M4_SPECIALS_PACKAGES.md
## P5-ANVIL): the mass override happens on the first armed physics_tick(),
## not at spawn time -- SpecialEffect exposes no pre-arm hook, and a mid-fall
## mass change does not alter the trajectory anyway (Jolt/Godot's gravity
## acceleration is mass-independent), so there is no reason to plumb one in
## just for this. Idempotent via the block-meta flag above rather than just
## re-assigning `mass` every tick (harmless either way, but the flag makes
## "did the override actually happen, once" directly assertable in a test
## instead of indistinguishable from a fixture that merely started with this
## mass by coincidence).
func physics_tick(block: Block, _behavior: SpecialBehavior, _delta: float) -> void:
	if block.has_meta(_MASS_APPLIED_META):
		return
	block.mass = mass
	block.set_meta(_MASS_APPLIED_META, true)


## DECISION (game/specials/AnvilEffect.gd): triggers the instant the anvil
## comes to rest (Jolt's own `sleeping` flag), not on a timer -- spec 2.6's
## "lands, tilts" read literally: the weight does its work once it has
## actually settled. An impact strong enough to satisfy SpecialBehavior's own
## arm_impulse check (game/specials/SpecialBehavior.gd's _check_impact()) can
## still trigger it earlier, same as every other special.
func wants_early_trigger(block: Block, _behavior: SpecialBehavior) -> bool:
	return block.sleeping


## Tilts the disk toward the point the anvil actually landed at, via
## Match.field() -- a SpecialEffect is a Resource with no scene-tree handle
## of its own (game/specials/SpecialEffect.gd). A landing exactly at the disk
## centre (distance 0) applies no impulse at all, rather than relying on
## Field.apply_tilt_impulse()'s own `dir == Vector2.ZERO` guard, so a test can
## tell "no-op because centred" apart from "no-op because tilt is disabled"
## by whether this even reaches Field. tilt_mode OFF itself needs no guard
## here: Field.apply_tilt_impulse() already no-ops while `_tilt_enabled` is
## false (game/Field.gd), and nothing else in this effect touches the field.
func detonate(block: Block, _behavior: SpecialBehavior, _chain_depth: int) -> void:
	var field: Field = Match.field()
	if field == null:
		return
	var local: Vector2 = field.disk_local_from_world(block.global_position)
	var distance: float = local.length()
	if distance <= 0.0:
		return
	field.apply_tilt_impulse(local.normalized(), tilt_impulse_per_distance * distance)
