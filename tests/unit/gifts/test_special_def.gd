extends GutTest
## SpecialDef checks (spec 1.6): the roster
## loader and the weighted draw. config/gifts/specials/ started genuinely empty
## (P2a landed before P3-P5's concrete specials); as of P5-EARTHQUAKE it
## holds at least earthquake.tres, so the loader test below now asserts
## against the real roster's contents instead of assuming it is empty. Every other test
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


## Review fix: a zero-weight candidate sitting first in the
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


## -- roster memo contract ------------------------------------------------------

func _ids_of(defs: Array[SpecialDef]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for def: SpecialDef in defs:
		ids.append(def.id)
	return ids


func test_load_all_specials_gives_the_same_ids_twice() -> void:
	var first: Array[StringName] = _ids_of(SpecialDef.load_all_specials())
	var second: Array[StringName] = _ids_of(SpecialDef.load_all_specials())
	assert_gt(first.size(), 0)
	assert_eq(second, first)


func test_a_mutated_returned_roster_does_not_change_the_next_call() -> void:
	var expected: Array[StringName] = _ids_of(SpecialDef.load_all_specials())
	var mine: Array[SpecialDef] = SpecialDef.load_all_specials()
	mine.clear()
	mine.append(_make_def(&"intruder"))
	assert_eq(_ids_of(SpecialDef.load_all_specials()), expected)
	assert_null(SpecialDef.find_by_id(&"intruder"), "a caller's edit never reaches the lookup")
	assert_eq(_ids_of(SpecialDef.load_selectable_specials()).has(&"intruder"), false)


func test_the_roster_survives_release_cache_unchanged() -> void:
	var before: Array[StringName] = _ids_of(SpecialDef.load_all_specials())
	SpecialDef.release_cache()
	assert_eq(_ids_of(SpecialDef.load_all_specials()), before)
	for special_id: StringName in before:
		var found: SpecialDef = SpecialDef.find_by_id(special_id)
		assert_not_null(found, "%s resolves after a release" % special_id)
		assert_eq(found.id, special_id)


func test_find_by_id_agrees_with_load_all_specials() -> void:
	for def: SpecialDef in SpecialDef.load_all_specials():
		assert_eq(SpecialDef.find_by_id(def.id), def, "%s" % def.id)
	assert_null(SpecialDef.find_by_id(&""))
	assert_null(SpecialDef.find_by_id(&"not_a_real_special"))


func test_selectable_specials_are_the_enabled_subset_of_load_all_in_order() -> void:
	var expected: Array[StringName] = []
	for def: SpecialDef in SpecialDef.load_all_specials():
		if def.enabled_by_default:
			expected.append(def.id)
	assert_eq(_ids_of(SpecialDef.load_selectable_specials()), expected)
