extends GutTest
## HudShares: after refresh(shares, mode_state, active_slot) each team's share is readable
## as text under the container and in the bar's value; the active slot is marked "you" and a
## held-beacon multiplier shows its text. Found by class and text, never by child index.

const PALETTE: PackedColorArray = [Color.RED, Color.GREEN, Color.BLUE]
const NO_SLOT: int = -1
const EPSILON: float = 0.001

var _container: VBoxContainer
var _arcade: ArcadeVisualTuning = load("res://config/ui/arcade_visual_tuning.tres") as ArcadeVisualTuning
var _tuning: HUDVisualTuning = load("res://config/ui/hud_visual_tuning.tres") as HUDVisualTuning
var _fake: FakeMatchContext
var _shares: HudShares


func _no_roster_name(_slot_id: int) -> String:
	return ""


func before_each() -> void:
	_fake = FakeMatchContext.new()
	var config: MatchConfig = MatchConfig.new()
	config.player_count = PALETTE.size()
	_fake.config_value = config
	for slot_id: int in range(PALETTE.size()):
		_fake.slot_by_id[slot_id] = PlayerSlot.new(slot_id, slot_id, "Name%d" % slot_id, PALETTE[slot_id])
	_container = VBoxContainer.new()
	add_child_autofree(_container)
	var lookup: HudPlayerLookup = HudPlayerLookup.new(_fake, PALETTE, _no_roster_name)
	_shares = HudShares.new(_container, lookup, _arcade, _tuning)


func _visible_texts() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for node: Node in _container.find_children("*", "Label", true, false):
		var label: Label = node as Label
		if label.is_visible_in_tree() and not label.text.is_empty():
			out.append(label.text)
	return out


func _has_text(text: String) -> bool:
	return _visible_texts().has(text)


func _count_containing(fragment: String) -> int:
	var count: int = 0
	for text: String in _visible_texts():
		if text.contains(fragment):
			count += 1
	return count


func _bar_values() -> Array[float]:
	var values: Array[float] = []
	for node: Node in _container.find_children("*", "ShareBar", true, false):
		values.append((node as ShareBar).fraction)
	values.sort()
	return values


## Rows a refresh removes may be queue_free'd: let the frame end before reading.
func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _ctf_state(held: Dictionary = {}, scores: Array = [0.0, 0.0, 0.0]) -> Dictionary:
	var extra: Dictionary = {}
	for team: int in held:
		extra["held_%d" % team] = held[team]
	return {"mode_id": MatchConfig.GameMode.CAPTURE_THE_FLAG, "scores": scores, "extra": extra}


func test_each_share_reads_as_percent_text_and_bar_value() -> void:
	_shares.refresh(PackedFloat32Array([0.25, 0.75]), {}, NO_SLOT)
	assert_true(_has_text("25%"))
	assert_true(_has_text("75%"))
	var values: Array[float] = _bar_values()
	assert_eq(values.size(), 2)
	if values.size() == 2:
		assert_almost_eq(values[0], 0.25, EPSILON)
		assert_almost_eq(values[1], 0.75, EPSILON)


func test_each_team_shows_its_name() -> void:
	_shares.refresh(PackedFloat32Array([0.5, 0.5]), {}, NO_SLOT)
	assert_true(_has_text("Name0"))
	assert_true(_has_text("Name1"))


func test_a_changed_share_updates_text_and_bar() -> void:
	_shares.refresh(PackedFloat32Array([0.25, 0.75]), {}, NO_SLOT)
	_shares.refresh(PackedFloat32Array([0.6, 0.4]), {}, NO_SLOT)
	await _settle()
	assert_true(_has_text("60%"))
	assert_true(_has_text("40%"))
	assert_false(_has_text("25%"))
	assert_false(_has_text("75%"))
	var values: Array[float] = _bar_values()
	assert_eq(values.size(), 2)
	if values.size() == 2:
		assert_almost_eq(values[0], 0.4, EPSILON)
		assert_almost_eq(values[1], 0.6, EPSILON)


func test_a_team_that_drops_out_of_shares_no_longer_shows() -> void:
	_shares.refresh(PackedFloat32Array([0.25, 0.75]), {}, NO_SLOT)
	_shares.refresh(PackedFloat32Array([1.0]), {}, NO_SLOT)
	await _settle()
	assert_true(_has_text("100%"))
	assert_false(_has_text("75%"))
	assert_false(_has_text("Name1"))
	assert_true(_has_text("Name0"))


func test_empty_shares_show_no_team() -> void:
	_shares.refresh(PackedFloat32Array([0.5, 0.5]), {}, NO_SLOT)
	assert_true(_has_text("Name0"), "fixture: rows exist first")
	_shares.refresh(PackedFloat32Array(), {}, NO_SLOT)
	await _settle()
	assert_false(_has_text("Name0"))
	assert_eq(_bar_values().size(), 0)


func test_refreshing_twice_with_the_same_input_changes_nothing() -> void:
	_shares.refresh(PackedFloat32Array([0.25, 0.75]), {}, 1)
	var before: PackedStringArray = _visible_texts()
	var bars: Array[float] = _bar_values()
	assert_gt(before.size(), 0)
	_shares.refresh(PackedFloat32Array([0.25, 0.75]), {}, 1)
	await _settle()
	assert_eq(_visible_texts(), before)
	assert_eq(_bar_values(), bars)


func test_active_slot_gets_exactly_one_you_marker() -> void:
	var you: String = _tuning.hud_you_text.strip_edges()
	_shares.refresh(PackedFloat32Array([0.5, 0.5, 0.0]), {}, NO_SLOT)
	assert_eq(_count_containing(you), 0, "no active slot, no marker")
	_shares.refresh(PackedFloat32Array([0.5, 0.5, 0.0]), {}, 1)
	assert_eq(_count_containing(you), 1)
	_shares.refresh(PackedFloat32Array([0.5, 0.5, 0.0]), {}, 0)
	assert_eq(_count_containing(you), 1, "the marker moves, it does not duplicate")


func test_you_marker_follows_the_active_slots_resolved_team() -> void:
	var config: MatchConfig = _fake.config_value
	config.team_mode = MatchConfig.TeamMode.TEAMS_2
	config.slot_team_ids = PackedInt32Array([0, 0, 1])
	config.team_numbers = PackedInt32Array([1, 2])
	var you: String = _tuning.hud_you_text.strip_edges()
	_shares.refresh(PackedFloat32Array([0.5, 0.5]), {}, 2)
	assert_eq(_count_containing(you), 1)
	_shares.refresh(PackedFloat32Array([0.5, 0.5]), {}, NO_SLOT)
	assert_eq(_count_containing(you), 0)


func test_multiplier_text_shows_for_a_team_holding_several_beacons() -> void:
	_shares.refresh(PackedFloat32Array([0.0, 0.0, 0.0]), _ctf_state({1: 3}), NO_SLOT)
	assert_true(_has_text("x3"))
	assert_eq(_count_containing("x"), 1, "only the holder has a multiplier")


func test_single_beacon_or_other_mode_shows_no_multiplier() -> void:
	_shares.refresh(PackedFloat32Array([0.5, 0.5, 0.0]), _ctf_state({0: 1}), NO_SLOT)
	assert_true(_has_text("Name0"), "fixture: rows exist")
	assert_eq(_count_containing("x"), 0)
	_shares.refresh(PackedFloat32Array([0.5, 0.5, 0.0]), {}, NO_SLOT)
	assert_eq(_count_containing("x"), 0)


func test_multiplier_disappears_when_the_state_loses_it() -> void:
	_shares.refresh(PackedFloat32Array([0.0, 0.0, 0.0]), _ctf_state({2: 2}), NO_SLOT)
	assert_true(_has_text("x2"))
	_shares.refresh(PackedFloat32Array([0.0, 0.0, 0.0]), _ctf_state(), NO_SLOT)
	assert_false(_has_text("x2"))


func test_capture_the_flag_shows_seconds_held_instead_of_percent() -> void:
	_shares.refresh(PackedFloat32Array([0.1, 0.2, 0.3]), _ctf_state({}, [12.5, 0.0, 3.0]), NO_SLOT)
	assert_true(_has_text("12.5 s"))
	assert_false(_has_text("10%"))


func test_reach_the_sky_shows_metres() -> void:
	var state: Dictionary = {"mode_id": MatchConfig.GameMode.REACH_THE_SKY, "scores": [4.5, 1.0]}
	_shares.refresh(PackedFloat32Array([0.5, 0.5]), state, NO_SLOT)
	assert_true(_has_text("4.5 m"))


func test_eliminated_team_is_marked_out() -> void:
	_fake.slot_by_id[1].home_flag_alive = false
	_shares.refresh(PackedFloat32Array([0.5, 0.5]), {}, NO_SLOT)
	assert_eq(_count_containing("(out)"), 1)
