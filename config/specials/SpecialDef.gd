class_name SpecialDef
extends Resource
## One special block type (spec 2.6, 1.3): the seven evidenced types are
## DaBomb/Bomb, Volcano, Earthquake, Propeller, Anvil, Rocket and Jumping
## Bean. This package (M4 P2a) defines only the shared interface, roster
## loader and weighted draw; concrete specials (a scene + SpecialEffect per
## type) are P3-P5's responsibility. An empty res://config/specials/ (today,
## before those land) is a supported state: load_all_specials() returns an
## empty array and pick_weighted() returns null, so a spawn with no special
## drawn behaves exactly like an ordinary block (see docs/M4_P2_PACKAGES.md
## P2c's "safe default").

## Unique identifier, e.g. &"rocket", &"volcano".
@export var id: StringName = &""

## Scene used to build this special's extra visuals (fuse glow, fins, ...).
## Optional -- SpecialBehavior only needs `effect` below to arm and trigger.
@export var scene: PackedScene = null

## Feed weight for pick_weighted() below, same convention as
## config/blocks/BlockShape.gd's `weight`.
@export var weight: float = 1.0

## Whether this special is offered by default when a match's enabled-specials
## config doesn't name it explicitly. Read by P3+'s roster filtering; P2a
## does not filter on it itself.
@export var enabled_by_default: bool = true

## Seconds after SpecialBehavior.bind() before this special can arm (spec
## 2.6: "[NEW] earlier 0.4 s arm delay").
@export var arm_delay: float = 0.4

## Minimum `mass * (prev_speed - now_speed)` -- an impulse-like deceleration
## measure, kg*m/s, the same shape as game/Block.gd's own impact detection --
## to trigger on impact once armed (spec 2.6: "[ORIGINAL] substantial impact
## activates a special").
@export var arm_impulse: float = 5.0

## Seconds after arming with no qualifying impact before the special
## force-triggers anyway, so an untouched special doesn't sit forever.
@export var fuse_timeout_s: float = 6.0

## The effect this special runs once armed (per-tick early-trigger check) and
## on trigger (detonate). Null-safe: SpecialBehavior checks before calling,
## so a SpecialDef with no effect assigned still ages/arms/force-triggers,
## it just detonates as a no-op.
@export var effect: SpecialEffect = null

## Directory scanned by load_all_specials() for every SpecialDef .tres
## resource, mirroring config/blocks/BlockShape.gd:28's SHAPES_DIR.
const SPECIALS_DIR: String = "res://config/specials/"


## Loads every SpecialDef resource in SPECIALS_DIR, sorted by id so the
## result is deterministic across platforms and directory-listing orders --
## mirrors config/blocks/BlockShape.gd's load_all_shapes() exactly. Returns
## an empty array when the directory holds no .tres yet (P2a lands before
## P3-P5 add concrete specials); callers must treat that as "no roster",
## never as an error.
static func load_all_specials() -> Array[SpecialDef]:
	var defs: Array[SpecialDef] = []
	var dir: DirAccess = DirAccess.open(SPECIALS_DIR)
	if dir == null:
		return defs
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var def: SpecialDef = load(SPECIALS_DIR + file_name)
			if def != null:
				defs.append(def)
		file_name = dir.get_next()
	dir.list_dir_end()
	defs.sort_custom(_sort_by_id)
	return defs


## DECISION (config/specials/SpecialDef.gd): pulled out of load_all_specials()
## as its own static function, rather than an inline lambda, so
## tests/unit/test_special_def.gd can exercise the loader's actual sort order
## against a hand-built, in-memory array of SpecialDef instances -- no need
## to write or clean up real/temporary .tres resources under
## res://config/specials/ (which docs/M4_P2_PACKAGES.md's P2a section wants
## to stay genuinely empty this package) or under user:// just to prove the
## comparator works.
static func _sort_by_id(a: SpecialDef, b: SpecialDef) -> bool:
	return String(a.id) < String(b.id)


## Roulette-wheel pick over `.weight` (docs/M4_P2_PACKAGES.md P2a: "roulette
## pick over .weight"). Null on an empty array so a caller (P2c) can treat
## "nothing to draw" as a safe no-op instead of a crash.
##
## DECISION (config/specials/SpecialDef.gd): a non-positive total weight
## (every candidate weighted <= 0, or a single candidate) falls back to the
## first candidate rather than raising an error -- mirrors
## core/feed/BlockBag.gd's weight_of() floor-at-a-tiny-positive-number
## philosophy of "never blocks a draw over a config mistake", but simpler
## since pick_weighted() draws once rather than maintaining a bag.
static func pick_weighted(candidates: Array[SpecialDef], rng: RandomNumberGenerator) -> SpecialDef:
	if candidates.is_empty():
		return null
	var total_weight: float = 0.0
	for candidate: SpecialDef in candidates:
		total_weight += maxf(candidate.weight, 0.0)
	if total_weight <= 0.0:
		return candidates[0]
	var roll: float = rng.randf_range(0.0, total_weight)
	var cursor: float = 0.0
	for candidate: SpecialDef in candidates:
		var candidate_weight: float = maxf(candidate.weight, 0.0)
		# Review fix (Bontago-1en.12): a zero-weight candidate must never be
		# selectable via the roll, not even when `roll` lands exactly on 0.0
		# (randf_range()'s range is inclusive at both ends) and a zero-weight
		# candidate sits first in the array -- skipping it here instead of
		# still comparing `roll <= cursor` (which a same-value cursor would
		# satisfy) keeps a 0-weight entry unreachable except via the
		# total_weight <= 0.0 fallback above.
		if candidate_weight <= 0.0:
			continue
		cursor += candidate_weight
		if roll <= cursor:
			return candidate
	return candidates[candidates.size() - 1]
