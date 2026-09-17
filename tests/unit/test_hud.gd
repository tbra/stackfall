extends GutTest
## docs/M2_PLAN.md P4: HUD.gd "connects to Events only" and implements its
## API exactly. Covers both halves: calling the public API directly (text and
## ratios update) and driving it through the documented Events signals.


func _make_hud() -> HUD:
	var scene: PackedScene = load("res://ui/HUD.tscn")
	var hud: HUD = autofree(scene.instantiate())
	add_child_autofree(hud)
	return hud


func test_set_active_slot_updates_the_turn_label() -> void:
	var hud: HUD = _make_hud()
	hud.set_active_slot(0, Color.RED)
	assert_true(hud._turn_label.text.findn("Player 1") >= 0)
	assert_true(hud._turn_label.text.findn("turn") >= 0)


func test_set_active_slot_shows_eliminated_slots(
) -> void:
	var hud: HUD = _make_hud()
	var fake_match: FakeMatch = FakeMatch.new()
	var eliminated_slot: PlayerSlot = PlayerSlot.new(0, 0, "P1", Color.RED)
	eliminated_slot.home_flag_alive = false
	fake_match.slots_by_id[0] = eliminated_slot
	hud.match_provider = fake_match

	hud.set_active_slot(0, Color.RED)

	assert_true(hud._turn_label.text.findn("eliminated") >= 0)


func test_set_next_shape_stores_the_shape_for_the_preview() -> void:
	var hud: HUD = _make_hud()
	var bar4: BlockShape = load("res://config/blocks/bar4.tres")
	hud.set_next_shape(bar4)
	assert_eq(hud._next_shape, bar4)


func test_set_feed_progress_clamps_into_0_1() -> void:
	var hud: HUD = _make_hud()
	hud.set_feed_progress(0.42)
	assert_almost_eq(hud._feed_progress, 0.42, 0.001)
	hud.set_feed_progress(1.5)
	assert_almost_eq(hud._feed_progress, 1.0, 0.001)
	hud.set_feed_progress(-0.5)
	assert_almost_eq(hud._feed_progress, 0.0, 0.001)


func test_set_height_formats_meters() -> void:
	var hud: HUD = _make_hud()
	hud.set_height(3.14159)
	assert_eq(hud._height_label.text, "Height: 3.14 m")


func test_set_territory_shares_builds_one_row_per_player_with_matching_width() -> void:
	var hud: HUD = _make_hud()
	hud.set_territory_shares(PackedFloat32Array([0.25, 0.75]))
	assert_eq(hud._share_bars.size(), 2)
	var bar0: ColorRect = hud._share_bars[0]
	var bar1: ColorRect = hud._share_bars[1]
	assert_almost_eq(bar0.custom_minimum_size.x, HUD.SHARE_BAR_MAX_WIDTH * 0.25, 0.01)
	assert_almost_eq(bar1.custom_minimum_size.x, HUD.SHARE_BAR_MAX_WIDTH * 0.75, 0.01)
	assert_true((hud._share_labels[0] as Label).text.contains("25"))
	assert_true((hud._share_labels[1] as Label).text.contains("75"))


func test_set_territory_shares_shrinks_rows_when_player_count_drops() -> void:
	var hud: HUD = _make_hud()
	hud.set_territory_shares(PackedFloat32Array([0.5, 0.5, 0.0]))
	assert_eq(hud._share_bars.size(), 3)
	hud.set_territory_shares(PackedFloat32Array([1.0]))
	assert_eq(hud._share_bars.size(), 1)


func test_set_territory_shares_marks_eliminated_slots() -> void:
	var hud: HUD = _make_hud()
	var fake_match: FakeMatch = FakeMatch.new()
	var eliminated_slot: PlayerSlot = PlayerSlot.new(1, 1, "P2", Color.BLUE)
	eliminated_slot.home_flag_alive = false
	fake_match.slots_by_id[1] = eliminated_slot
	hud.match_provider = fake_match

	hud.set_territory_shares(PackedFloat32Array([0.6, 0.4]))

	assert_true((hud._share_labels[1] as Label).text.findn("out") >= 0)


func test_set_capture_shows_the_ring_only_while_someone_is_capturing() -> void:
	var hud: HUD = _make_hud()
	hud.set_capture(0, 0.5, Color.GREEN)
	assert_true(hud._capture_ring.visible)
	assert_almost_eq(hud._capture_progress, 0.5, 0.001)

	hud.set_capture(-1, 0.0, Color.GREEN)
	assert_false(hud._capture_ring.visible)


func test_show_reject_sets_the_message() -> void:
	var hud: HUD = _make_hud()
	hud.show_reject(&"outside_territory")
	assert_true(hud._reject_label.text.findn("outside territory") >= 0)
	assert_almost_eq(hud._reject_label.modulate.a, 1.0, 0.001)


func test_show_winner_reveals_the_banner() -> void:
	var hud: HUD = _make_hud()
	assert_false(hud._winner_label.visible)
	hud.show_winner(0, Color.GOLD)
	assert_true(hud._winner_label.visible)
	assert_true(hud._winner_label.text.findn("wins") >= 0)


# --- Driven through Events, per docs/M2_PLAN.md's acceptance check ---------


func test_turn_changed_event_updates_the_hud() -> void:
	var hud: HUD = _make_hud()
	Events.turn_changed.emit(1)
	assert_eq(hud._active_slot, 1)
	assert_true(hud._turn_label.text.findn("Player 2") >= 0)


func test_feed_block_issued_event_updates_the_next_shape_preview_for_the_active_slot() -> void:
	var hud: HUD = _make_hud()
	var domino: BlockShape = load("res://config/blocks/domino.tres")
	Events.turn_changed.emit(0)
	Events.feed_block_issued.emit(0, &"cube", &"domino")
	assert_eq(hud._next_shape, domino)


func test_feed_block_issued_event_ignores_other_slots() -> void:
	var hud: HUD = _make_hud()
	Events.turn_changed.emit(0)
	Events.feed_block_issued.emit(1, &"cube", &"bar4")
	assert_null(hud._next_shape)


func test_territory_share_changed_event_updates_hud() -> void:
	var hud: HUD = _make_hud()
	Events.territory_share_changed.emit(PackedFloat32Array([0.3, 0.7]))
	assert_eq(hud._share_bars.size(), 2)


func test_goal_capture_progress_event_updates_hud() -> void:
	var hud: HUD = _make_hud()
	Events.goal_capture_progress.emit(0, 0.8)
	assert_true(hud._capture_ring.visible)
	assert_almost_eq(hud._capture_progress, 0.8, 0.001)


func test_match_won_event_shows_the_winner() -> void:
	var hud: HUD = _make_hud()
	Events.match_won.emit(1)
	assert_true(hud._winner_label.visible)


func test_placement_rejected_event_shows_reject_only_for_the_active_slot() -> void:
	var hud: HUD = _make_hud()
	Events.turn_changed.emit(0)
	Events.placement_rejected.emit(1, &"contested")
	assert_eq(hud._reject_label.text, "", "A rejection for a different slot shouldn't show on this hot-seat HUD.")
	Events.placement_rejected.emit(0, &"contested")
	assert_true(hud._reject_label.text.findn("contested") >= 0)
