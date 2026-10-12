extends GutTest
## Owner playtest 2026-10-12: Bontago-1pi.176 / .178 / .179 / .180.

const REMOVED_IDS: Array[StringName] = [&"bar4", &"bar5"]


func test_elimination_defaults_to_permanent_holes_others_temporary() -> void:
	assert_eq(MatchConfig.default_hole_mode(MatchConfig.GameMode.ELIMINATION), MatchConfig.HoleMode.PERMANENT)
	assert_eq(MatchConfig.default_hole_mode(MatchConfig.GameMode.CLASSIC), MatchConfig.HoleMode.TEMPORARY)
	assert_eq(MatchConfig.default_hole_mode(MatchConfig.GameMode.CAPTURE_THE_FLAG), MatchConfig.HoleMode.TEMPORARY)
	assert_eq(MatchConfig.default_hole_mode(MatchConfig.GameMode.REACH_THE_SKY), MatchConfig.HoleMode.TEMPORARY)


func test_gravity_default_and_range() -> void:
	assert_almost_eq(MatchConfig.new().gravity_multiplier, 1.0, 0.0001)
	assert_almost_eq((load("res://config/match_defaults.tres") as MatchConfig).gravity_multiplier, 1.0, 0.0001)
	assert_almost_eq(PhysicsTuning.new().lobby_gravity_baseline, 1.75, 0.0001)
	assert_almost_eq(PhysicsTuning.new().gravity_multiplier, 1.75, 0.0001)
	assert_almost_eq((load("res://config/physics_tuning.tres") as PhysicsTuning).gravity_multiplier, 1.75, 0.0001)
	assert_almost_eq(MatchConfig.GRAVITY_MIN, 0.1, 0.0001)
	assert_almost_eq(MatchConfig.GRAVITY_MAX, 2.0, 0.0001)
	var config: MatchConfig = MatchConfig.new()
	config.gravity_multiplier = 5.0
	config.sanitize()
	assert_almost_eq(config.gravity_multiplier, 2.0, 0.0001)
	config.gravity_multiplier = 0.0
	config.sanitize()
	assert_almost_eq(config.gravity_multiplier, 0.1, 0.0001)


func test_long_bars_stay_on_disk_but_not_in_the_bag() -> void:
	var all_ids: Array[StringName] = []
	for shape: BlockShape in BlockShape.load_all_shapes():
		all_ids.append(shape.id)
	var bag_ids: Array[StringName] = []
	for shape: BlockShape in BlockShape.load_bag_shapes():
		bag_ids.append(shape.id)
	for id: StringName in REMOVED_IDS:
		assert_true(all_ids.has(id), "%s resource stays on disk" % id)
		assert_false(bag_ids.has(id), "%s is not dealt" % id)
	assert_eq(bag_ids.size(), all_ids.size() - REMOVED_IDS.size())


func test_bag_and_gift_picker_never_deal_removed_shapes() -> void:
	var bag: BlockBag = BlockBag.new(BlockFeedConfig.new(), 7)
	for shape: BlockShape in bag.shapes():
		assert_false(REMOVED_IDS.has(shape.id))
	for shape: BlockShape in GiftShapePicker._shapes():
		assert_false(REMOVED_IDS.has(shape.id))


func test_settle_freeze_window_is_five_seconds() -> void:
	assert_almost_eq(PhysicsTuning.new().settle_freeze_window_s, 5.0, 0.0001)
	assert_almost_eq((load("res://config/physics_tuning.tres") as PhysicsTuning).settle_freeze_window_s, 5.0, 0.0001)
