extends GutTest
## Bontago-1pi.69: the hold-to-show scoreboard (ui/ScoreboardOverlay.gd, action
## show_scores = Tab / right-stick click). Press shows it during a live round,
## release hides it; the Back + R3 perf chord, a paused menu, a sandbox and a
## non-live state never show it.

const SCENE: PackedScene = preload("res://ui/ScoreboardOverlay.tscn")


class FakeStats:
	extends RefCounted
	var payload: Dictionary = {}

	func live_payload() -> Dictionary:
		return payload


class ScoreFakeMatch:
	extends RefCounted
	var config: MatchConfig = MatchConfig.new()
	var fake_stats: FakeStats = FakeStats.new()
	var current_state: MatchAutoload.State = MatchAutoload.State.PLAYING

	func state() -> MatchAutoload.State:
		return current_state

	func stats() -> FakeStats:
		return fake_stats


var _overlay: ScoreboardOverlay = null
var _match: ScoreFakeMatch = null


func before_each() -> void:
	_match = ScoreFakeMatch.new()
	_match.fake_stats.payload = _live_payload()
	_overlay = SCENE.instantiate() as ScoreboardOverlay
	_overlay.match_provider = _match
	add_child_autofree(_overlay)


func after_each() -> void:
	Input.action_release(&"show_scores")
	Input.action_release(&"camera_snap_home")
	Input.flush_buffered_events()
	Settings.set_active_input_device_for_test(Settings.DEFAULT_ACTIVE_DEVICE)


func _live_payload() -> Dictionary:
	return {
		"winner_kind": MatchStats.WINNER_KIND_SLOT, "winner_id": -1, "winner_name": "",
		"match_duration": 12.0, "live": true,
		"rows": [
			{
				"slot_id": 0, "name": "Ann", "team_id": 0, "is_bot": false, "blocks_placed": 4,
				"blocks_lost": 1, "gifts_claimed": 1, "specials_used": 1, "territory_share": 0.6,
				"eliminated_at": -1.0, "height": 2.5, "peak_territory": 0.7, "wins": 2,
			},
			{
				"slot_id": 1, "name": "Bo", "team_id": 1, "is_bot": true, "blocks_placed": 3,
				"blocks_lost": 0, "gifts_claimed": 0, "specials_used": 0, "territory_share": 0.2,
				"eliminated_at": 9.0, "height": 1.0, "peak_territory": 0.3, "wins": 0,
			},
		],
	}


func _key(pressed: bool) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_TAB
	event.physical_keycode = KEY_TAB
	event.pressed = pressed
	return event


func _pad(pressed: bool) -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = -1
	event.button_index = JOY_BUTTON_RIGHT_STICK
	event.pressed = pressed
	return event


func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await get_tree().process_frame


func test_action_has_tab_and_right_stick_defaults() -> void:
	assert_true(InputMap.has_action(&"show_scores"))
	assert_true(_key(true).is_action_pressed(&"show_scores"))
	assert_true(_pad(true).is_action_pressed(&"show_scores"))
	assert_false(_pad(true).is_action_pressed(&"use_gift_slot"), "R3 no longer spends a gift")
	var has_pad_gift: bool = false
	for event: InputEvent in InputMap.action_get_events(&"use_gift_slot"):
		has_pad_gift = has_pad_gift or event is InputEventJoypadButton
	assert_true(has_pad_gift, "use_gift_slot keeps a pad binding")


func test_tab_shows_while_held_and_hides_on_release() -> void:
	assert_false(_overlay.is_showing())
	await _send(_key(true))
	assert_true(_overlay.is_showing())
	await _send(_key(false))
	assert_false(_overlay.is_showing())


func test_right_stick_click_shows_while_held_and_hides_on_release() -> void:
	await _send(_pad(true))
	assert_true(_overlay.is_showing())
	await _send(_pad(false))
	assert_false(_overlay.is_showing())


func test_back_plus_r3_perf_chord_does_not_show_the_scoreboard() -> void:
	Input.action_press(&"camera_snap_home")
	await _send(_pad(true))
	assert_false(_overlay.is_showing())


func test_table_shows_the_live_rows_with_alive_status() -> void:
	await _send(_key(true))
	var rows: VBoxContainer = _overlay.get_node("%RowsList") as VBoxContainer
	assert_eq(rows.get_child_count(), 3, "header + one row per player")
	var texts: PackedStringArray = PackedStringArray()
	for cell: Node in (rows.get_child(1).get_child(0) as HBoxContainer).get_children():
		texts.append((cell as Label).text)
	assert_has(texts, "Ann")
	assert_has(texts, "Alive", "a live round says Alive, not Survived")
	assert_has(texts, "2", "wins column and placed/height columns come from the shared table")


func test_hidden_when_not_live_paused_suppressed_or_focus_lost() -> void:
	_match.current_state = MatchAutoload.State.END
	await _send(_key(true))
	assert_false(_overlay.is_showing(), "results screen owns the END state")
	await _send(_key(false))

	_match.current_state = MatchAutoload.State.PLAYING
	_overlay.suppressed = true
	await _send(_key(true))
	assert_false(_overlay.is_showing(), "sandbox keeps Tab for sandbox_next_slot")
	await _send(_key(false))
	_overlay.suppressed = false

	await _send(_key(true))
	assert_true(_overlay.is_showing())
	Events.pause_menu_opened.emit()
	assert_false(_overlay.is_showing(), "pause hides it")
	await _send(_key(false))
	Events.pause_menu_closed.emit()

	await _send(_key(true))
	assert_true(_overlay.is_showing())
	_overlay.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_false(_overlay.is_showing(), "focus loss hides it")
	await _send(_key(false))
