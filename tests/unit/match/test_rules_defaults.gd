extends GutTest
## / .178 / .179 / .180.

const REMOVED_IDS: Array[StringName] = [&"bar4", &"bar5"]


func test_elimination_defaults_to_permanent_holes_others_temporary() -> void:
	assert_eq(MatchConfig.default_hole_mode(MatchConfig.GameMode.ELIMINATION), MatchConfig.HoleMode.PERMANENT)
	assert_eq(MatchConfig.default_hole_mode(MatchConfig.GameMode.CLASSIC), MatchConfig.HoleMode.TEMPORARY)
	assert_eq(MatchConfig.default_hole_mode(MatchConfig.GameMode.CAPTURE_THE_FLAG), MatchConfig.HoleMode.TEMPORARY)
	assert_eq(MatchConfig.default_hole_mode(MatchConfig.GameMode.REACH_THE_SKY), MatchConfig.HoleMode.TEMPORARY)


func test_bag_and_gift_picker_never_deal_removed_shapes() -> void:
	var bag: BlockBag = BlockBag.new(BlockFeedConfig.new(), 7)
	for shape: BlockShape in bag.shapes():
		assert_false(REMOVED_IDS.has(shape.id))
	for shape: BlockShape in GiftShapePicker._shapes():
		assert_false(REMOVED_IDS.has(shape.id))

