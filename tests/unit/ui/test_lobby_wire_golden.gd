extends GutTest
## Golden wire dictionaries: what a host Lobby publishes through Net.set_lobby_data() and
## what its Start emits, for seven representative setups. The literals below are the wire
## format: a renamed, dropped or added MatchConfig.to_dict() key, or a changed default,
## fails here, so a lobby rebuild cannot change the wire by accident. Each setup is
## applied the way a host's lobby data arrives (Events.net_lobby_data_changed) and the
## publish is provoked by the host's own edit (the Experiments master toggle, pressed
## and restored), then Ready and Start are driven through the controls.

const SPECIAL_ON: StringName = &"rocket"

var _shared_before: Dictionary = {}


func before_each() -> void:
	_shared_before = LobbySettingsCard.QOL_SHARED.to_dict()


func after_each() -> void:
	for key: String in _shared_before:
		LobbySettingsCard.QOL_SHARED.set(key, _shared_before[key])


func _colors() -> PackedColorArray:
	return PackedColorArray([
		Color(0.9, 0.25, 0.25, 1), Color(0.25, 0.55, 0.95, 1), Color(0.35, 0.8, 0.4, 1),
		Color(0.95, 0.8, 0.25, 1), Color(0.7, 0.4, 0.9, 1), Color(0.95, 0.55, 0.2, 1),
		Color(0.3, 0.85, 0.85, 1), Color(0.95, 0.45, 0.75, 1),
	])


## The config half of the wire for two humans, no bots, every setting at its default
## (MatchConfig.to_dict() with no qol and no lobby extras).
func _config_dict(overrides: Dictionary = {}) -> Dictionary:
	var data: Dictionary = {
		"ai_count": 0,
		"ai_difficulty": 1,
		"allow_mid_match_join": false,
		"block_timer": 5.0,
		"disc_size_step": 2,
		"enabled_specials": [] as Array[StringName],
		"experiments_enabled": false,
		"game_mode": 0,
		"gifts_enabled": true,
		"goal_flag_count": 1,
		"gravity_multiplier": 1.0,
		"gravity_scale_version": 2,
		"hole_mode": 0,
		"match_timer_minutes": 0,
		"per_player_timer": true,
		"player_colors": _colors(),
		"player_count": 2,
		"rng_seed": -1,
		"round_timer_minutes": 5,
		"sky_start_phase": -1.0,
		"sky_team_sum": false,
		"sky_theme_mode": 3,
		"sky_theme_resolved": "",
		"sky_variation_seed": -1,
		"special_frequency": 30,
		"sudden_death": false,
		"sudden_death_seconds": 120,
		"team_mode": 0,
		"tilt_mode": 0,
		"turn_based": false,
		"weather_mode": 6,
	}
	data.merge(overrides, true)
	return data


func _qol_dict(overrides: Dictionary = {}) -> Dictionary:
	var data: Dictionary = {
		"backlog_enabled": false,
		"backlog_max": 2,
		"gift_loads_next": false,
		"gift_slot_capacity": 1,
		"gift_slot_enabled": false,
		"gift_slot_min_window_s": 2.0,
		"goal_radius_enabled": false,
		"goal_radius_multiplier": 2.0,
		"pause_event_s": 4.0,
		"pause_max_s": 10.0,
		"pause_tail_s": 1.5,
		"timer_pause_enabled": false,
		"timer_pause_on_special": true,
		"topple_moving_blocks_min": 4,
		"topple_scan_interval_s": 0.25,
		"topple_speed_threshold_mps": 1.5,
	}
	data.merge(overrides, true)
	return data


## What the host publishes: the config plus the qol block, the roster and the seat table.
func _published(config_overrides: Dictionary = {}, qol_overrides: Dictionary = {}) -> Dictionary:
	var data: Dictionary = _config_dict(config_overrides)
	data["qol"] = _qol_dict(qol_overrides)
	data["roster"] = [
		{"name": "Player", "peer_id": 1, "ready": true, "slot_id": 0},
		{"name": "Player", "peer_id": 2, "ready": true, "slot_id": 1},
	]
	data["seats"] = {
		"bots": [],
		"humans": [
			{"color": 0, "peer_id": 1, "team": 1},
			{"color": 1, "peer_id": 2, "team": 2},
		],
	}
	return data


## What Start emits: the config plus the qol block (and the team arrays when teams are on).
func _started(config_overrides: Dictionary = {}, qol_overrides: Dictionary = {}) -> Dictionary:
	var data: Dictionary = _config_dict(config_overrides)
	data["qol"] = _qol_dict(qol_overrides)
	return data


func _host_lobby() -> Lobby:
	var lobby: Lobby = autofree(load("res://ui/lobby/Lobby.tscn").instantiate())
	add_child_autofree(lobby)
	var fake: FakeNet = FakeNet.host({1: 0, 2: 1})
	fake.all_peers_ready_value = true
	lobby.net_provider = fake
	lobby._update_host_only_state()
	return lobby


## Drives one setup end to end and asserts the three wire views.
func _run(config: MatchConfig, config_overrides: Dictionary, qol_overrides: Dictionary = {}, started_extra: Dictionary = {}) -> void:
	var expected_config: Dictionary = _config_dict(config_overrides)
	if config.qol != null:
		expected_config["qol"] = _qol_dict(qol_overrides)
	assert_eq(config.to_dict(), expected_config, "MatchConfig.to_dict()")

	var lobby: Lobby = _host_lobby()
	var fake: FakeNet = lobby.net_provider as FakeNet
	Events.net_lobby_data_changed.emit(config.to_dict())
	assert_eq(fake.set_lobby_data_calls.size(), 0, "applying lobby data never publishes")

	var master: UiToggle = lobby.find_child("ExperimentsCheck", true, false) as UiToggle
	var was_on: bool = master.button_pressed
	master.button_pressed = not was_on
	master.button_pressed = was_on
	assert_eq(fake.set_lobby_data_calls.size(), 2, "one publish per host edit")
	var published: Dictionary = fake.set_lobby_data_calls[1]
	assert_eq(published, _published(config_overrides, qol_overrides), "set_lobby_data dictionary")

	(lobby.find_child("ReadyCheck", true, false) as CheckButton).button_pressed = true
	assert_eq(fake.set_local_ready_calls, [true] as Array[bool], "Ready reaches Net")
	watch_signals(lobby)
	(lobby.find_child("StartButton", true, false) as Button).pressed.emit()
	assert_signal_emitted(lobby, "start_requested")
	var started: MatchConfig = get_signal_parameters(lobby, "start_requested")[0]
	var expected_start: Dictionary = _started(config_overrides, qol_overrides)
	expected_start.merge(started_extra, true)
	assert_eq(started.to_dict(), expected_start, "start_requested config")


func _with_qol(config: MatchConfig) -> MatchConfig:
	config.qol = QolExperiments.new()
	return config


func _base() -> MatchConfig:
	var config: MatchConfig = MatchConfig.new()
	config.player_count = 2
	return _with_qol(config)


func test_classic() -> void:
	_run(_base(), {})


func test_team_mode() -> void:
	var config: MatchConfig = _base()
	config.team_mode = MatchConfig.TeamMode.TEAMS_2
	_run(config, {"team_mode": 1}, {}, {
		"slot_team_ids": PackedInt32Array([0, 1]),
		"team_numbers": PackedInt32Array([1, 2]),
	})


func test_timed_with_sudden_death() -> void:
	var config: MatchConfig = _base()
	config.match_timer_minutes = 10
	config.sudden_death = true
	config.sudden_death_seconds = 90
	_run(config, {"match_timer_minutes": 10, "sudden_death": true, "sudden_death_seconds": 90})


func test_elimination() -> void:
	var config: MatchConfig = _base()
	config.game_mode = MatchConfig.GameMode.ELIMINATION
	config.round_timer_minutes = 7
	config.hole_mode = MatchConfig.HoleMode.PERMANENT
	_run(config, {"game_mode": 2, "round_timer_minutes": 7, "hole_mode": 1})


func test_all_specials_off_uses_the_none_sentinel() -> void:
	var config: MatchConfig = _base()
	config.enabled_specials = [LobbySettingsCard.ALL_DISABLED_SENTINEL] as Array[StringName]
	_run(config, {"enabled_specials": [&"__none__"] as Array[StringName]})


func test_one_special_on() -> void:
	var config: MatchConfig = _base()
	config.enabled_specials = [SPECIAL_ON] as Array[StringName]
	_run(config, {"enabled_specials": [&"rocket"] as Array[StringName]})


func test_qol_on() -> void:
	var config: MatchConfig = _base()
	config.qol.timer_pause_enabled = true
	config.qol.backlog_enabled = true
	config.qol.goal_radius_enabled = true
	config.qol.gift_slot_enabled = true
	config.qol.gift_loads_next = true
	_run(config, {}, {
		"timer_pause_enabled": true,
		"backlog_enabled": true,
		"goal_radius_enabled": true,
		"gift_slot_enabled": true,
		"gift_loads_next": true,
	})
