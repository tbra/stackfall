class_name SfxChildren
extends RefCounted
## Observes the Sfx autoload through its public Node API: the match-cue player pool is the first
## `Sfx.config.max_simultaneous` AudioStreamPlayer children (ui, music and claim players are
## added after it), so silence asserts are not tripped by music or menu cues.


static func _cue_players() -> Array[AudioStreamPlayer]:
	var players: Array[AudioStreamPlayer] = []
	for child: Node in Sfx.get_children():
		var player: AudioStreamPlayer = child as AudioStreamPlayer
		if player == null:
			continue
		players.append(player)
		if players.size() >= Sfx.config.max_simultaneous:
			break
	return players


static func any_playing() -> bool:
	for player: AudioStreamPlayer in _cue_players():
		if player.playing:
			return true
	return false


static func stop_all() -> void:
	for player: AudioStreamPlayer in _cue_players():
		player.stop()
