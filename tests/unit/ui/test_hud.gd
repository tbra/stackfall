extends GutTest
## HUD behaviour as a player sees it: the HUD is driven through its public API and the
## Events signals, and every assertion reads rendered Label text or node visibility found
## through the scene tree (unique names from HUD.tscn, child types, Label text).

const WAIT_MAX_S: float = 2.0
const TOAST_HOLD_S: float = 0.1
const TOAST_FADE_S: float = 0.05
const TEAMS_2_PLAYERS: int = 4


func before_each() -> void:
	# Match is a singleton that outlives this script: reset it so a lingering state
	# does not leak into the next test file.
	Match.abort_match()


func after_each() -> void:
	Match.abort_match()
	Settings._input(InputEventKey.new())


## Builds the HUD scene. `configure` (optional) runs before add_child, so tunings set there
## are in place when the HUD builds itself.
func _make_hud(configure: Callable = Callable()) -> HUD:
	var hud: HUD = autofree((load("res://ui/hud/HUD.tscn") as PackedScene).instantiate()) as HUD
	if configure.is_valid():
		configure.call(hud)
	add_child_autofree(hud)
	return hud


func _node(hud: HUD, unique_name: String) -> Node:
	return hud.get_node("%" + unique_name)


func _named_match(names: Array[String]) -> FakeMatchContext:
	var fake_match: FakeMatchContext = FakeMatchContext.new()
	for slot_id: int in range(names.size()):
		fake_match.slot_by_id[slot_id] = PlayerSlot.new(slot_id, slot_id, names[slot_id], Color.WHITE)
	var config: MatchConfig = MatchConfig.new()
	config.player_count = names.size()
	fake_match.config_value = config
	fake_match.slot_count_value = names.size()
	return fake_match


## Texts of the visible Labels under `root`, in tree order.
func _visible_texts(root: Node) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for node: Node in root.find_children("*", "Label", true, false):
		var label: Label = node as Label
		if label.visible:
			out.append(label.text)
	return out


## The stats rows (one per player), top to bottom.
func _rows(hud: HUD) -> Array[Node]:
	var rows: Array[Node] = []
	for child: Node in _node(hud, "SharesBox").get_children():
		if not child.is_queued_for_deletion():
			rows.append(child)
	return rows


## Texts of the toasts currently on screen, oldest first.
func _toast_texts(hud: HUD) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for child: Node in _node(hud, "ToastStack").get_children():
		if child is Label and not child.is_queued_for_deletion():
			out.append((child as Label).text)
	return out


func _toast(hud: HUD, needle: String) -> Label:
	for child: Node in _node(hud, "ToastStack").get_children():
		if child is Label and (child as Label).text.findn(needle) >= 0:
			return child as Label
	return null


func _special_indicator(hud: HUD) -> Label:
	return _node(hud, "SpecialIndicator") as Label


## `hud` showing the local slot `slot_id` of `config`'s match.
func _hud_for_slot(slot_id: int, config: MatchConfig) -> HUD:
	var hud: HUD = _make_hud()
	var fake_match: FakeMatchContext = FakeMatchContext.new()
	fake_match.config_value = config
	hud.match_context = fake_match
	hud.set_local_slot(slot_id)
	return hud


func test_eliminated_banner_names_the_eliminator_or_falls_back() -> void:
	var hud: HUD = _make_hud()
	var fake_match: FakeMatchContext = FakeMatchContext.new()
	fake_match.slot_by_id[0] = PlayerSlot.new(0, 0, "P1", Color.RED)
	fake_match.slot_by_id[1] = PlayerSlot.new(1, 1, "Rival", Color.BLUE)
	hud.match_context = fake_match
	hud.set_local_slot(0)
	var banner: Label = hud.find_child("EliminatedLabel", true, false) as Label
	assert_false(banner.visible, "no banner while alive")

	Events.player_eliminated.emit(1, 1)
	assert_false(banner.visible, "another player's elimination is not announced here")

	Events.player_eliminated.emit(0, 0)
	assert_true(banner.visible)
	assert_eq(banner.text, hud.hud_visual_tuning.eliminated_text, "plain wording when no eliminator is known")

	fake_match.eliminated_by_slot[0] = 1
	Events.player_eliminated.emit(0, 0)
	assert_eq(banner.text, hud.hud_visual_tuning.eliminated_by_text % "Rival")

	Events.match_state_changed.emit(Match.State.PLAYING, Match.State.LOBBY)
	assert_false(banner.visible, "the banner clears when the match leaves play")


func test_reach_the_sky_height_line_shows_the_target() -> void:
	var hud: HUD = _make_hud()
	var height_label: Label = _node(hud, "HeightLabel") as Label
	Events.mode_state_changed.emit({"mode_id": MatchConfig.GameMode.REACH_THE_SKY})
	hud.set_height(3.14159)
	assert_eq(height_label.text, "Height: 3.14 m / 100 m")
	hud.set_tower_and_block_height(3.0, 12.0)
	assert_eq(height_label.text, "Tower: 3.00 m / 100 m   Block: 12.0 m")
	Events.mode_state_changed.emit({"mode_id": MatchConfig.GameMode.CLASSIC})
	hud.set_height(3.14159)
	assert_eq(height_label.text, "Height: 3.14 m", "no target outside Reach the Sky")


func test_rows_show_player_names_and_shares_not_p_numbers() -> void:
	var hud: HUD = _make_hud()
	hud.match_context = _named_match(["Tonyflow", "Mira"])
	hud.set_territory_shares(PackedFloat32Array([0.09, 0.5]))
	var shown: PackedStringArray = _visible_texts(_node(hud, "SharesBox"))
	for text: String in ["Tonyflow", "9%", "Mira", "50%"]:
		assert_has(shown, text, "the stats show %s" % text)
	for text: String in shown:
		assert_false(text.begins_with("P") and text.length() <= 2, "no P-number labels: %s" % text)
	var mira_row: Node = null
	for row: Node in _rows(hud):
		if _visible_texts(row).has("Mira"):
			mira_row = row
	assert_not_null(mira_row, "Mira has a row")
	var bar: ShareBar = mira_row.find_children("*", "ShareBar", true, false)[0] as ShareBar
	assert_almost_eq(bar.fraction, 0.5, 0.0001, "the bar fills to the share")


func test_rows_mark_eliminated_players() -> void:
	var hud: HUD = _make_hud()
	var fake_match: FakeMatchContext = _named_match(["A", "B"])
	(fake_match.slot_by_id[1] as PlayerSlot).home_flag_alive = false
	hud.match_context = fake_match
	hud.set_territory_shares(PackedFloat32Array([0.6, 0.4]))
	var rows: Array[Node] = _rows(hud)
	assert_eq(_visible_texts(rows[0]), PackedStringArray(["A", "60%"]))
	var eliminated_texts: PackedStringArray = _visible_texts(rows[1])
	assert_true(eliminated_texts[eliminated_texts.size() - 1].findn("out") >= 0, "the eliminated row reads out")


func test_only_the_local_row_carries_the_you_marker() -> void:
	var hud: HUD = _make_hud()
	hud.match_context = _named_match(["A", "B"])
	hud.set_territory_shares(PackedFloat32Array([0.5, 0.5]))
	hud.set_local_slot(1)
	var rows: Array[Node] = _rows(hud)
	var you: String = hud.hud_visual_tuning.hud_you_text
	assert_false(_visible_texts(rows[0]).has(you))
	assert_true(_visible_texts(rows[1]).has(you))
	hud.set_local_slot(0)
	assert_true(_visible_texts(rows[0]).has(you), "the marker follows the local slot")
	assert_false(_visible_texts(rows[1]).has(you))


func test_ctf_rows_show_hold_time_and_no_separate_score_line() -> void:
	var hud: HUD = _make_hud()
	hud.match_context = _named_match(["A", "B"])
	hud.set_territory_shares(PackedFloat32Array([0.4, 0.6]))
	Events.mode_state_changed.emit({
		"mode_id": MatchConfig.GameMode.CAPTURE_THE_FLAG, "scores": [58.0, 0.0], "extra": {}, "round_left": 209.0,
	})
	var rows: Array[Node] = _rows(hud)
	assert_eq(_visible_texts(rows[0]), PackedStringArray(["A", "58.0 s"]))
	assert_eq(_visible_texts(rows[1]), PackedStringArray(["B", "0.0 s"]))
	for text: String in _visible_texts(_node(hud, "StatusPill")):
		assert_eq(text.find("58"), -1, "the hold time lives in the rows, not a status line")


func test_domination_readout_only_in_domination() -> void:
	var hud: HUD = _make_hud()
	var pill: Node = _node(hud, "StatusPill")
	assert_eq(_leading_texts(pill).size(), 0, "no readout without a mode state (Classic)")
	Events.mode_state_changed.emit({
		"mode_id": MatchConfig.GameMode.DOMINATION, "scores": [0.25, 0.41], "extra": {}, "round_left": 125.0,
	})
	assert_eq(_leading_texts(pill), PackedStringArray(["Leading: 2 (41%)"]))
	Events.mode_state_changed.emit({
		"mode_id": MatchConfig.GameMode.DOMINATION, "scores": [0.3, 0.3], "extra": {}, "round_left": 0.0,
	})
	assert_eq(_leading_texts(pill), PackedStringArray(["Leading: 1 & 2 (30%)"]), "a tie lists every leader")
	Events.mode_state_changed.emit({
		"mode_id": MatchConfig.GameMode.CAPTURE_THE_FLAG, "scores": [1.0, 2.0], "extra": {}, "round_left": 0.0,
	})
	assert_eq(_leading_texts(pill).size(), 0, "other modes show no Leading line")


func _leading_texts(root: Node) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for text: String in _visible_texts(root):
		if text.begins_with("Leading"):
			out.append(text)
	return out


func test_capture_ring_shows_only_while_someone_is_capturing() -> void:
	var hud: HUD = _make_hud()
	var ring: Control = _node(hud, "CaptureRing") as Control
	assert_false(ring.visible)
	Events.goal_capture_progress.emit(0, 0.5)
	assert_true(ring.visible)
	hud.extrapolate_capture(2.0, 20.0)
	assert_true(ring.visible, "a client's extrapolated rise keeps the ring up between updates")
	Events.goal_capture_progress.emit(-1, 0.0)
	assert_false(ring.visible)
	hud.extrapolate_capture(2.0, 20.0)
	assert_false(ring.visible, "nothing is being captured, so nothing rises")


func test_toasts_stack_in_arrival_order_and_extra_ones_queue() -> void:
	var hud: HUD = _make_hud()
	var max_visible: int = hud.hud_visual_tuning.toast_max_visible
	var reasons: Array[StringName] = [&"hole", &"off_disk", &"goal_zone", &"no_block", &"contested"]
	assert_gt(reasons.size(), max_visible, "fixture: more reasons than visible slots")
	var expected: PackedStringArray = PackedStringArray()
	for i: int in range(max_visible):
		expected.append(hud.reject_messages.message_for(reasons[i]))
	for reason: StringName in reasons:
		hud.show_reject(reason)
	assert_eq(_toast_texts(hud), expected, "the oldest messages show, in arrival order")
	hud.show_reject(reasons[0])
	assert_eq(_toast_texts(hud), expected, "the same text restarts the showing toast, no duplicate")


func test_toasts_expire_in_order_and_promote_the_queue() -> void:
	var hud: HUD = _make_hud(func(h: HUD) -> void:
		var tuning: HUDVisualTuning = h.hud_visual_tuning.duplicate() as HUDVisualTuning
		tuning.toast_max_visible = 1
		h.hud_visual_tuning = tuning
		var ghost: GhostTuning = h.ghost_tuning.duplicate() as GhostTuning
		ghost.hud_reject_message_duration = TOAST_HOLD_S
		ghost.hud_reject_fade_duration = TOAST_FADE_S
		h.ghost_tuning = ghost)
	var first: String = hud.reject_messages.message_for(&"hole")
	var second: String = hud.reject_messages.message_for(&"off_disk")
	hud.show_reject(&"hole")
	hud.show_reject(&"off_disk")
	assert_eq(_toast_texts(hud), PackedStringArray([first]), "only the older toast shows first")
	var promoted: bool = await wait_until(func() -> bool: return _toast_texts(hud) == PackedStringArray([second]), WAIT_MAX_S)
	assert_true(promoted, "the queued toast starts once the first expires")
	var cleared: bool = await wait_until(func() -> bool: return _toast_texts(hud).is_empty(), WAIT_MAX_S)
	assert_true(cleared, "and it expires in turn")


func test_toasts_show_only_for_the_local_slot() -> void:
	var hud: HUD = _make_hud()
	Events.turn_changed.emit(0)
	Events.placement_rejected.emit(1, &"outside_territory")
	Events.placement_relocated.emit(1, Vector2(3.0, -2.0))
	assert_eq(_toast_texts(hud).size(), 0, "another slot's refusal or relocation does not show here")
	Events.placement_rejected.emit(0, &"outside_territory")
	var reject: Label = _toast(hud, "inside your territory")
	assert_not_null(reject)
	assert_almost_eq(reject.modulate.a, 1.0, 0.001, "a fresh toast is fully visible")
	Events.placement_relocated.emit(0, Vector2(3.0, -2.0))
	assert_not_null(_toast(hud, "relocated"))


func test_a_tied_results_payload_announces_a_shared_win() -> void:
	var hud: HUD = _make_hud()
	var winner: Label = _node(hud, "WinnerLabel") as Label
	Events.match_won.emit(0)
	assert_eq(winner.text, "Team 1 wins!")
	Events.match_results_ready.emit({
		"winner_kind": MatchStats.WINNER_KIND_TEAM, "winner_id": 0,
		"mode": {"winners": "0,1"},
	})
	assert_eq(winner.text, "Teams 1 & 2 share the win!")


func test_release_locked_slot_greys_the_cards_and_shows_no_text() -> void:
	var hud: HUD = _make_hud()
	var fake_match: FakeMatchContext = FakeMatchContext.new()
	fake_match.release_locked_by_slot[0] = true
	hud.match_context = fake_match
	var held: Control = _node(hud, "HeldShapeCard") as Control
	var next: Control = _node(hud, "NextShapeCard") as Control

	hud.set_local_slot(0)
	await wait_frames(1)
	assert_almost_eq(held.modulate.a, hud.hud_visual_tuning.locked_card_alpha, 0.001)
	assert_almost_eq(next.modulate.a, hud.hud_visual_tuning.locked_card_alpha, 0.001)
	assert_null(hud.find_child("LockedLabel", true, false), "the lock shows only as the greyed cards")

	hud.set_local_slot(1)
	await wait_frames(1)
	assert_almost_eq(held.modulate.a, 1.0, 0.001, "a slot that is not locked draws its cards normally")


func test_glue_charges_show_beside_the_pending_special_and_clear_when_spent() -> void:
	var hud: HUD = _make_hud()
	var fake_match: FakeMatchContext = FakeMatchContext.new()
	hud.match_context = fake_match
	var indicator: Label = _special_indicator(hud)
	fake_match.glue_drops_by_slot[0] = 3
	hud.set_local_slot(0)
	assert_true(indicator.visible)
	assert_eq(indicator.text, "Glue ×3")
	fake_match.held_special_by_slot[0] = &"paintball"
	fake_match.pending_special_count_by_slot[0] = 1
	await wait_frames(1)
	assert_eq(indicator.text, "Paintball · Glue ×3")
	fake_match.glue_drops_by_slot[0] = 0
	fake_match.pending_special_count_by_slot[0] = 0
	await wait_frames(1)
	assert_false(indicator.visible, "nothing queued and no glue left")


func test_special_indicator_follows_a_claim_for_the_local_slot_only() -> void:
	var hud: HUD = _make_hud()
	var fake_match: FakeMatchContext = FakeMatchContext.new()
	hud.match_context = fake_match
	hud.set_local_slot(0)
	var indicator: Label = _special_indicator(hud)
	assert_false(indicator.visible)

	# A claim for another slot leaves this HUD alone.
	fake_match.pending_special_count_by_slot[1] = 1
	Events.gift_claimed.emit(0, 1, MatchGifts.PENDING_SPECIAL_ID)
	await wait_frames(1)
	assert_false(indicator.visible, "a claim for another slot must not show on this HUD")

	fake_match.pending_special_count_by_slot[0] = 1
	Events.gift_claimed.emit(1, 0, MatchGifts.PENDING_SPECIAL_ID)
	assert_true(indicator.visible)
	assert_eq(indicator.text, "Special", "an unrevealed gift reads as a generic special")

	fake_match.held_special_by_slot[0] = &"jumping_bean"
	fake_match.pending_special_count_by_slot[0] = 2
	Events.gift_claimed.emit(2, 0, &"jumping_bean")
	assert_eq(indicator.text, "Hopper ×2", "a second queued special adds a count badge")


func test_gift_claim_toast_reaches_the_claiming_team_only() -> void:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.player_count = TEAMS_2_PLAYERS
	config.team_mode = MatchConfig.TeamMode.TEAMS_2
	var claimer: HUD = _hud_for_slot(0, config)
	var teammate: HUD = _hud_for_slot(2, config)
	var rival_a: HUD = _hud_for_slot(1, config)
	var rival_b: HUD = _hud_for_slot(3, config)

	Events.gift_claimed.emit(0, 0, &"jumping_bean")

	var expected: PackedStringArray = PackedStringArray(["SPECIAL QUEUED: HOPPER"])
	assert_eq(_toast_texts(claimer), expected)
	assert_eq(_toast_texts(teammate), expected, "a teammate sees the team's claim")
	assert_eq(_toast_texts(rival_a).size(), 0, "the other team does not")
	assert_eq(_toast_texts(rival_b).size(), 0, "the other team does not")
	assert_almost_eq(_toast(claimer, "SPECIAL QUEUED").modulate.a, 1.0, 0.0001)


func test_glue_overlay_clears_on_match_end_and_lobby() -> void:
	for to_state: int in [Match.State.END, Match.State.LOBBY]:
		var hud: HUD = _make_hud()
		var fake_match: FakeMatchContext = FakeMatchContext.new()
		hud.match_context = fake_match
		hud.set_local_slot(0)
		fake_match.glue_drops_by_slot[0] = 5
		await wait_frames(1)
		assert_true(hud.glue_overlay.active)
		Events.match_state_changed.emit(Match.State.PLAYING, to_state)
		assert_false(hud.glue_overlay.active)
