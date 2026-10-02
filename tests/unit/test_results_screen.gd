extends GutTest
## ui/ResultsScreen.gd (Bontago-1pi.6, owner playtest: "the win screen always
## says 'Team x wins!' even when not playing in teams"). Reads Events.
## match_results_ready's payload (autoload/match/MatchStats.gd's own header
## documents the shape) and never assumes team_mode -- these tests drive
## show_results() directly with a hand-built payload, the same "call the
## handler, don't fake the signal" style tests/unit/test_pause_menu.gd uses.

const RESULTS_SCREEN_SCENE: PackedScene = preload("res://ui/ResultsScreen.tscn")


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
## inherit gamepad mode from this one (tests/unit/test_options_menu.gd's own
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


func test_single_winner_rows_unchanged_without_a_winners_list() -> void:
	var rows: Array[Dictionary] = ResultsScreen.sorted_rows(_team_results())
	assert_true(bool(rows[0].get("is_winner")))
	assert_eq(int(rows[0].get("team_id")), 1)
	assert_false(bool(rows[1].get("is_winner")))


# --- Headline: the reported defect ------------------------------------------

func test_ffa_headline_uses_the_winning_players_own_name() -> void:
	_screen.show_results(_ffa_results())
	assert_eq(_screen._headline.text, "Alice wins!", "FFA must name the winning player, never 'Team N'.")


func test_team_headline_uses_the_team_name() -> void:
	_screen.show_results(_team_results())
	assert_eq(_screen._headline.text, "Team 2 wins!")


func test_no_winner_reads_as_a_draw() -> void:
	var results: Dictionary = _ffa_results()
	results["winner_id"] = -1
	results["winner_name"] = ""
	_screen.show_results(results)
	assert_eq(_screen._headline.text, "It's a draw!")


# --- Stats table: one row per player, sorted, winner highlighted -----------

func test_sorted_rows_orders_winner_first_then_survivors_then_eliminated() -> void:
	var rows: Array[Dictionary] = ResultsScreen.sorted_rows(_ffa_results())
	assert_eq(rows.size(), 3)
	assert_eq(int(rows[0].get("slot_id")), 0, "the winner must be first.")
	assert_true(bool(rows[0].get("is_winner")))
	assert_eq(int(rows[1].get("slot_id")), 1, "the surviving non-winner ranks next.")
	assert_false(bool(rows[1].get("is_winner")))
	assert_eq(int(rows[2].get("slot_id")), 2, "the eliminated bot ranks last.")


func test_populate_rows_builds_one_panel_per_player_plus_a_header() -> void:
	_screen.show_results(_ffa_results())
	assert_eq(_screen._rows_list.get_child_count(), 4, "header row + 3 player rows.")
	var winner_panel: PanelContainer = _screen._rows_list.get_child(1) as PanelContainer
	assert_true(bool(winner_panel.get_meta(&"is_winner")), "the winner's row must be flagged/highlighted.")
	assert_eq(int(winner_panel.get_meta(&"slot_id")), 0)
	var other_panel: PanelContainer = _screen._rows_list.get_child(2) as PanelContainer
	assert_false(bool(other_panel.get_meta(&"is_winner")))


# --- Host/client gate ---------------------------------------------------------

func test_host_sees_enabled_buttons_and_no_waiting_hint() -> void:
	_fake_net.is_host_value = true
	_screen.show_results(_ffa_results())
	assert_false(_screen._replay_button.disabled)
	assert_false(_screen._lobby_button.disabled)
	assert_false(_screen._settings_button.disabled)
	assert_false(_screen._waiting_hint.visible)


func test_client_sees_disabled_buttons_and_a_waiting_hint() -> void:
	_fake_net.is_host_value = false
	_screen.show_results(_ffa_results())
	assert_true(_screen._replay_button.disabled, "a client must not be able to restart the match locally.")
	assert_true(_screen._lobby_button.disabled)
	assert_true(_screen._settings_button.disabled)
	assert_true(_screen._waiting_hint.visible, "a client needs to know why its buttons are inert.")


func test_replay_button_calls_match_net_request_replay() -> void:
	_screen.show_results(_ffa_results())
	_screen._on_replay_pressed()
	assert_eq(_fake_match_net.replay_calls, 1)


func test_lobby_button_calls_match_net_request_return_to_lobby() -> void:
	_screen.show_results(_ffa_results())
	_screen._on_lobby_pressed()
	assert_eq(_fake_match_net.return_to_lobby_calls, 1)


func test_a_new_match_state_hides_the_screen() -> void:
	_screen.show_results(_ffa_results())
	assert_true(_screen.visible)
	_screen._on_match_state_changed(Match.State.END, Match.State.LOBBY)
	assert_false(_screen.visible, "a Back-to-lobby/Replay restart must take this overlay down.")


# --- Quick settings: edits MatchConfig, sanitized ---------------------------

func test_settings_apply_writes_sanitized_fields_onto_the_running_config() -> void:
	_fake_match.config.player_count = 2
	_screen.show_results(_ffa_results())

	_screen._block_timer_spin.value = 9.0
	_screen._gravity_spin.value = 1.2
	_screen._special_freq_spin.value = 60
	_screen._gifts_check.button_pressed = false
	_screen._ai_count_spin.value = 8  # spin's own max; sanitize() must clamp to player_count.
	_screen._ai_difficulty_option.selected = MatchConfig.AiDifficulty.HARD

	_screen._on_settings_apply_pressed()

	var config: MatchConfig = _fake_match.config
	assert_eq(config.block_timer, 9.0)
	assert_eq(config.gravity_multiplier, 1.2)
	assert_eq(config.special_frequency, 60)
	assert_false(config.gifts_enabled)
	assert_eq(config.ai_count, 2, "sanitize() must clamp ai_count down to player_count.")
	assert_eq(config.ai_difficulty, MatchConfig.AiDifficulty.HARD)
	assert_false(_screen._settings_panel.visible, "Apply must close the panel.")


func test_settings_button_disabled_on_client_keeps_the_panel_unreachable() -> void:
	_fake_net.is_host_value = false
	_screen.show_results(_ffa_results())
	assert_true(_screen._settings_button.disabled)


# --- Focus chain: gamepad/keyboard navigability -----------------------------

func test_focus_chain_wraps_top_and_bottom() -> void:
	_screen.show_results(_ffa_results())
	var replay: Button = _screen._replay_button
	var lobby: Button = _screen._lobby_button
	var settings: Button = _screen._settings_button

	assert_eq(replay.get_node(replay.focus_neighbor_bottom), lobby)
	assert_eq(lobby.get_node(lobby.focus_neighbor_bottom), settings)
	assert_eq(settings.get_node(settings.focus_neighbor_bottom), replay, "the chain must wrap.")


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

func test_showing_results_grabs_focus_on_the_host() -> void:
	_screen.show_results(_ffa_results())
	assert_not_null(get_viewport().gui_get_focus_owner(), "the results screen must land focus somewhere as soon as it shows for the host.")
	assert_true(_screen._replay_button.has_focus())


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


## Bontago-1pi.15.1: %SettingsPanel is the one popup this screen owns; gamepad
## B must close it (ui/ResultsScreen.gd's new _unhandled_input()), the same
## "popups close with B" contract ui/Lobby.gd's advanced-rules popup and
## ui/OptionsMenu.gd's own Back both already follow.
func test_gamepad_b_closes_the_settings_panel_via_real_binding() -> void:
	_screen.show_results(_ffa_results())
	_screen._on_settings_pressed()
	assert_true(_screen._settings_panel.visible, "fixture: settings panel opened.")

	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = -1
	event.button_index = JOY_BUTTON_B
	event.pressed = true
	assert_true(event.is_action_pressed(&"ui_cancel"), "gamepad B should map to ui_cancel")
	_screen._unhandled_input(event)

	assert_false(_screen._settings_panel.visible, "gamepad B must close the settings panel.")


# --- Bontago-1pi.25.1 Domination ---------------------------------------------

func test_domination_results_show_shares_and_winners() -> void:
	var results: Dictionary = _team_results()
	results["mode"] = {"mode_id": MatchConfig.GameMode.DOMINATION, "scores": [0.4, 0.6], "winners": "1"}
	var text: String = ResultsScreen.mode_outcome_text(results)
	assert_true(text.find("Domination") >= 0 and text.find("60%") >= 0 and text.find("40%") >= 0)
	assert_eq(ResultsScreen.winner_ids(results), PackedInt32Array([1]))


func test_domination_early_end_falls_back_to_the_finish_winner() -> void:
	var results: Dictionary = _team_results()
	results["mode"] = {"mode_id": MatchConfig.GameMode.DOMINATION, "scores": [0.4, 0.6], "winners": ""}
	assert_eq(ResultsScreen.winner_ids(results), PackedInt32Array([1]), "empty winners -> winner_id")
	var rows: Array[Dictionary] = ResultsScreen.sorted_rows(results)
	assert_eq(int(rows[0].get("team_id")), 1)
	assert_true(bool(rows[0].get("is_winner")))
