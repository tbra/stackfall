extends GutTest
## HUD.gd "connects to Events only" and implements its
## API exactly. Covers both halves: calling the public API directly (text and
## ratios update) and driving it through the documented Events signals.


func _make_hud() -> HUD:
	var scene: PackedScene = load("res://ui/hud/HUD.tscn")
	var hud: HUD = autofree(scene.instantiate())
	add_child_autofree(hud)
	return hud


## the special-indicator tests below drive Match._gifts
## directly, the same way tests/unit/gifts/test_gift_claim.gd does (no full match
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
	Settings._input(InputEventKey.new())


## the eliminated local player gets the big red banner, naming
## the eliminator, or plain "Eliminated" when none is known.
func test_eliminated_banner_names_the_eliminator_or_falls_back() -> void:
	var hud: HUD = _make_hud()
	var fake_match: FakeMatch = FakeMatch.new()
	fake_match.slots_by_id[0] = PlayerSlot.new(0, 0, "P1", Color.RED)
	fake_match.slots_by_id[1] = PlayerSlot.new(1, 1, "Rival", Color.BLUE)
	hud.match_provider = fake_match
	hud.set_local_slot(0)
	assert_eq(hud.eliminated_banner_text(), "")
	hud.show_eliminated_banner(0)
	assert_eq(hud.eliminated_banner_text(), "Eliminated")
	fake_match.eliminated_by_slot = 1
	hud.show_eliminated_banner(0)
	assert_true(hud.eliminated_banner_text().begins_with("Eliminated by "))
	assert_true(hud._eliminated_label.get_theme_font_size("font_size") > 0)


func test_reach_the_sky_height_line_shows_the_target() -> void:
	var hud: HUD = _make_hud()
	hud._mode_state = {"mode_id": MatchConfig.GameMode.REACH_THE_SKY}
	hud.set_height(3.14159)
	assert_eq(hud._height_label.text, "Height: 3.14 m / 100 m")
	hud.set_tower_and_block_height(3.0, 12.0)
	assert_eq(hud._height_label.text, "Tower: 3.00 m / 100 m   Block: 12.0 m")
	assert_eq(HUD.sky_target_suffix({"mode_id": MatchConfig.GameMode.CLASSIC}), "")


func test_set_territory_shares_builds_one_row_per_player_with_matching_width() -> void:
	var hud: HUD = _make_hud()
	hud.set_territory_shares(PackedFloat32Array([0.25, 0.75]))
	assert_eq(hud._share_bars.size(), 2)
	var bar0: ShareBar = hud._share_bars[0]
	var bar1: ShareBar = hud._share_bars[1]
	assert_almost_eq(bar0.fraction, 0.25, 0.0001)
	assert_almost_eq(bar1.fraction, 0.75, 0.0001)
	assert_eq(bar0.get_child_count(), 0, "the fill is drawn inside the track control, not a child bar")
	assert_true((hud._share_labels[0] as Label).text.contains("25"))
	assert_true((hud._share_labels[1] as Label).text.contains("75"))


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


## Texts of the toasts currently on screen, oldest first.
func _toast_texts(hud: HUD) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for entry: Dictionary in hud._toasts._active:
		out.append((entry["label"] as Label).text)
	return out


## The on-screen toast whose text contains `needle` (case-insensitive), or null.
func _toast(hud: HUD, needle: String) -> Label:
	for entry: Dictionary in hud._toasts._active:
		var label: Label = entry["label"] as Label
		if label.text.findn(needle) >= 0:
			return label
	return null


func test_toasts_stack_in_arrival_order_and_extra_ones_queue() -> void:
	var hud: HUD = _make_hud()
	hud._toasts.max_visible = 2
	hud.show_reject(&"a")
	hud.show_reject(&"b")
	hud.show_reject(&"c")
	assert_eq(_toast_texts(hud), PackedStringArray(["REJECTED: A", "REJECTED: B"]))
	assert_eq(hud._toasts._queue.size(), 1)
	hud.show_reject(&"a")
	assert_eq(_toast_texts(hud).size(), 2, "the same text restarts the showing toast, no duplicate")
	assert_eq(hud._toasts._queue.size(), 1)


func test_toasts_expire_in_order_and_promote_the_queue() -> void:
	var hud: HUD = _make_hud()
	hud._toasts.max_visible = 1
	hud._toasts.push("FIRST", Color.RED, HudCallout.Glyph.CROSS, 0.05, 0.05)
	hud._toasts.push("SECOND", Color.RED, HudCallout.Glyph.CROSS, 0.05, 0.05)
	assert_eq(_toast_texts(hud), PackedStringArray(["FIRST"]))
	await get_tree().create_timer(0.3).timeout
	assert_eq(_toast_texts(hud).size(), 0, "both have expired by now")
	assert_eq(hud._toasts._queue.size(), 0)
	hud._toasts.push("THIRD", Color.RED, HudCallout.Glyph.CROSS, 0.2, 0.05)
	hud._toasts.push("FOURTH", Color.RED, HudCallout.Glyph.CROSS, 0.2, 0.05)
	assert_eq(_toast_texts(hud), PackedStringArray(["THIRD"]), "the older toast shows first")
	await get_tree().create_timer(0.4).timeout
	assert_eq(_toast_texts(hud), PackedStringArray(["FOURTH"]), "the queued toast starts after the first expires")


func test_show_reject_sets_the_message() -> void:
	var hud: HUD = _make_hud()
	hud.show_reject(&"outside_territory")
	var label: Label = _toast(hud, "outside territory")
	assert_not_null(label)
	assert_almost_eq(label.modulate.a, 1.0, 0.001)


func test_placement_relocated_event_shows_relocated_only_for_the_active_slot() -> void:
	var hud: HUD = _make_hud()
	Events.turn_changed.emit(0)
	Events.placement_relocated.emit(1, Vector2(3.0, -2.0))
	assert_eq(
		_toast_texts(hud).size(), 0,
		"a relocation for a different slot shouldn't show on this hot-seat HUD."
	)
	Events.placement_relocated.emit(0, Vector2(3.0, -2.0))
	assert_not_null(_toast(hud, "relocated"))


func test_a_tied_results_payload_announces_a_shared_win() -> void:
	var hud: HUD = _make_hud()
	Events.match_won.emit(0)
	assert_eq(hud._winner_label.text, "Team 1 wins!")
	Events.match_results_ready.emit({
		"winner_kind": MatchStats.WINNER_KIND_TEAM, "winner_id": 0,
		"mode": {"winners": "0,1"},
	})
	assert_eq(hud._winner_label.text, "Teams 1 & 2 share the win!")


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


func test_process_shows_locked_when_the_local_slots_release_is_locked() -> void:
	var hud: HUD = _make_hud()
	var fake_match: FakeMatch = FakeMatch.new()
	fake_match.release_locked_by_slot[0] = true
	hud.match_provider = fake_match

	hud.set_local_slot(0)
	hud._process(0.0)

	assert_true(hud._locked)
	# the lock shows only as the greyed ring, never as text.
	assert_null(hud.find_child("LockedLabel", true, false))

	hud.set_local_slot(1)
	hud._process(0.0)

	assert_false(hud._locked)


# --- pending-special queue indicator ------------------------
# Drives the real Match/MatchGifts singleton, the same way
# tests/unit/gifts/test_gift_claim.gd does, rather than FakeMatch -- these tests
# are specifically about the indicator's read of held and next gifts.


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


func test_glue_overlay_clears_on_match_end_and_lobby() -> void:
	for to_state: int in [Match.State.END, Match.State.LOBBY]:
		var hud: HUD = _make_hud()
		var fake_match: FakeMatch = FakeMatch.new()
		hud.match_provider = fake_match
		hud.set_local_slot(0)
		fake_match.glue_drops_by_slot[0] = 5
		hud._refresh_special_indicator()
		assert_true(hud._glue_active)
		Events.match_state_changed.emit(Match.State.PLAYING, to_state)
		assert_false(hud._glue_active)


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


func test_special_indicator_ignores_a_claim_for_a_different_slot() -> void:
	var hud: HUD = _make_hud()
	hud.set_local_slot(0)

	Match._gifts._ensure_capacity(1)
	(Match._gifts._pending_queues[1] as Array).append(MatchGifts.PENDING_SPECIAL_ID)
	Events.gift_claimed.emit(0, 1, MatchGifts.PENDING_SPECIAL_ID)
	hud._process(0.0)

	assert_false(hud._special_indicator.visible, "a claim for another slot must not show on this HUD")


# --- claim toast -------------------------------------------------
#  "I grabbed a yellow cube but nothing seemed to happen": the
# claim itself already worked (the indicator tests above), but nothing told
# the player it had. show_gift_toast()/_on_gift_claimed() add a one-line
# "Special queued: <name>" message next to the pending-special indicator.

func test_gift_claimed_for_the_local_slot_shows_the_toast_with_the_special_name() -> void:
	var hud: HUD = _make_hud()
	hud.set_local_slot(0)

	Match._gifts._ensure_capacity(0)
	(Match._gifts._pending_queues[0] as Array).append(&"jumping_bean")
	Events.gift_claimed.emit(0, 0, &"jumping_bean")

	assert_eq(_toast_texts(hud), PackedStringArray(["SPECIAL QUEUED: JUMPING BEAN"]))
	assert_almost_eq(_toast(hud, "SPECIAL QUEUED").modulate.a, 1.0, 0.0001)


func _teams_2_config() -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
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
		_toast_texts(hud_slot0), PackedStringArray(["SPECIAL QUEUED: JUMPING BEAN"]),
		"team 0's claim must show on slot 0's own HUD"
	)
	assert_eq(
		_toast_texts(hud_slot2), PackedStringArray(["SPECIAL QUEUED: JUMPING BEAN"]),
		"team 0's claim must also show on its teammate slot 2's HUD"
	)


func test_gift_claimed_toast_skips_the_other_team_under_teams_2() -> void:
	var config: MatchConfig = _teams_2_config()
	var hud_slot1: HUD = _hud_for_slot(1, config)
	var hud_slot3: HUD = _hud_for_slot(3, config)

	Events.gift_claimed.emit(0, 0, &"jumping_bean")

	assert_eq(
		_toast_texts(hud_slot1).size(), 0,
		"team 1's slot 1 HUD must not react to a team 0 claim"
	)
	assert_eq(
		_toast_texts(hud_slot3).size(), 0,
		"team 1's slot 3 HUD must not react to a team 0 claim"
	)


# --- HUD minimap ------------------------------------
## Rebuilt after the report that the minimap was
## "reflecting the sky depending on the camera angle" --
## see ui/hud/Minimap.gd's own class doc DECISION for the root cause and fix.)


func test_domination_readout_only_in_domination() -> void:
	var hud: HUD = _make_hud()
	var dom: Dictionary = {"mode_id": MatchConfig.GameMode.DOMINATION, "scores": [0.25, 0.41], "extra": {}, "round_left": 125.0}
	hud._on_mode_state_changed(dom)
	assert_not_null(hud._mode_score_label)
	assert_eq(hud._mode_score_label.text, "Leading: 2 (41%)")
	var tied: Dictionary = {"mode_id": MatchConfig.GameMode.DOMINATION, "scores": [0.3, 0.3], "extra": {}, "round_left": 0.0}
	assert_eq(HUD.mode_score_text(tied), "Leading: 1 & 2 (30%)")
	var ctf: Dictionary = {"mode_id": MatchConfig.GameMode.CAPTURE_THE_FLAG, "scores": [1.0, 2.0], "extra": {}, "round_left": 0.0}
	assert_eq(HUD.mode_score_text(ctf).find("Leading"), -1)
	var hud2: HUD = _make_hud()
	assert_null(hud2._mode_score_label, "no readout without a mode state (Classic)")


# --- experiments line + gift-slot card glyph ----------------

const INPUT_GLYPH_SCENE: PackedScene = preload("res://ui/hud/InputGlyph.tscn")
const LAYOUT_SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(3440, 1440)]
const LAYOUT_SETTLE_FRAMES: int = 4
const LAYOUT_PLAYER_COUNT: int = 8
const EDGE_EPS: float = 1.0


## FakeMatch plus the two gift-slot reads the HUD polls (the real Match has them).
class GiftFakeMatch:
	extends FakeMatch

	var gift_head: StringName = &""
	var gift_count: int = 0

	func gift_slot_head(_slot_id: int) -> StringName:
		return gift_head

	func gift_slot_count(_slot_id: int) -> int:
		return gift_count


func _named_match(names: Array[String]) -> FakeMatch:
	var fake_match: FakeMatch = FakeMatch.new()
	for slot_id: int in range(names.size()):
		var slot: PlayerSlot = PlayerSlot.new(slot_id, slot_id, names[slot_id], Color.WHITE)
		fake_match.slots_by_id[slot_id] = slot
	var config: MatchConfig = MatchConfig.new()
	config.player_count = names.size()
	fake_match.config = config
	return fake_match


func test_rows_show_player_names_not_p_numbers() -> void:
	var hud: HUD = _make_hud()
	hud.match_provider = _named_match(["Tonyflow", "Mira"])
	hud.set_territory_shares(PackedFloat32Array([0.09, 0.5]))
	assert_eq((hud._share_name_labels[0] as Label).text, "Tonyflow")
	assert_eq((hud._share_name_labels[1] as Label).text, "Mira")
	assert_eq((hud._share_labels[0] as Label).text, "9%")
	assert_eq((hud._share_labels[1] as Label).text, "50%")
	for name_label: Label in hud._share_name_labels:
		assert_eq(name_label.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS, "long names ellipsize")


func test_ctf_rows_show_hold_time_and_no_separate_score_line() -> void:
	var hud: HUD = _make_hud()
	hud.match_provider = _named_match(["A", "B"])
	hud.set_territory_shares(PackedFloat32Array([0.4, 0.6]))
	var ctf: Dictionary = {"mode_id": MatchConfig.GameMode.CAPTURE_THE_FLAG, "scores": [58.0, 0.0], "extra": {}, "round_left": 209.0}
	hud._on_mode_state_changed(ctf)
	assert_eq((hud._share_labels[0] as Label).text, "58.0 s")
	assert_eq((hud._share_labels[1] as Label).text, "0.0 s")
	assert_null(hud._mode_score_label, "the round clock moved to the UiRoundTimer; no CTF status line is left")
	assert_eq(HUD.mode_status_text(ctf).find("58"), -1)


## a client gets sparse capture updates on a static board; the
## ring must rise between them at the hold rate, snap on each update, and stop.
func test_client_capture_ring_rises_between_sparse_updates_and_snaps() -> void:
	var hud: HUD = _make_hud()
	Events.goal_capture_progress.emit(0, 0.1)
	hud.extrapolate_capture(2.0, 20.0)
	assert_almost_eq(hud._capture_progress, 0.2, 0.0001)
	hud.extrapolate_capture(2.0, 20.0)
	assert_almost_eq(hud._capture_progress, 0.3, 0.0001, "monotonic rise")
	Events.goal_capture_progress.emit(0, 0.6)
	assert_almost_eq(hud._capture_progress, 0.6, 0.0001, "snaps to the received value")
	hud.extrapolate_capture(1000.0, 20.0)
	assert_almost_eq(hud._capture_progress, 1.0, 0.0001, "capped")


func test_scoreboard_marks_only_the_local_row_with_you() -> void:
	var hud: HUD = _make_hud()
	hud.set_territory_shares(PackedFloat32Array([0.5, 0.5]))
	hud.set_local_slot(1)
	assert_false((hud._share_you_labels[0] as Label).visible)
	assert_true((hud._share_you_labels[1] as Label).visible)
	assert_eq((hud._share_you_labels[1] as Label).get_theme_color("font_color"), hud._arcade.rim_color)


## a gift staged as the block AFTER next marks the NEXT label and leaves the
## next preview an ordinary block.
class StagedGiftFakeMatch:
	extends FakeMatch

	var staged_id: StringName = &""

	func after_next_special(_slot_id: int) -> StringName:
		return staged_id
