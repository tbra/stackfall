extends GutTest
## SoakFuzzPlan only ever produces place intents the host must refuse (SOAK_PLAN section 6.3), so
## a seated fuzz client's accepted count stays exactly zero. These tests state "refusable" from
## the host's rules (SPEC 2.6) and check it for every intent of many seeded batches.

const OWN_SLOT: int = 1
const FEED_SEQ: int = 17
const DISC_RADIUS_M: float = 45.0
const BATCHES: int = 1200
const BATCHES_PER_VARIANT: int = 400
const BATCHES_PER_SLOT: int = 300

var _config: SoakConfig = load("res://config/soak/soak_config.tres") as SoakConfig
var _net: NetConfig = NetConfig.new()


func _plan(rng_seed: int = 8331, config: SoakConfig = _config, net: NetConfig = _net) -> SoakFuzzPlan:
	return SoakFuzzPlan.new(rng_seed, config, net)


func _flood_size() -> int:
	return roundi(_config.fuzz_flood_factor * float(_net.flood_place_burst))


## The same claim the host's intent checks make: this intent cannot be a legitimate placement
## by `own_slot` at sequence `feed_seq` inside a field of `radius`.
func _is_refusable(
	intent: SoakFuzzPlan.Intent, own_slot: int, feed_seq: int, radius: float
) -> bool:
	if intent.slot_id != own_slot:
		return true
	if intent.feed_seq != feed_seq:
		return true
	if not intent.origin.is_finite():
		return true
	return Vector2(intent.origin.x, intent.origin.z).length() > radius


func _signature(intent: SoakFuzzPlan.Intent) -> String:
	return "%d|%d|%s|%d|%s|%d" % [
		intent.kind,
		intent.slot_id,
		var_to_str(intent.origin),
		intent.orientation_index,
		var_to_str(intent.free_quat),
		intent.feed_seq,
	]


func _run(plan: SoakFuzzPlan, batches: int, own_slot: int, feed_seq: int, radius: float) -> Array[String]:
	var out: Array[String] = []
	for _i: int in batches:
		var line: Array[String] = []
		for intent: SoakFuzzPlan.Intent in plan.next_batch(own_slot, feed_seq, radius):
			line.append(_signature(intent))
		out.append(",".join(line))
	return out


func test_a_batch_always_has_an_intent() -> void:
	var plan: SoakFuzzPlan = _plan()
	for _i: int in 50:
		assert_gt(plan.next_batch(OWN_SLOT, FEED_SEQ, DISC_RADIUS_M).size(), 0)


func test_the_same_seed_gives_the_same_sequence() -> void:
	var first: Array[String] = _run(_plan(8331), 200, OWN_SLOT, FEED_SEQ, DISC_RADIUS_M)
	var second: Array[String] = _run(_plan(8331), 200, OWN_SLOT, FEED_SEQ, DISC_RADIUS_M)
	assert_eq(first.size(), 200)
	assert_ne(first[0], "", "Batches hold intents.")
	assert_eq(first, second)


func test_a_different_seed_gives_a_different_sequence() -> void:
	var first: Array[String] = _run(_plan(8331), 200, OWN_SLOT, FEED_SEQ, DISC_RADIUS_M)
	var second: Array[String] = _run(_plan(8332), 200, OWN_SLOT, FEED_SEQ, DISC_RADIUS_M)
	assert_ne(first[0], "", "Batches hold intents.")
	assert_ne(first, second)


func test_the_sequence_is_not_a_constant() -> void:
	var seen: Dictionary = {}
	for line: String in _run(_plan(), 100, OWN_SLOT, FEED_SEQ, DISC_RADIUS_M):
		seen[line] = true
	assert_gt(seen.size(), 20, "Batches vary.")


func test_the_global_random_generator_does_not_disturb_a_plan() -> void:
	var quiet: SoakFuzzPlan = _plan(77)
	var noisy: SoakFuzzPlan = _plan(77)
	var expected: Array[String] = []
	var actual: Array[String] = []
	for _i: int in 60:
		expected.append_array(_run(quiet, 1, OWN_SLOT, FEED_SEQ, DISC_RADIUS_M))
		randi()
		randf()
		actual.append_array(_run(noisy, 1, OWN_SLOT, FEED_SEQ, DISC_RADIUS_M))
	assert_ne(expected[0], "", "Batches hold intents.")
	assert_eq(actual, expected)


func test_two_interleaved_plans_do_not_share_state() -> void:
	var alone: Array[String] = _run(_plan(5), 80, OWN_SLOT, FEED_SEQ, DISC_RADIUS_M)
	var plan_a: SoakFuzzPlan = _plan(5)
	var plan_b: SoakFuzzPlan = _plan(6)
	var mixed: Array[String] = []
	for _i: int in 80:
		mixed.append_array(_run(plan_a, 1, OWN_SLOT, FEED_SEQ, DISC_RADIUS_M))
		_run(plan_b, 1, OWN_SLOT, FEED_SEQ, DISC_RADIUS_M)
	assert_ne(alone[0], "", "Batches hold intents.")
	assert_eq(mixed, alone)


func test_every_intent_is_refusable() -> void:
	for feed_seq: int in [0, 1, FEED_SEQ, 5000]:
		var plan: SoakFuzzPlan = _plan(feed_seq + 1)
		var checked: int = 0
		for _i: int in BATCHES:
			for intent: SoakFuzzPlan.Intent in plan.next_batch(OWN_SLOT, feed_seq, DISC_RADIUS_M):
				checked += 1
				if not _is_refusable(intent, OWN_SLOT, feed_seq, DISC_RADIUS_M):
					fail_test("A legitimate intent (kind %d) at feed_seq %d." % [intent.kind, feed_seq])
					return
		assert_gt(checked, BATCHES - 1, "Intents were produced for feed_seq %d." % feed_seq)


func test_no_intent_is_ever_a_legitimate_placement_for_any_seat_or_radius() -> void:
	var checked: int = 0
	for own_slot: int in [0, 3, 7]:
		for radius: float in [10.0, 45.0, 120.0]:
			var plan: SoakFuzzPlan = _plan(own_slot * 100 + int(radius))
			for _i: int in 300:
				for intent: SoakFuzzPlan.Intent in plan.next_batch(own_slot, FEED_SEQ, radius):
					checked += 1
					if not _is_refusable(intent, own_slot, FEED_SEQ, radius):
						fail_test("Legitimate intent for slot %d radius %.0f." % [own_slot, radius])
						return
	assert_gt(checked, 2000)


func test_every_kind_is_produced() -> void:
	var seen: Dictionary = {}
	var plan: SoakFuzzPlan = _plan()
	for _i: int in BATCHES:
		for intent: SoakFuzzPlan.Intent in plan.next_batch(OWN_SLOT, FEED_SEQ, DISC_RADIUS_M):
			seen[intent.kind] = true
	for kind: int in SoakFuzzPlan.Kind.values():
		assert_true(seen.has(kind), "Kind %s is produced." % SoakFuzzPlan.Kind.keys()[kind])


func test_negative_seq_intents_carry_a_negative_sequence() -> void:
	var plan: SoakFuzzPlan = _plan()
	var found: int = 0
	for _i: int in BATCHES:
		for intent: SoakFuzzPlan.Intent in plan.next_batch(OWN_SLOT, FEED_SEQ, DISC_RADIUS_M):
			if intent.kind == SoakFuzzPlan.Kind.NEGATIVE_SEQ:
				found += 1
				assert_lt(intent.feed_seq, 0)
	assert_gt(found, 0)


func test_stale_seq_intents_carry_the_previous_sequence() -> void:
	var plan: SoakFuzzPlan = _plan()
	var found: int = 0
	for feed_seq: int in [1, FEED_SEQ, 400]:
		for _i: int in BATCHES_PER_VARIANT:
			for intent: SoakFuzzPlan.Intent in plan.next_batch(OWN_SLOT, feed_seq, DISC_RADIUS_M):
				if intent.kind == SoakFuzzPlan.Kind.STALE_SEQ:
					found += 1
					assert_eq(intent.feed_seq, feed_seq - 1)
	assert_gt(found, 0)


func test_non_finite_pose_intents_have_a_non_finite_origin() -> void:
	var plan: SoakFuzzPlan = _plan()
	var found: int = 0
	for _i: int in BATCHES:
		for intent: SoakFuzzPlan.Intent in plan.next_batch(OWN_SLOT, FEED_SEQ, DISC_RADIUS_M):
			if intent.kind == SoakFuzzPlan.Kind.NON_FINITE_POSE:
				found += 1
				assert_false(intent.origin.is_finite())
	assert_gt(found, 0)


func test_foreign_slot_intents_name_another_slot() -> void:
	var found: int = 0
	for own_slot: int in [0, 1, 5, 7]:
		var plan: SoakFuzzPlan = _plan(own_slot + 11)
		for _i: int in BATCHES_PER_SLOT:
			for intent: SoakFuzzPlan.Intent in plan.next_batch(own_slot, FEED_SEQ, DISC_RADIUS_M):
				if intent.kind == SoakFuzzPlan.Kind.FOREIGN_SLOT:
					found += 1
					assert_ne(intent.slot_id, own_slot)
	assert_gt(found, 0)


func test_other_kinds_are_sent_from_the_own_slot() -> void:
	var plan: SoakFuzzPlan = _plan()
	var found: int = 0
	for _i: int in BATCHES:
		for intent: SoakFuzzPlan.Intent in plan.next_batch(OWN_SLOT, FEED_SEQ, DISC_RADIUS_M):
			if intent.kind == SoakFuzzPlan.Kind.FOREIGN_SLOT:
				continue
			found += 1
			assert_eq(intent.slot_id, OWN_SLOT, "Only FOREIGN_SLOT forges the slot.")
	assert_gt(found, 0)


func test_out_of_disc_intents_lie_outside_the_field_radius() -> void:
	var found: int = 0
	for radius: float in [10.0, 45.0, 120.0]:
		var plan: SoakFuzzPlan = _plan(int(radius))
		for _i: int in BATCHES_PER_VARIANT:
			for intent: SoakFuzzPlan.Intent in plan.next_batch(OWN_SLOT, FEED_SEQ, radius):
				if intent.kind == SoakFuzzPlan.Kind.OUT_OF_DISC:
					found += 1
					assert_true(intent.origin.is_finite(), "Out of the disc, not non-finite.")
					assert_gt(Vector2(intent.origin.x, intent.origin.z).length(), radius)
	assert_gt(found, 0)


func test_a_flood_is_factor_times_the_burst_in_one_batch() -> void:
	var plan: SoakFuzzPlan = _plan()
	var floods: int = 0
	for _i: int in BATCHES:
		var batch: Array[SoakFuzzPlan.Intent] = plan.next_batch(OWN_SLOT, FEED_SEQ, DISC_RADIUS_M)
		var has_flood: bool = false
		for intent: SoakFuzzPlan.Intent in batch:
			has_flood = has_flood or intent.kind == SoakFuzzPlan.Kind.FLOOD
		if has_flood:
			floods += 1
			assert_eq(batch.size(), _flood_size(), "3 x flood_place_burst 6 intents.")
			for intent: SoakFuzzPlan.Intent in batch:
				assert_eq(intent.kind, SoakFuzzPlan.Kind.FLOOD, "A flood batch is all flood.")
		else:
			assert_eq(batch.size(), 1, "Any other kind is a single-intent batch.")
	assert_gt(floods, 0)
	assert_eq(_flood_size(), 18)


func test_the_flood_size_follows_the_config() -> void:
	var config: SoakConfig = _config.duplicate() as SoakConfig
	config.fuzz_flood_factor = 2.0
	var net: NetConfig = NetConfig.new()
	net.flood_place_burst = 4
	var plan: SoakFuzzPlan = _plan(3, config, net)
	var floods: int = 0
	for _i: int in BATCHES:
		var batch: Array[SoakFuzzPlan.Intent] = plan.next_batch(OWN_SLOT, FEED_SEQ, DISC_RADIUS_M)
		if batch.size() > 1:
			floods += 1
			assert_eq(batch.size(), 8, "2 x 4.")
	assert_gt(floods, 0)


func test_every_flood_intent_is_refusable() -> void:
	var plan: SoakFuzzPlan = _plan(21)
	var checked: int = 0
	for _i: int in BATCHES:
		var batch: Array[SoakFuzzPlan.Intent] = plan.next_batch(OWN_SLOT, FEED_SEQ, DISC_RADIUS_M)
		if batch.size() <= 1:
			continue
		for intent: SoakFuzzPlan.Intent in batch:
			checked += 1
			assert_true(_is_refusable(intent, OWN_SLOT, FEED_SEQ, DISC_RADIUS_M))
	assert_gt(checked, 0)


func test_a_new_batch_does_not_reuse_the_previous_intents() -> void:
	var plan: SoakFuzzPlan = _plan()
	var first: Array[SoakFuzzPlan.Intent] = plan.next_batch(OWN_SLOT, FEED_SEQ, DISC_RADIUS_M)
	assert_false(first.is_empty())
	if first.is_empty():
		return
	var before: String = _signature(first[0])
	for _i: int in 20:
		plan.next_batch(OWN_SLOT, FEED_SEQ, DISC_RADIUS_M)
	assert_eq(_signature(first[0]), before, "A returned intent is not rewritten by later calls.")


func test_intents_carry_the_default_orientation() -> void:
	var plan: SoakFuzzPlan = _plan()
	var checked: int = 0
	for _i: int in 200:
		for intent: SoakFuzzPlan.Intent in plan.next_batch(OWN_SLOT, FEED_SEQ, DISC_RADIUS_M):
			checked += 1
			assert_eq(intent.orientation_index, 0)
			assert_eq(intent.free_quat, Quaternion.IDENTITY)
	assert_gt(checked, 0)


func test_out_of_disc_intents_use_every_corner() -> void:
	var corners: Dictionary = {}
	var plan: SoakFuzzPlan = _plan()
	for _i: int in BATCHES:
		for intent: SoakFuzzPlan.Intent in plan.next_batch(OWN_SLOT, FEED_SEQ, DISC_RADIUS_M):
			if intent.kind == SoakFuzzPlan.Kind.OUT_OF_DISC:
				corners[Vector2(signf(intent.origin.x), signf(intent.origin.z))] = true
	assert_eq(corners.size(), 4, "All four corners of the bounding square are used.")


func test_non_finite_poses_spoil_every_axis() -> void:
	var axes: Dictionary = {}
	var plan: SoakFuzzPlan = _plan()
	for _i: int in BATCHES:
		for intent: SoakFuzzPlan.Intent in plan.next_batch(OWN_SLOT, FEED_SEQ, DISC_RADIUS_M):
			if intent.kind != SoakFuzzPlan.Kind.NON_FINITE_POSE:
				continue
			for axis: int in 3:
				if is_nan(intent.origin[axis]):
					axes[axis] = true
	assert_eq(axes.size(), 3, "x, y and z each get spoiled sometimes.")
