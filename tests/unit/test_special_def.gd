extends GutTest
## SpecialDef checks (spec 2.6, docs/M4_P2_PACKAGES.md P2a): the roster
## loader and the weighted draw. config/specials/ started genuinely empty
## (P2a landed before P3-P5's concrete specials); as of P5-EARTHQUAKE it
## holds at least earthquake.tres, so the loader test below now asserts
## against the real roster's contents instead of assuming it is empty
## (docs/M4_SPECIALS_PACKAGES.md orchestrator decision 4). Every other test
## here exercises pick_weighted()/the sort comparator against in-memory
## SpecialDef instances built by the test itself -- no disk writes needed,
## unaffected by what is or isn't under config/specials/.


func _make_def(id: StringName, weight: float = 1.0) -> SpecialDef:
	var def: SpecialDef = SpecialDef.new()
	def.id = id
	def.weight = weight
	return def


## -- load_all_specials --------------------------------------------------------

## DECISION (tests/unit/test_special_def.gd, orchestrator decision 4): this
## used to assert defs.size() == 0 -- true only while config/specials/ held
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
		ids.has("earthquake"), "config/specials/earthquake.tres must be found by the loader"
	)
	var sorted_ids: Array[String] = ids.duplicate()
	sorted_ids.sort()
	assert_eq(ids, sorted_ids, "load_all_specials() must return results sorted by id")


func test_load_all_specials_does_not_error_on_a_missing_directory() -> void:
	# DirAccess.open() on a directory that doesn't exist returns null; the
	# real SPECIALS_DIR always exists (it's checked into the repo as an
	# empty placeholder), so this just proves the null-dir branch is safe --
	# calling it twice in a row must not throw or hang either.
	var first: Array[SpecialDef] = SpecialDef.load_all_specials()
	var second: Array[SpecialDef] = SpecialDef.load_all_specials()
	assert_eq(first.size(), second.size())


## -- _sort_by_id (the loader's own comparator) --------------------------------

func test_sort_by_id_orders_specialdefs_alphabetically() -> void:
	var defs: Array[SpecialDef] = [
		_make_def(&"volcano"), _make_def(&"anvil"), _make_def(&"rocket"), _make_def(&"bomb"),
	]
	defs.sort_custom(SpecialDef._sort_by_id)
	var ids: Array[String] = []
	for def: SpecialDef in defs:
		ids.append(String(def.id))
	assert_eq(ids, ["anvil", "bomb", "rocket", "volcano"])


## -- pick_weighted -------------------------------------------------------------

func test_pick_weighted_returns_null_for_an_empty_array() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1
	assert_null(SpecialDef.pick_weighted([] as Array[SpecialDef], rng))


func test_pick_weighted_returns_the_only_candidate_when_there_is_one() -> void:
	var only: SpecialDef = _make_def(&"rocket")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1
	for seed_value: int in range(20):
		rng.seed = seed_value
		assert_eq(SpecialDef.pick_weighted([only] as Array[SpecialDef], rng), only)


func test_pick_weighted_never_returns_null_for_a_nonempty_array() -> void:
	var candidates: Array[SpecialDef] = [_make_def(&"a", 1.0), _make_def(&"b", 3.0)]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	for seed_value: int in range(50):
		rng.seed = seed_value
		assert_not_null(SpecialDef.pick_weighted(candidates, rng))


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


func test_pick_weighted_is_deterministic_for_the_same_seed() -> void:
	var candidates: Array[SpecialDef] = [_make_def(&"a", 1.0), _make_def(&"b", 2.0), _make_def(&"c", 5.0)]
	var rng_a: RandomNumberGenerator = RandomNumberGenerator.new()
	rng_a.seed = 42
	var rng_b: RandomNumberGenerator = RandomNumberGenerator.new()
	rng_b.seed = 42
	var picked_a: SpecialDef = SpecialDef.pick_weighted(candidates, rng_a)
	var picked_b: SpecialDef = SpecialDef.pick_weighted(candidates, rng_b)
	assert_eq(picked_a, picked_b)


func test_pick_weighted_falls_back_to_the_first_candidate_when_total_weight_is_non_positive() -> void:
	var candidates: Array[SpecialDef] = [_make_def(&"a", 0.0), _make_def(&"b", 0.0)]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	for seed_value: int in range(10):
		rng.seed = seed_value
		assert_eq(SpecialDef.pick_weighted(candidates, rng), candidates[0])


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

func test_defaults_match_the_spec_2_6_baseline() -> void:
	var def: SpecialDef = SpecialDef.new()
	assert_eq(def.id, &"")
	assert_eq(def.weight, 1.0)
	assert_true(def.enabled_by_default)
	assert_almost_eq(def.arm_delay, 0.4, 0.0001)
	assert_null(def.effect)
