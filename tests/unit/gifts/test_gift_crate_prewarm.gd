extends GutTest
## Bontago-1pi.11.87: the crate model table/GLB is built before the first gift spawn, so the
## first GiftCrate no longer costs a 40+ ms hitch inside a placement frame.


func test_match_gifts_prewarms_crate_assets_at_setup() -> void:
	assert_true(Match._gifts.crate_prewarmed(), "Match setup prewarmed the crate assets")


func test_prewarm_is_idempotent_and_leaves_no_orphan_nodes() -> void:
	var orphans_before: int = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) as int
	Match._gifts.prewarm_crate_assets()
	Match._gifts.prewarm_crate_assets()
	assert_true(Match._gifts.crate_prewarmed())
	assert_eq(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)), orphans_before, "no orphan left")


func test_crate_visual_builds_after_prewarm() -> void:
	var visual: Node3D = GiftModelTable.shared().build_crate_visual()
	assert_not_null(visual, "crate row resolves")
	if visual != null:
		visual.free()
