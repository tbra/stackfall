extends GutTest
## Bontago-mp0.117: lobby/loading UI cues play on their events.

const SFX_SCRIPT: GDScript = preload("res://autoload/Sfx.gd")

var _config: AudioConfig


func before_each() -> void:
	_config = load("res://config/audio_config.tres") as AudioConfig


func _autoload() -> Node:
	return get_tree().root.get_node("Sfx")


func _played_stream(sfx: Node, before: int) -> AudioStream:
	assert_ne(sfx._next_sfx_player_index, before, "a cue should have started a player")
	var index: int = (sfx._next_sfx_player_index - 1 + sfx._sfx_players.size()) % sfx._sfx_players.size()
	return (sfx._sfx_players[index] as AudioStreamPlayer).stream


func _expect_cue(cue: StringName, emit: Callable) -> void:
	var sfx: Node = _autoload()
	var before: int = sfx._next_sfx_player_index
	emit.call()
	var stream: AudioStream = _played_stream(sfx, before)
	assert_same(stream, sfx._load_stream(_config.ui_cue_file(cue)), "cue %s" % cue)


func test_all_cue_files_load() -> void:
	var sfx: Node = _autoload()
	for cue: StringName in _config.ui_cue_files:
		assert_not_null(sfx._load_stream(_config.ui_cue_file(cue)), String(cue))


func test_lobby_ui_cue_signal_plays_each_cue() -> void:
	for cue: StringName in _config.ui_cue_files:
		_expect_cue(cue, func() -> void: Events.lobby_ui_cue.emit(cue))


func test_unknown_cue_is_silent() -> void:
	assert_false(_autoload().play_ui_cue(&"no_such_cue"))


func test_peer_join_leave_and_gate_cues() -> void:
	_expect_cue(&"player_joined", func() -> void: Events.net_peer_joined.emit(99, 1, "x"))
	_expect_cue(&"player_left", func() -> void: Events.net_peer_left.emit(99, 1, 0))
	_expect_cue(&"all_players_ready", func() -> void: Events.loading_gate_opened.emit())


func test_own_departure_is_silent() -> void:
	var sfx: Node = _autoload()
	var before: int = sfx._next_sfx_player_index
	Events.net_peer_left.emit(Net.local_peer_id(), 0, 0)
	assert_eq(sfx._next_sfx_player_index, before)
