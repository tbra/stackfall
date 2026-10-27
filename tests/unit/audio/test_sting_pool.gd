extends GutTest
## StingPool: round-robin player slots and no-repeat variant picks (core/audio/StingPool.gd).

const SFX_SLOTS: int = 8
const UI_SLOTS: int = 4
const SEEDS: Array[int] = [1, 7, 42, 1234, 99991]
const PICKS: int = 200


func _pool(rng_seed: int = 1) -> StingPool:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = rng_seed
	return StingPool.new(SFX_SLOTS, UI_SLOTS, rng)


func test_sfx_slots_cycle_in_order_and_wrap() -> void:
	var pool: StingPool = _pool()
	for lap: int in range(3):
		for expected: int in range(SFX_SLOTS):
			assert_eq(pool.next_sfx_slot(), expected, "lap %d" % lap)


func test_ui_slots_cycle_in_order_and_wrap() -> void:
	var pool: StingPool = _pool()
	for lap: int in range(3):
		for expected: int in range(UI_SLOTS):
			assert_eq(pool.next_ui_slot(), expected, "lap %d" % lap)


func test_sfx_and_ui_cursors_are_independent() -> void:
	var pool: StingPool = _pool()
	assert_eq(pool.next_sfx_slot(), 0)
	assert_eq(pool.next_sfx_slot(), 1)
	assert_eq(pool.next_ui_slot(), 0, "ui cursor untouched by sfx picks")
	assert_eq(pool.next_sfx_slot(), 2)
	assert_eq(pool.next_ui_slot(), 1)


func test_single_slot_pool_always_returns_zero() -> void:
	var pool: StingPool = StingPool.new(1, 1, RandomNumberGenerator.new())
	for _i: int in range(4):
		assert_eq(pool.next_sfx_slot(), 0)
		assert_eq(pool.next_ui_slot(), 0)


func test_variant_never_repeats_the_previous_pick_for_a_key() -> void:
	for rng_seed: int in SEEDS:
		for count: int in [2, 3, 5]:
			var pool: StingPool = _pool(rng_seed)
			var previous: int = -1
			for _i: int in range(PICKS):
				var pick: int = pool.pick_variant(0, count)
				assert_between(pick, 0, count - 1, "in range (count %d)" % count)
				assert_ne(pick, previous, "no immediate repeat (seed %d, count %d)" % [rng_seed, count])
				previous = pick


func test_two_variants_alternate() -> void:
	var pool: StingPool = _pool()
	var first: int = pool.pick_variant(3, 2)
	assert_eq(pool.pick_variant(3, 2), 1 - first)
	assert_eq(pool.pick_variant(3, 2), first)


func test_every_variant_gets_picked() -> void:
	var pool: StingPool = _pool()
	var seen: Dictionary = {}
	for _i: int in range(PICKS):
		seen[pool.pick_variant(0, 4)] = true
	assert_eq(seen.size(), 4, "the pick is spread over all variants, not stuck on a pair")


func test_single_variant_always_zero_even_repeated() -> void:
	var pool: StingPool = _pool()
	for _i: int in range(5):
		assert_eq(pool.pick_variant(0, 1), 0)


func test_variant_memory_is_per_key() -> void:
	var pool: StingPool = _pool()
	for _i: int in range(PICKS):
		var a: int = pool.pick_variant(0, 2)
		var b: int = pool.pick_variant(1, 2)
		var a_next: int = pool.pick_variant(0, 2)
		var b_next: int = pool.pick_variant(1, 2)
		assert_eq(a_next, 1 - a, "key 0 alternates despite key 1 picks in between")
		assert_eq(b_next, 1 - b, "key 1 alternates despite key 0 picks in between")


func test_same_seed_gives_same_picks() -> void:
	var one: StingPool = _pool(5)
	var two: StingPool = _pool(5)
	for _i: int in range(20):
		assert_eq(one.pick_variant(0, 6), two.pick_variant(0, 6))
