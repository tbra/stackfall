extends GutTest
## lobby/loading UI cues play on their events.

var _config: AudioConfig


func before_each() -> void:
	_config = load("res://config/audio/audio_config.tres") as AudioConfig
	_stop_ui_players()


func after_each() -> void:
	_stop_ui_players()


## The menu-cue pool: the AudioStreamPlayer children right after the match-cue pool.
func _ui_players() -> Array[AudioStreamPlayer]:
	var players: Array[AudioStreamPlayer] = []
	var seen: int = 0
	for child: Node in Sfx.get_children():
		var player: AudioStreamPlayer = child as AudioStreamPlayer
		if player == null:
			continue
		seen += 1
		if seen > _config.max_simultaneous and players.size() < Sfx.UI_PLAYER_COUNT:
			players.append(player)
	return players


func _stop_ui_players() -> void:
	for player: AudioStreamPlayer in _ui_players():
		player.stop()


func _playing_data() -> Array[PackedByteArray]:
	var found: Array[PackedByteArray] = []
	for player: AudioStreamPlayer in _ui_players():
		var wav: AudioStreamWAV = player.stream as AudioStreamWAV
		if player.playing and wav != null:
			found.append(wav.data)
	return found


func _expect_cue(cue: StringName, emit: Callable) -> void:
	_stop_ui_players()
	emit.call()
	var expected: AudioStreamWAV = AudioStreamWAV.load_from_file("res://assets/audio/sfx".path_join(_config.ui_cue_file(cue)))
	assert_not_null(expected, "cue %s file exists" % cue)
	assert_eq(_playing_data().size(), 1, "cue %s started exactly one menu player" % cue)
	assert_true(_playing_data().has(expected.data), "cue %s" % cue)


func test_lobby_ui_cue_signal_plays_each_cue() -> void:
	for cue: StringName in _config.ui_cue_files:
		_expect_cue(cue, func() -> void: Events.lobby_ui_cue.emit(cue))


func test_peer_join_leave_and_gate_cues() -> void:
	_expect_cue(&"player_joined", func() -> void: Events.net_peer_joined.emit(99, 1, "x"))
	_expect_cue(&"player_left", func() -> void: Events.net_peer_left.emit(99, 1, 0))
	_expect_cue(&"all_players_ready", func() -> void: Events.loading_gate_opened.emit())


func test_own_departure_is_silent() -> void:
	Events.net_peer_left.emit(Net.local_peer_id(), 0, 0)
	assert_true(_playing_data().is_empty())
