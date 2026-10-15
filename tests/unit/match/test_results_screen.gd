extends GutTest
## ui/menus/ResultsScreen (Bontago-1pi.6): headline, rows, buttons and gamepad focus over match_results_ready.

const RESULTS_SCREEN_SCENE: PackedScene = preload("res://ui/menus/ResultsScreen.tscn")


## Records request_replay()/request_return_to_lobby() calls instead of
## reaching net/MatchNet.gd's real RPC machinery (which needs an actual
## MultiplayerAPI peer) -- match_net_provider is a `Variant` seam for exactly
## this reason.
class FakeMatchNet:
	extends RefCounted
	var replay_calls: int = 0
	var return_to_lobby_calls: int = 0

	func request_replay() -> void:
		replay_calls += 1

	func request_return_to_lobby() -> void:
		return_to_lobby_calls += 1


var _screen: ResultsScreen = null
var _fake_net: FakeNet = null
var _fake_match_net: FakeMatchNet = null
var _fake_match: FakeMatch = null


func before_each() -> void:
	_screen = autofree(RESULTS_SCREEN_SCENE.instantiate())
	add_child_autofree(_screen)
	_fake_net = FakeNet.host()
	_fake_match_net = FakeMatchNet.new()
	_fake_match = FakeMatch.new()
	_fake_match.config = MatchConfig.new()
	_screen.net_provider = _fake_net
	_screen.match_net_provider = _fake_match_net
	_screen.match_provider = _fake_match


## Bontago-1pi.15.1: this file's own gamepad D-pad/A/B tests route real
## InputEventJoypadButton events through Input.parse_input_event(), which
## flips the Settings autoload's own active_input_device() to DEVICE_GAMEPAD
## as a side effect -- reset it so a later test file in the same run doesn't
## inherit gamepad mode from this one (tests/unit/ui/test_options_menu.gd's own
## after_each() already does this for its own gamepad tests).
func after_each() -> void:
	Settings.set_active_input_device_for_test(Settings.DEFAULT_ACTIVE_DEVICE)


func _ffa_results(winner_slot: int = 0) -> Dictionary:
	return {
		"winner_kind": MatchStats.WINNER_KIND_SLOT,
		"winner_id": winner_slot,
		"winner_name": "Alice",
		"match_duration": 120.0,
		"rows": [
			{
				"slot_id": 0, "name": "Alice", "team_id": 0, "is_bot": false,
				"blocks_placed": 10, "blocks_lost": 1, "gifts_claimed": 2, "specials_used": 1,
				"territory_share": 0.6, "eliminated_at": MatchStats.NOT_ELIMINATED,
			},
			{
				"slot_id": 1, "name": "Bob", "team_id": 1, "is_bot": false,
				"blocks_placed": 8, "blocks_lost": 3, "gifts_claimed": 0, "specials_used": 0,
				"territory_share": 0.3, "eliminated_at": MatchStats.NOT_ELIMINATED,
			},
			{
				"slot_id": 2, "name": "Bot 1", "team_id": 2, "is_bot": true,
				"blocks_placed": 4, "blocks_lost": 5, "gifts_claimed": 0, "specials_used": 0,
				"territory_share": 0.1, "eliminated_at": 50.0,
			},
		],
	}


func _team_results() -> Dictionary:
	return {
		"winner_kind": MatchStats.WINNER_KIND_TEAM,
		"winner_id": 1,
		"winner_name": "Team 2",
		"match_duration": 200.0,
		"rows": [
			{
				"slot_id": 0, "name": "Alice", "team_id": 0, "is_bot": false,
				"blocks_placed": 5, "blocks_lost": 0, "gifts_claimed": 0, "specials_used": 0,
				"territory_share": 0.4, "eliminated_at": MatchStats.NOT_ELIMINATED,
			},
			{
				"slot_id": 1, "name": "Bob", "team_id": 1, "is_bot": false,
				"blocks_placed": 6, "blocks_lost": 0, "gifts_claimed": 0, "specials_used": 0,
				"territory_share": 0.6, "eliminated_at": MatchStats.NOT_ELIMINATED,
			},
		],
	}


# --- CTF tie: every tied team is a winner -----------------------------------

func test_a_tie_highlights_every_tied_team_row() -> void:
	var results: Dictionary = _team_results()
	results["winner_id"] = 0
	results["winner_name"] = "Team 1"
	results["mode"] = {"mode_id": MatchConfig.GameMode.CAPTURE_THE_FLAG, "scores": [5.0, 5.0], "winners": "0,1"}
	var rows: Array[Dictionary] = ResultsScreen.sorted_rows(results)
	assert_true(bool(rows[0].get("is_winner")))
	assert_true(bool(rows[1].get("is_winner")), "the second tied team is a winner too")
	assert_eq(ResultsScreen.shared_winners_text(results), "Teams 1 & 2 share the win!")


# --- Headline: the reported defect ------------------------------------------

func test_team_headline_uses_the_team_name() -> void:
	_screen.show_results(_team_results())
	assert_eq(_screen._headline.text, "Team 2 wins!")


# --- Stats table: one row per player, sorted, winner highlighted -----------

# Bontago-1t5.45: a bot row names its tier, a human row does not; a client's config
# (round-tripped through to_dict/from_dict like the replicated one) shows the same tier.
func _name_text_of_row(index: int) -> String:
	var panel: PanelContainer = _screen._rows_list.get_child(index) as PanelContainer
	return ((panel.get_child(0) as HBoxContainer).get_child(0) as Label).text


func _tag_text_of_row(index: int) -> String:
	var panel: PanelContainer = _screen._rows_list.get_child(index) as PanelContainer
	var tag: Label = ((panel.get_child(0) as HBoxContainer).get_child(0) as Label).get_node_or_null("BotTag") as Label
	return tag.text if tag != null else ""


func test_bot_row_shows_its_difficulty_and_human_rows_do_not() -> void:
	_fake_match.config.slot_ai_difficulties = PackedInt32Array([
		MatchConfig.AiDifficulty.NORMAL, MatchConfig.AiDifficulty.NORMAL, MatchConfig.AiDifficulty.HARD,
	])
	_screen.show_results(_ffa_results())
	assert_eq(_name_text_of_row(1), "Alice")
	assert_eq(_name_text_of_row(2), "Bob")
	assert_eq(_name_text_of_row(3), "Bot 1")
	assert_eq(_tag_text_of_row(3), "(Bot, Hard)")
	assert_eq(_tag_text_of_row(1), "", "a human row has no tag")


# --- Host/client gate ---------------------------------------------------------

func test_host_sees_enabled_buttons_and_no_waiting_hint() -> void:
	_fake_net.is_host_value = true
	_screen.show_results(_ffa_results())
	assert_false(_screen._replay_button.disabled)
	assert_false(_screen._lobby_button.disabled)
	assert_false(_screen._waiting_hint.visible)


# --- Focus chain: gamepad/keyboard navigability -----------------------------

func test_gamepad_dpad_down_moves_focus_to_the_next_button() -> void:
	_screen.show_results(_ffa_results())
	_screen._replay_button.grab_focus()
	assert_true(_screen._replay_button.has_focus(), "fixture: focus starts on Replay.")

	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = -1
	event.button_index = JOY_BUTTON_DPAD_DOWN
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame

	assert_true(_screen._lobby_button.has_focus(), "a synthetic gamepad D-pad-down press must move focus along the wired chain.")


# --- Gamepad parity (Bontago-1pi.15.1: "gamepad works in some menus but not
# all; B never goes back in any menu") ------------------------------------------

func test_gamepad_a_activates_the_focused_replay_button() -> void:
	_screen.show_results(_ffa_results())
	assert_true(_screen._replay_button.has_focus(), "fixture: focus starts on Replay.")

	var press: InputEventJoypadButton = InputEventJoypadButton.new()
	press.device = -1
	press.button_index = JOY_BUTTON_A
	press.pressed = true
	Input.parse_input_event(press)
	var release: InputEventJoypadButton = InputEventJoypadButton.new()
	release.device = -1
	release.button_index = JOY_BUTTON_A
	release.pressed = false
	Input.parse_input_event(release)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(_fake_match_net.replay_calls, 1, "gamepad A on the focused Replay button must activate it via ui_accept.")


# --- Bontago-1pi.72.1 --------------------------------------------------------

## Pause menu open when the round ends: it closes itself, and once it is closed
## the results own the cursor and focus again.
func test_pause_menu_open_at_round_end_leaves_results_interactive() -> void:
	var pause: PauseMenu = autofree((load("res://ui/menus/PauseMenu.tscn") as PackedScene).instantiate())
	add_child_autofree(pause)
	pause._open()
	assert_true(pause.visible)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Events.match_results_ready.emit(_ffa_results())
	assert_false(pause.visible, "results close the pause menu")
	# Simulate PlayerController re-capturing the mouse on pause_menu_closed.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_screen._on_pause_menu_closed()
	await get_tree().process_frame
	assert_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE, "cursor usable on results")
	assert_true(_screen._replay_button.has_focus(), "results regain focus")
	var press: InputEventJoypadButton = InputEventJoypadButton.new()
	press.device = -1
	press.button_index = JOY_BUTTON_A
	press.pressed = true
	Input.parse_input_event(press)
	var release: InputEventJoypadButton = InputEventJoypadButton.new()
	release.device = -1
	release.button_index = JOY_BUTTON_A
	Input.parse_input_event(release)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_fake_match_net.replay_calls, 1, "gamepad A reaches the results after the pause menu closed")


# --- Bontago-1pi.25.1 Domination ---------------------------------------------

func test_domination_results_show_shares_and_winners() -> void:
	var results: Dictionary = _team_results()
	results["mode"] = {"mode_id": MatchConfig.GameMode.DOMINATION, "scores": [0.4, 0.6], "winners": "1"}
	var text: String = ResultsScreen.mode_outcome_text(results)
	assert_true(text.find("60%") >= 0 and text.find("40%") >= 0)
	assert_eq(ResultsScreen.mode_title(results), "Domination")
	assert_eq(ResultsScreen.winner_ids(results), PackedInt32Array([1]))


# --- Stackfall Arcade table (Bontago-hfa.7) ----------------------------------
