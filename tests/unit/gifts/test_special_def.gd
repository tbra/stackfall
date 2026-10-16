extends GutTest
## SpecialDef checks (spec 2.6, docs/archive/M4_P2_PACKAGES.md P2a): the roster
## loader and the weighted draw. config/gifts/specials/ started genuinely empty
## (P2a landed before P3-P5's concrete specials); as of P5-EARTHQUAKE it
## holds at least earthquake.tres, so the loader test below now asserts
## against the real roster's contents instead of assuming it is empty
## (docs/archive/M4_SPECIALS_PACKAGES.md orchestrator decision 4). Every other test
## here exercises pick_weighted()/the sort comparator against in-memory
## SpecialDef instances built by the test itself -- no disk writes needed,
## unaffected by what is or isn't under config/gifts/specials/.


func _make_def(id: StringName, weight: float = 1.0) -> SpecialDef:
	var def: SpecialDef = SpecialDef.new()
	def.id = id
	def.weight = weight
	return def


## -- load_all_specials --------------------------------------------------------

## DECISION (tests/unit/gifts/test_special_def.gd, orchestrator decision 4): this
## used to assert defs.size() == 0 -- true only while config/gifts/specials/ held
## no real .tres. P5-EARTHQUAKE's earthquake.tres makes that assumption
## false, so this now asserts against the real roster's actual contents
## (finds the committed special, and the loader's own sort-by-id contract
## still holds) rather than a directory-emptiness assumption future packages
## would have had to keep re-breaking.
func test_load_all_specials_finds_every_committed_special_and_sorts_by_id() -> void:
	var defs: Array[SpecialDef] = SpecialDef.load_all_specials()
	var ids: Array[String] = []
	for def: SpecialDef in defs:
		ids.append(String(def.id))

	assert_true(
		ids.has("earthquake"), "config/gifts/specials/earthquake.tres must be found by the loader"
	)
	var sorted_ids: Array[String] = ids.duplicate()
	sorted_ids.sort()
	assert_eq(ids, sorted_ids, "load_all_specials() must return results sorted by id")


func test_pick_weighted_favors_the_higher_weight_candidate() -> void:
	var light: SpecialDef = _make_def(&"light", 1.0)
	var heavy: SpecialDef = _make_def(&"heavy", 9.0)
	var candidates: Array[SpecialDef] = [light, heavy]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var heavy_count: int = 0
	var light_count: int = 0
	var draws: int = 400
	for seed_value: int in range(draws):
		rng.seed = seed_value
		var picked: SpecialDef = SpecialDef.pick_weighted(candidates, rng)
		if picked == heavy:
			heavy_count += 1
		elif picked == light:
			light_count += 1
	assert_eq(heavy_count + light_count, draws, "Every draw must return one of the two candidates.")
	assert_gt(heavy_count, light_count * 3, "A 9:1 weight ratio should show up clearly over %d draws." % draws)


## Review fix (Bontago-1en.12): a zero-weight candidate sitting first in the
## array must never be selectable via the roll (randf_range()'s range is
## inclusive at 0.0, so a roll of exactly 0.0 could otherwise satisfy
## `roll <= cursor` against a zero-weight entry's own unmoved cursor). Uses
## many seeds rather than one hand-picked roll, since RandomNumberGenerator's
## exact output for a given seed is an implementation detail this test
## shouldn't depend on.
func test_pick_weighted_never_selects_a_zero_weight_candidate_even_when_it_is_first() -> void:
	var never: SpecialDef = _make_def(&"never", 0.0)
	var real: SpecialDef = _make_def(&"real", 5.0)
	var candidates: Array[SpecialDef] = [never, real]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	for seed_value: int in range(200):
		rng.seed = seed_value
		assert_eq(SpecialDef.pick_weighted(candidates, rng), real)


## -- defaults ------------------------------------------------------------------

func test_selectable_specials_exclude_cat_but_load_all_keeps_it() -> void:
	var all_ids: Array[StringName] = []
	for def: SpecialDef in SpecialDef.load_all_specials():
		all_ids.append(def.id)
	assert_true(all_ids.has(&"cat"), "Cat code/resource must stay in the catalogue.")
	var selectable: Array[SpecialDef] = SpecialDef.load_selectable_specials()
	assert_gt(selectable.size(), 0)
	for def: SpecialDef in selectable:
		assert_true(def.enabled_by_default)
		assert_ne(def.id, &"cat")
