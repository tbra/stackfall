class_name SpecialDef
extends Resource
## One special block type (spec 2.6, 1.3): the seven evidenced types are
## DaBomb/Bomb, Volcano, Earthquake, Propeller, Anvil, Rocket and Jumping
## Bean. This package (M4 P2a) defines only the shared interface, roster
## loader and weighted draw; concrete specials (a scene + SpecialEffect per
## type) are P3-P5's responsibility. An empty res://config/specials/ (today,
## before those land) is a supported state: load_all_specials() returns an
## empty array and pick_weighted() returns null, so a spawn with no special
## drawn behaves exactly like an ordinary block (see docs/archive/M4_P2_PACKAGES.md
## P2c's "safe default").

## Unique identifier, e.g. &"rocket", &"volcano".
@export var id: StringName = &""

## Player-facing name (Bontago-1pi.86 Q1). Empty falls back to the capitalised id
## through get_display_name(); read it through DisplayNames.special(), not directly.
@export var display_name: String = ""

## Scene used to build this special's extra visuals (fuse glow, fins, ...).
## Optional -- SpecialBehavior only needs `effect` below to arm and trigger.
@export var scene: PackedScene = null

## Bontago-59o.13/.14 presentation interface (per-gift art is 59o.14; both
## fields are optional and every gift already shows something sensible):
## `held_scene` is the model the local/remote ghost shows INSTEAD of the plain
## block ghost while this gift is the current piece. It is instanced under the
## ghost, centred on the held shape's bounds and rotated with it; its root
## should be a Node3D roughly one block cell in size. Null falls back to the
## generic gift-crate look (game/GhostPreview.gd build_fallback_gift_visual()).
@export var held_scene: PackedScene = null

## 2D icon the HUD held/next previews draw while this gift is held or next.
## Null falls back to GENERIC_PREVIEW_ICON.
@export var preview_icon: Texture2D = null

## Generic gift icon used by the HUD when `preview_icon` is unset.
const GENERIC_PREVIEW_ICON: Texture2D = preload("res://assets/ui/icons/gift_generic.svg")

## Feed weight for pick_weighted() below, same convention as
## config/blocks/BlockShape.gd's `weight`.
@export var weight: float = 1.0

## Whether this special is offered by default when a match's enabled-specials
## config doesn't name it explicitly. Read by P3+'s roster filtering; P2a
## does not filter on it itself.
@export var enabled_by_default: bool = true

## Bontago-1pi.85.16 (owner answer 1pi.85.1): whether this gift can be thrown on the fixed
## gift trajectory (Bomb, Magnet, Jumping Bean). Every other gift is only dropped in place.
@export var throwable: bool = false

## Bontago-1pi.85.16: Rocket/Paintball are not thrown; on release they fire in a straight line
## along the activating player's camera forward (host-validated, see core/gifts/GiftThrow.gd).
@export var aimed_launch: bool = false

## Bontago-1pi.85.35 (gift playtest 2, docs/GIFT_PLAYTEST2_PLAN.md): true = releasing this gift
## activates it at the cursor surface point with no physical carrier falling first
## (MatchGiftActivation.try_activate). SpecialBehavior then never waits for landing
## (needs_landing is ignored). False (default) keeps the falling carrier.
@export var activates_in_place: bool = false

## Bontago-1pi.85.45: metres above the validated release point the physical carrier spawns
## and falls from (Anvil: "falls from the sky"). 0 = off (spawn at the point). Host-only;
## clients see the fall through the normal body snapshots.
@export_range(0.0, 60.0, 0.5) var sky_drop_height_m: float = 0.0

## Bontago-1pi.85.35: uniform size multiplier of the gift carrier from release on (visual and
## collider, mass via SpecialTuning.activation_mass_exponent). 1.0 = today's size.
@export_range(0.1, 10.0, 0.1) var activation_scale: float = 1.0

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

## The player-facing name: `display_name` when authored, else the id with
## underscores as spaces and each word capitalised ("jumping_bean" -> "Jumping Bean").
func get_display_name() -> String:
	if display_name != "":
		return display_name
	return name_from_id(id)


## "jumping_bean" -> "Jumping Bean"; "" for an empty id.
static func name_from_id(special_id: StringName) -> String:
	return String(special_id).replace("_", " ").capitalize()


## Looks up a roster entry by id (cached); null for unknown/empty ids.
static var _by_id_cache: Dictionary = {}


static func find_by_id(special_id: StringName) -> SpecialDef:
	if special_id == &"":
		return null
	if _by_id_cache.is_empty():
		for def: SpecialDef in load_all_specials():
			_by_id_cache[def.id] = def
	return _by_id_cache.get(special_id) as SpecialDef


## The HUD icon for `special_id`: its own preview_icon or the generic one.
static func preview_icon_for(special_id: StringName) -> Texture2D:
	# Bontago-mp0.125: the rendered model preview (config/gift_icon_table.tres) wins so
	# the HUD card agrees with the held GLB; then the def's own icon, then the generic one.
	var table: GiftIconTable = GiftIconTable.shared()
	if table != null:
		var model_icon: Texture2D = table.model_preview(special_id)
		if model_icon != null:
			return model_icon
	var def: SpecialDef = find_by_id(special_id)
	if def != null and def.preview_icon != null:
		return def.preview_icon
	return GENERIC_PREVIEW_ICON


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
		# Exported PCKs list text resources as "<name>.tres.remap" (the editor's
		# convert-text-resources-to-binary step); load() resolves the original
		# path through that remap, so only the listing suffix needs stripping.
		# Without this no shape/special ever loads in an exported build
		# (feedback/playtest.md 2026-09-26: "no block ever spawns").
		if file_name.ends_with(".remap"):
			file_name = file_name.trim_suffix(".remap")
		if file_name.ends_with(".tres"):
			var def: SpecialDef = load(SPECIALS_DIR + file_name)
			if def != null:
				defs.append(def)
		file_name = dir.get_next()
	dir.list_dir_end()
	defs.sort_custom(_sort_by_id)
	return defs


## The roster a match may draw from: load_all_specials() minus defs with
## `enabled_by_default == false` (Bontago-1pi.85.9: Cat is disabled but its
## code and resource stay). Same id order. load_all_specials() stays the full
## catalogue (find_by_id, icon table, net id tables must still resolve Cat).
static func load_selectable_specials() -> Array[SpecialDef]:
	var defs: Array[SpecialDef] = []
	for def: SpecialDef in load_all_specials():
		if def.enabled_by_default:
			defs.append(def)
	return defs


## DECISION (config/specials/SpecialDef.gd): pulled out of load_all_specials()
## as its own static function, rather than an inline lambda, so
## tests/unit/test_special_def.gd can exercise the loader's actual sort order
## against a hand-built, in-memory array of SpecialDef instances -- no need
## to write or clean up real/temporary .tres resources under
## res://config/specials/ (which docs/archive/M4_P2_PACKAGES.md's P2a section wants
## to stay genuinely empty this package) or under user:// just to prove the
## comparator works.
static func _sort_by_id(a: SpecialDef, b: SpecialDef) -> bool:
	return String(a.id) < String(b.id)


## Roulette-wheel pick over `.weight` (docs/archive/M4_P2_PACKAGES.md P2a: "roulette
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
