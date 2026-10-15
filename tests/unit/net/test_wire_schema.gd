extends GutTest
## WireSchema table tests plus the accept/reject tables of the
## migrated sites (breeze gust, snow state header, weather state).

func _schema() -> Dictionary:
	return {
		"i": WireSchema.int_field(1, 9),
		"n": WireSchema.number_field(-2.0, 2.0),
		"p": WireSchema.number_field(-INF, 5.0, 0.0),
		"s": WireSchema.string_field(4),
		"a": WireSchema.int_array_field(3),
	}


func _good() -> Dictionary:
	return {"i": 3, "n": 1, "p": 2.5, "s": &"abc", "a": PackedInt32Array([1, 2])}


func test_good_payload_is_normalised() -> void:
	var out: Dictionary = WireSchema.sanitize(_good(), _schema())
	assert_eq(out["i"], 3)
	assert_eq(typeof(out["n"]), TYPE_FLOAT, "int number becomes float")
	assert_eq(typeof(out["s"]), TYPE_STRING)
	assert_eq(out.size(), 5)


func test_non_dictionary_payloads_are_rejected() -> void:
	for bad: Variant in [null, "x", 5, [1], PackedInt32Array([1]), 1.5]:
		assert_true(WireSchema.sanitize(bad, _schema()).is_empty(), "rejects %s" % [bad])


func test_missing_and_extra_keys_are_rejected() -> void:
	var extra: Dictionary = _good()
	extra["z"] = 1
	assert_true(WireSchema.sanitize(extra, _schema()).is_empty())
	var missing: Dictionary = _good()
	missing.erase("s")
	assert_true(WireSchema.sanitize(missing, _schema()).is_empty())
	var renamed: Dictionary = _good()
	renamed.erase("s")
	renamed["q"] = "abc"
	assert_true(WireSchema.sanitize(renamed, _schema()).is_empty(), "same size, wrong key")


# --- Migrated sites ---------------------------------------------------------------------

func test_snow_state_maximum_size_is_accepted() -> void:
	var tuning: SnowTuning = SnowTuning.new()
	var blocks: PackedInt32Array = PackedInt32Array()
	# One patch per block: the largest block array the budget allows (5 ints worth per patch).
	for net_id: int in range(1, tuning.max_block_patches + 1):
		SnowGeometry.append_block_record(blocks, net_id, 0, PackedInt32Array([0]), PackedInt32Array([1]))
	var disc: PackedInt32Array = PackedInt32Array()
	for cell: int in range(tuning.max_disc_patches):
		disc.append(cell)
		disc.append(1)
	var state: Dictionary = SnowGeometry.make_state(3, tuning.depth_levels, blocks, disc)
	var out: Dictionary = SnowGeometry.sanitize_state(state, tuning, tuning.max_disc_patches)
	assert_false(out.is_empty(), "maximum-size state")
	assert_eq((out["blocks"] as Dictionary).size(), tuning.max_block_patches)
	assert_eq((out["disc"] as Dictionary).size(), tuning.max_disc_patches)
