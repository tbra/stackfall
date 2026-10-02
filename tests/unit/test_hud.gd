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


## Bontago-1pi.5 (owner playtest: a separate results screen replaces this
## in-HUD banner): show_winner() still formats the text/tint (a cheap seam
## for whatever consumes it next) but must no longer make %WinnerLabel
## visible.
func test_show_winner_no_longer_shows_the_hud_banner() -> void:
	var hud: HUD = _make_hud()
	assert_false(hud._winner_label.visible)
	hud.show_winner(0, Color.GOLD)
	assert_false(hud._winner_label.visible, "the results screen owns the winner announcement now, not this HUD banner")
	assert_true(hud._winner_label.text.findn("wins") >= 0, "the formatted text is kept harmless, just not shown")


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


func test_gift_claim_refreshes_only_recipient_next_preview_immediately() -> void:
	var hud: HUD = _make_hud()
	var fake_match: FakeMatch = FakeMatch.new()
	var gift_shape: BlockShape = load("res://config/blocks/bar4.tres")
	hud.match_provider = fake_match
	hud.set_local_slot(0)
	fake_match.next_shapes[0] = gift_shape
	Events.gift_claimed.emit(42, 1, &"jumping_bean")
	assert_null(hud._next_shape)
	Events.gift_claimed.emit(43, 0, &"jumping_bean")
	assert_same(hud._next_shape, gift_shape)
	assert_eq(hud._next_label.text, "NEXT")
	fake_match.pending_special_count_by_slot[0] = 1
	hud._refresh_special_indicator()
	assert_eq(hud._next_label.text, "NEXT GIFT")
	fake_match.held_special_by_slot[0] = &"jumping_bean"
	hud._refresh_special_indicator()
	assert_eq(hud._held_label.text, "HELD: Jumping Bean")
	assert_eq(hud._next_label.text, "NEXT")


func test_territory_share_changed_event_updates_hud() -> void:
	var hud: HUD = _make_hud()
	Events.territory_share_changed.emit(PackedFloat32Array([0.3, 0.7]))
	assert_eq(hud._share_bars.size(), 2)


func test_goal_capture_progress_event_updates_hud() -> void:
	var hud: HUD = _make_hud()
	Events.goal_capture_progress.emit(0, 0.8)
	assert_true(hud._capture_ring.visible)
	assert_almost_eq(hud._capture_progress, 0.8, 0.001)


## Bontago-1pi.5: the signal wiring (Events.match_won -> _on_match_won ->
## show_winner()) must stay harmless -- it still runs, it just must not show
## anything on this HUD instance anymore (a separate results screen owns
## that now).
func test_match_won_event_no_longer_shows_the_hud_winner_label() -> void:
	var hud: HUD = _make_hud()
	Events.match_won.emit(1)
	assert_false(hud._winner_label.visible)


func test_a_tied_results_payload_announces_a_shared_win() -> void:
	var hud: HUD = _make_hud()
	Events.match_won.emit(0)
	assert_eq(hud._winner_label.text, "Team 1 wins!")
	Events.match_results_ready.emit({
		"winner_kind": MatchStats.WINNER_KIND_TEAM, "winner_id": 0,
		"mode": {"winners": "0,1"},
	})
	assert_eq(hud._winner_label.text, "Teams 1 & 2 share the win!")


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
# are specifically about the indicator's read of held and next gifts.


func test_special_indicator_hidden_when_nothing_is_pending() -> void:
	var hud: HUD = _make_hud()
	hud.set_local_slot(0)

	hud._process(0.0)

	assert_false(hud._special_indicator.visible)


func test_glue_charges_show_for_the_active_slot_and_clear_when_spent() -> void:
	var hud: HUD = _make_hud()
	var fake_match: FakeMatch = FakeMatch.new()
	hud.match_provider = fake_match
	fake_match.glue_drops_by_slot[0] = 3
	hud.set_local_slot(0)
	assert_true(hud._special_indicator.visible)
	assert_eq(hud._special_indicator.text, "Glue ×3")
	fake_match.held_special_by_slot[0] = &"paintball"
	fake_match.pending_special_count_by_slot[0] = 1
	hud._refresh_special_indicator()
	assert_eq(hud._special_indicator.text, "Paintball · Glue ×3")
	fake_match.glue_drops_by_slot[0] = 0
	fake_match.pending_special_count_by_slot[0] = 0
	hud._refresh_special_indicator()
	assert_false(hud._special_indicator.visible)


func test_glue_preview_overlay_follows_charges() -> void:
	var hud: HUD = _make_hud()
	var fake_match: FakeMatch = FakeMatch.new()
	hud.match_provider = fake_match
	hud.set_local_slot(0)
	assert_false(hud.glue_preview_active())
	fake_match.glue_drops_by_slot[0] = 5
	hud._refresh_special_indicator()
	assert_true(hud.glue_preview_active())
	fake_match.glue_drops_by_slot[0] = 0
	hud._refresh_special_indicator()
	assert_false(hud.glue_preview_active())


func test_glue_overlay_clears_when_the_provider_goes_away() -> void:
	var hud: HUD = _make_hud()
	var fake_match: FakeMatch = FakeMatch.new()
	hud.match_provider = fake_match
	hud.set_local_slot(0)
	fake_match.glue_drops_by_slot[0] = 5
	hud._refresh_special_indicator()
	assert_true(hud.glue_preview_active())
	hud.match_provider = null
	hud._refresh_special_indicator()
	assert_false(hud.glue_preview_active())


func test_glue_overlay_clears_on_match_end_and_lobby() -> void:
	for to_state: int in [Match.State.END, Match.State.LOBBY]:
		var hud: HUD = _make_hud()
		var fake_match: FakeMatch = FakeMatch.new()
		hud.match_provider = fake_match
		hud.set_local_slot(0)
		fake_match.glue_drops_by_slot[0] = 5
		hud._refresh_special_indicator()
		assert_true(hud.glue_preview_active())
		Events.match_state_changed.emit(Match.State.PLAYING, to_state)
		assert_false(hud.glue_preview_active())


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
	Match._gifts._held_specials[0] = &"jumping_bean"
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

	Match._gifts.activate_next_special(0)
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


# --- Bontago-keo.17: gift_claimed's slot_id must still reach every teammate -
# Owner decision "b": Events.gift_claimed's second argument is the RESOLVED
# RECIPIENT slot (the one teammate nearest the crate), not a team id. Under
# TEAMS_2 with 4 players, team_of_slot() interleaves
# (posmod(slot_id, team_count())), so slots 0/2 are team 0 and slots 1/3 are
# team 1. A claim resolved to slot 0 (team 0) must still show on both slots 0
# and 2's HUD -- this toast is a team-wide notification, deriving "my team"
# from _team_of_slot() on both sides -- and on neither slot 1 nor 3's.

func _teams_2_config() -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.player_count = 4
	config.team_mode = MatchConfig.TeamMode.TEAMS_2
	return config


func _hud_for_slot(slot_id: int, config: MatchConfig) -> HUD:
	var hud: HUD = _make_hud()
	var fake_match: FakeMatch = FakeMatch.new()
	fake_match.config = config
	hud.match_provider = fake_match
	hud.set_local_slot(slot_id)
	return hud


func test_gift_claimed_toast_reaches_both_teammates_under_teams_2() -> void:
	var config: MatchConfig = _teams_2_config()
	var hud_slot0: HUD = _hud_for_slot(0, config)
	var hud_slot2: HUD = _hud_for_slot(2, config)

	Events.gift_claimed.emit(0, 0, &"jumping_bean")

	assert_eq(
		hud_slot0._gift_toast_label.text, "Special queued: Jumping Bean",
		"team 0's claim must show on slot 0's own HUD"
	)
	assert_eq(
		hud_slot2._gift_toast_label.text, "Special queued: Jumping Bean",
		"team 0's claim must also show on its teammate slot 2's HUD"
	)


func test_gift_claimed_toast_skips_the_other_team_under_teams_2() -> void:
	var config: MatchConfig = _teams_2_config()
	var hud_slot1: HUD = _hud_for_slot(1, config)
	var hud_slot3: HUD = _hud_for_slot(3, config)

	Events.gift_claimed.emit(0, 0, &"jumping_bean")

	assert_eq(
		hud_slot1._gift_toast_label.text, "",
		"team 1's slot 1 HUD must not react to a team 0 claim"
	)
	assert_eq(
		hud_slot3._gift_toast_label.text, "",
		"team 1's slot 3 HUD must not react to a team 0 claim"
	)


# --- M7 P5 / Bontago-mp0.3.3: HUD minimap ------------------------------------
## (docs/M7_PLAN.md "P5 -- HUD minimap + reskin"; rebuilt for Bontago-mp0.3.3,
## owner: the minimap "reflecting the sky depending on the camera angle" --
## see ui/Minimap.gd's own class doc DECISION for the root cause and fix.)


## Pins the fix directly: nothing under the minimap may be a 3D camera or
## viewport ever again, because that is exactly what let the mirror's sky
## reflection leak in depending on view angle. The minimap now draws the live
## TerritoryRaster in 2D instead.
func test_minimap_never_creates_a_3d_camera_or_viewport() -> void:
	var hud: HUD = _make_hud()
	assert_eq(
		hud._minimap.find_children("*", "Camera3D", true, false).size(), 0,
		"the minimap must not own a Camera3D (that path sampled the sky/mirror through camera angle)"
	)
	assert_eq(
		hud._minimap.find_children("*", "SubViewport", true, false).size(), 0,
		"the minimap must not own a SubViewport"
	)


## No match loaded (a bare HUD-only instance, e.g. a menu behind the scenes)
## must render nothing and cost nothing: the widget stays hidden until
## set_map_def() is ever called with a real map.
func test_minimap_stays_disabled_with_no_match_loaded() -> void:
	var hud: HUD = _make_hud()
	assert_false(hud._minimap.is_active())
	assert_false(hud._minimap.visible)


func test_set_map_def_frames_from_the_maps_radius() -> void:
	var hud: HUD = _make_hud()
	var small_map: MapDef = MapDef.for_variant_and_size(MatchConfig.MapVariant.ROUND, MapDef.MapSize.SMALL)
	var large_map: MapDef = MapDef.for_variant_and_size(MatchConfig.MapVariant.ROUND, MapDef.MapSize.LARGE)
	assert_true(large_map.field_radius > small_map.field_radius, "fixture: LARGE must actually be bigger than SMALL")

	hud._minimap.set_map_def(small_map)
	var small_extent: float = hud._minimap.half_extent()
	assert_true(hud._minimap.is_active())
	assert_true(hud._minimap.visible)

	hud._minimap.set_map_def(large_map)
	var large_extent: float = hud._minimap.half_extent()

	assert_true(
		large_extent > small_extent,
		"a bigger map's radius must widen the minimap's framed half-extent"
	)


func test_minimap_gift_markers_follow_camera_and_disappear_from_read_model() -> void:
	var hud: HUD = _make_hud()
	var minimap: Minimap = hud._minimap
	var map_def: MapDef = MapDef.new()
	map_def.field_radius = 20.0
	minimap.set_map_def(map_def)
	minimap.set_gift_states([
		{"id": 7, "phase": MatchGifts.FALLING, "position": Vector2(10.0, 0.0)},
		{"id": 8, "phase": MatchGifts.LANDED, "position": Vector2(0.0, 10.0)},
	])
	var markers: Array[Dictionary] = minimap.gift_marker_draw_data()
	assert_eq(markers.size(), 2)
	assert_gt((markers[0]["pixel"] as Vector2).x, minimap.size.x * 0.5)
	assert_lt((markers[1]["pixel"] as Vector2).y, minimap.size.y * 0.5)
	minimap.set_camera_basis(Vector2(0.0, -1.0), Vector2(1.0, 0.0))
	markers = minimap.gift_marker_draw_data()
	assert_lt((markers[0]["pixel"] as Vector2).y, minimap.size.y * 0.5)
	minimap.set_gift_states([{"id": 8, "phase": MatchGifts.LANDED, "position": Vector2(0.0, 10.0)}])
	assert_eq(minimap.gift_marker_draw_data().size(), 1)
	minimap.set_gift_states([])
	assert_eq(minimap.gift_marker_draw_data().size(), 0)


## Drives the minimap the same way real play does -- through
## Events.territory_share_changed, HUD.gd's own chosen hook (no new signal) --
## and confirms it actually re-frames from the FakeMatch's MapDef, with no
## error in headless mode. FakeMatch has no raster(), pinning that the
## has_method(&"raster") guard in HUD._update_minimap() lets this run cleanly
## with a double that cannot answer it.
func test_territory_share_changed_event_updates_the_minimap_from_match_config() -> void:
	var hud: HUD = _make_hud()
	var fake_match: FakeMatch = FakeMatch.new()
	fake_match.config = MatchConfig.new()
	fake_match.config.map_size = MapDef.MapSize.LARGE
	hud.match_provider = fake_match

	Events.territory_share_changed.emit(PackedFloat32Array([0.5, 0.5]))

	assert_true(hud._minimap.is_active())
	var expected_map: MapDef = fake_match.config.map_def()
	assert_almost_eq(
		hud._minimap.half_extent(), expected_map.field_radius + hud.hud_visual_tuning.minimap_zoom_margin_m, 0.01
	)


func test_territory_share_changed_event_leaves_the_minimap_disabled_with_no_config() -> void:
	var hud: HUD = _make_hud()
	var fake_match: FakeMatch = FakeMatch.new()
	hud.match_provider = fake_match

	Events.territory_share_changed.emit(PackedFloat32Array([0.5, 0.5]))

	assert_false(hud._minimap.is_active())


## Content regression for the owner's actual complaint: the minimap must show
## the real TerritoryRaster's team colors, and never anything sampled from a
## 3D scene (no sky can leak into a value nothing here ever reads from a
## camera). Builds a real raster (same fixture shape as
## tests/unit/test_territory_raster.gd) with one home circle at the disk
## centre, feeds it to the minimap directly via set_match_state()+
## render_now(), and reads the rendered image back.
func test_minimap_image_draws_the_live_raster_not_a_camera_sample() -> void:
	var hud: HUD = _make_hud()
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_minimap"
	map_def.field_radius = 20.0
	map_def.cell_size = 1.0
	hud._minimap.set_map_def(map_def)

	var tuning: TerritoryTuning = load("res://config/territory_tuning.tres")
	var grid: CellGrid = CellGrid.new(map_def.field_radius, map_def.cell_size)
	var solver: TerritorySolver = TerritorySolver.new(tuning)
	var raster: TerritoryRaster = TerritoryRaster.new(grid, tuning)
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.new(Vector2(0.0, 0.0), tuning.home_radius, 0, 0, true, -1)
	]
	var groups: TerritoryGroups = solver.solve(circles)
	raster.update(circles, groups, 0.1, true, false)

	hud._minimap.set_match_state(raster, PackedColorArray([Color.RED]), PackedVector2Array([Vector2.ZERO]))
	hud._minimap.render_now()

	var image: Image = hud._minimap.debug_image()
	var size_px: int = image.get_width()
	var center: Color = image.get_pixel(size_px / 2, size_px / 2)
	assert_almost_eq(center.r, 1.0, 0.05, "the disk centre, inside the home circle, must render team 0's own color")
	assert_almost_eq(center.a, 1.0, 0.05, "an owned in-disk cell must be fully opaque")

	var corner: Color = image.get_pixel(1, 1)
	assert_almost_eq(
		corner.a, 0.0, 0.001,
		"outside the disk must be fully transparent -- never a sampled sky/mirror pixel"
	)


## Every dealt shape has a baked thumbnail; repeated draws reuse its texture.
func test_static_preview_assets_cover_every_shape_and_are_cached() -> void:
	var hud: HUD = _make_hud()
	for shape: BlockShape in BlockShape.load_all_shapes():
		var texture: Texture2D = hud._preview_texture(shape)
		assert_not_null(texture, "%s needs a baked preview" % shape.id)
		assert_same(texture, hud._preview_texture(shape), "preview textures must be reused")
		if texture != null:
			assert_gt(texture.get_width(), 0)
			assert_gt(texture.get_height(), 0)


func test_null_shape_has_no_static_preview() -> void:
	var hud: HUD = _make_hud()
	assert_null(hud._preview_texture(null))
	assert_eq(hud._preview_textures.size(), 0)


func test_gift_slot_card_shows_only_while_a_gift_is_slotted() -> void:
	var hud: HUD = _make_hud()
	hud.set_active_slot(0, Color.RED)
	hud._refresh_gift_slot()
	assert_false(hud._gift_slot_column.visible)
	var base_right: float = hud._held_next_panel.offset_right
	Match._gifts._gift_slots[0] = [&"anvil"]
	hud._refresh_gift_slot()
	assert_true(hud._gift_slot_column.visible)
	assert_gt(hud._held_next_panel.offset_right, base_right, "panel widens for the card")
	assert_true(hud._gift_slot_label.text.begins_with("GIFT"))
	Match._gifts._gift_slots.clear()
	hud._refresh_gift_slot()
	assert_false(hud._gift_slot_column.visible)
	assert_eq(hud._held_next_panel.offset_right, base_right)


# --- Bontago-1pi.25.1 Domination readout ------------------------------------

func test_domination_readout_only_in_domination() -> void:
	var hud: HUD = _make_hud()
	var dom: Dictionary = {"mode_id": MatchConfig.GameMode.DOMINATION, "scores": [0.25, 0.41], "extra": {}, "round_left": 125.0}
	hud._on_mode_state_changed(dom)
	assert_not_null(hud._mode_score_label)
	assert_eq(hud._mode_score_label.text, "Leading: 2 (41%)   2:05")
	var tied: Dictionary = {"mode_id": MatchConfig.GameMode.DOMINATION, "scores": [0.3, 0.3], "extra": {}, "round_left": 0.0}
	assert_eq(HUD.mode_score_text(tied), "Leading: 1 & 2 (30%)")
	var ctf: Dictionary = {"mode_id": MatchConfig.GameMode.CAPTURE_THE_FLAG, "scores": [1.0, 2.0], "extra": {}, "round_left": 0.0}
	assert_eq(HUD.mode_score_text(ctf).find("Leading"), -1)
	var hud2: HUD = _make_hud()
	assert_null(hud2._mode_score_label, "no readout without a mode state (Classic)")
