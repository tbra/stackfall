extends GutTest
## docs/M2_PLAN.md P4: HUD.gd "connects to Events only" and implements its
## API exactly. Covers both halves: calling the public API directly (text and
## ratios update) and driving it through the documented Events signals.


func _make_hud() -> HUD:
	var scene: PackedScene = load("res://ui/HUD.tscn")
	var hud: HUD = autofree(scene.instantiate())
	add_child_autofree(hud)
	return hud


## Bontago-1en.16: the special-indicator tests below drive Match._gifts
## directly, the same way tests/unit/test_gift_claim.gd does (no full match
## needs to be running for a FIFO queue read/write). Match is a singleton
## that outlives this script, so a lingering pending-special queue or claim
## left behind here would leak into whichever test file runs next -- the same
## singleton-leak class of bug test_gift_claim.gd's own after_each documents.
## Match.abort_match() resets MatchGifts entirely (autoload/match/
## MatchLifecycle.gd's _reset_match_state() calls _gifts.reset()), so it is
## both the setup and the teardown here.
func before_each() -> void:
	Match.abort_match()


func after_each() -> void:
	Match.abort_match()


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


func test_set_held_shape_stores_the_shape_for_the_held_preview() -> void:
	var hud: HUD = _make_hud()
	var cube: BlockShape = load("res://config/blocks/cube.tres")
	hud.set_held_shape(cube)
	assert_eq(hud._held_shape, cube)


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


## Bontago-xtq.23 (owner playtest 2026-09-24, "if I'm hovering over another
## player's area I get the rejected message but the block still drops more or
## less in place"): root cause was a silent auto-drop relocation right after
## an earlier, correctly-refused manual click -- see
## tests/unit/test_placement_refusal.gd for the rule-level regression tests;
## these pin the HUD's own missing feedback fix.
func test_show_relocated_sets_a_distinct_message_from_show_reject() -> void:
	var hud: HUD = _make_hud()
	hud.show_relocated()
	assert_true(hud._reject_label.text.findn("relocated") >= 0)
	assert_true(hud._reject_label.text.findn("territory") >= 0)
	assert_almost_eq(hud._reject_label.modulate.a, 1.0, 0.001)
	assert_almost_eq(
		hud._reject_label.modulate.r, hud.ghost_tuning.auto_drop_flash_color.r, 0.001,
		"the relocated message should read distinctly from a reject (ties it to the same auto-drop flash tint)."
	)


## Guards show_reject()/show_relocated() sharing one label from bleeding into
## each other: a relocated message right after an unrelated reject must not
## keep the reject's own (different) tint.
func test_show_relocated_after_show_reject_does_not_keep_the_stale_reject_tint() -> void:
	var hud: HUD = _make_hud()
	hud.show_reject(&"outside_territory")
	hud.show_relocated()
	assert_true(hud._reject_label.text.findn("relocated") >= 0)
	assert_almost_eq(hud._reject_label.modulate.r, hud.ghost_tuning.auto_drop_flash_color.r, 0.001)

	hud.show_reject(&"outside_territory")
	assert_true(hud._reject_label.text.findn("outside territory") >= 0)
	assert_almost_eq(
		hud._reject_label.modulate.r, 1.0, 0.001,
		"a reject right after a relocated message must not keep the relocated tint either."
	)


func test_placement_relocated_event_shows_relocated_only_for_the_active_slot() -> void:
	var hud: HUD = _make_hud()
	Events.turn_changed.emit(0)
	Events.placement_relocated.emit(1, Vector2(3.0, -2.0))
	assert_eq(
		hud._reject_label.text, "",
		"a relocation for a different slot shouldn't show on this hot-seat HUD."
	)
	Events.placement_relocated.emit(0, Vector2(3.0, -2.0))
	assert_true(hud._reject_label.text.findn("relocated") >= 0)


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


# --- Bontago-mv0.9: real-time status replaces the hot-seat "turn" banner ----


func test_set_local_slot_never_shows_turn_wording() -> void:
	var hud: HUD = _make_hud()
	hud.set_local_slot(0)
	assert_true(hud._turn_label.text.findn("turn") < 0)
	assert_true(hud._turn_label.text.findn("Player 1") >= 0)


func test_set_local_slot_switches_which_slot_the_widgets_read() -> void:
	var hud: HUD = _make_hud()
	var fake_match: FakeMatch = FakeMatch.new()
	var slot0: PlayerSlot = PlayerSlot.new(0, 0, "P1", Color.RED)
	var slot1: PlayerSlot = PlayerSlot.new(1, 1, "P2", Color.BLUE)
	fake_match.slots_by_id[0] = slot0
	fake_match.slots_by_id[1] = slot1
	hud.match_provider = fake_match

	hud.set_local_slot(0)
	assert_eq(hud._active_slot, 0)
	assert_almost_eq(hud._active_color.r, slot0.color.r, 0.01)

	hud.set_local_slot(1)
	assert_eq(hud._active_slot, 1)
	assert_almost_eq(hud._active_color.r, slot1.color.r, 0.01)


func test_turn_changed_event_shows_no_turn_wording_outside_hot_seat() -> void:
	var hud: HUD = _make_hud()
	var fake_match: FakeMatch = FakeMatch.new()
	fake_match.config = MatchConfig.new()
	fake_match.config.hot_seat = false
	hud.match_provider = fake_match

	Events.turn_changed.emit(0)

	assert_true(hud._turn_label.text.findn("turn") < 0)
	assert_eq(hud._active_slot, 0)


func test_turn_changed_event_still_shows_turn_wording_in_hot_seat() -> void:
	var hud: HUD = _make_hud()
	var fake_match: FakeMatch = FakeMatch.new()
	fake_match.config = MatchConfig.new()
	fake_match.config.hot_seat = true
	hud.match_provider = fake_match

	Events.turn_changed.emit(0)

	assert_true(hud._turn_label.text.findn("turn") >= 0)


func test_process_updates_ring_progress_from_the_local_slots_feed_progress() -> void:
	var hud: HUD = _make_hud()
	var fake_match: FakeMatch = FakeMatch.new()
	fake_match.feed_progress_by_slot[0] = 0.75
	fake_match.feed_progress_by_slot[1] = 0.25
	hud.match_provider = fake_match

	hud.set_local_slot(0)
	hud._process(0.0)
	assert_almost_eq(hud._feed_progress, 0.75, 0.001)

	hud.set_local_slot(1)
	hud._process(0.0)
	assert_almost_eq(hud._feed_progress, 0.25, 0.001)


func test_process_shows_locked_when_the_local_slots_release_is_locked() -> void:
	var hud: HUD = _make_hud()
	var fake_match: FakeMatch = FakeMatch.new()
	fake_match.release_locked_by_slot[0] = true
	hud.match_provider = fake_match

	hud.set_local_slot(0)
	hud._process(0.0)

	assert_true(hud._locked)
	assert_true(hud._locked_label.visible)

	hud.set_local_slot(1)
	hud._process(0.0)

	assert_false(hud._locked)
	assert_false(hud._locked_label.visible)


# --- Bontago-1en.16: pending-special queue indicator ------------------------
# Drives the real Match/MatchGifts singleton, the same way
# tests/unit/test_gift_claim.gd does, rather than FakeMatch -- these tests
# are specifically about the indicator's read of the live FIFO queue.


func test_special_indicator_hidden_when_nothing_is_pending() -> void:
	var hud: HUD = _make_hud()
	hud.set_local_slot(0)

	hud._process(0.0)

	assert_false(hud._special_indicator.visible)


func test_special_indicator_shows_special_after_a_claim_for_the_local_slot() -> void:
	var hud: HUD = _make_hud()
	hud.set_local_slot(0)

	Match._gifts._ensure_capacity(0)
	(Match._gifts._pending_queues[0] as Array).append(MatchGifts.PENDING_SPECIAL_ID)
	Events.gift_claimed.emit(0, 0, MatchGifts.PENDING_SPECIAL_ID)

	assert_true(hud._special_indicator.visible)
	assert_eq(hud._special_indicator.text, "Special")


func test_special_indicator_shows_a_count_badge_once_a_second_special_is_queued() -> void:
	var hud: HUD = _make_hud()
	hud.set_local_slot(0)

	Match._gifts._ensure_capacity(0)
	var queue: Array = Match._gifts._pending_queues[0]
	queue.append(&"jumping_bean")
	queue.append(&"jumping_bean")
	Events.gift_claimed.emit(1, 0, &"jumping_bean")

	assert_true(hud._special_indicator.visible)
	assert_eq(hud._special_indicator.text, "Jumping Bean ×2")


func test_special_indicator_hides_again_after_popping_the_last_pending_special() -> void:
	var hud: HUD = _make_hud()
	hud.set_local_slot(0)
	Match._gifts._ensure_capacity(0)
	(Match._gifts._pending_queues[0] as Array).append(MatchGifts.PENDING_SPECIAL_ID)
	hud._process(0.0)
	assert_true(hud._special_indicator.visible, "must show before the pop")

	Match.pop_pending_special(0)
	hud._process(0.0)

	assert_false(hud._special_indicator.visible)


func test_special_indicator_ignores_a_claim_for_a_different_slot() -> void:
	var hud: HUD = _make_hud()
	hud.set_local_slot(0)

	Match._gifts._ensure_capacity(1)
	(Match._gifts._pending_queues[1] as Array).append(MatchGifts.PENDING_SPECIAL_ID)
	Events.gift_claimed.emit(0, 1, MatchGifts.PENDING_SPECIAL_ID)
	hud._process(0.0)

	assert_false(hud._special_indicator.visible, "a claim for another slot must not show on this HUD")


# --- Bontago-d04: claim toast -------------------------------------------------
# Owner report "I grabbed a yellow cube but nothing seemed to happen": the
# claim itself already worked (the indicator tests above), but nothing told
# the player it had. show_gift_toast()/_on_gift_claimed() add a one-line
# "Special queued: <name>" message next to the pending-special indicator.

func test_gift_claimed_for_the_local_slot_shows_the_toast_with_the_special_name() -> void:
	var hud: HUD = _make_hud()
	hud.set_local_slot(0)

	Match._gifts._ensure_capacity(0)
	(Match._gifts._pending_queues[0] as Array).append(&"jumping_bean")
	Events.gift_claimed.emit(0, 0, &"jumping_bean")

	assert_eq(hud._gift_toast_label.text, "Special queued: Jumping Bean")
	assert_almost_eq(hud._gift_toast_label.modulate.a, 1.0, 0.0001)


func test_gift_claimed_toast_ignores_a_claim_for_a_different_slot() -> void:
	var hud: HUD = _make_hud()
	hud.set_local_slot(0)

	Match._gifts._ensure_capacity(1)
	(Match._gifts._pending_queues[1] as Array).append(MatchGifts.PENDING_SPECIAL_ID)
	Events.gift_claimed.emit(0, 1, MatchGifts.PENDING_SPECIAL_ID)

	assert_eq(hud._gift_toast_label.text, "", "a claim for another slot must not show a toast on this HUD")


func test_gift_claimed_toast_fades_after_its_configured_hold_duration() -> void:
	var hud: HUD = _make_hud()
	hud.set_local_slot(0)
	hud.gift_config = hud.gift_config.duplicate() as GiftConfig
	hud.gift_config.claim_toast_visible_duration_s = 0.1
	hud.gift_config.claim_toast_fade_duration_s = 0.1

	Match._gifts._ensure_capacity(0)
	(Match._gifts._pending_queues[0] as Array).append(MatchGifts.PENDING_SPECIAL_ID)
	Events.gift_claimed.emit(0, 0, MatchGifts.PENDING_SPECIAL_ID)
	assert_almost_eq(hud._gift_toast_label.modulate.a, 1.0, 0.0001, "fixture: fully visible right after the claim")

	await get_tree().create_timer(0.35).timeout

	assert_almost_eq(hud._gift_toast_label.modulate.a, 0.0, 0.0001, "must have faded out after hold + fade elapsed")
